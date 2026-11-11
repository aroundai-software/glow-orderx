from supabase import create_client
from src.config import load_config
import json

def check_db():
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])
    
    # Query tally_companies to see exactly how the name is spelled
    response = supabase.table("tally_companies").select("company_name").execute()
    print("--- COMPANIES IN DB ---")
    for row in response.data:
        print(f"'{row.get('company_name')}'")
        
    print("\n--- SAMPLE FROM CUSTOMERS TABLE ---")
    # Fetch 1 ledger from AL ZAHRA
    response = supabase.table("customers").select("company_name, customer_name").limit(5).execute()
    for row in response.data:
        print(f"Customer: '{row.get('customer_name')}', Company: '{row.get('company_name')}'")
        
if __name__ == "__main__":
    check_db()
