import sys
sys.path.insert(0, '.')
from src.config import load_config
from supabase import create_client
import requests
import xmltodict
from src.stock_items import clean_tally_xml
from src.sales_orders_to_tally import _build_voucher_xml, _resolve_sales_ledger, _fetch_items_and_products, _fetch_customers, _line_amount_and_rate
from src.tally_client import TallyClient

cfg = load_config()
sb = create_client(cfg['supabase_url'], cfg['supabase_key'])
client = TallyClient()

# 1. Fetch order ORD20263083
so = sb.table('sales_orders').select('*').eq('id', 'ee3e31ec-e628-4a57-83f4-eedb4680d1e7').execute().data[0]
print("SO:", so['order_number'], so['customer_name'], so['company_name'])

items_by_order, products_by_id = _fetch_items_and_products(sb, [so])
items = items_by_order.get(so['id'], [])
print("Items count:", len(items))
for it in items:
    q, up, dp, tx = _line_amount_and_rate(it)
    print("Item:", it.get('product_name'), "qty:", q, "unit_price:", up, "disc_pct:", dp, "taxable:", tx)

# 2. Check all ledgers in Tally
url = f"http://localhost:{cfg['tally_port']}"
xml = """<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>Ledger List</ID></HEADER>
  <BODY><DESC><TDL><TDLMESSAGE><COLLECTION NAME="Ledger List"><TYPE>Ledger</TYPE><FETCH>NAME, PARENT, TAXTYPE</FETCH></COLLECTION></TDLMESSAGE></TDL></DESC></BODY>
</ENVELOPE>"""
r = requests.post(url, data=xml.encode('utf-8'))
data = xmltodict.parse(clean_tally_xml(r.text))
leds = data.get('ENVELOPE', {}).get('BODY', {}).get('DATA', {}).get('COLLECTION', {}).get('LEDGER', [])
if isinstance(leds, dict):
    leds = [leds]
all_led_names = [l.get('@NAME') for l in leds if l.get('@NAME')]
print("Tally ledgers:", all_led_names)
