import logging
import re
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from xml.sax.saxutils import escape as xml_escape

from supabase import create_client

from .config import load_config
from .tally_client import TallyClient
from .tally_companies import get_company_details, resolve_company_row
from .tally_so_xml_templates import ITEM_TEMPLATE, TAX_LEDGER_TEMPLATE, VOUCHER_TEMPLATE

VOUCHER_TYPE = "Sales Order"
REMOTE_PREFIX = "Orderx-"
CANCELLED_STATUSES = {"cancelled", "canceled", "deleted"}
DISCOUNT_LEDGERS = (
    "Discount Given",
    "Discount Given A/c",
    "Less Discount",
    "Discount",
)


GST_STATE_NAMES = {
    "32": "Kerala",
    "33": "Tamil Nadu",
    "29": "Karnataka",
    "36": "Telangana",
    "37": "Andhra Pradesh",
    "27": "Maharashtra",
    "24": "Gujarat",
    "07": "Delhi",
    "06": "Haryana",
    "09": "Uttar Pradesh",
    "23": "Madhya Pradesh",
    "08": "Rajasthan",
    "19": "West Bengal",
    "10": "Bihar",
    "21": "Odisha",
    "22": "Chhattisgarh",
    "03": "Punjab",
    "30": "Goa",
}


def _xml(value):
    if value is None:
        return ""
    return xml_escape(str(value), {"'": "&apos;", '"': "&quot;"})


def _clean(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def _first_text(*values):
    for value in values:
        text = _clean(value)
        if text:
            return text
    return ""


def _extract_pincode(*values):
    for value in values:
        match = re.search(r"\b(\d{6})\b", str(value or ""))
        if match:
            return match.group(1)
    return ""


def _state_from_gst(gst, fallback="Kerala"):
    gst = re.sub(r"[\s-]", "", str(gst or "")).upper()
    if len(gst) >= 2 and gst[:2].isdigit() and gst[:2] != "00":
        return GST_STATE_NAMES.get(gst[:2], fallback)
    return fallback


def _address_lines(address, city="", pincode="", mobile=""):
    raw = str(address or "").replace("\r\n", "\n").replace("\r", "\n")
    lines = []
    for part in raw.split("\n"):
        part = part.strip(" ,")
        if not part:
            continue
        lines.extend([p.strip() for p in part.split(",") if p.strip()])
    seen = set()
    unique = []
    for line in lines:
        key = line.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append(line)
    blob = " ".join(unique).lower()
    extras = []
    if city and city.lower() not in blob:
        extras.append(city)
    if pincode and pincode not in " ".join(unique):
        extras.append(pincode)
    if mobile:
        extras.append(f"Mob: {mobile}")
    return (unique + extras)[:4]


def _xml_list(list_tag, item_tag, lines):
    if not lines:
        return ""
    inner = "".join(f"      <{item_tag}>{_xml(line)}</{item_tag}>\n" for line in lines)
    return f'     <{list_tag} TYPE="String">\n{inner}     </{list_tag}>\n'


def _optional_tag(name, value):
    value = _clean(value)
    if not value:
        return ""
    return f"     <{name}>{_xml(value)}</{name}>\n"


def _party_details(order, customer=None):
    customer = customer or {}
    address = _first_text(order.get("customer_address"), customer.get("address"))
    shipping = _first_text(order.get("shipping_address"), address)
    gstin = re.sub(
        r"[\s-]",
        "",
        _first_text(order.get("customer_gst"), customer.get("gst_number")),
    ).upper()
    pincode = _extract_pincode(
        customer.get("pincode"),
        address,
        shipping,
        customer.get("city"),
    )
    city = _first_text(customer.get("city"))
    mobile = _first_text(order.get("customer_mobile"), customer.get("mobile_number"))
    state = _first_text(customer.get("state")) or _state_from_gst(gstin)
    buyer_lines = _address_lines(address, city=city, pincode=pincode, mobile=mobile)
    consignee_lines = _address_lines(shipping, city=city, pincode=pincode, mobile=mobile)
    return {
        "state": state or "Kerala",
        "address_xml": _xml_list("ADDRESS.LIST", "ADDRESS", consignee_lines),
        "buyer_address_xml": _xml_list(
            "BASICBUYERADDRESS.LIST", "BASICBUYERADDRESS", buyer_lines
        ),
        "gstin_xml": _optional_tag("PARTYGSTIN", gstin),
        "consignee_gstin_xml": _optional_tag("CONSIGNEEGSTIN", gstin),
        "pincode_xml": (
            _optional_tag("PARTYPINCODE", pincode)
            + _optional_tag("CONSIGNEEPINCODE", pincode)
            + _optional_tag("BUYERPINNUMBER", pincode)
            + _optional_tag("CONSIGNEEPINNUMBER", pincode)
        ),
    }


def _to_tally_date(value):
    if not value:
        return datetime.now().strftime("%Y%m%d")
    digits = re.sub(r"\D", "", str(value))[:8]
    if len(digits) == 8:
        return digits
    return datetime.now().strftime("%Y%m%d")


def _to_tally_date_display(yyyymmdd):
    try:
        return datetime.strptime(yyyymmdd, "%Y%m%d").strftime("%d-%b-%y")
    except ValueError:
        return datetime.now().strftime("%d-%b-%y")


def _money(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _qty(value):
    try:
        n = float(value)
    except (TypeError, ValueError):
        return 1.0
    return n if n > 0 else 1.0


def _parse_import_result(xml_text):
    text = xml_text or ""

    def count(tag):
        match = re.search(rf"<{tag}>(\d+)</{tag}>", text, re.I)
        return int(match.group(1)) if match else 0

    line_errors = [
        re.sub(r"\s+", " ", err).strip()
        for err in re.findall(r"<LINEERROR>(.*?)</LINEERROR>", text, re.I | re.S)
    ]
    return {
        "created": count("CREATED"),
        "altered": count("ALTERED"),
        "errors": count("ERRORS"),
        "exceptions": count("EXCEPTIONS"),
        "line_errors": line_errors,
        "raw": text,
    }


def _import_ok(result):
    if result["errors"] or result["exceptions"] or result["line_errors"]:
        return False
    return (result["created"] + result["altered"]) > 0


def _error_text(result):
    parts = list(result["line_errors"])
    if result["errors"]:
        parts.append(f"ERRORS={result['errors']}")
    if result["exceptions"]:
        parts.append(f"EXCEPTIONS={result['exceptions']}")
    if not parts:
        snippet = (result["raw"] or "").replace("\n", " ")[:400]
        parts.append(snippet or "Tally import returned no CREATED/ALTERED")
    return "; ".join(parts)


def _looks_like_duplicate(result):
    blob = " ".join(result["line_errors"]).lower() + " " + (result["raw"] or "").lower()
    return "duplicate" in blob or "already exists" in blob


def _ledger_key(name):
    return re.sub(r"[\s@%]+", "", name or "").lower()


def _resolve_sales_ledger(client):
    """Use Local Sales @18% for intra-state SO, not Export Sales."""
    xml_request = """
<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>Sales Ledgers</ID>
  </HEADER>
  <BODY>
    <DESC>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="Sales Ledgers">
            <TYPE>Ledger</TYPE>
            <BELONGSTO>Yes</BELONGSTO>
            <FETCH>NAME, PARENT</FETCH>
            <FILTER>IsSalesAc</FILTER>
          </COLLECTION>
          <SYSTEM TYPE="Formulae" NAME="IsSalesAc">
            $$IsLedOfGrp:$Name:$$GroupSales
          </SYSTEM>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>
"""
    names = []
    try:
        text = client.send_request(xml_request, timeout=30) or ""
        names = [
            re.sub(r"\s+", " ", n).strip()
            for n in re.findall(r'<LEDGER[^>]*NAME="([^"]+)"', text, re.I)
        ]
        if not names:
            names = [
                re.sub(r"\s+", " ", n).strip()
                for n in re.findall(r"<NAME>([^<]+)</NAME>", text, re.I)
            ]
        names = [n for n in names if n]
    except Exception as exc:
        logging.warning("Could not list Tally sales ledgers: %s", exc)

    preferred_keys = {"localsales18", "localsales018"}
    for name in names:
        if _ledger_key(name) in preferred_keys:
            logging.info("Using Tally sales ledger: %s", name)
            return name
    for name in names:
        key = _ledger_key(name)
        if "localsales" in key and "18" in key:
            logging.info("Using Tally sales ledger: %s", name)
            return name
    non_export = [name for name in names if "export" not in name.lower()]
    if non_export:
        logging.info("Using Tally sales ledger: %s", non_export[0])
        return non_export[0]
    if names:
        logging.info("Using Tally sales ledger: %s", names[0])
        return names[0]
    logging.warning("No Sales Accounts ledger found in Tally; defaulting to Local Sales@18%")
    return "Local Sales@18%"


def _resolve_godown_name(client):
    xml_request = """<ENVELOPE>
      <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>Godown List</ID></HEADER>
      <BODY><DESC><TDL><TDLMESSAGE><COLLECTION NAME="Godown List"><TYPE>Godown</TYPE><FETCH>NAME</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY>
    </ENVELOPE>"""
    try:
        text = client.send_request(xml_request, timeout=30) or ""
        names = [
            re.sub(r"\s+", " ", n).strip()
            for n in re.findall(r'<GODOWN[^>]*NAME="([^"]+)"', text, re.I)
        ]
        if not names:
            names = [
                re.sub(r"\s+", " ", n).strip()
                for n in re.findall(r"<NAME>([^<]+)</NAME>", text, re.I)
            ]
        names = [n for n in names if n]
        if names:
            logging.info("Using Tally Godown: %s", names[0])
            return names[0]
    except Exception as exc:
        logging.warning("Could not list Tally godowns: %s", exc)
    return "Main Location"


def _ensure_ledger_exists(client, ledger_name, parent="Indirect Expenses"):
    create_xml = f"""<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Import Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <IMPORTDATA>
      <REQUESTDESC>
        <REPORTNAME>All Masters</REPORTNAME>
      </REQUESTDESC>
      <REQUESTDATA>
        <TALLYMESSAGE xmlns:UDF="TallyUDF">
          <LEDGER NAME="{_xml(ledger_name)}" ACTION="Create">
            <NAME.LIST>
              <NAME>{_xml(ledger_name)}</NAME>
            </NAME.LIST>
            <PARENT>{_xml(parent)}</PARENT>
          </LEDGER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>"""
    try:
        res = client.send_request(create_xml, timeout=15)
        logging.info("Ensured Tally ledger '%s' exists under %s", ledger_name, parent)
        return True
    except Exception as exc:
        logging.warning("Could not auto-create Tally ledger '%s': %s", ledger_name, exc)
        return False


def _resolve_tax_ledger_names(client):
    """Dynamically find tax, round-off, and discount ledgers that exist in Tally."""
    xml_request = """<ENVELOPE>
      <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>All Ledgers</ID></HEADER>
      <BODY><DESC><TDL><TDLMESSAGE><COLLECTION NAME="All Ledgers"><TYPE>Ledger</TYPE><FETCH>NAME, PARENT, TAXTYPE, GSTDUTYHEAD</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY>
    </ENVELOPE>"""
    names = []
    try:
        text = client.send_request(xml_request, timeout=30) or ""
        names = [
            re.sub(r"\s+", " ", n).strip()
            for n in re.findall(r'<LEDGER[^>]*NAME="([^"]+)"', text, re.I)
        ]
        if not names:
            names = [
                re.sub(r"\s+", " ", n).strip()
                for n in re.findall(r"<NAME>([^<]+)</NAME>", text, re.I)
            ]
        names = [n for n in names if n]
    except Exception as exc:
        logging.warning("Could not list Tally ledgers for tax resolution: %s", exc)

    def match(patterns, default=None):
        for pat in patterns:
            for name in names:
                if re.search(pat, name, re.IGNORECASE):
                    return name
        return default

    cgst = match([r"^output\s*cgst", r"cgst.*output", r"^cgst$"], default="OUTPUT CGST" if "OUTPUT CGST" in names else "CGST")
    sgst = match([r"^output\s*sgst", r"sgst.*output", r"^sgst$"], default="OUTPUT SGST" if "OUTPUT SGST" in names else "SGST")
    igst = match([r"^output\s*igst", r"igst.*output", r"^igst$"], default="OUTPUT IGST" if "OUTPUT IGST" in names else "IGST")
    round_off = match([r"^round\s*off", r"^rounding"])
    discount = match([r"discount\s*given", r"^discount$", r"discount\s*allowed", r"less.*discount"])

    if not round_off:
        _ensure_ledger_exists(client, "Round Off", "Indirect Expenses")
        round_off = "Round Off"
    if not discount:
        _ensure_ledger_exists(client, "Discount Given", "Indirect Expenses")
        discount = "Discount Given"

    logging.info(
        "Resolved Tally ledgers: CGST=%s, SGST=%s, IGST=%s, RoundOff=%s, Discount=%s",
        cgst,
        sgst,
        igst,
        round_off,
        discount,
    )
    return {
        "cgst": cgst,
        "sgst": sgst,
        "igst": igst,
        "round_off": round_off,
        "discount": discount,
        "all_names": names,
    }



def _resolve_discount_ledger(client, tax_ledgers_map=None):
    """Order-level discount posts to this existing Tally ledger, before GST."""
    if tax_ledgers_map and tax_ledgers_map.get("discount"):
        return tax_ledgers_map["discount"]
    return DISCOUNT_LEDGERS[0]


def _resolve_company(supabase, company_data):
    company_data = company_data or get_company_details() or {}
    company_name = company_data.get("company_name") or ""
    tally_guid = company_data.get("Guid") or ""
    db_guid = company_data.get("db_guid") or ""
    company_id = company_data.get("company_id") or None

    if not company_id:
        try:
            resolved = resolve_company_row(supabase, company_data)
            if resolved:
                company_id = str(resolved.get("id") or "")
                db_guid = resolved.get("Guid") or db_guid
                company_name = resolved.get("company_name") or company_name
        except Exception as exc:
            logging.warning(f"Could not resolve company_id: {exc}")

    if company_id:
        logging.info(
            "SO push company: id=%s name=%s tally_guid=%s db_guid=%s",
            company_id,
            company_name,
            tally_guid,
            db_guid,
        )
    return company_id, company_name, company_data, tally_guid, db_guid


def _is_so_sync_enabled(supabase, company_id, extra_ids=None):
    ids = []
    for value in (company_id, *(extra_ids or [])):
        if value and value not in ids:
            ids.append(value)
    for cid in ids:
        try:
            res = (
                supabase.table("company_settings")
                .select("sync_so_to_tally")
                .eq("company_id", cid)
                .limit(1)
                .execute()
            )
            if res.data:
                return bool(res.data[0].get("sync_so_to_tally"))
        except Exception as exc:
            logging.warning(
                f"Could not read company_settings.sync_so_to_tally (run migration 008?): {exc}"
            )
            return False
    return False


def _fetch_pending_orders(supabase, company_id, extra_keys=None):
    keys = []
    for value in (company_id, *(extra_keys or [])):
        if value and value not in keys:
            keys.append(value)

    or_parts = []
    for key in keys:
        or_parts.append(f"company_id.eq.{key}")
        or_parts.append(f"Guid.eq.{key}")

    query = supabase.table("sales_orders").select("*")
    if or_parts:
        query = query.or_(",".join(or_parts))
    res = query.order("order_date").execute()
    rows = res.data or []
    pending = []
    for row in rows:
        synced = row.get("so_synced_to_tally")
        alter_id = row.get("alter_id")
        if synced is True and not alter_id:
            continue
        pending.append(row)
    return pending


def _fetch_customers(supabase, orders):
    ids = list(
        dict.fromkeys(
            str(order.get("customer_id"))
            for order in orders
            if order.get("customer_id")
        )
    )
    customers_by_id = {}
    if not ids:
        return customers_by_id
    try:
        res = (
            supabase.table("customers")
            .select("id, address, city, state, pincode, gst_number, mobile_number")
            .in_("id", ids)
            .execute()
        )
        for row in res.data or []:
            customers_by_id[str(row.get("id"))] = row
    except Exception as exc:
        logging.warning("Could not load customer address/GST for SO push: %s", exc)
    return customers_by_id


def _fetch_items_and_products(supabase, orders):
    order_ids = [row["id"] for row in orders if row.get("id")]
    items_by_order = {oid: [] for oid in order_ids}
    products_by_id = {}
    if not order_ids:
        return items_by_order, products_by_id

    items_res = (
        supabase.table("order_items")
        .select(
            "id, order_id, product_id, product_name, quantity, unit_price, "
            "discount_amount, discount_percentage, total_amount, gst_amount, gst_rate"
        )
        .in_("order_id", order_ids)
        .execute()
    )
    items = items_res.data or []
    product_ids = []
    for item in items:
        items_by_order.setdefault(item.get("order_id"), []).append(item)
        pid = item.get("product_id")
        if pid:
            product_ids.append(pid)

    unique_ids = list(dict.fromkeys(product_ids))
    if unique_ids:
        try:
            prod_res = (
                supabase.table("products")
                .select("id, ItemName, ItemUnit, GstRate")
                .in_("id", unique_ids)
                .execute()
            )
            for prod in prod_res.data or []:
                products_by_id[str(prod["id"])] = prod
        except Exception as exc:
            logging.warning(f"Could not load products with GstRate, retrying without: {exc}")
            try:
                prod_res = (
                    supabase.table("products")
                    .select("id, ItemName, ItemUnit")
                    .in_("id", unique_ids)
                    .execute()
                )
                for prod in prod_res.data or []:
                    products_by_id[str(prod["id"])] = prod
            except Exception as inner:
                logging.warning(f"Could not load product names/units: {inner}")

    return items_by_order, products_by_id


def _line_amount_and_rate(item):
    qty = _qty(item.get("quantity"))
    unit_price = _money(item.get("unit_price"))
    discount_pct = _money(item.get("discount_percentage"))
    discount_amt = _money(item.get("discount_amount"))

    total = _money(item.get("total_amount"))
    gst = _money(item.get("gst_amount"))
    taxable = total - gst if total > gst else total

    if discount_pct <= 0 and discount_amt > 0 and (unit_price * qty) > 0:
        discount_pct = (discount_amt / (unit_price * qty)) * 100.0

    if unit_price <= 0 and taxable > 0 and qty > 0:
        if discount_pct > 0 and discount_pct < 100:
            unit_price = (taxable / (1.0 - discount_pct / 100.0)) / qty
        else:
            unit_price = taxable / qty

    if taxable <= 0 and unit_price > 0:
        taxable = (unit_price * qty) * (1.0 - discount_pct / 100.0)

    return qty, unit_price, discount_pct, taxable


def _gst_percent(item, product=None):
    rate = _money(item.get("gst_rate"))
    if rate <= 0 and product:
        rate = _money(product.get("GstRate"))
    if rate <= 0:
        return 0.0
    return rate * 100.0 if rate <= 1 else rate


def _line_gst(item, taxable, product=None):
    gst = _money(item.get("gst_amount"))
    if gst > 0:
        return gst
    pct = _gst_percent(item, product)
    if pct > 0 and taxable > 0:
        return float(Decimal(str(taxable * pct / 100.0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
    return 0.0


def _tally_rate(fraction):
    return f" {fraction:.2f}"


def _q2(value):
    return float(Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def _q0(value):
    return float(Decimal(str(value)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _fill_tax_ledger(
    name,
    amount,
    *,
    deemed_positive="No",
    round_type="&#4; Not Applicable",
    round_limit="0",
):
    block = TAX_LEDGER_TEMPLATE
    replacements = {
        "__LEDGER_NAME__": _xml(name),
        "__AMOUNT__": f"{amount:.2f}",
        "__ISDEEMEDPOSITIVE__": deemed_positive,
        "__ROUNDTYPE__": round_type,
        "__ROUNDLIMIT__": round_limit,
    }
    for key, value in replacements.items():
        block = block.replace(key, value)
    return block


def _tax_ledgers_xml(
    taxable,
    gst_total,
    order_discount=0.0,
    tax_ledgers_map=None,
):
    """Order discount (before GST), CGST + SGST, and nearest-rupee round off."""
    tax_ledgers_map = tax_ledgers_map or {}
    cgst_ledger = tax_ledgers_map.get("cgst") or "CGST"
    sgst_ledger = tax_ledgers_map.get("sgst") or "SGST"
    round_off_ledger = tax_ledgers_map.get("round_off")
    discount_ledger = tax_ledgers_map.get("discount")

    taxable = _q2(taxable)
    order_discount = _q2(order_discount)
    if order_discount < 0:
        order_discount = 0.0
    net = _q2(taxable - order_discount)
    if net < 0:
        net = 0.0
    gst_total = _q2(gst_total)

    blocks = []
    if order_discount >= 0.005 and discount_ledger:
        blocks.append(
            _fill_tax_ledger(discount_ledger, order_discount, deemed_positive="Yes")
        )

    cgst = sgst = 0.0
    if gst_total > 0:
        cgst = _q2(gst_total / 2.0)
        sgst = _q2(gst_total - cgst)
        blocks.append(_fill_tax_ledger(cgst_ledger, cgst))
        blocks.append(_fill_tax_ledger(sgst_ledger, sgst))

    raw = _q2(net + cgst + sgst)
    if round_off_ledger:
        rounded = _q0(raw)
        round_off = _q2(rounded - raw)
        if abs(round_off) >= 0.005:
            blocks.append(
                _fill_tax_ledger(
                    round_off_ledger,
                    abs(round_off),
                    deemed_positive="Yes" if round_off < 0 else "No",
                    round_type="Normal Rounding",
                    round_limit=" 1",
                )
            )
        party_amount = -rounded
    else:
        party_amount = -raw

    logging.info(
        "SO tax ledgers: taxable=%.2f discount=%.2f net=%.2f cgst=%.2f (%s) sgst=%.2f (%s) party=%.2f",
        taxable,
        order_discount,
        net,
        cgst,
        cgst_ledger,
        sgst,
        sgst_ledger,
        party_amount,
    )
    return "\n".join(blocks), party_amount


def _voucher_gst_total(order, inventory_total, line_gst_total, order_discount):
    header_gst = _money(order.get("gst_amount"))
    if header_gst > 0:
        return header_gst
    if order_discount > 0 and inventory_total > 0 and line_gst_total > 0:
        return _q2(line_gst_total * ((inventory_total - order_discount) / inventory_total))
    return line_gst_total


def _build_inventory_xml(
    items,
    products_by_id,
    sales_ledger,
    voucher_no="",
    date_display="",
    godown_name="Main Location",
):
    """Fill a native Tally Sales Order inventory block so items are not dropped."""
    blocks = []
    total = 0.0
    gst_total = 0.0
    has_discount = False
    for item in items:
        qty, unit_price, discount_pct, amount = _line_amount_and_rate(item)
        product = products_by_id.get(str(item.get("product_id") or "")) or {}
        name = (
            product.get("ItemName")
            or item.get("product_name")
            or ""
        ).strip()
        if not name:
            logging.warning("Skipping SO line with no stock item name: %s", item.get("id"))
            continue
        if amount <= 0 or unit_price <= 0:
            logging.warning(
                "Skipping SO line with zero rate/amount: %s %s",
                voucher_no,
                name,
            )
            continue
        unit = (product.get("ItemUnit") or "Nos").strip() or "Nos"
        if discount_pct > 0:
            has_discount = True
        gst_amt = _line_gst(item, amount, product)
        gst_pct = _gst_percent(item, product)
        if gst_pct <= 0 and amount > 0 and gst_amt > 0:
            gst_pct = (gst_amt / amount) * 100.0
        half_frac = (gst_pct / 2.0) / 100.0
        full_frac = gst_pct / 100.0
        total += amount
        gst_total += gst_amt
        logging.info(
            "SO %s inventory: %s qty=%.4f rate=%.2f/%s amt=%.2f gst=%.2f (%.2f%%) ledger=%s godown=%s",
            voucher_no,
            name,
            qty,
            unit_price,
            unit,
            amount,
            gst_amt,
            gst_pct,
            sales_ledger,
            godown_name,
        )
        block = ITEM_TEMPLATE
        replacements = {
            "__ITEM_NAME__": _xml(name),
            "__RATE__": f"{unit_price:.2f}",
            "__UNIT__": _xml(unit),
            "__AMOUNT__": f"{amount:.2f}",
            "__QTY__": f"{qty:.4f}",
            "__DISCOUNT__": f"{discount_pct:g}" if discount_pct > 0 else "0",
            "__SALES_LEDGER__": _xml(sales_ledger),
            "__DATE_DISPLAY__": _xml(date_display),
            "__CGST_RATE__": _tally_rate(half_frac),
            "__SGST_RATE__": _tally_rate(half_frac),
            "__IGST_RATE__": _tally_rate(full_frac),
            "01 Main Location": _xml(godown_name),
        }
        for key, value in replacements.items():
            block = block.replace(key, value)
        blocks.append(block)
    return "\n".join(blocks), total, gst_total, has_discount


def _build_voucher_xml(
    *,
    company_name,
    order,
    items,
    products_by_id,
    sales_ledger,
    action,
    remote_id=None,
    tax_ledgers_map=None,
    godown_name="Main Location",
    customer=None,
    override_date=None,
):
    order_id = str(order.get("id") or "")
    remote_id = (remote_id or "").strip() or f"{REMOTE_PREFIX}{order_id}"
    voucher_no = (order.get("order_number") or "").strip() or order_id[:8]
    party = (order.get("customer_name") or "").strip()
    order_date = override_date or _to_tally_date(order.get("order_date"))
    date_display = _to_tally_date_display(order_date)
    narration = order.get("remarks") or order.get("notes") or f"Orderx {voucher_no}"
    party_details = _party_details(order, customer)
    inventory_xml, inventory_total, line_gst_total, has_discount = _build_inventory_xml(
        items,
        products_by_id,
        sales_ledger,
        voucher_no,
        date_display=date_display,
        godown_name=godown_name,
    )
    order_discount = _money(order.get("discount_amount"))
    gst_total = _voucher_gst_total(order, inventory_total, line_gst_total, order_discount)
    tax_xml, party_amount = _tax_ledgers_xml(
        inventory_total,
        gst_total,
        order_discount=order_discount,
        tax_ledgers_map=tax_ledgers_map,
    )
    xml_request = VOUCHER_TEMPLATE
    replacements = {
        "__COMPANY__": _xml(company_name),
        "__REMOTE_ID__": _xml(remote_id),
        "__REFERENCE__": _xml(voucher_no),
        "__DATE__": order_date,
        "__DATE_DISPLAY__": _xml(date_display),
        "__NARRATION__": _xml(narration),
        "__PARTY__": _xml(party),
        "__STATE__": _xml(party_details["state"]),
        "__ADDRESS_LIST_XML__": party_details["address_xml"],
        "__BASICBUYERADDRESS_XML__": party_details["buyer_address_xml"],
        "__PARTYGSTIN_XML__": party_details["gstin_xml"],
        "__CONSIGNEEGSTIN_XML__": party_details["consignee_gstin_xml"],
        "__PINCODE_XML__": party_details["pincode_xml"],
        "__PARTY_AMOUNT__": f"{party_amount:.2f}",
        "__HAS_DISCOUNTS__": "Yes" if has_discount else "No",
        "__INVENTORY__": inventory_xml,
        "__TAX_LEDGERS__": tax_xml,
    }
    for key, value in replacements.items():
        xml_request = xml_request.replace(key, value)
    xml_request = xml_request.replace('ACTION="Create"', f'ACTION="{action}"', 1)
    return xml_request


def _delete_existing_voucher(client, company_name, remote_id, voucher_no, order_date):
    """Remove a previously imported accounting-only SO so Create can use Item Invoice."""
    if not remote_id and not voucher_no:
        return
    xml_request = f"""<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Import Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <IMPORTDATA>
      <REQUESTDESC>
        <REPORTNAME>Vouchers</REPORTNAME>
        <STATICVARIABLES>
          <SVCURRENTCOMPANY>{_xml(company_name)}</SVCURRENTCOMPANY>
        </STATICVARIABLES>
      </REQUESTDESC>
      <REQUESTDATA>
        <TALLYMESSAGE xmlns:UDF="TallyUDF">
          <VOUCHER REMOTEID="{_xml(remote_id)}" VCHTYPE="{_xml(VOUCHER_TYPE)}" ACTION="Delete">
            <DATE>{order_date}</DATE>
            <VOUCHERTYPENAME>{_xml(VOUCHER_TYPE)}</VOUCHERTYPENAME>
          </VOUCHER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>"""
    try:
        result = _parse_import_result(client.send_request(xml_request, timeout=30))
        logging.info(
            "Deleted Tally SO %s remote=%s cancelled/errors=%s",
            voucher_no,
            remote_id,
            _error_text(result) if not _import_ok(result) else "ok",
        )
    except Exception as exc:
        logging.warning("Could not delete Tally SO %s: %s", voucher_no, exc)


def _mark_synced(supabase, order, remote_id):
    now = datetime.now(timezone.utc).isoformat()
    payload = {
        "so_synced_to_tally": True,
        "so_tally_sync_date": now,
        "tally_so_guid": remote_id,
        "alter_id": None,
    }
    try:
        supabase.table("sales_orders").update(payload).eq("id", order["id"]).execute()
    except Exception as exc:
        logging.warning("Could not mark SO synced (run migration 008?): %s", exc)


def _push_one(
    client,
    supabase,
    company_name,
    order,
    items,
    products_by_id,
    sales_ledger,
    tax_ledgers_map=None,
    godown_name="Main Location",
    customer=None,
):
    voucher_no = order.get("order_number") or order.get("id")
    party = (order.get("customer_name") or "").strip()
    if not party:
        return False, "missing customer_name"
    if not items:
        return False, "no order items"

    if not any(
        (products_by_id.get(str(item.get("product_id") or "")) or {}).get("ItemName")
        or item.get("product_name")
        for item in items
    ):
        return False, "no stock item names on order lines"

    old_remote_id = (order.get("tally_so_guid") or "").strip()
    remote_id = f"{REMOTE_PREFIX}{order['id']}"
    order_date = _to_tally_date(order.get("order_date"))

    if old_remote_id or voucher_no:
        _delete_existing_voucher(
            client, company_name, old_remote_id or remote_id, voucher_no, order_date
        )

    xml_request = _build_voucher_xml(
        company_name=company_name,
        order=order,
        items=items,
        products_by_id=products_by_id,
        sales_ledger=sales_ledger,
        action="Create",
        remote_id=remote_id,
        tax_ledgers_map=tax_ledgers_map,
        godown_name=godown_name,
        customer=customer,
    )
    response = client.send_request(xml_request, timeout=60)
    result = _parse_import_result(response)

    # In Tally Educational mode, dates other than 1, 2, 31 are rejected.
    # Retry with the 1st of the month if date error is detected.
    if result["exceptions"] or not _import_ok(result):
        err_msg = _error_text(result)
        if "Voucher date is missing" in err_msg or "Date" in err_msg:
            edu_date = f"{order_date[:6]}01"
            if edu_date != order_date:
                logging.info(f"Retrying SO {voucher_no} with EDU date {edu_date}...")
                xml_retry = _build_voucher_xml(
                    company_name=company_name,
                    order=order,
                    items=items,
                    products_by_id=products_by_id,
                    sales_ledger=sales_ledger,
                    action="Create",
                    remote_id=remote_id,
                    tax_ledgers_map=tax_ledgers_map,
                    godown_name=godown_name,
                    customer=customer,
                    override_date=edu_date,
                )
                response = client.send_request(xml_retry, timeout=60)
                result = _parse_import_result(response)

    if result["exceptions"]:
        return False, _error_text(result)

    if not _import_ok(result):
        return False, _error_text(result)

    _mark_synced(supabase, order, remote_id)
    return True, "Create"


def push_sales_orders(company_data=None):
    """
    Push app sales orders into Tally as Sales Order vouchers.

    First run (so_synced_to_tally is false for everyone): send all.
    Later runs: only unsynced (new) and rows with alter_id (edited).
    Skipped entirely when company_settings.sync_so_to_tally is off.
    """
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])
    company_id, company_name, company_data, tally_guid, db_guid = _resolve_company(
        supabase, company_data
    )

    if not company_id:
        logging.warning("Skipping SO → Tally: company_id not found in tally_companies")
        print(" Skipping SO → Tally: company not found in Supabase")
        return 0

    extra_keys = [k for k in (tally_guid, db_guid) if k]
    if not _is_so_sync_enabled(supabase, company_id, extra_keys):
        logging.info("Sync SO to Tally is OFF — skipping sales order push")
        print(" Sync SO to Tally is OFF — skipped")
        return 0

    try:
        orders = _fetch_pending_orders(supabase, company_id, extra_keys)
    except Exception as exc:
        logging.error(
            f"Could not load pending sales orders (run migration 008?): {exc}"
        )
        print(f" Could not load pending sales orders: {exc}")
        return 0

    if not orders:
        logging.info("No new or edited sales orders to push")
        print(" No new or edited sales orders to push")
        return 0

    items_by_order, products_by_id = _fetch_items_and_products(supabase, orders)
    customers_by_id = _fetch_customers(supabase, orders)
    client = TallyClient()
    sales_ledger = _resolve_sales_ledger(client)
    tax_ledgers_map = _resolve_tax_ledger_names(client)
    godown_name = _resolve_godown_name(client)

    pushed = 0
    failed = 0
    skipped = 0

    for order in orders:
        voucher_no = order.get("order_number") or order.get("id")
        status = str(order.get("status") or "").lower()
        if status in CANCELLED_STATUSES:
            skipped += 1
            continue
        items = items_by_order.get(order.get("id"), [])
        try:
            ok, detail = _push_one(
                client,
                supabase,
                company_name,
                order,
                items,
                products_by_id,
                sales_ledger,
                tax_ledgers_map=tax_ledgers_map,
                godown_name=godown_name,
                customer=customers_by_id.get(str(order.get("customer_id") or "")),
            )
        except Exception as exc:
            ok, detail = False, str(exc)
            logging.error(f"Tally connection failed on SO {voucher_no}: {exc}")
            failed += 1
            print(f"  Failed SO {voucher_no}: {detail}")
            print("  Stopping remaining SO pushes — Tally may have crashed. Click OK in Tally, then retry.")
            break

        if ok:
            pushed += 1
            logging.info(f"Pushed SO {voucher_no} to Tally ({detail})")
        else:
            failed += 1
            logging.error(f"Failed to push SO {voucher_no}: {detail}")
            print(f"  Failed SO {voucher_no}: {detail}")

    logging.info(
        f"SO → Tally: pushed={pushed}, failed={failed}, skipped={skipped}, pending={len(orders)}"
    )
    if failed:
        print(f" Pushed {pushed} sales orders ({failed} failed)")
    else:
        print(f" Pushed {pushed} sales orders")
    return pushed
