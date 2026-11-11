import requests
import xmltodict
import json

# Test fetching stock items with FULLPRICELIST
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
                        <FETCH>NAME, GUID, MASTERID, PARENT, BASEUNITS, FULLPRICELIST.LIST, PRICELIST.LIST, STANDARDCOST, STANDARDPRICE</FETCH>
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
if isinstance(items, dict):
    items = [items]

print(f"Total Stock Items fetched: {len(items)}")

found_with_pricelist = []
for item in items:
    pl = item.get("FULLPRICELIST.LIST") or item.get("PRICELIST.LIST")
    if pl:
        found_with_pricelist.append(item)

print(f"Items with price list: {len(found_with_pricelist)}")

if found_with_pricelist:
    print("Sample Item with Price List:")
    print(json.dumps(found_with_pricelist[0], indent=2))
elif items:
    print("Sample Item keys:")
    print(items[0].keys())
    print(json.dumps(items[0], indent=2))
