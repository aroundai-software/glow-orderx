from src.config import load_config
from supabase import create_client
import json

config = load_config()
supabase = create_client(config["supabase_url"], config["supabase_key"])

res = supabase.table("price_level").select("*").eq("product_name", "K37SALA_865/F(2) Purple").order("from_qty").execute()
print(f"Total rows in Supabase: {len(res.data)}")
for r in res.data:
    print(f"from_qty: {r['from_qty']}, less_than_qty: {r['less_than_qty']}, rate: {r['rate']}, cost: {r['cost_price']}")
