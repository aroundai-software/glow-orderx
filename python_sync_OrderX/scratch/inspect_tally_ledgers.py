import sys
sys.path.insert(0, '.')
from src.config import load_config
import requests
import xmltodict

cfg = load_config()
url = f"http://localhost:{cfg['tally_port']}"
xml = """<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>Ledger List</ID></HEADER>
  <BODY><DESC><TDL><TDLMESSAGE><COLLECTION NAME="Ledger List"><TYPE>Ledger</TYPE><FETCH>NAME, PARENT, TAXTYPE</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY>
</ENVELOPE>"""
r = requests.post(url, data=xml.encode('utf-8'))
from src.stock_items import clean_tally_xml
data = xmltodict.parse(clean_tally_xml(r.text))
leds = data.get('ENVELOPE', {}).get('BODY', {}).get('DATA', {}).get('COLLECTION', {}).get('LEDGER', [])
if isinstance(leds, dict):
    leds = [leds]
print(f"Total ledgers in Tally: {len(leds)}")
for l in leds:
    print(f"  Name: {l.get('@NAME')} | Parent: {l.get('PARENT')} | TaxType: {l.get('TAXTYPE')}")
