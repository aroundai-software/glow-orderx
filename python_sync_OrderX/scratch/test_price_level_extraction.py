import requests
import xmltodict
import json
import re

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
                        <FETCH>NAME, GUID, MASTERID, PARENT, BASEUNITS, FULLPRICELIST.LIST, STANDARDCOST, STANDARDPRICE</FETCH>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""

res = requests.post("http://localhost:9000", data=xml_request.encode('utf-8'), headers={"Content-Type": "application/xml"})
data = xmltodict.parse(res.text)
items = data.get("ENVELOPE", {}).get("BODY", {}).get("DATA", {}).get("COLLECTION", {}).get("STOCKITEM", [])

price_level_rows = []

def clean_text(v):
    if v is None: return ""
    if isinstance(v, dict): return str(v.get("#text", "")).strip()
    if isinstance(v, list): return clean_text(v[0]) if v else ""
    return str(v).strip()

def safe_float(v):
    text = clean_text(v).replace(",", "")
    m = re.search(r"-?\d+(\.\d+)?", text)
    return float(m.group()) if m else 0.0

def safe_unit(v, default="PCS"):
    text = clean_text(v)
    if "/" in text:
        parts = text.split("/")
        if len(parts) > 1 and parts[1].strip():
            return parts[1].strip()
    return default

for item in items:
    name = clean_text(item.get("@NAME") or item.get("NAME"))
    guid = clean_text(item.get("GUID"))
    master_id = int(safe_float(item.get("MASTERID"))) if item.get("MASTERID") else None
    parent = clean_text(item.get("PARENT")) or "All Items"
    base_unit = clean_text(item.get("BASEUNITS")) or "PCS"
    cost_price = safe_float(item.get("STANDARDCOST"))
    
    pl_list = item.get("FULLPRICELIST.LIST") or item.get("PRICELIST.LIST")
    if not pl_list:
        continue
    if isinstance(pl_list, dict):
        pl_list = [pl_list]
        
    for pl in pl_list:
        p_level = clean_text(pl.get("PRICELEVEL")) or "Sales"
        date_str = clean_text(pl.get("DATE"))
        # Parse date YYYYMMDD
        applicable_from = f"{date_str[:4]}-{date_str[4:6]}-{date_str[6:8]}" if len(date_str) == 8 else date_str
        
        slabs = pl.get("PRICELEVELLIST.LIST") or []
        if isinstance(slabs, dict):
            slabs = [slabs]
            
        if not slabs:
            # Single price with no slabs
            rate = safe_float(pl.get("RATE"))
            unit = safe_unit(pl.get("RATE"), base_unit)
            disc = safe_float(pl.get("DISCOUNT"))
            price_level_rows.append({
                "price_level": p_level,
                "under_group": parent,
                "applicable_from": applicable_from,
                "product_name": name,
                "from_qty": 0.0,
                "less_than_qty": None,
                "rate": rate,
                "unit": unit,
                "discount_percentage": disc,
                "cost_price": cost_price,
                "Guid": guid,
                "MasterID": master_id
            })
        else:
            for s in slabs:
                from_q = safe_float(s.get("STARTINGFROM") or s.get("STARTINGAT") or s.get("FROMQTY"))
                to_q = safe_float(s.get("ENDINGAT") or s.get("LESSTHAN") or s.get("TOQTY")) if (s.get("ENDINGAT") or s.get("LESSTHAN") or s.get("TOQTY")) else None
                rate = safe_float(s.get("RATE"))
                unit = safe_unit(s.get("RATE"), base_unit)
                disc = safe_float(s.get("DISCOUNT"))
                
                price_level_rows.append({
                    "price_level": p_level,
                    "under_group": parent,
                    "applicable_from": applicable_from,
                    "product_name": name,
                    "from_qty": from_q,
                    "less_than_qty": to_q,
                    "rate": rate,
                    "unit": unit,
                    "discount_percentage": disc,
                    "cost_price": cost_price,
                    "Guid": guid,
                    "MasterID": master_id
                })

print(f"Total price level rows extracted: {len(price_level_rows)}")
print("First 5 rows:")
print(json.dumps(price_level_rows[:5], indent=2))
