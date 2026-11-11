import sys
sys.path.insert(0, '.')
from src.config import load_config
from supabase import create_client
import requests
import xmltodict
import re
from src.stock_items import clean_tally_xml
from src.tally_client import TallyClient

cfg = load_config()
client = TallyClient()

# Get all ledgers from Tally with their parent group and tax type
xml = """<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>All Ledgers</ID></HEADER>
  <BODY><DESC><TDL><TDLMESSAGE><COLLECTION NAME="All Ledgers"><TYPE>Ledger</TYPE><FETCH>NAME, PARENT, TAXTYPE, GSTDUTYHEAD</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY>
</ENVELOPE>"""
r = requests.post(f"http://localhost:{cfg['tally_port']}", data=xml.encode('utf-8'))
data = xmltodict.parse(clean_tally_xml(r.text))
leds = data.get('ENVELOPE', {}).get('BODY', {}).get('DATA', {}).get('COLLECTION', {}).get('LEDGER', [])
if isinstance(leds, dict):
    leds = [leds]

print(f"Total ledgers: {len(leds)}")
ledger_names = [l.get('@NAME') for l in leds if l.get('@NAME')]
print("Ledgers:", ledger_names)

def find_ledger(patterns, default=None):
    for pat in patterns:
        for name in ledger_names:
            if re.search(pat, name, re.IGNORECASE):
                return name
    return default

cgst_ledger = find_ledger([r'^output\s*cgst', r'cgst.*output', r'^cgst$'], default="OUTPUT CGST" if "OUTPUT CGST" in ledger_names else "CGST")
sgst_ledger = find_ledger([r'^output\s*sgst', r'sgst.*output', r'^sgst$'], default="OUTPUT SGST" if "OUTPUT SGST" in ledger_names else "SGST")
igst_ledger = find_ledger([r'^output\s*igst', r'igst.*output', r'^igst$'], default="OUTPUT IGST" if "OUTPUT IGST" in ledger_names else "IGST")
round_off_ledger = find_ledger([r'^round\s*off', r'rounding'], default="Round Off" if "Round Off" in ledger_names else None)
discount_ledger = find_ledger([r'discount\s*given', r'^discount', r'discount\s*allowed'], default="Discount Given" if "Discount Given" in ledger_names else None)

print(f"Resolved CGST: {cgst_ledger}")
print(f"Resolved SGST: {sgst_ledger}")
print(f"Resolved IGST: {igst_ledger}")
print(f"Resolved Round Off: {round_off_ledger}")
print(f"Resolved Discount: {discount_ledger}")
