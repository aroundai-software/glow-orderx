from supabase import create_client
from src.config import load_config
import uuid

def check_db():
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])
    
    try:
        supabase.table("customers").upsert(
            [{"Guid": str(uuid.uuid4()), "customer_name": "TEST"}],
            on_conflict="Guid"
        ).execute()
        print("Guid WORKS!")
    except Exception as e:
        print(f"Error with Guid: {e}")
        
if __name__ == "__main__":
    check_db()
