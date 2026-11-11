import requests
import xmltodict
import json
from src.config import load_config
from supabase import create_client

# 1. Fetch from Tally
xml_request = """
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>ItemCheck</ID>
    </HEADER>
    <BODY>
        <DESC>
            <STATICVARIABLES>
                <SVCURRENTCOMPANY>VESTARA</SVCURRENTCOMPANY>
            </STATICVARIABLES>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="ItemCheck">
                        <TYPE>Stock Item</TYPE>
                        <FETCH>NAME, GUID, MASTERID, PARENT, BASEUNITS, FULLPRICELIST.LIST, PRICELIST.LIST, STANDARDCOST, STANDARDPRICE</FETCH>
                        <FILTER>NameFilter</FILTER>
                    </COLLECTION>
                    <SYSTEM TYPE="Formulae" NAME="NameFilter">$$IsEqual:$NAME:"K2(b)SCRG_2749(3) Grey"</SYSTEM>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""

res = requests.post("http://localhost:9000", data=xml_request.encode('utf-8'), headers={"Content-Type": "application/xml"})
data = xmltodict.parse(res.text)
item = data.get("ENVELOPE", {}).get("BODY", {}).get("DATA", {}).get("COLLECTION", {}).get("STOCKITEM", {})

print("=== TALLY RAW SLABS ===")
pl = item.get("FULLPRICELIST.LIST", {})
slabs = pl.get("PRICELEVELLIST.LIST", [])
print(json.dumps(slabs, indent=2))
print("Cost Price in Tally:", item.get("STANDARDCOST"))

# 2. Fetch from Supabase
config = load_config()
supabase = create_client(config["supabase_url"], config["supabase_key"])
rows = supabase.table("price_level").select("*").eq("product_name", "K2(b)SCRG_2749(3) Grey").order("from_qty").execute()

print("\n=== SUPABASE ROWS ===")
for r in rows.data:
    print(f"Slab (from {r['from_qty']} to {r['less_than_qty']}): Rate = Rs. {r['rate']}/MTR, Cost = Rs. {r['cost_price']}")
