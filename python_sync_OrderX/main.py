import time
import logging
import socket
from datetime import datetime, timezone
import sys
import os


def application_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


application_path = application_dir()
log_file = os.path.join(application_path, "sync.log")


class _FlushFileHandler(logging.FileHandler):
    """Write each line to sync.log immediately so the file is visible while the service runs."""

    def emit(self, record):
        super().emit(record)
        self.flush()


def setup_logging():
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    for handler in list(root.handlers):
        root.removeHandler(handler)
    formatter = logging.Formatter("[%(asctime)s] %(message)s", datefmt="%b %d %I:%M %p")
    file_handler = _FlushFileHandler(log_file, encoding="utf-8")
    file_handler.setFormatter(formatter)
    root.addHandler(file_handler)
    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(formatter)
    root.addHandler(console)
    logging.info("Log file: %s", log_file)


setup_logging()

try:
    from src.config import load_config
    from supabase import create_client

    import src.tally_companies as tally_companies
    import src.ledgers as ledgers
    import src.stock_items as stock_items
    import src.price_level as price_level
    import src.sale_bill as sale_bill
    import src.outstanding_receivables as outstanding_receivables
    import src.sales_orders_to_tally as sales_orders_to_tally
    import src.customers_to_tally as customers_to_tally
except Exception:
    logging.exception("TallySync failed to start")
    raise

# Silence noisy third-party network logs
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)


# --- SCRIPT CONTROL VARIABLES ---
last_known_sync_state = True
machine_hostname = socket.gethostname()

def check_script_control(company_name: str) -> bool:
    """
    Pings the script_control table in Supabase.
    Registers the machine if it doesn't exist, updates heartbeat/company if it does.
    Returns True if sync should proceed, False if paused remotely.
    """
    global last_known_sync_state
    try:
        config = load_config()
        supabase = create_client(config["supabase_url"], config["supabase_key"])
        
        now_utc = datetime.now(timezone.utc).isoformat()
        
        # 1. Fetch current row
        response = supabase.table("script_control").select("*").eq("machine_name", machine_hostname).execute()
        
        if not response.data:
            # 2. Doesn't exist, insert it (startup registration)
            supabase.table("script_control").insert({
                "machine_name": machine_hostname,
                "sync_should_run": True,
                "current_company": company_name,
                "last_seen_at": now_utc
            }).execute()
            last_known_sync_state = True
        else:
            # 3. Exists, update the heartbeat and company
            supabase.table("script_control").update({
                "current_company": company_name,
                "last_seen_at": now_utc
            }).eq("machine_name", machine_hostname).execute()
            
            # 4. Read the remote pause switch
            last_known_sync_state = response.data[0].get("sync_should_run", True)
            
    except Exception as e:
        logging.warning(f"Could not reach Supabase for script_control. Using last known state (run={last_known_sync_state}). Error: {e}")
        
    return last_known_sync_state
import requests
_original_post = requests.post

def _custom_tally_post(*args, **kwargs):
    if "data" in kwargs:
        try:
            data_str = kwargs["data"].decode("utf-8")
            config = load_config()
            target = config.get("target_company_name", "").strip()
            
            if target and "<ENVELOPE>" in data_str and "<SVCURRENTCOMPANY>" not in data_str:
                if "<STATICVARIABLES>" in data_str:
                    data_str = data_str.replace("<STATICVARIABLES>", f"<STATICVARIABLES>\n<SVCURRENTCOMPANY>{target}</SVCURRENTCOMPANY>")
                elif "<DESC>" in data_str:
                    data_str = data_str.replace("<DESC>", f"<DESC>\n<STATICVARIABLES>\n<SVCURRENTCOMPANY>{target}</SVCURRENTCOMPANY>\n</STATICVARIABLES>")
                kwargs["data"] = data_str.encode("utf-8")
        except Exception as e:
            logging.error(f"Error injecting target company into XML: {e}")
    return _original_post(*args, **kwargs)

requests.post = _custom_tally_post

def run_sync_cycle():
    
    logging.info("=====================================")
    logging.info("🚀 Starting Tally data sync cycle...")
    
    try:
        # 1. Fetch and sync company
        try:
            company_data = tally_companies.get_company_details()
            if not company_data:
                raise Exception("No company found in Tally")
                
            tally_companies.save_company_to_supabase(company_data)
            company_name = company_data.get("company_name", "Unknown")
            
            # --- NEW TARGET COMPANY CHECK ---
            config = load_config()
            target_company = config.get("target_company_name", "").strip().upper()
            if target_company and company_name.upper() != target_company:
                logging.info(f"Skipping sync: Active company '{company_name}' does not match target '{target_company}'.")
                print(f"Skipping sync: Active company '{company_name}' does not match target '{target_company}'.\n")
                return True
            # --- END TARGET COMPANY CHECK ---
            
            # --- NEW SCRIPT CONTROL CHECK START ---
            if not check_script_control(company_name):
                logging.info(f"Sync paused remotely for {machine_hostname}. Skipping this cycle.")
                return True
            # --- NEW SCRIPT CONTROL CHECK END ---
            
            logging.info(f"✅ Connected to Tally Company: {company_name}")
            print(f" [1/7] Synced Company: {company_name}\n")
            time.sleep(1)
            
        except Exception as e:
            logging.error(f"Could not connect to Tally company: {e}")
            print(f"Could not connect to Tally company: {e}")
            return False
        
        # 1.5 Push new customers created in app to Tally
        try:
            pushed_customers = customers_to_tally.push_customers(company_data)
            count = pushed_customers if isinstance(pushed_customers, int) else 0
            if count > 0:
                logging.info(f"Pushed {count} new customers to Tally")
                print(f" [1.5/7] Pushed {count} New Customers to Tally\n")
            time.sleep(1)
        except Exception as e:
            logging.error(f"Customer push to Tally failed: {e}")
            print(f" [1.5/7] Customer push failed: {e}\n")

        # 2. Fetch and sync customers/suppliers
        try:
            customers_data = ledgers.get_customers()
            count = len(customers_data) if customers_data else 0
            if customers_data:
                ledgers.save_customers_to_supabase(customers_data)
            logging.info(f"Synced {count} customers/suppliers")
            print(f" [2/7] Synced {count} Customers & Suppliers\n")
            time.sleep(1)
        except Exception as e:
            logging.error(f"Customers sync failed: {e}")

        # 3. Fetch and sync stock items
        try:
            items_data = stock_items.get_stock_items()
            count = len(items_data) if items_data else 0
            if items_data:
                stock_items.save_stock_items_to_supabase(items_data)
            logging.info(f"Synced {count} stock items")
            print(f" [3/7] Synced {count} Stock Items\n")
            time.sleep(1)
        except Exception as e:
            logging.error(f"Stock items sync failed: {e}")

        # 4. Fetch and sync price levels / price lists
        try:
            price_levels_data = price_level.get_price_levels()
            count = len(price_levels_data) if price_levels_data else 0
            if price_levels_data:
                price_level.save_price_levels_to_supabase(price_levels_data)
            logging.info(f"Synced {count} price level records")
            print(f" [4/7] Synced {count} Price Level Records\n")
            time.sleep(1)
        except Exception as e:
            logging.error(f"Price levels sync failed: {e}")
            
        # 5. Fetch and sync sale bills
        try:
            sale_bills_data = sale_bill.get_sale_bills()
            count = len(sale_bills_data) if sale_bills_data else 0
            if sale_bills_data:
                sale_bill.save_sale_bills_to_supabase(sale_bills_data)
            logging.info(f"Synced {count} sale bills")
            print(f" [5/7] Synced {count} Sale Bills\n")
            time.sleep(1)
        except Exception as e:
            logging.error(f"Sale bills sync failed: {e}")
            
        # 6. Fetch and sync outstanding receivables
        try:
            outstanding_receivables_data = outstanding_receivables.get_outstanding_receivables()
            count = len(outstanding_receivables_data) if outstanding_receivables_data else 0
            if outstanding_receivables_data:
                outstanding_receivables.save_outstanding_receivables_to_supabase(outstanding_receivables_data)
            logging.info(f"Synced {count} outstanding receivables")
            print(f" [6/7] Synced {count} Outstanding Receivables\n")
            time.sleep(1)
        except Exception as e:
            logging.error(f"Outstanding receivables sync failed: {e}")

        # 7. Push app sales orders to Tally (only if System toggle is ON)
        try:
            count = sales_orders_to_tally.push_sales_orders(company_data)
            logging.info(f"Pushed {count} sales orders to Tally")
            print(f" [7/7] Pushed {count} Sales Orders to Tally\n")
            time.sleep(1)
        except Exception as e:
            logging.error(f"Sales order push to Tally failed: {e}")
            print(f" [7/7] Sales order push failed: {e}\n")

        logging.info("Sync completed successfully!")
        print("\nAll steps finished. Sync cycle completed successfully!\n")
        return True
    except Exception as e:
        logging.error(f"❌ Error during sync: {e}")
        return False

def wait_for_next_cycle(interval):
    """
    Wait out the current interval, re-reading .env about every 2 seconds.
    Changing SYNC_INTERVAL_SECONDS in that file applies to this wait immediately.
    The Windows service does not need to be reinstalled or restarted.
    """
    started = time.monotonic()
    active = interval
    while True:
        try:
            latest = load_config().get("sync_interval_seconds", active)
        except Exception as e:
            logging.error(f"Failed to reload .env during wait: {e}")
            latest = active
        if latest != active:
            logging.info(
                f"SYNC_INTERVAL_SECONDS changed from {active} to {latest}. "
                "Applying immediately (no service reinstall)."
            )
            active = latest
        remaining = active - (time.monotonic() - started)
        if remaining <= 0:
            return active
        time.sleep(min(2.0, remaining))


def acquire_single_instance_lock(app_path):
    """
    Ensures that only one continuous background daemon runs at a time.
    Combines Windows named mutex and a non-blocking file lock.
    """
    mutex = None
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        for name in ["Global\\OrderX_TallySync_Daemon_Mutex", "Local\\OrderX_TallySync_Daemon_Mutex"]:
            m = kernel32.CreateMutexW(None, False, name)
            if kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
                return None
            if m:
                mutex = m
                break
    except Exception as e:
        logging.debug(f"Windows mutex notice: {e}")

    lock_file = None
    try:
        import msvcrt
        lock_path = os.path.join(app_path, "tallysync.lock")
        f = open(lock_path, "a+")
        f.seek(0)
        msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
        f.seek(0)
        f.truncate()
        f.write(f"PID: {os.getpid()}\nStarted: {datetime.now(timezone.utc).isoformat()}\n")
        f.flush()
        lock_file = f
    except Exception as e:
        if mutex is None:
            return None

    return (mutex, lock_file)


if __name__ == "__main__":
    is_once = "--once" in sys.argv or "--one-shot" in sys.argv

    if is_once:
        logging.info("TallySync running in one-shot manual mode (--once)...")
        print("\n--- Running One-Time Sync Cycle ---")
        success = run_sync_cycle()
        print("--- Manual Sync Cycle Complete ---\n")
        sys.exit(0 if success else 1)

    # In continuous background / daemon mode, enforce single instance
    lock_handles = acquire_single_instance_lock(application_path)
    if not lock_handles:
        logging.warning(
            "⚠️ Another instance of TallySync is already running. "
            "Exiting duplicate instance to prevent overlapping cycles."
        )
        print("⚠️ Another instance of TallySync is already running. Exiting duplicate process.")
        sys.exit(0)

    logging.info("TallySync started. Sync interval is controlled by SYNC_INTERVAL_SECONDS in .env.")
    while True:
        try:
            config = load_config()
            interval = config.get("sync_interval_seconds", 300)
        except Exception as e:
            logging.error(f"Failed to load config: {e}")
            interval = 300

        logging.info("Starting sync cycle...")
        run_sync_cycle()
        logging.info(
            f"Cycle finished. Next sync in {interval} seconds. "
            "Edit SYNC_INTERVAL_SECONDS in .env to change this without reinstalling."
        )
        wait_for_next_cycle(interval)

