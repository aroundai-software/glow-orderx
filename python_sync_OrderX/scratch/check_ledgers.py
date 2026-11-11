from supabase import create_client
from src.config import load_config
import json

def check_db():
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])
    
    # Fetch 5 ledgers (customers) to verify
    response = supabase.table("customers").select("*").limit(5).execute()
    
    print("--- FIRST 5 LEDGERS IN DATABASE ---")
    if not response.data:
        print("No ledgers found in 'customers' table!")
    else:
        for i, row in enumerate(response.data):
            print(f"Customer {i+1}:")
            print(f"  ID: {row.get('id')}")
            print(f"  Name: {row.get('customer_name')}")
            print(f"  Company Name: {row.get('company_name')}")
            print(f"  Company ID: {row.get('company_id')}")
            print(f"  GST: {row.get('gst_number')}")
            print(f"  City: {row.get('city')}")
            print(f"  Mobile: {row.get('mobile_number')}")
            print(f"  Guid: {row.get('Guid')}")
            print("-" * 40)
            
if __name__ == "__main__":
    check_db()
