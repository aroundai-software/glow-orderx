import requests
import xmltodict

xml = """<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Company Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Company Collection">
                        <TYPE>Company</TYPE>
                        <FETCH>*, MOBILENO, MASTERID</FETCH>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>"""

r = requests.post(
    "http://localhost:9000",
    data=xml.encode("utf-8"),
    headers={"Content-Type": "application/xml"},
    timeout=60,
)
print("status", r.status_code, "len", len(r.text))
data = xmltodict.parse(r.text)
col = data.get("ENVELOPE", {}).get("BODY", {}).get("DATA", {}).get("COLLECTION", {})
c = col.get("COMPANY")
if isinstance(c, list):
    c = c[0]
print("type", type(c))
if isinstance(c, dict):
    print("NAME", c.get("NAME"))
    print("@NAME", c.get("@NAME"))
    guid = c.get("GUID")
    print("GUID", str(guid)[:120] if guid is not None else None)
    print("keys", list(c.keys())[:20])
