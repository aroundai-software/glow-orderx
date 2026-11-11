import logging
import re
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from xml.sax.saxutils import escape as xml_escape

from supabase import create_client

from .config import load_config
from .tally_client import TallyClient
from .tally_companies import get_company_details, resolve_company_row


GST_STATE_NAMES = {
    "32": "Kerala",
    "33": "Tamil Nadu",
    "29": "Karnataka",
    "36": "Telangana",
    "37": "Andhra Pradesh",
    "27": "Maharashtra",
    "24": "Gujarat",
    "07": "Delhi",
    "06": "Haryana",
    "09": "Uttar Pradesh",
    "23": "Madhya Pradesh",
    "08": "Rajasthan",
    "19": "West Bengal",
    "10": "Bihar",
    "21": "Odisha",
    "22": "Chhattisgarh",
    "03": "Punjab",
    "30": "Goa",
}


def _xml(value):
    if value is None:
        return ""
    return xml_escape(str(value), {"'": "&apos;", '"': "&quot;"})


def _clean(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def _state_from_gst(gst, fallback="Kerala"):
    gst = re.sub(r"[\s-]", "", str(gst or "")).upper()
    if len(gst) >= 2 and gst[:2].isdigit() and gst[:2] != "00":
        return GST_STATE_NAMES.get(gst[:2], fallback)
    return fallback


def _clean_tally_xml(xml_text):
    if not xml_text:
        return ""
    xml_text = xml_text.replace('encoding="utf-16"', 'encoding="utf-8"')
    xml_text = xml_text.replace("\x00", "")
    xml_text = re.sub(r"&#(?:x[0-9A-Fa-f]+|\d+);", "", xml_text)
    xml_text = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;)", "&amp;", xml_text)
    return xml_text


def _fetch_ledger_identifiers(client, company_name, ledger_name):
    """
    Query Tally by exact ledger name to retrieve its permanent GUID and MASTERID.
    """
    escaped_name = ledger_name.replace('"', '""')
    xml_request = f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>SingleLedger</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVCURRENTCOMPANY>{_xml(company_name)}</SVCURRENTCOMPANY>
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="SingleLedger">
            <TYPE>Ledger</TYPE>
            <FETCH>NAME, GUID, MASTERID</FETCH>
            <FILTER>NameFilter</FILTER>
          </COLLECTION>
          <SYSTEM TYPE="Formulae" NAME="NameFilter">$$IsEqual:$NAME:"{escaped_name}"</SYSTEM>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""

    try:
        response_text = client.send_request(xml_request, timeout=30)
        clean_text = _clean_tally_xml(response_text)
        root = ET.fromstring(clean_text)

        for ledger in root.findall(".//LEDGER"):
            name = (ledger.attrib.get("NAME") or "").strip()
            if not name:
                name = (ledger.findtext("NAME") or "").strip()
            if name.lower() == ledger_name.strip().lower():
                guid = (ledger.findtext("GUID") or "").strip()
                master_id_text = (ledger.findtext("MASTERID") or "").strip()
                master_id = int(master_id_text) if master_id_text.isdigit() else None
                return guid, master_id
    except Exception as e:
        logging.warning(f"Could not fetch ledger identifiers for '{ledger_name}': {e}")

    return None, None


def _build_create_ledger_xml(company_name, customer):
    """
    Construct Tally XML to create a new Customer Ledger under 'Sundry Debtors'.
    """
    customer_name = _clean(customer.get("customer_name"))
    mobile = _clean(customer.get("mobile_number"))
    gst = _clean(customer.get("gst_number")).upper()
    address = _clean(customer.get("address"))
    city = _clean(customer.get("city"))
    pincode = _clean(customer.get("pincode"))
    state = _clean(customer.get("state")) or (_state_from_gst(gst) if gst else "")

    mobile_xml = ""
    if mobile:
        mobile_xml = f"""            <LEDGERMOBILE>{_xml(mobile)}</LEDGERMOBILE>
            <PARTYMOBILENO>{_xml(mobile)}</PARTYMOBILENO>"""

    address_lines = []
    if address:
        for line in address.split(","):
            if line.strip():
                address_lines.append(line.strip())
    if city and city not in address:
        address_lines.append(city)

    address_xml = ""
    if address_lines:
        inner_address = "\n".join([f"              <ADDRESS>{_xml(line)}</ADDRESS>" for line in address_lines])
        address_xml = f"""            <ADDRESS.LIST>
{inner_address}
            </ADDRESS.LIST>"""

    state_xml = ""
    if state:
        state_xml = f"""            <STATENAME>{_xml(state)}</STATENAME>
            <COUNTRYOFRESIDENCE>India</COUNTRYOFRESIDENCE>"""

    pincode_xml = ""
    if pincode:
        pincode_xml = f"""            <PINCODE>{_xml(pincode)}</PINCODE>"""

    gst_xml = ""
    if gst:
        effective_state = state or _state_from_gst(gst, fallback="Kerala")
        gst_xml = f"""            <PARTYGSTIN>{_xml(gst)}</PARTYGSTIN>
            <GSTREGISTRATIONTYPE>Regular</GSTREGISTRATIONTYPE>
            <LEDGSTREGDETAILS.LIST>
              <APPLICABLEFROM>20200401</APPLICABLEFROM>
              <GSTREGISTRATIONTYPE>Regular</GSTREGISTRATIONTYPE>
              <PLACEOFSUPPLY>{_xml(effective_state)}</PLACEOFSUPPLY>
              <GSTIN>{_xml(gst)}</GSTIN>
            </LEDGSTREGDETAILS.LIST>"""
    else:
        gst_xml = """            <GSTREGISTRATIONTYPE>Consumer</GSTREGISTRATIONTYPE>"""

    return f"""<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Import Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <IMPORTDATA>
      <REQUESTDESC>
        <REPORTNAME>All Masters</REPORTNAME>
        <STATICVARIABLES>
          <SVCURRENTCOMPANY>{_xml(company_name)}</SVCURRENTCOMPANY>
        </STATICVARIABLES>
      </REQUESTDESC>
      <REQUESTDATA>
        <TALLYMESSAGE xmlns:UDF="TallyUDF">
          <LEDGER NAME="{_xml(customer_name)}" ACTION="Create">
            <NAME.LIST>
              <NAME>{_xml(customer_name)}</NAME>
            </NAME.LIST>
            <PARENT>Sundry Debtors</PARENT>
            <ISBILLWISEON>Yes</ISBILLWISEON>
            <AFFECTSSTOCK>No</AFFECTSSTOCK>
            <MAILINGNAME>{_xml(customer_name)}</MAILINGNAME>
{mobile_xml}
{address_xml}
{state_xml}
{pincode_xml}
{gst_xml}
          </LEDGER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>"""


def push_customers(company_data=None):
    """
    Finds unsynced customers in Supabase (where Guid is NULL), creates them as
    Sundry Debtors ledgers in Tally, retrieves Tally's GUID & MasterID, and
    updates the Supabase customer record to prevent duplication on future edits.
    """
    config = load_config()
    supabase = create_client(config["supabase_url"], config["supabase_key"])
    client = TallyClient()

    company_data = company_data or get_company_details() or {}
    company_name = company_data.get("company_name") or ""
    company_row = resolve_company_row(supabase, company_data)
    company_id = company_row.get("id") if company_row else company_data.get("company_id")

    if not company_name:
        logging.warning("No active company found for pushing customers to Tally.")
        return 0

    # Query customers that have not yet been synced to Tally (Guid is NULL)
    try:
        query = supabase.table("customers").select("*").is_("Guid", "null")
        if company_id:
            query = query.eq("company_id", company_id)
        res = query.execute()
        unsynced_customers = res.data or []
    except Exception as e:
        logging.error(f"Error fetching unsynced customers from Supabase: {e}")
        return 0

    if not unsynced_customers:
        logging.info("No unsynced customers found to push to Tally.")
        return 0

    logging.info(f"Found {len(unsynced_customers)} unsynced customers to push to Tally ({company_name})")

    pushed_count = 0

    for customer in unsynced_customers:
        cust_id = customer.get("id")
        cust_name = _clean(customer.get("customer_name"))

        if not cust_name:
            continue

        try:
            # 1. Check if the ledger already exists in Tally under this name
            tally_guid, tally_master_id = _fetch_ledger_identifiers(client, company_name, cust_name)

            if not tally_guid:
                # 2. Does not exist yet: create in Tally
                create_xml = _build_create_ledger_xml(company_name, customer)
                response_text = client.send_request(create_xml, timeout=30)

                # Check if Tally created it
                if "<ERRORS>0</ERRORS>" in response_text or "<CREATED>1</CREATED>" in response_text or "<ALTERED>1</ALTERED>" in response_text:
                    time.sleep(0.5)
                    tally_guid, tally_master_id = _fetch_ledger_identifiers(client, company_name, cust_name)
                else:
                    # Parse error details if any
                    line_err = re.search(r"<LINEERROR>(.*?)</LINEERROR>", response_text, re.S)
                    err_msg = line_err.group(1).strip() if line_err else "Tally import error"
                    logging.warning(f"Tally response for customer '{cust_name}': {err_msg}")
                    # Attempt fetching anyway in case it was a duplicate name
                    tally_guid, tally_master_id = _fetch_ledger_identifiers(client, company_name, cust_name)

            if tally_guid:
                # 3. Update Supabase with Tally GUID and MasterID
                update_payload = {
                    "Guid": tally_guid,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }
                if tally_master_id is not None:
                    update_payload["MasterID"] = tally_master_id

                supabase.table("customers").update(update_payload).eq("id", cust_id).execute()
                pushed_count += 1
                logging.info(
                    f"✅ Successfully mapped customer '{cust_name}' (ID: {cust_id}) with Tally GUID: {tally_guid}, MasterID: {tally_master_id}"
                )
            else:
                logging.warning(f"⚠️ Could not obtain Tally GUID for customer '{cust_name}'")

        except Exception as exc:
            logging.error(f"❌ Failed to sync customer '{cust_name}' to Tally: {exc}")

    return pushed_count


if __name__ == "__main__":
    count = push_customers()
    print(f"Pushed {count} customers to Tally.")
