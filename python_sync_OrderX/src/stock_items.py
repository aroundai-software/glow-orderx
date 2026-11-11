import logging
import re
import requests
import xmltodict
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

    value = re.sub(
        r"&#\d+;",
        "",
        value
    )

    return value.strip()


def get_text(value):

    if value is None:
        return ""

    if isinstance(value, list):

        if len(value) > 0:
            return get_text(value[0])

        return ""

    if isinstance(value, dict):

        return clean_text(
            value.get("#text", "")
        )

    return clean_text(value)


def safe_float(value, default=0):

    try:

        value = get_text(value)

        value = value.replace(",", "")

        match = re.search(
            r"-?\d+(\.\d+)?",
            value
        )

        if not match:
            return default

        return float(match.group())

    except Exception:

        return default


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def parse_tally_date(value):
    text = get_text(value)
    if not text:
        return None
    text = text.strip()
    for fmt in ("%Y%m%d", "%d-%b-%y", "%d-%b-%Y"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    return None


def latest_standard_selling_price(item):
    """Latest Standard Selling Price from Tally. Never use Standard Cost / Opening Rate."""
    dated = []
    for row in as_list(item.get("STANDARDPRICELIST.LIST")):
        if not isinstance(row, dict):
            continue
        rate = safe_float(row.get("RATE"), 0)
        if rate <= 0:
            continue
        dated.append((parse_tally_date(row.get("DATE")), rate))

    if dated:
        today = datetime.now().date()
        applicable = [row for row in dated if row[0] is not None and row[0] <= today]
        pool = applicable or [row for row in dated if row[0] is not None] or dated
        pool.sort(key=lambda row: (row[0] is None, row[0] or datetime.min.date()))
        return pool[-1][1]

    return safe_float(item.get("STANDARDPRICE"), 0)


def clean_tally_xml(xml_text):
    """Remove invalid XML character refs and fix stray ampersands."""

    xml_text = re.sub(
        r'&#(?:x[0-9A-Fa-f]+|\d+);',
        '',
        xml_text
    )

    xml_text = re.sub(
        r"&(?!amp;|lt;|gt;|quot;|apos;)",
        "&amp;",
        xml_text
    )

    return xml_text


# =====================================================
# TALLY FETCH
# =====================================================

_PRIMARY_STOCK_GROUP = "primary"


def get_stock_group_parents(tally_url):
    """Map each Tally stock group name to its parent (Under)."""
    xml_request = """
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Stock Group Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Stock Group Collection">
                        <TYPE>Stock Group</TYPE>
                        <FETCH>NAME, PARENT</FETCH>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""
    response = requests.post(
        tally_url,
        data=xml_request.encode("utf-8"),
        headers={"Content-Type": "application/xml", "Connection": "close"},
        timeout=120,
    )
    response.raise_for_status()

    try:
        data = xmltodict.parse(clean_tally_xml(response.text))
    except Exception as exc:
        logging.error("Error parsing Tally stock group XML: %s", exc)
        return {}

    collection = (
        data.get("ENVELOPE", {})
        .get("BODY", {})
        .get("DATA", {})
        .get("COLLECTION", {})
    )
    groups = collection.get("STOCKGROUP", [])
    if isinstance(groups, dict):
        groups = [groups]

    mapping = {}
    for group in groups:
        name = get_text(group.get("@NAME")) or get_text(group.get("NAME"))
        parent = get_text(group.get("PARENT")) or None
        if name:
            mapping[name] = parent
    return mapping


def resolve_item_category(item_parent, group_parents):
    """Immediate parent of the item's stock group. Skip Tally's Primary group."""
    if not item_parent:
        return None
    parent = (group_parents.get(item_parent) or "").strip()
    if not parent or parent.lower() == _PRIMARY_STOCK_GROUP:
        return None
    return parent


def get_closing_quantities(tally_url):
    """Fetch closing balance quantities via COMPUTE (computed field).
    Returns dict of {guid: closing_qty}."""
    xml_request = """<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>StockClosingBalance</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="StockClosingBalance">
                        <TYPE>Stock Item</TYPE>
                        <FETCH>NAME, GUID</FETCH>
                        <COMPUTE>ClQty : $$NumValue:$ClosingBalance</COMPUTE>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>"""
    try:
        response = requests.post(
            tally_url,
            data=xml_request.encode("utf-8"),
            headers={"Content-Type": "application/xml", "Connection": "close"},
            timeout=120,
        )
        response.raise_for_status()
        data = xmltodict.parse(clean_tally_xml(response.text))
        collection = (
            data.get("ENVELOPE", {})
            .get("BODY", {})
            .get("DATA", {})
            .get("COLLECTION", {})
        )
        items = collection.get("STOCKITEM", [])
        if isinstance(items, dict):
            items = [items]

        qty_map = {}
        for item in items:
            guid = get_text(item.get("GUID"))
            qty = safe_float(item.get("CLQTY"), 0)
            if guid:
                qty_map[guid] = qty
        logging.info(f"Fetched closing quantities for {len(qty_map)} stock items.")
        return qty_map
    except Exception as e:
        logging.error(f"Error fetching closing quantities: {e}")
        return {}


def get_stock_items():
    xml_request = """
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Stock Item Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Stock Item Collection">
                        <TYPE>Stock Item</TYPE>
                        <FETCH>NAME, MASTERID, GUID, PARENT, BASEUNITS, ADDITIONALUNITS, PARTNO, PARTNUMBER, ITEMCODE, MAILINGNAME.LIST, CATEGORY, HSNCODE, GSTHSN, DESCRIPTION, ADDITIONALDESCRIPTION, OPENINGBALANCE, OPENINGRATE, VATRATE, IGSTRATE, GSTDETAILS.LIST, HSNDETAILS.LIST, MRP, MAXIMUMRETAILPRICE, STANDARDPRICE, STANDARDPRICELIST.LIST, OPENINGVALUE, MINIMUMSALESPRICE, DISCOUNT, ISDELETED, LANGUAGENAME.LIST</FETCH>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""
    config = load_config()
    tally_url = f"http://localhost:{config['tally_port']}"
    group_parents = get_stock_group_parents(tally_url)
    closing_qty_map = get_closing_quantities(tally_url)

    response = requests.post(
        tally_url,
        data=xml_request.encode("utf-8"),
        headers={"Content-Type": "application/xml", "Connection": "close"},
        timeout=300
    )
    response.raise_for_status()
    response_text = clean_tally_xml(response.text)
    
    try:
        data = xmltodict.parse(response_text)
    except Exception as e:
        import logging
        logging.error(f"Error parsing Tally XML response: {e}")
        return []
        
    collection = data.get("ENVELOPE", {}).get("BODY", {}).get("DATA", {}).get("COLLECTION", {})
    stock_items = collection.get("STOCKITEM", [])
    
    if isinstance(stock_items, dict):
        stock_items = [stock_items]
        
    company_details = get_company_details()
    company_name = company_details.get("company_name", "")
    company_id = None
    try:
        supabase = create_client(config["supabase_url"], config["supabase_key"])
        resolved = resolve_company_row(supabase, company_details)
        if resolved:
            company_id = str(resolved.get("id") or "")
    except Exception as e:
        logging.info(f"Failed to fetch company_id: {e}")
    
    all_stock_items = []
    
    for item in stock_items:
        try:
            item_name = get_text(item.get("@NAME"))
            if not item_name:
                continue
                
            aliases = []
            language_list = item.get("LANGUAGENAME.LIST")
            if language_list:
                name_list = language_list.get("NAME.LIST")
                if isinstance(name_list, dict):
                    names = name_list.get("NAME", [])
                    if not isinstance(names, list):
                        names = [names]
                    aliases = [clean_text(x) for x in names if clean_text(x)]
            aliases = [a for a in aliases if a != item_name]
            
            master_id_raw = get_text(item.get("MASTERID"))
            try:
                master_id_val = int(master_id_raw) if master_id_raw else None
            except ValueError:
                master_id_val = None

            # Extract GST Rate
            gst_rate = safe_float(item.get("IGSTRATE")) or safe_float(item.get("VATRATE"), 0)
            if gst_rate == 0:
                gst_details_list = item.get("GSTDETAILS.LIST")
                if gst_details_list:
                    if isinstance(gst_details_list, list):
                        gst_details_list = gst_details_list[-1]
                    statewise_list = gst_details_list.get("STATEWISEDETAILS.LIST")
                    if statewise_list:
                        if isinstance(statewise_list, list):
                            statewise_list = statewise_list[-1]
                        rate_details_list = statewise_list.get("RATEDETAILS.LIST", [])
                        if not isinstance(rate_details_list, list):
                            rate_details_list = [rate_details_list]
                        for rate_detail in rate_details_list:
                            duty_head = get_text(rate_detail.get("GSTRATEDUTYHEAD"))
                            if duty_head == "IGST":
                                gst_rate = safe_float(rate_detail.get("GSTRATE"), 0)
                                break

            # Extract HSN Code
            hsn_code = get_text(item.get("HSNCODE")) or get_text(item.get("GSTHSN"))
            if not hsn_code:
                hsn_details_list = item.get("HSNDETAILS.LIST")
                if hsn_details_list:
                    if isinstance(hsn_details_list, list):
                        hsn_details_list = hsn_details_list[-1]
                    hsn_code = get_text(hsn_details_list.get("HSNCODE"))

            item_parent = get_text(item.get("PARENT")) or None
            row = {
                "company_name": company_name,
                "company_id": company_id,
                "ItemName": item_name,
                "PartNumber": get_text(item.get("PARTNO")) or get_text(item.get("PARTNUMBER")) or get_text(item.get("ITEMCODE")) or get_text((item.get("MAILINGNAME.LIST") or {}).get("MAILINGNAME")),
                "ItemUnit": get_text(item.get("BASEUNITS")) or "Nos",
                "ItemAltUnit": get_text(item.get("ADDITIONALUNITS")) or None,
                "ItemParent": item_parent,
                "ItemCategory": resolve_item_category(item_parent, group_parents),
                "ItemAlias": aliases[0] if len(aliases) > 0 else None,
                "ItemAlias1": aliases[1] if len(aliases) > 1 else None,
                "ItemAlias2": aliases[2] if len(aliases) > 2 else None,
                "ItemAlias3": aliases[3] if len(aliases) > 3 else None,
                "hsn": hsn_code or None,
                "description": get_text(item.get("DESCRIPTION")) or get_text(item.get("ADDITIONALDESCRIPTION")) or None,
                "ItemQuantity": closing_qty_map.get(get_text(item.get("GUID")), 0),
                "ItemRate": latest_standard_selling_price(item),
                "GstRate": gst_rate,
                "MRP": safe_float(item.get("MRP")) or safe_float(item.get("MAXIMUMRETAILPRICE")),
                "floor_rate": safe_float(item.get("MINIMUMSALESPRICE")),
                "offer_discount_percentage": safe_float(item.get("DISCOUNT"), 0),
                "is_active": get_text(item.get("ISDELETED")) != "Yes",
                "Guid": get_text(item.get("GUID")),
                "MasterID": master_id_val,
                "parent_id": None,
                "image_url": None,
                "image_path": None,
                "ComboStartDate": None,
                "ComboEndDate": None,
                "ComboQtyOffTake": None,
                "SpecialStartDate": None,
                "SpecialEndDate": None,
                "SpecialDiscount": None,
            }
            all_stock_items.append(row)
        except Exception as e:
            import logging
            logging.error(f"Error parsing stock item: {e}")
            
    return all_stock_items

def save_stock_items_to_supabase(stock_items):

    config = load_config()

    supabase = create_client(
        config["supabase_url"],
        config["supabase_key"]
    )

    if not stock_items:
        logging.info("No stock items found.")
        return 0

    BATCH_SIZE = 50
    total_saved = 0
    batches = [stock_items[i: i + BATCH_SIZE] for i in range(0, len(stock_items), BATCH_SIZE)]

    for batch_idx, batch in enumerate(batches, start=1):
        try:
            supabase.table("products").upsert(
                batch,
                on_conflict="MasterID,Guid"
            ).execute()
            total_saved += len(batch)
        except Exception as e:
            logging.error(f"Batch {batch_idx} upload failed: {e}. Retrying row by row...")
            for row in batch:
                try:
                    supabase.table("products").upsert(
                        [row],
                        on_conflict="MasterID,Guid"
                    ).execute()
                    total_saved += 1
                except Exception as row_err:
                    logging.error(f"Failed to upsert item {row.get('ItemName')}: {row_err}")

    logging.info(f"Saved {total_saved} of {len(stock_items)} stock items to Supabase.")
    return total_saved


# =====================================================
# MAIN
# =====================================================

if __name__ == "__main__":

    try:
        print("Fetching stock items from Tally...\n")

        stock_items = get_stock_items()

        print(f"Found {len(stock_items)} stock items.\n")

        print("Saving to Supabase...\n")

        saved = save_stock_items_to_supabase(stock_items)

        print(f"Stock Items synced successfully ({saved} records).")
    except Exception as e:
        print(f"\nStock items sync failed: {e}")
        import logging
        logging.error(f"Stock items sync failed: {e}")