import sys
sys.path.insert(0, '.')
from src.tally_client import TallyClient
from src.stock_items import clean_tally_xml
import xmltodict

client = TallyClient()
xml = """<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>Company Info</ID></HEADER>
  <BODY><DESC><TDL><TDLMESSAGE><COLLECTION NAME="Company Info"><TYPE>Company</TYPE><FETCH>NAME, STARTINGFROM, ENDINGAT, BOOKSFROM</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY>
</ENVELOPE>"""
res = client.send_request(xml)
print("Company Info:", res)
