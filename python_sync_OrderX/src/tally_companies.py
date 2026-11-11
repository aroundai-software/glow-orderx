import logging
import re
import requests
import xmltodict
from datetime import datetime, timezone

from supabase import create_client

from .config import load_config


# =====================================================
# HELPERS
# =====================================================

def clean_text(value):

    if value is None:
        return ""

    value = str(value)

    value = re.sub(
        r"&#\d+;",
        "",
        value
    )

    return value.strip()


def get_text(value):

    if value is None:
        return ""

    if isinstance(value, list):

        if len(value) > 0:
            return get_text(value[0])

        return ""

    if isinstance(value, dict):

        return clean_text(
            value.get("#text", "")
        )

    return clean_text(value)


def get_text_or_none(value):
    """Return text or None if empty"""
    text = get_text(value)
    return text if text else None


def format_tally_date(value):

    value = get_text(value)

    if not value:
        return None

    try:

        return datetime.strptime(
            value,
            "%Y%m%d"
        ).date().isoformat()

    except Exception:

        return None


def get_nested_text(item, *keys):
    """Walk nested Tally dicts/lists and return the first non-empty text."""
    current = item
    for key in keys:
        if current is None:
            return None
        if isinstance(current, list):
            current = current[0] if current else None
            if current is None:
                return None
        if isinstance(current, dict):
            current = current.get(key)
        else:
            return None
    text = get_text_or_none(current)
    if text:
        return text
    if isinstance(current, list) and current:
        return get_text_or_none(current[0])
    if isinstance(current, dict):
        return get_text_or_none(current.get("#text"))
    return None


def pan_from_gst(gst):
    gst = (gst or "").replace(" ", "").replace("-", "").upper()
    if len(gst) >= 12:
        return gst[2:12]
    return None


def get_address_parts(item):

    # Try COMPUTE fields first (ADDR1, ADDR2, ADDR3)
    computed = [
        clean_text(item.get("ADDR1", "")),
        clean_text(item.get("ADDR2", "")),
        clean_text(item.get("ADDR3", "")),
    ]

    computed = [
        a for a in computed if a
    ]

    if computed:
        return computed

    # Fallback: try BASICCOMPANYADDRESS.LIST
    address_list = item.get(
        "BASICCOMPANYADDRESS.LIST"
    ) or {}

    if isinstance(address_list, list):

        address_list = (
            address_list[0]
            if address_list
            else {}
        )

    addresses = address_list.get(
        "BASICCOMPANYADDRESS", []
    )

    if isinstance(addresses, str):
        addresses = [addresses]

    return [
        clean_text(a)
        for a in addresses
        if clean_text(a)
    ]


def clean_tally_xml(xml_text):
    """Remove invalid XML character refs and fix stray ampersands."""

    xml_text = re.sub(
        r'&#(?:x[0-9A-Fa-f]+|\d+);',
        '',
        xml_text
    )

    xml_text = re.sub(
        r"&(?!amp;|lt;|gt;|quot;|apos;)",
        "&amp;",
        xml_text
    )

    return xml_text


# =====================================================
# TALLY FETCH
# =====================================================

def get_company_details():

    xml_request = """
<ENVELOPE>

    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Company Collection</ID>
    </HEADER>

    <BODY>

        <DESC>

            <TDL>

                <TDLMESSAGE>

                    <COLLECTION NAME="Company Collection">

                        <TYPE>Company</TYPE>

                        <FETCH>
                            *,
                            MOBILENO,
                            MASTERID,
                            GSTREGISTRATIONNUMBER,
                            INCOMETAXNUMBER,
                            STATENAME,
                            PINCODE,
                            COUNTRYNAME,
                            EMAIL,
                            COMPANYCONTACTNUMBER,
                            PHONENUMBER,
                            BASICCOMPANYADDRESS
                        </FETCH>

                    </COLLECTION>

                </TDLMESSAGE>

            </TDL>

        </DESC>

    </BODY>

</ENVELOPE>
"""

    config = load_config()

    tally_url = f"http://localhost:{config['tally_port']}"

    # -------------------------------------------------
    # CONNECT TO TALLY
    # -------------------------------------------------

    response = requests.post(
        tally_url,
        data=xml_request.encode("utf-8"),
        headers={
            "Content-Type": "application/xml", "Connection": "close"
        },
        timeout=60
    )

    response.raise_for_status()

    # -------------------------------------------------
    # CLEAN & PARSE XML
    # -------------------------------------------------

    xml_content = clean_tally_xml(response.text)

    data = xmltodict.parse(xml_content)

    # -------------------------------------------------
    # FIND COMPANY
    # -------------------------------------------------

    collection = (
        data.get("ENVELOPE", {})
        .get("BODY", {})
        .get("DATA", {})
        .get("COLLECTION", {})
    )

    companies = collection.get("COMPANY", [])

    if isinstance(companies, dict):
        companies = [companies]

    if not companies:
        raise Exception("No company found in Tally")

    target_company = config.get("target_company_name", "").strip().upper()
    
    company = companies[0]
    if target_company:
        for c in companies:
            c_name = (get_text(c.get("NAME")) or get_text(c.get("@NAME"))).strip().upper()
            if c_name == target_company:
                company = c
                break

    # -------------------------------------------------
    # EXTRACT FIELDS
    # -------------------------------------------------

    address_parts = get_address_parts(company)

    books_from = get_text(
        company.get("BOOKSFROM")
    )

    company_data = {

        "company_name":
            get_text(company.get("NAME"))
            or get_text(company.get("@NAME")),

        "company_number":
            get_text_or_none(
                company.get("COMPANYNUMBER")
            ),

        "Guid":
            get_text(company.get("GUID"))
            or get_text(company.get("@GUID")),

        "company_alias":
            None,

        "company_description":
            None,

        "address_line1":
            address_parts[0]
            if len(address_parts) > 0
            else None,

        "address_line2":
            address_parts[1]
            if len(address_parts) > 1
            else None,

        "city":
            address_parts[2]
            if len(address_parts) > 2
            else None,

        "state":
            get_text_or_none(
                company.get("STATENAME")
            ),

        "pin_code":
            get_text_or_none(
                company.get("PINCODE")
            ),

        "country":
            get_text_or_none(
                company.get("COUNTRYNAME")
            ) or "India",

        "phone_number":
            get_text_or_none(
                company.get("MOBILENO")
            )
            or get_text_or_none(
                company.get("COMPANYCONTACTNUMBER")
            )
            or get_text_or_none(
                company.get("PHONENUMBER")
            ),

        "email":
            get_text_or_none(
                company.get("EMAIL")
            ),

        "website":
            get_text_or_none(
                company.get("WEBSITE")
            ),

        "gst_number":
            get_text_or_none(
                company.get("GSTREGISTRATIONNUMBER")
            )
            or get_nested_text(company, "COMPANYGSTIN.LIST", "GSTIN")
            or get_text_or_none(
                company.get("COMPANYGSTIN")
            )
            or get_text_or_none(
                company.get("GSTIN")
            ),

        "pan_number":
            get_text_or_none(
                company.get("INCOMETAXNUMBER")
            )
            or get_text_or_none(
                company.get("INCOMETAXNO")
            )
            or get_text_or_none(
                company.get("PAN")
            ),

        "tan_number":
            None,

        "financial_year_start_date":
            format_tally_date(books_from),

        "financial_year_end_date":
            None,

        "is_active":
            True,

        "is_synced":
            True,

        "tally_server_url":
            None,

        "tally_port":
            9000,

        "tally_username":
            None,

        "tally_password":
            None,

        "last_synced_at":
            datetime.now(
                timezone.utc
            ).isoformat(),

        "sync_status":
            "completed",

        "sync_error_message":
            None
    }

    if not company_data.get("pan_number"):
        company_data["pan_number"] = pan_from_gst(company_data.get("gst_number"))

    return company_data


def resolve_company_row(supabase, company_data=None, guid=None, name=None, serial=None):
    """
    Find the tally_companies row for the company currently open in Tally.
    Match Guid first, then company_name, then company_number (Tally EDU reuses serials).
    """
    company_data = company_data or {}
    guid = guid or company_data.get("Guid") or ""
    name = name or company_data.get("company_name") or ""
    serial = serial or company_data.get("company_number") or ""

    for field, value in (
        ("Guid", guid),
        ("company_name", name),
        ("company_number", serial),
    ):
        if not value:
            continue
        try:
            row = (
                supabase.table("tally_companies")
                .select("id, Guid, company_name")
                .eq(field, value)
                .limit(1)
                .execute()
            )
            if row.data:
                logging.info("Resolved company by %s -> id=%s Guid=%s", field, row.data[0].get("id"), row.data[0].get("Guid"))
                return row.data[0]
        except Exception as exc:
            logging.warning("Company lookup by %s failed: %s", field, exc)
    return None


# =====================================================
# SUPABASE SAVE
# =====================================================

def save_company_to_supabase(company_data):

    config = load_config()

    supabase = create_client(
        config["supabase_url"],
        config["supabase_key"]
    )

    payload = dict(company_data)
    guid = payload.get("Guid")
    name = payload.get("company_name")
    serial = payload.get("company_number")

    existing_guid = None
    for field, value in (
        ("Guid", guid),
        ("company_name", name),
        ("company_number", serial),
    ):
        if not value:
            continue
        row = (
            supabase
            .table("tally_companies")
            .select("Guid")
            .eq(field, value)
            .limit(1)
            .execute()
        )
        if row.data:
            existing_guid = row.data[0].get("Guid")
            if existing_guid:
                logging.info("Matched existing company by %s", field)
                break

    if existing_guid:
        payload["Guid"] = existing_guid

    if serial:
        other = (
            supabase
            .table("tally_companies")
            .select("Guid")
            .eq("company_number", serial)
            .limit(1)
            .execute()
        )
        other_guid = other.data[0].get("Guid") if other.data else None
        if other_guid and other_guid != payload.get("Guid"):
            payload.pop("company_number", None)

    result = (
        supabase
        .table("tally_companies")
        .upsert(payload, on_conflict="Guid")
        .execute()
    )

    resolved = resolve_company_row(supabase, company_data)
    if resolved and company_data is not None:
        company_data["company_id"] = str(resolved.get("id") or "")
        company_data["db_guid"] = resolved.get("Guid")
    return result


# =====================================================
# MAIN
# =====================================================

if __name__ == "__main__":

    try:
        print("Fetching company from Tally...\n")

        company_data = get_company_details()

        print(f"Found company: {company_data.get('company_name')}\n")

        print("Saving to Supabase...\n")

        save_company_to_supabase(company_data)

        print("Company synced successfully!")

    except Exception as e:
        print(f"\nCompany sync failed: {e}")
        raise