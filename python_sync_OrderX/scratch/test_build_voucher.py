import sys
sys.path.insert(0, '.')
from src.config import load_config
from supabase import create_client
from src.tally_client import TallyClient
from src.sales_orders_to_tally import (
    _build_voucher_xml,
    _fetch_items_and_products,
    _fetch_customers,
    _parse_import_result,
    _resolve_sales_ledger
)

cfg = load_config()
sb = create_client(cfg['supabase_url'], cfg['supabase_key'])
client = TallyClient()

# Load order
so = sb.table('sales_orders').select('*').eq('id', 'ee3e31ec-e628-4a57-83f4-eedb4680d1e7').execute().data[0]
items_by_order, products_by_id = _fetch_items_and_products(sb, [so])
items = items_by_order.get(so['id'], [])
customers = _fetch_customers(sb, [so])
customer = customers.get(str(so.get('customer_id')))

print("Customer:", customer)
print("Items:", items)
print("Product in products_by_id:", products_by_id)

sales_ledger = _resolve_sales_ledger(client)
print("Sales ledger:", sales_ledger)
