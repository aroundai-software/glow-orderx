import re
import uuid
import requests
import xmltodict
import concurrent.futures
from datetime import datetime, timezone, timedelta

from supabase import create_client
from .config import load_config
from .tally_companies import get_company_details, resolve_company_row


# =====================================================
# HELPERS
# =====================================================

def clean_text(value):
    if value is None:
        return ""
    value = str(value)
    value = re.sub(r"&#\d+;", "", value)
    return value.strip()


def get_text(value):
    if value is None:
        return ""
    if isinstance(value, list):
        if len(value) > 0:
            return get_text(value[0])
        return ""
    if isinstance(value, dict):
        return clean_text(value.get("#text", ""))
    return clean_text(value)


def get_text_or_none(value):
    text = get_text(value)
    return text if text else None


def safe_float(value, default=0.0):
    try:
        value = get_text(value)
        value = value.replace(",", "")
        match = re.search(r"-?\d+(\.\d+)?", value)
        if not match:
            return default
        return float(match.group())
    except Exception:
        return default


def format_tally_date(value):
    value = get_text(value)
    if not value or len(value) != 8:
        return None
    try:
        return datetime.strptime(value, "%Y%m%d").date().isoformat()
    except Exception:
        return None


def julian_to_date(jd_value):
    try:
        jd = int(str(jd_value).strip())
        if jd <= 0:
            return None
        epoch = datetime(1899, 12, 30)
        result = epoch + timedelta(days=jd)
        return result.date().isoformat()
    except Exception:
        return None


def clean_tally_xml(xml_text):
    if not xml_text:
        return ""
    xml_text = xml_text.replace('encoding="utf-16"', 'encoding="utf-8"')
    xml_text = xml_text.replace('\x00', '')
    xml_text = re.sub(r'&#(?:x[0-9A-Fa-f]+|\d+);', '', xml_text)
    xml_text = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;)", "&amp;", xml_text)
    return xml_text


# =====================================================
# TALLY FETCH
# =====================================================

def get_outstanding_receivables():
    xml_request = """
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Outstanding Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Outstanding Collection">
                        <TYPE>Bill</TYPE>
                        <CHILDOF>$$SundryDebtors</CHILDOF>
                        <FETCH>
                            NAME,
                            BILLDATE,
                            BILLCREDITPERIOD,
                            OPENINGBALANCE,
                            CLOSINGBALANCE,
                            LEDGERNAME,
                            BILLID,
                            PARENT
                        </FETCH>
                        <FILTER>IsOutstanding</FILTER>
                    </COLLECTION>
                    <SYSTEM TYPE="Formulae" NAME="IsOutstanding">
                        $ClosingBalance != 0
                    </SYSTEM>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""
    config = load_config()
    tally_url = f"http://localhost:{config['tally_port']}"
    supabase = create_client(config["supabase_url"], config["supabase_key"])

    response = requests.post(
        tally_url,
        data=xml_request.encode("utf-8"),
        headers={"Content-Type": "application/xml", "Connection": "close"},
        timeout=120
    )
    response.raise_for_status()

    xml_content = clean_tally_xml(response.text)
    data = xmltodict.parse(xml_content)

    company_details = get_company_details()
    company_name = company_details.get("company_name", "")
    company_id = None

    try:
        resolved = resolve_company_row(supabase, company_details)
        if resolved:
            company_id = str(resolved.get("id") or "")
    except Exception as e:
        print(f"Failed to fetch company_id: {e}")

    envelope = data.get("ENVELOPE") or {}
    body = envelope.get("BODY") or {}
    body_data = body.get("DATA") or {}
    collection = body_data.get("COLLECTION") or {}
    bills = collection.get("BILL", [])
    if isinstance(bills, dict):
        bills = [bills]

    if not bills:
        print("No Outstanding Bills Found")
        return []

    print(f"Found {len(bills)} outstanding bills")

    now = datetime.now(timezone.utc).isoformat()
    outstandings_list = []

    for bill in bills:
        try:
            invoice_number = get_text(bill.get("NAME"))
            if not invoice_number:
                continue

            bill_id = get_text(bill.get("BILLID"))
            guid = f"BILL-{bill_id}" if bill_id else invoice_number
            
            customer_name = get_text(bill.get("LEDGERNAME"))
            if not customer_name:
                customer_name = get_text(bill.get("PARENT"))

            if not customer_name:
                continue

            invoice_date = format_tally_date(bill.get("BILLDATE"))
            if not invoice_date:
                continue

            credit_period = bill.get("BILLCREDITPERIOD", {})
            jd = credit_period.get("@JD", "") if isinstance(credit_period, dict) else ""
            due_date = julian_to_date(jd) or invoice_date

            raw_closing_balance = safe_float(bill.get("CLOSINGBALANCE"))
            if raw_closing_balance >= 0:
                continue
                
            pending_amount = abs(raw_closing_balance)
            if pending_amount == 0:
                continue

            invoice_amount = abs(safe_float(bill.get("OPENINGBALANCE")))
            if not invoice_amount:
                invoice_amount = pending_amount

            row = {
                "customer_name": customer_name,
                "date": invoice_date,
                "invoicenumber": invoice_number,
                "opening_balance": round(invoice_amount, 2),
                "closing_balance": round(pending_amount, 2),
                "amount": round(pending_amount, 2),
                "duedate": due_date,
                "company_name": company_name,
                "Guid": guid,
                "company_id": company_id,
                "updated_at": now,
            }
            outstandings_list.append(row)

        except Exception as e:
            print(f"Bill Error: {e}")

    return outstandings_list


# =====================================================
# SUPABASE SAVE
# =====================================================

def save_outstanding_receivables_to_supabase(outstandings):
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])

    if not outstandings:
        print("No outstandings to save.")
        return 0

    company_id = outstandings[0].get("company_id")
    company_name = outstandings[0].get("company_name")

    # WIPE OLD OUTSTANDINGS FOR THIS COMPANY
    try:
        if company_id:
            print(f"Clearing old outstandings for company: {company_name}...")
            supabase.table("outstanding").delete().eq("company_id", company_id).execute()
        elif company_name:
            print(f"Clearing old outstandings for company_name: {company_name}...")
            supabase.table("outstanding").delete().eq("company_name", company_name).execute()
    except Exception as e:
        print(f"Failed to clear old outstandings: {e}")
        raise

    BATCH_SIZE = 100
    total_saved = 0
    batches = [outstandings[i: i + BATCH_SIZE] for i in range(0, len(outstandings), BATCH_SIZE)]

    def upload_batch(batch):
        try:
            batch_without_company = [{k: v for k, v in row.items() if k != 'company_name'} for row in batch]
            supabase.table("outstanding").upsert(
                batch_without_company,
                on_conflict="invoicenumber,Guid"
            ).execute()

            c_name = batch[0].get('company_name', '') if batch else ''
            if c_name:
                guids = [row['Guid'] for row in batch if row.get('Guid')]
                supabase.table("outstanding").update({"company_name": c_name}).in_("Guid", guids).execute()

            return len(batch)
        except Exception as e:
            print(f"Batch upload failed: {e}")
            return 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        results = executor.map(upload_batch, batches)
        total_saved = sum(results)

    return total_saved


# =====================================================
# MAIN
# =====================================================

if __name__ == "__main__":
    try:
        print("Fetching outstandings from Tally...\n")
        outstandings = get_outstanding_receivables()
        print(f"Found {len(outstandings)} outstandings.\n")
        
        print("Saving to Supabase...\n")
        saved = save_outstanding_receivables_to_supabase(outstandings)
        
        print(f"Outstandings synced successfully ({saved} records).")
    except Exception as e:
        print(f"\nOutstanding sync failed: {e}")
        raise
