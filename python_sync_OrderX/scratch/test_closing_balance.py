"""Test: Use COMPUTE in Collection TDL to get closing balance."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import requests
import xmltodict
from src.config import load_config
from src.stock_items import clean_tally_xml

config = load_config()
tally_url = f"http://localhost:{config['tally_port']}"

# Use COMPUTE to calculate closing balance
xml = """<ENVELOPE>
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
                        <COMPUTE>ClBal : $$String:$ClosingBalance</COMPUTE>
                        <COMPUTE>ClQty : $$NumValue:$ClosingBalance</COMPUTE>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>"""

try:
    resp = requests.post(tally_url, data=xml.encode("utf-8"),
                         headers={"Content-Type": "application/xml"}, timeout=60)
    
    # Print raw response first
    print("Raw response (first 3000 chars):")
    print(resp.text[:3000])
    print()
    
    data = xmltodict.parse(clean_tally_xml(resp.text))
    collection = data.get("ENVELOPE", {}).get("BODY", {}).get("DATA", {}).get("COLLECTION", {})
    
    items = collection.get("STOCKITEM", [])
    if isinstance(items, dict):
        items = [items]
    
    print(f"Total items: {len(items)}")
    if items:
        # Print first 5 items with ALL their keys
        for item in items[:5]:
            print(f"\n  Keys: {list(item.keys())}")
            name = item.get("@NAME") or item.get("NAME")
            clbal = item.get("CLBAL")
            clqty = item.get("CLQTY")
            print(f"  {name}: CLBAL={clbal!r}, CLQTY={clqty!r}")
    else:
        print(f"  Collection keys: {list(collection.keys()) if collection else 'empty'}")
except Exception as e:
    print(f"ERROR: {e}")
    import traceback
    traceback.print_exc()
