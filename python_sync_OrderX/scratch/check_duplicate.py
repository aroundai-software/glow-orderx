from supabase import create_client
from src.config import load_config
import uuid

def check_db():
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])
    
    gid = str(uuid.uuid4())
    
    try:
        # Insert once
        supabase.table("customers").insert([{"Guid": gid, "company_name": "TEST", "customer_name": "TEST"}]).execute()
        # Insert duplicate
        supabase.table("customers").insert([{"Guid": gid, "company_name": "TEST", "customer_name": "TEST2"}]).execute()
    except Exception as e:
        print(f"Duplicate Error: {e}")
        
    try:
        supabase.table("customers").delete().eq("Guid", gid).execute()
    except:
        pass
        
if __name__ == "__main__":
    check_db()
