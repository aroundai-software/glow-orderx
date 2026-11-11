from supabase import create_client
from src.config import load_config
import uuid

def check_db():
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])
    
    gid = str(uuid.uuid4())
    
    try:
        supabase.table("customers").upsert(
            [{"Guid": gid, "MasterID": 999999, "customer_name": "TEST"}],
            on_conflict="MasterID,Guid"
        ).execute()
        print("MasterID,Guid WORKS!")
    except Exception as e:
        print(f"Error with MasterID,Guid: {e}")
        
    try:
        supabase.table("customers").delete().eq("Guid", gid).execute()
    except:
        pass
        
if __name__ == "__main__":
    check_db()
