import logging
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


def safe_float(value, default=0.0):
    try:
        value = get_text(value)
        value = value.replace(",", "")
        match = re.search(r"-?\d+(\.\d+)?", value)
        if not match:
            return default
        return float(match.group())
    except Exception:
        return default


def safe_unit(value, default="PCS"):
    """Extract unit from rate string like '1270.00/MTR' or '10.00/PCS'."""
    text = get_text(value)
    if "/" in text:
        parts = text.split("/")
        if len(parts) > 1 and parts[1].strip():
            return parts[1].strip()
    return default


def parse_tally_date(value):
    text = get_text(value)
    if not text:
        return None
    text = text.strip()
    for fmt in ("%Y%m%d", "%d-%b-%y", "%d-%b-%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(text, fmt).date().isoformat()
        except ValueError:
            continue
    return None


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def clean_tally_xml(xml_text):
    """Remove invalid XML character refs and fix stray ampersands."""
    if not xml_text:
        return ""
    xml_text = xml_text.replace('encoding="utf-16"', 'encoding="utf-8"')
    xml_text = xml_text.replace('\x00', '')
    xml_text = re.sub(r'&#(?:x[0-9A-Fa-f]+|\d+);', '', xml_text)
    xml_text = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;)", "&amp;", xml_text)
    return xml_text


# =====================================================
# TALLY FETCH & EXTRACTION
# =====================================================

def get_price_levels():
    """
    Extracts all Price Lists / Price Levels and per-meter/quantity slabs from Tally.
    """
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])

    company_data = get_company_details()
    company_id = None
    company_name = None

    if company_data:
        company_name = company_data.get("company_name")
        company_row = resolve_company_row(supabase, company_data=company_data)
        if company_row:
            company_id = company_row.get("id")
            company_name = company_row.get("company_name") or company_name

    # Build product lookup from Supabase (Guid -> product_id, ItemName -> product_id)
    product_guid_map = {}
    product_name_map = {}
    try:
        query = supabase.table("products").select("id, Guid, ItemName")
        if company_id:
            query = query.eq("company_id", company_id)
        products_res = query.execute()
        for p in (products_res.data or []):
            p_id = p.get("id")
            if p.get("Guid"):
                product_guid_map[p.get("Guid")] = p_id
            if p.get("ItemName"):
                product_name_map[p.get("ItemName")] = p_id
    except Exception as e:
        logging.warning(f"Could not load products map for price level: {e}")

    xml_request = """
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>PriceList Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="PriceList Collection">
                        <TYPE>Stock Item</TYPE>
                        <FETCH>NAME, GUID, MASTERID, PARENT, BASEUNITS, ADDITIONALUNITS, FULLPRICELIST.LIST, PRICELIST.LIST, STANDARDCOST, STANDARDPRICE, STANDARDPRICELIST.LIST</FETCH>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""

    tally_url = f"http://localhost:{config.get('tally_port', 9000)}"

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
        logging.error(f"Error parsing PriceList XML: {e}")
        return []

    collection = (
        data.get("ENVELOPE", {})
        .get("BODY", {})
        .get("DATA", {})
        .get("COLLECTION", {})
    )
    items = collection.get("STOCKITEM", [])
    if isinstance(items, dict):
        items = [items]

    all_price_levels = []
    serial_no = 1
    now_iso = datetime.now(timezone.utc).isoformat()
    today_iso = datetime.now(timezone.utc).date().isoformat()

    for item in items:
        try:
            item_name = get_text(item.get("@NAME") or item.get("NAME"))
            if not item_name:
                continue

            guid = get_text(item.get("GUID"))
            master_id = int(safe_float(item.get("MASTERID"))) if item.get("MASTERID") else None
            under_group = get_text(item.get("PARENT")) or "All Items"
            base_unit = get_text(item.get("BASEUNITS")) or "PCS"
            cost_price = safe_float(item.get("STANDARDCOST"), 0.0)

            product_id = product_guid_map.get(guid) or product_name_map.get(item_name)

            # Historical / As on comparison rates from STANDARDPRICELIST
            as_on_date = None
            as_on_rate = 0.0
            for sp in as_list(item.get("STANDARDPRICELIST.LIST")):
                if isinstance(sp, dict):
                    sp_rate = safe_float(sp.get("RATE"), 0.0)
                    sp_date = parse_tally_date(sp.get("DATE"))
                    if sp_rate > 0:
                        as_on_date = sp_date
                        as_on_rate = sp_rate

            # Check for Price List definitions
            pl_lists = as_list(item.get("FULLPRICELIST.LIST") or item.get("PRICELIST.LIST"))
            if not pl_lists:
                continue

            for pl in pl_lists:
                if not isinstance(pl, dict):
                    continue

                price_level_name = get_text(pl.get("PRICELEVEL")) or "Sales"
                applicable_from = parse_tally_date(pl.get("DATE") or pl.get("APPLICABLEFROM")) or today_iso

                # Extract quantity slabs (e.g. 0-5 MTR, 5-10 MTR, 10+ MTR)
                slabs = as_list(pl.get("PRICELEVELLIST.LIST"))
                
                if not slabs:
                    # Single price level entry without multiple slabs
                    rate_val = safe_float(pl.get("RATE"), 0.0)
                    unit_val = safe_unit(pl.get("RATE"), base_unit)
                    disc_val = safe_float(pl.get("DISCOUNT"), 0.0)

                    row = {
                        "price_level": price_level_name,
                        "under_group": under_group,
                        "applicable_from": applicable_from,
                        "s_no": serial_no,
                        "product_id": product_id,
                        "product_name": item_name,
                        "from_qty": 0.0,
                        "less_than_qty": None,
                        "rate": rate_val,
                        "unit": unit_val,
                        "discount_percentage": disc_val,
                        "as_on_date": as_on_date,
                        "as_on_rate": as_on_rate,
                        "as_on_disc_percentage": 0.0,
                        "cost_price": cost_price,
                        "company_id": company_id,
                        "company_name": company_name,
                        "Guid": guid,
                        "MasterID": master_id,
                        "is_active": True,
                        "updated_at": now_iso
                    }
                    all_price_levels.append(row)
                else:
                    for slab in slabs:
                        if not isinstance(slab, dict):
                            continue

                        from_qty = safe_float(slab.get("STARTINGFROM") or slab.get("STARTINGAT") or slab.get("FROMQTY"), 0.0)
                        
                        ending_raw = slab.get("ENDINGAT") or slab.get("LESSTHAN") or slab.get("TOQTY")
                        less_than_qty = safe_float(ending_raw) if ending_raw else None

                        slab_rate = safe_float(slab.get("RATE"), 0.0)
                        slab_unit = safe_unit(slab.get("RATE"), base_unit)
                        slab_disc = safe_float(slab.get("DISCOUNT"), 0.0)

                        row = {
                            "price_level": price_level_name,
                            "under_group": under_group,
                            "applicable_from": applicable_from,
                            "s_no": serial_no,
                            "product_id": product_id,
                            "product_name": item_name,
                            "from_qty": from_qty,
                            "less_than_qty": less_than_qty,
                            "rate": slab_rate,
                            "unit": slab_unit,
                            "discount_percentage": slab_disc,
                            "as_on_date": as_on_date,
                            "as_on_rate": as_on_rate,
                            "as_on_disc_percentage": 0.0,
                            "cost_price": cost_price,
                            "company_id": company_id,
                            "company_name": company_name,
                            "Guid": guid,
                            "MasterID": master_id,
                            "is_active": True,
                            "updated_at": now_iso
                        }
                        all_price_levels.append(row)

            serial_no += 1

        except Exception as e:
            logging.error(f"Error parsing price level item {item.get('@NAME')}: {e}")

    return all_price_levels


# =====================================================
# SUPABASE SAVE
# =====================================================

def save_price_levels_to_supabase(price_levels):
    """
    Clears existing price_level records for this company and inserts freshly extracted slabs.
    """
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])

    if not price_levels:
        logging.info("No price level records to save.")
        return 0

    company_id = price_levels[0].get("company_id")
    company_name = price_levels[0].get("company_name")

    # Clear old price levels for this company to avoid orphaned/outdated slabs
    try:
        if company_id:
            logging.info(f"Clearing old price levels for company_id: {company_id}...")
            supabase.table("price_level").delete().eq("company_id", company_id).execute()
        elif company_name:
            logging.info(f"Clearing old price levels for company_name: {company_name}...")
            supabase.table("price_level").delete().eq("company_name", company_name).execute()
    except Exception as e:
        logging.error(f"Failed to clear old price levels: {e}")
        raise

    BATCH_SIZE = 100
    total_saved = 0
    batches = [price_levels[i: i + BATCH_SIZE] for i in range(0, len(price_levels), BATCH_SIZE)]

    def upload_batch(batch):
        try:
            supabase.table("price_level").insert(batch).execute()
            return len(batch)
        except Exception as e:
            logging.error(f"Price level batch upload failed: {e}")
            return 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        results = executor.map(upload_batch, batches)
        total_saved = sum(results)

    return total_saved


# =====================================================
# DIRECT EXECUTION TEST
# =====================================================

if __name__ == "__main__":
    try:
        print("Fetching Price Levels from Tally...\n")
        records = get_price_levels()
        print(f"Found {len(records)} price level slab records.\n")

        print("Saving to Supabase 'price_level' table...\n")
        saved = save_price_levels_to_supabase(records)
        print(f"Price Levels synced successfully ({saved} records).")
    except Exception as e:
        print(f"\nPrice level sync failed: {e}")
        logging.error(f"Price level sync failed: {e}")
