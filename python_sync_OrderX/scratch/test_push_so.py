import sys
sys.path.insert(0, '.')
from src.config import load_config
from supabase import create_client
import requests
import xmltodict
import re
from decimal import Decimal, ROUND_HALF_UP
from src.stock_items import clean_tally_xml
from src.tally_client import TallyClient
from src.tally_so_xml_templates import ITEM_TEMPLATE, TAX_LEDGER_TEMPLATE, VOUCHER_TEMPLATE
from src.sales_orders_to_tally import (
    _xml, _money, _qty, _q2, _q0, _to_tally_date, _to_tally_date_display,
    _party_details, _tally_rate, _gst_percent, _line_gst,
    _fetch_items_and_products, _fetch_customers, _parse_import_result,
    _resolve_sales_ledger
)

cfg = load_config()
sb = create_client(cfg['supabase_url'], cfg['supabase_key'])
client = TallyClient()

def _resolve_tax_ledger_names(client):
    xml_request = """<ENVELOPE>
      <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>All Ledgers</ID></HEADER>
      <BODY><DESC><TDL><TDLMESSAGE><COLLECTION NAME="All Ledgers"><TYPE>Ledger</TYPE><FETCH>NAME, PARENT, TAXTYPE, GSTDUTYHEAD</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY>
    </ENVELOPE>"""
    names = []
    try:
        text = client.send_request(xml_request, timeout=30) or ""
        data = xmltodict.parse(clean_tally_xml(text))
        leds = data.get('ENVELOPE', {}).get('BODY', {}).get('DATA', {}).get('COLLECTION', {}).get('LEDGER', [])
        if isinstance(leds, dict):
            leds = [leds]
        names = [l.get('@NAME') for l in leds if l.get('@NAME')]
    except Exception as exc:
        print(f"Could not fetch Tally ledgers: {exc}")

    def match(patterns, default=None):
        for pat in patterns:
            for name in names:
                if re.search(pat, name, re.IGNORECASE):
                    return name
        return default

    cgst = match([r"^output\s*cgst", r"cgst.*output", r"^cgst$"], default="OUTPUT CGST" if "OUTPUT CGST" in names else "CGST")
    sgst = match([r"^output\s*sgst", r"sgst.*output", r"^sgst$"], default="OUTPUT SGST" if "OUTPUT SGST" in names else "SGST")
    igst = match([r"^output\s*igst", r"igst.*output", r"^igst$"], default="OUTPUT IGST" if "OUTPUT IGST" in names else "IGST")
    round_off = match([r"^round\s*off", r"^rounding"], default="Round Off" if "Round Off" in names else None)
    discount = match([r"discount\s*given", r"^discount$", r"discount\s*allowed", r"less.*discount"], default=None)

    return {
        "cgst": cgst,
        "sgst": sgst,
        "igst": igst,
        "round_off": round_off,
        "discount": discount,
        "all_names": names,
    }

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

    return "\n".join(blocks), party_amount

def _build_inventory_xml(
    items,
    products_by_id,
    sales_ledger,
    voucher_no="",
    date_display="",
    godown_name="Main Location",
):
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
            continue
        if amount <= 0 or unit_price <= 0:
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
    customer=None,
):
    order_id = str(order.get("id") or "")
    remote_id = (remote_id or "").strip() or f"Orderx-{order_id}"
    voucher_no = (order.get("order_number") or "").strip() or order_id[:8]
    party = (order.get("customer_name") or "").strip()
    order_date = "20260901"
    date_display = _to_tally_date_display(order_date)
    narration = order.get("remarks") or order.get("notes") or f"Orderx {voucher_no}"
    party_details = _party_details(order, customer)
    inventory_xml, inventory_total, line_gst_total, has_discount = _build_inventory_xml(
        items,
        products_by_id,
        sales_ledger,
        voucher_no,
        date_display=date_display,
    )
    order_discount = _money(order.get("discount_amount"))
    gst_total = _money(order.get("gst_amount")) or line_gst_total
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

# Now test!
so = sb.table('sales_orders').select('*').eq('id', 'ee3e31ec-e628-4a57-83f4-eedb4680d1e7').execute().data[0]
items_by_order, products_by_id = _fetch_items_and_products(sb, [so])
items = items_by_order.get(so['id'], [])
customers = _fetch_customers(sb, [so])
customer = customers.get(str(so.get('customer_id')))
tax_ledgers_map = _resolve_tax_ledger_names(client)
sales_ledger = _resolve_sales_ledger(client)

voucher_xml = _build_voucher_xml(
    company_name='VESTARA',
    order=so,
    items=items,
    products_by_id=products_by_id,
    sales_ledger=sales_ledger,
    action="Create",
    tax_ledgers_map=tax_ledgers_map,
    customer=customer
)

print("VOUCHER XML:\n", voucher_xml)
resp = client.send_request(voucher_xml)
result = _parse_import_result(resp)
print("Import Result:", result)
