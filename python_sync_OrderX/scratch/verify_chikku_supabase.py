from src.config import load_config
from supabase import create_client
import json

config = load_config()
supabase = create_client(config["supabase_url"], config["supabase_key"])

res = supabase.table("price_level").select("*").eq("product_name", "K24SCRG_2750(1) Chikku").order("from_qty").execute()
print(f"Total rows in Supabase for Chikku: {len(res.data)}")
print(json.dumps(res.data, indent=2))
