import sys
sys.path.insert(0, '.')
from src.tally_client import TallyClient

client = TallyClient()

create_ledger_xml = """<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Import Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <IMPORTDATA>
      <REQUESTDESC>
        <REPORTNAME>All Masters</REPORTNAME>
      </REQUESTDESC>
      <REQUESTDATA>
        <TALLYMESSAGE xmlns:UDF="TallyUDF">
          <LEDGER NAME="Round Off" ACTION="Create">
            <NAME.LIST>
              <NAME>Round Off</NAME>
            </NAME.LIST>
            <PARENT>Indirect Expenses</PARENT>
          </LEDGER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>"""

res = client.send_request(create_ledger_xml)
print("Create Ledger Result:", res)

