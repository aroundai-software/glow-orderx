import requests
import json
from src.config import load_config

def get_openapi_spec():
    config = load_config()
    headers = {
        "apikey": config["supabase_key"],
        "Authorization": f"Bearer {config['supabase_key']}"
    }
    url = f"{config['supabase_url']}/rest/v1/"
    response = requests.get(url, headers=headers)
    spec = response.json()
    
    with open("scratch/openapi.json", "w") as f:
        json.dump(spec, f, indent=2)
        
    print("Saved OpenAPI spec to scratch/openapi.json")

if __name__ == "__main__":
    get_openapi_spec()
