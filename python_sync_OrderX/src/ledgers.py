import logging
import re
import requests
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from xml.sax.saxutils import escape as xml_escape

from supabase import create_client

from .config import load_config
from .tally_companies import get_company_details, resolve_company_row


# =====================================================
# HELPERS
# =====================================================

def safe_text(parent, tag):

    node = parent.find(tag)

    if node is None:
        return None

    value = (node.text or "").strip()

    return value if value else None


def clean_tally_xml(xml_text):

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

    # Tally SDK UDF fields use an undeclared "UDF:" namespace prefix.
    xml_text = re.sub(r'<(/?)\s*UDF:', r'<\1', xml_text)

    return xml_text


def parse_opening_balance(raw):
    """
    Tally returns opening balance with a sign suffix:
      e.g. '15000.00 Dr' or '5000.00 Cr' or '0.00'
    Returns (amount: float, type: 'DR'|'CR'|None)
    """

    if not raw:
        return 0.0, None

    raw = raw.strip()
    ob_type = None

    if raw.lower().endswith("dr"):
        ob_type = "DR"
        raw = raw[:-2].strip()

    elif raw.lower().endswith("cr"):
        ob_type = "CR"
        raw = raw[:-2].strip()

    try:
        return float(raw), ob_type
    except ValueError:
        return 0.0, ob_type


def parse_amount(raw):
    """Parse a plain numeric amount from Tally (no Dr/Cr suffix)."""

    if not raw:
        return None

    raw = raw.strip()

    try:
        return float(raw)
    except ValueError:
        return None


def normalize_phone(value):
    if not value:
        return None
    kept = "".join(ch for ch in str(value) if ch.isdigit() or ch == "+")
    return kept or None


CUST_CATEGORY_TAGS = (
    "SDKCUSTCATEGORY",
    "UDF:SDKCUSTCATEGORY",
    "SDKCUSTCLASSSUNDRY",
    "CUSTCATEGORY",
    "CUST.CATEGORY",
    "CUST_CATEGORY",
    "LEDCUSTCATEGORY",
    "CUSTCAT",
    "UDF:CUSTCATEGORY",
    "UDF:CUST.CATEGORY",
)


def extract_cust_category(ledger):
    """Tally SDK UDF 'Cust Category' (stored as UDF:SDKCUSTCATEGORY)."""

    def tag_name(node):
        raw = node.tag or ""
        if "}" in raw:
            raw = raw.split("}", 1)[1]
        if raw.upper().startswith("UDF:"):
            raw = raw[4:]
        return raw

    def first_text(node):
        text = (node.text or "").strip()
        if text:
            return text
        for child in list(node):
            child_text = (child.text or "").strip()
            if child_text:
                return child_text
        return None

    for node in ledger.iter():
        name = tag_name(node)
        name_upper = name.upper()
        name_base = name_upper.replace(".LIST", "")
        desc = (node.attrib.get("DESC") or "").lower().replace("`", "")
        compact = re.sub(r"[^A-Z]", "", name_upper)

        if name_base in CUST_CATEGORY_TAGS or name_upper in CUST_CATEGORY_TAGS:
            value = first_text(node)
            if value:
                return value
        if "CUST" in compact and "CATEG" in compact:
            value = first_text(node)
            if value:
                return value
        if "sdkcustcategory" in desc or ("cust" in desc and "categ" in desc):
            value = first_text(node)
            if value:
                return value

    for tag in (
        "SDKCUSTCATEGORY",
        "CUSTCATEGORY",
        "CUSTCATEGORY2",
        "CUSTCATEGORY3",
        "CUSTCATEGORY4",
        "CUSTCATEGORY5",
    ):
        value = safe_text(ledger, tag)
        if value:
            return value
    return None


# =====================================================
# LEDGER GROUPS (category + parent)
# =====================================================

_PRIMARY_GROUP = "primary"


def get_ledger_group_parents(tally_url):
    """Map each Tally group name to its parent (Under)."""
    xml_request = """
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Group Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Group Collection">
                        <TYPE>Group</TYPE>
                        <FETCH>NAME, PARENT</FETCH>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""
    try:
        response = requests.post(
            tally_url,
            data=xml_request.encode("utf-8"),
            headers={"Content-Type": "application/xml", "Connection": "close"},
            timeout=120,
        )
        response.raise_for_status()
        root = ET.fromstring(clean_tally_xml(response.text))
    except Exception as exc:
        logging.error("Error fetching Tally ledger groups: %s", exc)
        return {}

    mapping = {}
    for group in root.findall(".//COLLECTION/GROUP"):
        name = (group.attrib.get("NAME") or "").strip() or (safe_text(group, "NAME") or "")
        parent = safe_text(group, "PARENT")
        if name:
            mapping[name] = parent
    logging.info("  Tally ledger groups fetched: %s", len(mapping))
    return mapping


def resolve_group_parent(group_name, group_parents):
    """Immediate parent of the ledger's group. Skip Tally's Primary group."""
    if not group_name:
        return None
    parent = (group_parents.get(group_name) or "").strip()
    if not parent or parent.lower() == _PRIMARY_GROUP:
        return None
    return parent


# =====================================================
# LEDGERS
# =====================================================

def extract_ledger_data(ledger, company_name, group_parents=None):
    """
    Extract all relevant fields from a <LEDGER> XML element.
    Address lines come from LEDMAILINGDETAILS.LIST > ADDRESS.LIST > ADDRESS (multi-line).
    TRN from LEDGSTREGDETAILS.LIST > GSTIN.
    """

    # --- Basic identity ---
    name = ledger.attrib.get("NAME", "").strip()
    guid = safe_text(ledger, "GUID") or ledger.attrib.get("GUID", "").strip()

    master_id_raw = (
        safe_text(ledger, "MASTERID")
        or ledger.attrib.get("MASTERID")
    )

    try:
        master_id = int(str(master_id_raw).strip())
    except (ValueError, AttributeError, TypeError):
        master_id = 0

    ledger_group = safe_text(ledger, "PARENT") or ""

    alias = None

    language_list = ledger.find("LANGUAGENAME.LIST")

    if language_list is not None:

        names = []

        for name_node in language_list.findall(".//NAME"):
            value = (name_node.text or "").strip()
            if value:
                names.append(value)

        if len(names) > 1:
            alias = names[1]

    if not alias:
        alias = safe_text(ledger, "BASICALIASNAME")

    if not alias:
        alias = safe_text(ledger, "ALTERNATENAME")

    # --- Mailing / address details ---
    address_line1 = address_line2 = address_line3 = None
    city = emirate = country = pin_code = None

    mailing = ledger.find("LEDMAILINGDETAILS.LIST")
    if mailing is None:
        mailing = ledger

    if mailing is not None:

        addr_list = mailing.find("ADDRESS.LIST")

        if addr_list is not None:

            addresses = [
                (a.text or "").strip()
                for a in addr_list.findall("ADDRESS")
                if (a.text or "").strip()
            ]

            if len(addresses) >= 1:
                address_line1 = addresses[0]
            if len(addresses) >= 2:
                address_line2 = addresses[1]
            if len(addresses) >= 3:
                address_line3 = addresses[2]

        state_node = mailing.find("STATE")
        emirate = (
            (state_node.text or "").strip()
            if state_node is not None
            else None
        )

        country_node = mailing.find("COUNTRY")
        country = (
            (country_node.text or "").strip()
            if country_node is not None
            else None
        )

        pin_code = safe_text(mailing, "PINCODE")
        city = (
            safe_text(mailing, "CITY")
            or safe_text(mailing, "PLACEOFSUPPLY")
            or None
        )

    # --- Contact details ---
    mobile_number = (
        safe_text(ledger, "MOBILE")
        or safe_text(ledger, "MOBILENO")
        or safe_text(ledger, "LEDGERMOBILE")
        or safe_text(ledger, "PARTYMOBILENO")
    )

    phone_number = (
        safe_text(ledger, "PHONENUMBER")
        or safe_text(ledger, "LEDGERPHONE")
        or safe_text(ledger, "PARTYPHONENO")
    )

    email = (
        safe_text(ledger, "EMAIL")
        or safe_text(ledger, "PARTYEMAIL")
    )

    contact_person = (
        safe_text(ledger, "CONTACTPERSON")
        or safe_text(ledger, "CONTACT")
    )

    # --- GST / TRN ---
    trn_number = None
    gst_details = ledger.find("LEDGSTREGDETAILS.LIST")

    if gst_details is not None:
        trn_number = safe_text(gst_details, "GSTIN")

    # --- Financial ---
    ob_raw = safe_text(ledger, "OPENINGBALANCE")
    opening_balance, opening_balance_type = parse_opening_balance(ob_raw)

    credit_limit = parse_amount(safe_text(ledger, "CREDITLIMIT"))

    credit_period_raw = safe_text(ledger, "CREDITPERIOD")

    try:
        credit_period = int(credit_period_raw) if credit_period_raw else None
    except ValueError:
        credit_period = None

    ledger_code = (
        safe_text(ledger, "LEDGERCODE")
        or safe_text(ledger, "ALTERID")
    )

    return {

        "company_name":
            company_name,

        "guid":
            guid,

        "master_id":
            master_id,

        "ledger_name":
            name,

        "alias":
            alias,

        "ledger_group":
            ledger_group,

        "ledger_group_parent":
            resolve_group_parent(ledger_group, group_parents or {}),

        "address_line1":
            address_line1,

        "address_line2":
            address_line2,

        "address_line3":
            address_line3,

        "city":
            city,

        "emirate":
            emirate or None,

        "country":
            country or "UAE",

        "pin_code":
            pin_code,

        "mobile_number":
            mobile_number,

        "phone_number":
            phone_number,

        "email":
            email,

        "contact_person":
            contact_person,

        "trn_number":
            trn_number,

        "trade_license_number":
            None,

        "opening_balance":
            round(opening_balance, 2),

        "opening_balance_type":
            opening_balance_type,

        "credit_limit":
            credit_limit,

        "credit_period":
            credit_period,

        "ledger_code":
            ledger_code,

        "area":
            None,

        "mobile":
            mobile_number,

        "phone":
            phone_number,

        "outstanding_balance":
            None,

        "current_balance":
            None,

        "status":
            "active",

        "transportation_cost":
            None,

        "sales_person":
            None,

        "credit_date":
            None,

        "is_active":
            True,

        "updated_at":
            datetime.now(
                timezone.utc
            ).isoformat(),
    }


def get_ledgers():
    xml_request = """
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Ledger Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Ledger Collection">
                        <TYPE>Ledger</TYPE>
                        <FETCH>NAME, PARENT, OPENINGBALANCE, CLOSINGBALANCE, MAILINGNAME.LIST, ADDRESS.LIST, STATE, COUNTRY, PINCODE, CITY, PLACEOFSUPPLY, MOBILE, MOBILENO, LEDGERMOBILE, PARTYMOBILENO, PHONENUMBER, LEDGERPHONE, PARTYPHONENO, EMAIL, PARTYEMAIL, CONTACTPERSON, CONTACT, LEDGSTREGDETAILS.LIST, CREDITLIMIT, CREDITPERIOD, LEDGERCODE, ALTERID, MASTERID, GUID</FETCH>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""
    config = load_config()
    tally_url = f"http://localhost:{config['tally_port']}"
    company_details = get_company_details()
    company_name = company_details.get("company_name", "")
    group_parents = get_ledger_group_parents(tally_url)

    response = requests.post(
        tally_url,
        data=xml_request.encode("utf-8"),
        headers={"Content-Type": "application/xml", "Connection": "close"},
        timeout=300
    )
    response.raise_for_status()

    response_text = clean_tally_xml(response.text)
    root = ET.fromstring(response_text)

    ledgers = []
    for ledger in root.findall(".//COLLECTION/LEDGER"):
        name = ledger.attrib.get("NAME", "").strip()
        if not name:
            continue
        data = extract_ledger_data(ledger, company_name, group_parents)
        ledgers.append(data)

    return ledgers

def save_ledgers_to_supabase(ledgers):

    config = load_config()

    supabase = create_client(
        config["supabase_url"],
        config["supabase_key"]
    )

    if not ledgers:
        logging.info("No ledgers to save.")
        return

    BATCH_SIZE = 100
    total_saved = 0
    batches = [ledgers[i: i + BATCH_SIZE] for i in range(0, len(ledgers), BATCH_SIZE)]

    import concurrent.futures

    def upload_batch(batch):
        try:
            supabase.table("ledgers").upsert(
                batch,
                on_conflict="guid"
            ).execute()
            return len(batch)
        except Exception as e:
            logging.info(f"Batch upload failed: {e}")
            return 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        results = executor.map(upload_batch, batches)
        total_saved = sum(results)

    return total_saved


# =====================================================
# CUSTOMERS (Debtors + Creditors)
# =====================================================

# Groups treated as debtors (receivable)
DEBTOR_GROUPS = [
    "sundry debtors",
    "debtors",
    "customers",
    "accounts receivable",
]

# Groups treated as creditors (payable)
CREDITOR_GROUPS = [
    "sundry creditors",
    "creditors",
    "suppliers",
    "accounts payable",
]

ALL_CUSTOMER_GROUPS = DEBTOR_GROUPS + CREDITOR_GROUPS


def extract_customer_data(ledger, company_name, company_id=None, group_parents=None):
    """
    Extract customer/supplier data from a <LEDGER> XML element.
    ledger_group = Tally Under of the ledger (e.g. KOTTAYAM-KAMP).
    ledger_group_parent = that group's Under (e.g. Central Zone Kamp).
    """

    # --- Basic identity ---
    customer_name = ledger.attrib.get("NAME", "").strip()
    guid = safe_text(ledger, "GUID") or ledger.attrib.get("GUID", "").strip()

    master_id_raw = (
        safe_text(ledger, "MASTERID")
        or ledger.attrib.get("MASTERID")
    )

    try:
        master_id = int(str(master_id_raw).strip()) if master_id_raw else None
    except (ValueError, AttributeError, TypeError):
        master_id = None

    # ledger_type = parent group from Tally
    ledger_type = safe_text(ledger, "PARENT") or None

    # --- Alias ---
    alias = None

    language_list = ledger.find("LANGUAGENAME.LIST")

    if language_list is not None:

        names = []

        for name_node in language_list.findall(".//NAME"):
            value = (name_node.text or "").strip()
            if value:
                names.append(value)

        if len(names) > 1:
            alias = names[1]

    if not alias:
        alias = safe_text(ledger, "BASICALIASNAME")

    if not alias:
        alias = safe_text(ledger, "ALTERNATENAME")

    # --- Mailing / address details ---
    address_lines = []
    city = state = country = pincode = None

    mailing = ledger.find("LEDMAILINGDETAILS.LIST")
    if mailing is None:
        mailing = ledger

    if mailing is not None:

        addr_list = mailing.find("ADDRESS.LIST")

        if addr_list is not None:
            address_lines = [
                (a.text or "").strip()
                for a in addr_list.findall("ADDRESS")
                if (a.text or "").strip()
            ]

        state_node = mailing.find("STATE")
        state = (
            (state_node.text or "").strip()
            if state_node is not None
            else None
        )

        country_node = mailing.find("COUNTRY")
        country = (
            (country_node.text or "").strip()
            if country_node is not None
            else None
        )

        pincode = safe_text(mailing, "PINCODE")

        city = (
            safe_text(mailing, "CITY")
            or safe_text(mailing, "PLACEOFSUPPLY")
            or None
        )

    address = "\n".join(address_lines) if address_lines else None

    mailing_name = safe_text(ledger, "MAILINGNAME") or customer_name

    # --- Contact details ---
    mobile_number = normalize_phone(
        safe_text(ledger, "MOBILE")
        or safe_text(ledger, "MOBILENO")
        or safe_text(ledger, "LEDGERMOBILE")
        or safe_text(ledger, "PARTYMOBILENO")
    )

    email = (
        safe_text(ledger, "EMAIL")
        or safe_text(ledger, "PARTYEMAIL")
    )

    contact_person = (
        safe_text(ledger, "CONTACTPERSON")
        or safe_text(ledger, "CONTACT")
    )

    # --- GST / PAN ---
    gst_number = None
    gst_details = ledger.find("LEDGSTREGDETAILS.LIST")

    if gst_details is not None:
        gst_number = safe_text(gst_details, "GSTIN")

    if not gst_number:
        gst_number = safe_text(ledger, "PARTYGSTIN")

    pan_number = (
        safe_text(ledger, "PANNUMBER")
        or safe_text(ledger, "PAN")
    )

    # --- Financial ---
    ob_raw = safe_text(ledger, "OPENINGBALANCE")
    opening_balance, _ = parse_opening_balance(ob_raw)

    credit_limit = parse_amount(safe_text(ledger, "CREDITLIMIT"))

    credit_period_raw = safe_text(ledger, "CREDITPERIOD")
    credit_period = credit_period_raw if credit_period_raw else None

    customer_discount_percentage = (
        parse_amount(
            safe_text(ledger, "DISCOUNTPERCENTAGE")
        ) or 0
    )

    return {
        "customer_name":
            customer_name,

        "mobile_number":
            mobile_number,

        "address":
            address,

        "city":
            city,

        "state":
            state,

        "pincode":
            pincode,

        "gst_number":
            gst_number,

        "MasterID":
            master_id,

        "Guid":
            guid,

        "customer_discount_percentage":
            customer_discount_percentage,

        "customer_category_name":
            ledger_type,

        "ledger_group":
            ledger_type,

        "ledger_group_parent":
            resolve_group_parent(ledger_type, group_parents or {}),

        "cust_category":
            extract_cust_category(ledger),

        "company_id":
            company_id,

        "company_name":
            company_name,

        "updated_at":
            datetime.now(
                timezone.utc
            ).isoformat(),
    }


LEDGER_FETCH_FIELDS = (
    "NAME, PARENT, OPENINGBALANCE, CLOSINGBALANCE, MAILINGNAME.LIST, ADDRESS.LIST, "
    "STATE, COUNTRY, PINCODE, CITY, PLACEOFSUPPLY, MOBILE, MOBILENO, LEDGERMOBILE, "
    "PARTYMOBILENO, PHONENUMBER, LEDGERPHONE, PARTYPHONENO, EMAIL, PARTYEMAIL, "
    "CONTACTPERSON, CONTACT, LEDGSTREGDETAILS.LIST, CREDITLIMIT, CREDITPERIOD, "
    "LEDGERCODE, ALTERID, MASTERID, GUID, PARTYGSTIN, "
    "UDF:SDKCUSTCATEGORY, SdkCustCategory, SdkCustClassSundry, "
    "CUSTCATEGORY, CUST.CATEGORY, CUST_CATEGORY, LEDCUSTCATEGORY, CUSTCAT"
)


def _customer_row_key(row):
    guid = str(row.get("Guid") or "").strip()
    master_id = str(row.get("MasterID") or "").strip()
    if guid or master_id:
        return ("id", guid, master_id)
    return ("name", row.get("customer_name") or "")


def _parse_customer_ledgers(xml_text, company_name, company_id, group_parents):
    root = ET.fromstring(clean_tally_xml(xml_text))
    rows = []
    for ledger in root.findall(".//COLLECTION/LEDGER"):
        name = ledger.attrib.get("NAME", "").strip()
        if not name:
            continue
        rows.append(
            extract_customer_data(ledger, company_name, company_id, group_parents)
        )
    return rows


def _request_ledger_xml(
    config,
    child_of=None,
    belongsto=True,
    fetch_fields=LEDGER_FETCH_FIELDS,
    timeout=300,
):
    child_xml = ""
    if child_of:
        belong_value = "Yes" if belongsto else "No"
        child_xml = (
            f"<CHILDOF>{xml_escape(child_of)}</CHILDOF>\n"
            f"                        <BELONGSTO>{belong_value}</BELONGSTO>"
        )

    xml_request = f"""
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Ledger Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Ledger Collection">
                        <TYPE>Ledger</TYPE>
                        {child_xml}
                        <FETCH>{fetch_fields}</FETCH>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""
    tally_url = f"http://localhost:{config['tally_port']}"
    response = requests.post(
        tally_url,
        data=xml_request.encode("utf-8"),
        headers={"Content-Type": "application/xml", "Connection": "close"},
        timeout=timeout,
    )
    response.raise_for_status()
    return response.text


def _count_named_ledgers(xml_text):
    root = ET.fromstring(clean_tally_xml(xml_text))
    count = 0
    for ledger in root.findall(".//COLLECTION/LEDGER"):
        if (ledger.attrib.get("NAME") or "").strip():
            count += 1
    return count


def _fetch_ledger_collection(
    config,
    company_name,
    company_id=None,
    group_parents=None,
    child_of=None,
    belongsto=True,
    timeout=300,
):
    xml_text = _request_ledger_xml(
        config,
        child_of=child_of,
        belongsto=belongsto,
        timeout=timeout,
    )
    return _parse_customer_ledgers(
        xml_text, company_name, company_id, group_parents
    )


def _top_level_group_names(group_parents):
    names = []
    for name, parent in (group_parents or {}).items():
        parent_name = (parent or "").strip()
        if not parent_name or parent_name.lower() == _PRIMARY_GROUP:
            names.append(name)
    return names


CUST_CATEGORY_TDL_ATTEMPTS = (
    ("sdkCustCategory", "$sdkCustCategory"),
    ("SdkCustCategory", "$SdkCustCategory"),
    ("SdkCustClassSundry", "$SdkCustClassSundry"),
    ("Cust.Category", "$Cust.Category"),
    ("CustCategory", "$CustCategory"),
    ("Cust Category", "$Cust Category"),
    ("LEDCustCategory", "$LEDCustCategory"),
    ("LED Cust Category", "$LED Cust Category"),
)


def _request_cust_category_xml(config, native_name, formula, timeout=180):
    xml_request = f"""
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Cust Category Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Cust Category Collection">
                        <TYPE>Ledger</TYPE>
                        <FETCH>NAME, GUID, MASTERID</FETCH>
                        <NATIVEMETHOD>{xml_escape(native_name)}</NATIVEMETHOD>
                        <COMPUTE>CUSTCATEGORY:{xml_escape(formula)}</COMPUTE>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
"""
    tally_url = f"http://localhost:{config['tally_port']}"
    response = requests.post(
        tally_url,
        data=xml_request.encode("utf-8"),
        headers={"Content-Type": "application/xml", "Connection": "close"},
        timeout=timeout,
    )
    response.raise_for_status()
    return response.text


def _parse_cust_category_map(xml_text):
    root = ET.fromstring(clean_tally_xml(xml_text))
    mapping = {}
    for ledger in root.findall(".//COLLECTION/LEDGER"):
        name = (ledger.attrib.get("NAME") or "").strip()
        guid = safe_text(ledger, "GUID") or (ledger.attrib.get("GUID") or "").strip()
        category = extract_cust_category(ledger)
        if not category:
            continue
        if guid:
            mapping[("guid", guid)] = category
        if name:
            mapping[("name", name)] = category
    return mapping


def _fetch_cust_category_map(config):
    """Pull Tally UDF Cust.Category. Standard FETCH skips custom fields."""
    for native_name, formula in CUST_CATEGORY_TDL_ATTEMPTS:
        try:
            xml_text = _request_cust_category_xml(config, native_name, formula)
            if "<LINEERROR" in xml_text.upper():
                logging.warning(
                    "  Cust.Category TDL error for %s: %s",
                    native_name,
                    xml_text[:300].replace("\n", " "),
                )
                continue
            mapping = _parse_cust_category_map(xml_text)
            filled_names = len({key[1] for key in mapping if key[0] == "name"})
            logging.info(
                "  Cust.Category via %s: %s ledgers with a value",
                native_name,
                filled_names,
            )
            if mapping:
                return mapping
        except Exception as exc:
            logging.warning("  Cust.Category fetch %s failed: %s", native_name, exc)
    logging.warning("  Cust.Category was not returned by Tally (all TDL names empty)")
    return {}


def _apply_cust_category_map(customers, mapping):
    if not mapping:
        return 0
    filled = 0
    for row in customers:
        category = mapping.get(("guid", str(row.get("Guid") or "").strip())) or mapping.get(
            ("name", row.get("customer_name") or "")
        )
        if not category:
            continue
        row["cust_category"] = category
        filled += 1
    return filled


def get_customers():
    config = load_config()
    company_details = get_company_details()
    company_name = company_details.get("company_name", "")
    company_id = None
    try:
        supabase = create_client(config["supabase_url"], config["supabase_key"])
        resolved = resolve_company_row(supabase, company_details)
        if resolved:
            company_id = str(resolved.get("id") or "")
    except Exception as e:
        logging.info(f"Failed to fetch company_id: {e}")

    tally_url = f"http://localhost:{config['tally_port']}"
    group_parents = get_ledger_group_parents(tally_url)

    tally_ledger_count = 0
    try:
        tally_ledger_count = _count_named_ledgers(
            _request_ledger_xml(
                config,
                child_of=None,
                fetch_fields="NAME, PARENT, MASTERID, GUID",
                timeout=180,
            )
        )
        logging.info("  Tally ledger master count: %s", tally_ledger_count)
    except Exception as e:
        logging.warning("Could not count Tally ledgers: %s", e)

    seen = set()
    all_customers = []

    def add_rows(rows, label):
        added = 0
        for row in rows or []:
            key = _customer_row_key(row)
            if key in seen:
                continue
            seen.add(key)
            all_customers.append(row)
            added += 1
        logging.info(
            "  %s: +%s ledgers (total %s)",
            label,
            added,
            len(all_customers),
        )

    try:
        add_rows(
            _fetch_ledger_collection(
                config,
                company_name,
                company_id,
                group_parents,
                child_of=None,
                timeout=300,
            ),
            "All ledgers",
        )
    except Exception as e:
        logging.warning("Full ledger collection failed: %s", e)

    missing = tally_ledger_count > len(all_customers)
    if missing or not all_customers:
        logging.info(
            "  Filling remaining ledgers by top-level group "
            "(have %s, Tally has %s)",
            len(all_customers),
            tally_ledger_count or "unknown",
        )
        top_groups = _top_level_group_names(group_parents)
        for reserved in ("Primary", "$$GroupPrimary"):
            if reserved not in top_groups:
                top_groups.append(reserved)

        for group_name in top_groups:
            try:
                add_rows(
                    _fetch_ledger_collection(
                        config,
                        company_name,
                        company_id,
                        group_parents,
                        child_of=group_name,
                        belongsto=True,
                        timeout=180,
                    ),
                    group_name,
                )
            except Exception as e:
                logging.warning("Ledger group '%s' failed: %s", group_name, e)

    try:
        category_map = _fetch_cust_category_map(config)
        filled = _apply_cust_category_map(all_customers, category_map)
        logging.info(
            "  Cust.Category applied to %s of %s ledgers",
            filled,
            len(all_customers),
        )
    except Exception as exc:
        logging.warning("  Cust.Category merge failed: %s", exc)

    logging.info("  Total ledgers found: %s", len(all_customers))
    return all_customers

def save_customers_to_supabase(customers):

    config = load_config()

    supabase = create_client(
        config["supabase_url"],
        config["supabase_key"]
    )

    if not customers:
        logging.info("No customers to save.")
        return 0

    VARCHAR15_FIELDS = (
        "mobile_number",
        "pincode",
        "gst_number",
        "city",
        "state",
    )

    def clip_row(row):
        clipped = dict(row)
        for field in VARCHAR15_FIELDS:
            value = clipped.get(field)
            if isinstance(value, str) and len(value) > 15:
                clipped[field] = value[:15]
        return clipped

    def upload_rows(rows, clip=False):
        payload = [clip_row(row) for row in rows] if clip else rows
        supabase.table("customers").upsert(
            payload,
            on_conflict="MasterID,Guid",
        ).execute()
        return len(rows)

    BATCH_SIZE = 100
    total_saved = 0
    failed = 0
    batches = [customers[i: i + BATCH_SIZE] for i in range(0, len(customers), BATCH_SIZE)]

    for batch_index, batch in enumerate(batches, start=1):
        try:
            total_saved += upload_rows(batch)
            continue
        except Exception as e:
            logging.error("Batch %s upload failed: %s", batch_index, e)

        for row in batch:
            try:
                total_saved += upload_rows([row])
            except Exception:
                try:
                    total_saved += upload_rows([row], clip=True)
                except Exception as row_error:
                    failed += 1
                    logging.error(
                        "Ledger upload failed (%s): %s",
                        row.get("customer_name"),
                        row_error,
                    )

    logging.info(
        "Saved %s of %s ledgers (%s failed)",
        total_saved,
        len(customers),
        failed,
    )
    return total_saved


# =====================================================
# MAIN
# =====================================================

if __name__ == "__main__":

    import sys

    try:

        sync_type = sys.argv[1] if len(sys.argv) > 1 else "customers"

        if sync_type == "customers":

            print("Fetching customers from Tally...\n")
            customers = get_customers()
            print(f"Found {len(customers)} total records.\n")

            print("Saving to Supabase...\n")
            saved = save_customers_to_supabase(customers)
            print(f"Customers synced successfully ({saved} records).")


        else:

            print("Fetching ledgers from Tally...\n")
            ledgers = get_ledgers()
            print(f"Found {len(ledgers)} ledgers.\n")

            print("Saving to Supabase...\n")
            save_ledgers_to_supabase(ledgers)
            print(f"Ledgers synced successfully ({len(ledgers)} records).")

    except Exception as e:

        print(f"\nSync failed: {e}")

        raise
