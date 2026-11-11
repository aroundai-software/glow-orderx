import sys
sys.path.insert(0, '.')
from src.config import load_config
from src.tally_client import TallyClient
import xmltodict
from src.stock_items import clean_tally_xml

client = TallyClient()
xml = """<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>Godowns</ID></HEADER>
  <BODY><DESC><TDL><TDLMESSAGE><COLLECTION NAME="Godowns"><TYPE>Godown</TYPE><FETCH>NAME</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY>
</ENVELOPE>"""
res = client.send_request(xml)
print("Raw godown response:", res)
