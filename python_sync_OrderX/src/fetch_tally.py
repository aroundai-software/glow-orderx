import requests

xml_request = '''
<ENVELOPE>
    <HEADER>
        <VERSION>1</VERSION>
        <TALLYREQUEST>Export</TALLYREQUEST>
        <TYPE>Collection</TYPE>
        <ID>Stock Item Collection</ID>
    </HEADER>
    <BODY>
        <DESC>
            <TDL>
                <TDLMESSAGE>
                    <COLLECTION NAME="Stock Item Collection">
                        <TYPE>Stock Item</TYPE>
                        <FETCH>NAME, HSNDETAILS.LIST, HSNCODE</FETCH>
                        <MAX>1</MAX>
                    </COLLECTION>
                </TDLMESSAGE>
            </TDL>
        </DESC>
    </BODY>
</ENVELOPE>
'''
response = requests.post("http://localhost:9000", data=xml_request.encode('utf-8'))
with open("tally_item_dump.xml", "w", encoding="utf-8") as f:
    f.write(response.text)
