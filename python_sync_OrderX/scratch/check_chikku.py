import requests
import xmltodict
import json

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
                        <FETCH>NAME, GUID, MASTERID, PARENT, BASEUNITS, FULLPRICELIST.LIST, PRICELIST.LIST, STANDARDCOST, STANDARDPRICE, OPENINGBALANCE, OPENINGRATE, OPENINGVALUE</FETCH>
                        <FILTER>NameFilter</FILTER>
                    </COLLECTION>
                    <SYSTEM TYPE="Formulae" NAME="NameFilter">$$IsEqual:$NAME:"K24SCRG_2750(1) Chikku"</SYSTEM>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""

res = requests.post("http://localhost:9000", data=xml_request.encode('utf-8'), headers={"Content-Type": "application/xml"})
data = xmltodict.parse(res.text)
item = data.get("ENVELOPE", {}).get("BODY", {}).get("DATA", {}).get("COLLECTION", {}).get("STOCKITEM", {})

print("Tally Raw Item:")
print(json.dumps(item, indent=2))
