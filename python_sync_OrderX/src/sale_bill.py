import re
import requests
import xmltodict
import concurrent.futures
from datetime import datetime, timezone

from supabase import create_client

from .config import load_config
from .tally_companies import get_company_details, resolve_company_row


# =====================================================
# HELPERS
# =====================================================

def clean_text(value):
    if value is None:
        return ""
    value = str(value)
    value = re.sub(r"&#\d+;", "", value)
    return value.strip()


def get_text(value):
    if value is None:
        return ""
    if isinstance(value, list):
        if len(value) > 0:
            return get_text(value[0])
        return ""
    if isinstance(value, dict):
        return clean_text(value.get("#text", ""))
    return clean_text(value)


def get_text_or_none(value):
    text = get_text(value)
    return text if text else None


def safe_float(value, default=0):
    try:
        value = get_text(value)
        value = value.replace(",", "")
        match = re.search(r"-?\d+(\.\d+)?", value)
        if not match:
            return default
        return float(match.group())
    except Exception:
        return default


def format_tally_date(value):
    value = get_text(value)
    if not value or len(value) != 8:
        return None
    try:
        return datetime.strptime(value, "%Y%m%d").date().isoformat()
    except Exception:
        return None


def clean_tally_xml(xml_text):
    xml_text = re.sub(r'&#(?:x[0-9A-Fa-f]+|\d+);', '', xml_text)
    xml_text = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;)", "&amp;", xml_text)
    return xml_text


def _looks_like_app_order_no(value):
    text = (value or "").strip()
    if not text:
        return False
    upper = text.upper()
    return upper.startswith("ORD") or upper.startswith("ORDERX-")


def _load_app_order_numbers(supabase):
    numbers = set()
    try:
        rows = supabase.table("sales_orders").select("order_number").execute().data or []
        for row in rows:
            number = (row.get("order_number") or "").strip()
            if number:
                numbers.add(number)
    except Exception as exc:
        print(f"Could not load app order numbers: {exc}")
    return numbers


def _linked_order_number(voucher, app_orders=None):
    """Tally invoice number is not the app SO number; REFERENCE / PO no is."""
    app_orders = app_orders or set()
    for key in ("REFERENCE", "BASICPURCHASEORDERNO"):
        text = get_text(voucher.get(key)).strip()
        if not text:
            continue
        if text in app_orders or _looks_like_app_order_no(text):
            return text
    return ""


def _as_list(value):
    if value is None or value == "":
        return []
    if isinstance(value, list):
        return value
    return [value]


def _norm_item_name(value):
    text = get_text(value).strip().lower()
    return re.sub(r"\s+", " ", text)


def _inventory_lines(voucher, default_order_number="", app_orders=None):
    """Stock qty billed on a Tally sales voucher, keyed to the app SO when possible."""
    app_orders = app_orders or set()
    entries = (
        voucher.get("ALLINVENTORYENTRIES.LIST")
        or voucher.get("ALLINVENTORYENTRIES")
        or voucher.get("INVENTORYENTRIES.LIST")
        or []
    )
    lines = []
    for entry in _as_list(entries):
        if not isinstance(entry, dict):
            continue
        name = get_text(entry.get("STOCKITEMNAME"))
        qty = safe_float(entry.get("BILLEDQTY"), 0) or safe_float(
            entry.get("ACTUALQTY"), 0
        )
        if not name or qty <= 0:
            continue
        line_order = get_text(entry.get("ORDERNO")).strip() or get_text(
            entry.get("BASICPURCHASEORDERNO")
        ).strip()
        if line_order in app_orders or _looks_like_app_order_no(line_order):
            order_number = line_order
        else:
            order_number = default_order_number
        lines.append(
            {
                "item_name": name,
                "qty": qty,
                "order_number": order_number,
            }
        )
    return lines


def _sale_bill_db_row(bill):
    row = dict(bill)
    row.pop("_inventory", None)
    return row


# =====================================================
# TALLY FETCH
# =====================================================

def get_sale_bills():

    config = load_config()
    tally_url = f"http://localhost:{config['tally_port']}"
    supabase = create_client(config["supabase_url"], config["supabase_key"])
    company_details = get_company_details()
    company_name = company_details.get("company_name", "")
    company_id = None
    now = datetime.now(timezone.utc).isoformat()

    try:
        resolved = resolve_company_row(supabase, company_details)
        if resolved:
            company_id = str(resolved.get("id") or "")
    except Exception as e:
        print(f"Failed to fetch company_id: {e}")

    # -------------------------------------------------
    # DATE CHUNKING
    # -------------------------------------------------
    
    from .date_utils import get_current_fy_monthly_date_ranges
    date_ranges = get_current_fy_monthly_date_ranges()
    
    print(f"Fetching sale bills in {len(date_ranges)} chunks...\n")
    
    sale_bills_list = []
    app_orders = _load_app_order_numbers(supabase)
    
    for start_date, end_date in date_ranges:
        print(f"Fetching {start_date} to {end_date}...")
        
        xml_request = f"""
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Sale Bill Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <STATICVARIABLES>
                <SVFROMDATE TYPE="Date">{start_date}</SVFROMDATE>
                <SVTODATE TYPE="Date">{end_date}</SVTODATE>
            </STATICVARIABLES>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Sale Bill Collection">
                        <TYPE>Voucher</TYPE>
                        <NATIVEMETHOD>ALLINVENTORYENTRIES.LIST</NATIVEMETHOD>
                        <FETCH>
                            DATE,
                            GUID,
                            MASTERID,
                            VOUCHERNUMBER,
                            VOUCHERTYPENAME,
                            REFERENCE,
                            BASICPURCHASEORDERNO,
                            PARTYLEDGERNAME,
                            ISDELETED,
                            ISCANCELLED,
                            ALLINVENTORYENTRIES.LIST.STOCKITEMNAME,
                            ALLINVENTORYENTRIES.LIST.BILLEDQTY,
                            ALLINVENTORYENTRIES.LIST.ACTUALQTY,
                            ALLINVENTORYENTRIES.LIST.ORDERNO
                        </FETCH>
                        <FILTER>IsSales</FILTER>
                    </COLLECTION>
                    <SYSTEM TYPE="Formulae" NAME="IsSales">
                        $$IsSales:$VoucherTypeName
                    </SYSTEM>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""
        try:
            response = requests.post(
                tally_url,
                data=xml_request.encode("utf-8"),
                headers={"Content-Type": "application/xml"},
                timeout=120
            )
            response.raise_for_status()
            
            xml_content = clean_tally_xml(response.text)
            data = xmltodict.parse(xml_content)
            
            collection = (
                data.get("ENVELOPE", {})
                .get("BODY", {})
                .get("DATA", {})
                .get("COLLECTION", {})
            )

            vouchers = collection.get("VOUCHER", [])
            if isinstance(vouchers, dict):
                vouchers = [vouchers]
                
            if not vouchers:
                continue

            for voucher in vouchers:
                if get_text(voucher.get("ISDELETED")) == "Yes":
                    continue
                if get_text(voucher.get("ISCANCELLED")) == "Yes":
                    continue

                invoice_number = get_text(voucher.get("VOUCHERNUMBER"))
                if not invoice_number:
                    continue

                order_number = _linked_order_number(voucher, app_orders) or invoice_number

                guid = get_text(voucher.get("GUID"))
                master_id_val = safe_float(voucher.get("MASTERID"))
                master_id = int(master_id_val) if master_id_val else None
                date = format_tally_date(voucher.get("DATE"))
                
                if not date:
                    continue

                inventory = _inventory_lines(
                    voucher, default_order_number=order_number, app_orders=app_orders
                )
                row = {
                    "order_number": order_number,
                    "date": date,
                    "invoice_number": invoice_number,
                    "status": "Pending",
                    "company_name": company_name,
                    "Guid": guid,
                    "MasterID": master_id,
                    "company_id": company_id,
                    "updated_at": now,
                    "_inventory": inventory,
                }

                sale_bills_list.append(row)
                
        except Exception as e:
            print(f"Chunk Error ({start_date}-{end_date}): {e}")

    # Deduplicate by GUID to prevent batch upsert conflicts
    unique_bills = {}
    for bill in sale_bills_list:
        guid = bill.get("Guid")
        if guid:
            unique_bills[guid] = bill

    linked = sum(
        1
        for bill in unique_bills.values()
        if _looks_like_app_order_no(bill.get("order_number"))
        or (bill.get("order_number") or "") in app_orders
    )
    print(f"Linked {linked} Tally bills to app sales orders")

    return list(unique_bills.values())


# =====================================================
# SUPABASE SAVE
# =====================================================

def save_sale_bills_to_supabase(sale_bills):

    config = load_config()

    supabase = create_client(
        config["supabase_url"],
        config["supabase_key"]
    )

    if not sale_bills:
        print("No sale bills to save.")
        return 0

    BATCH_SIZE = 100
    total_saved = 0
    batches = [sale_bills[i: i + BATCH_SIZE] for i in range(0, len(sale_bills), BATCH_SIZE)]

    def upload_batch(batch):
        try:
            guids = [bill.get("Guid") for bill in batch if bill.get("Guid")]
            existing_by_guid = {}
            if guids:
                existing = (
                    supabase.table("sale_bill")
                    .select("id,Guid,status,payment_received")
                    .in_("Guid", guids)
                    .execute()
                    .data
                    or []
                )
                for row in existing:
                    existing_by_guid[row.get("Guid")] = row
                supabase.table("sale_bill").delete().in_("Guid", guids).execute()

            payload = []
            for bill in batch:
                old = existing_by_guid.get(bill.get("Guid")) or {}
                row = _sale_bill_db_row(bill)
                if old.get("status"):
                    row["status"] = old["status"]
                if old.get("payment_received") is not None:
                    row["payment_received"] = old["payment_received"]
                payload.append(row)

            supabase.table("sale_bill").upsert(
                payload,
                on_conflict="Guid,order_number"
            ).execute()
            return len(payload)
        except Exception as e:
            print(f"Batch upload failed: {e}")
            return 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        results = executor.map(upload_batch, batches)
        total_saved = sum(results)

    _apply_order_billing(supabase, sale_bills)
    return total_saved


def _app_order_numbers_from_bills(sale_bills):
    numbers = []
    seen = set()
    for bill in sale_bills:
        candidates = [(bill.get("order_number") or "").strip()]
        for line in bill.get("_inventory") or []:
            candidates.append((line.get("order_number") or "").strip())
        for number in candidates:
            if not number or number in seen:
                continue
            if _looks_like_app_order_no(number):
                seen.add(number)
                numbers.append(number)
    return numbers


def _mark_orders_fully_billed(supabase, order_numbers):
    """Fallback when Tally did not return inventory lines."""
    if not order_numbers:
        return
    CHUNK = 100
    for i in range(0, len(order_numbers), CHUNK):
        chunk = order_numbers[i : i + CHUNK]
        try:
            supabase.table("sales_orders").update(
                {"is_sale_billed": True, "is_partially_billed": False}
            ).in_("order_number", chunk).execute()
        except Exception as e:
            print(f"Could not mark sales orders billed: {e}")
            try:
                supabase.table("sales_orders").update(
                    {"is_sale_billed": True}
                ).in_("order_number", chunk).execute()
            except Exception as inner:
                print(f"Could not mark sales orders billed: {inner}")
                return


def _apply_order_billing(supabase, sale_bills):
    """Set billed_qty on order_items and Partial vs fully billed on the SO."""
    order_numbers = _app_order_numbers_from_bills(sale_bills)
    if not order_numbers:
        return

    billed_by_order = {}
    inventory_line_count = 0
    for bill in sale_bills:
        for line in bill.get("_inventory") or []:
            number = (line.get("order_number") or bill.get("order_number") or "").strip()
            name = _norm_item_name(line.get("item_name"))
            qty = float(line.get("qty") or 0)
            if not number or not _looks_like_app_order_no(number) or not name or qty <= 0:
                continue
            billed_by_order.setdefault(number, {})
            billed_by_order[number][name] = billed_by_order[number].get(name, 0) + qty
            inventory_line_count += 1

    print(f"Sale bill inventory lines linked to app orders: {inventory_line_count}")
    if inventory_line_count == 0:
        print("No inventory on Tally sales vouchers; marking linked orders fully billed.")
        _mark_orders_fully_billed(supabase, order_numbers)
        return

    try:
        orders = (
            supabase.table("sales_orders")
            .select("id,order_number")
            .in_("order_number", order_numbers)
            .execute()
            .data
            or []
        )
    except Exception as e:
        print(f"Could not load sales orders for billing: {e}")
        return

    order_id_by_number = {
        (row.get("order_number") or "").strip(): row.get("id")
        for row in orders
        if row.get("id") and row.get("order_number")
    }
    order_ids = [oid for oid in order_id_by_number.values() if oid]
    if not order_ids:
        return

    try:
        items = (
            supabase.table("order_items")
            .select("id,order_id,product_name,quantity,product_code,total_amount")
            .in_("order_id", order_ids)
            .execute()
            .data
            or []
        )
    except Exception as e:
        print(
            "Could not load/update billed_qty. Run migration "
            "013_add_order_item_billed_qty.sql in Supabase. "
            f"Error: {e}"
        )
        _mark_orders_fully_billed(supabase, order_numbers)
        return

    items_by_order = {}
    for item in items:
        items_by_order.setdefault(item.get("order_id"), []).append(item)

    partial_count = 0
    full_count = 0
    for number, order_id in order_id_by_number.items():
        remaining = dict(billed_by_order.get(number, {}))
        order_items = items_by_order.get(order_id) or []
        if not remaining:
            try:
                supabase.table("sales_orders").update(
                    {"is_sale_billed": True, "is_partially_billed": False}
                ).eq("id", order_id).execute()
                full_count += 1
            except Exception as e:
                print(f"Could not mark {number} billed without inventory: {e}")
            continue
        any_billed = False
        all_full = True if order_items else False
        order_billed_amount = 0.0
        for item in order_items:
            ordered_qty = float(item.get("quantity") or item.get("ItemQuantity") or 0)
            key = _norm_item_name(
                item.get("product_name") or item.get("ItemName")
            )
            code_key = _norm_item_name(item.get("product_code"))
            take = min(ordered_qty, remaining.get(key, 0))
            if take <= 0 and code_key:
                take = min(ordered_qty, remaining.get(code_key, 0))
                remaining[code_key] = remaining.get(code_key, 0) - take
            else:
                remaining[key] = remaining.get(key, 0) - take
            if take > 0:
                any_billed = True
            if take + 0.0001 < ordered_qty:
                all_full = False
            line_total = float(item.get("total_amount") or 0)
            if ordered_qty > 0:
                order_billed_amount += line_total * (take / ordered_qty)
            try:
                supabase.table("order_items").update({"billed_qty": take}).eq(
                    "id", item["id"]
                ).execute()
            except Exception as e:
                print(f"Could not update billed_qty for item {item.get('id')}: {e}")
                return
        leftover = sum(qty for qty in remaining.values() if qty > 0.0001)
        if leftover:
            print(f"Unmatched billed qty on {number}: {leftover}")

        is_full = any_billed and all_full
        is_partial = any_billed and not all_full
        if is_full:
            full_count += 1
        if is_partial:
            partial_count += 1
        payload = {
            "is_sale_billed": is_full,
            "is_partially_billed": is_partial,
            "billed_amount": round(order_billed_amount, 2),
        }
        try:
            supabase.table("sales_orders").update(payload).eq("id", order_id).execute()
        except Exception as e:
            print(f"Could not update billing flags for {number}: {e}")
            try:
                supabase.table("sales_orders").update(
                    {
                        "is_sale_billed": is_full or is_partial,
                        "is_partially_billed": is_partial,
                    }
                ).eq("id", order_id).execute()
            except Exception as inner:
                print(f"Could not update is_sale_billed for {number}: {inner}")

    print(f"Orders fully billed: {full_count}; partially billed: {partial_count}")


# =====================================================
# MAIN
# =====================================================

if __name__ == "__main__":

    try:

        print("Fetching sale bills from Tally...\n")

        sale_bills = get_sale_bills()

        print(f"\nFound {len(sale_bills)} sale bills.\n")

        print("Saving to Supabase...\n")

        save_sale_bills_to_supabase(sale_bills)

        print(f"Sale Bills synced successfully ({len(sale_bills)} records).")

    except Exception as e:

        print(f"\nSale Bill sync failed: {e}")

        raise
