// supabase/functions/check-tally-stock/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

// CORS headers for Flutter app
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface StockRequest {
  productCode: string;
  tallyServerUrl: string;
  tallyPort: number;
  companyName: string;
}

interface StockResponse {
  success: boolean;
  productCode: string;
  productName: string;
  currentStock: number;
  unit: string;
  lastUpdated: string;
  error?: string;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { productCode, tallyServerUrl, tallyPort, companyName }: StockRequest = await req.json()

    console.log('📦 Stock check request:', { productCode, tallyServerUrl, tallyPort, companyName })

    // Validate input
    if (!productCode || !tallyServerUrl || !tallyPort || !companyName) {
      throw new Error('Missing required parameters: productCode, tallyServerUrl, tallyPort, or companyName')
    }

    // Build Tally XML request to fetch stock
    const tallyXmlRequest = buildTallyStockQuery(productCode, companyName)

    console.log('📤 Sending request to Tally:', `http://${tallyServerUrl}:${tallyPort}`)

    // Make HTTP request to Tally
    const tallyUrl = `http://${tallyServerUrl}:${tallyPort}`
    const tallyResponse = await fetch(tallyUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/xml',
        'Content-Length': tallyXmlRequest.length.toString(),
      },
      body: tallyXmlRequest,
    })

    if (!tallyResponse.ok) {
      throw new Error(`Tally server error: ${tallyResponse.status} ${tallyResponse.statusText}`)
    }

    const xmlResponse = await tallyResponse.text()
    console.log('📥 Received response from Tally')
    
    // Parse Tally XML response
    const stockData = parseTallyStockResponse(xmlResponse, productCode)

    const response: StockResponse = {
      success: true,
      productCode: stockData.productCode,
      productName: stockData.productName,
      currentStock: stockData.currentStock,
      unit: stockData.unit,
      lastUpdated: new Date().toISOString(),
    }

    console.log('✅ Stock check successful:', response)

    return new Response(
      JSON.stringify(response),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      },
    )

  } catch (error) {
    console.error('❌ Error checking Tally stock:', error)
    
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error.message || 'Failed to check stock from Tally',
        productCode: '',
        productName: '',
        currentStock: 0,
        unit: '',
        lastUpdated: new Date().toISOString(),
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      },
    )
  }
})

/**
 * Build XML query for Tally to fetch stock item details
 * 
 * This uses Tally's XML API with TDL (Tally Definition Language) to query stock
 * 
 * @param productCode - The product code (PartNumber) to search for
 * @param companyName - The Tally company name to query
 * @returns XML string for Tally request
 */
function buildTallyStockQuery(productCode: string, companyName: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Data</TYPE>
    <ID>StockItemQuery</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        <SVCURRENTCOMPANY>${escapeXml(companyName)}</SVCURRENTCOMPANY>
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="StockItems">
            <TYPE>Stock Item</TYPE>
            <FETCH>Name, PartNumber, ClosingBalance, BaseUnits</FETCH>
            <FILTER>PartNumberFilter</FILTER>
          </COLLECTION>
          <SYSTEM TYPE="Formulae" NAME="PartNumberFilter">
            $$String:$PartNumber = "${escapeXml(productCode)}"
          </SYSTEM>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>`
}

/**
 * Parse Tally XML response to extract stock information
 * 
 * Tally returns XML with stock item details. This function extracts:
 * - Product name
 * - Current stock (closing balance)
 * - Unit of measurement
 * 
 * @param xmlResponse - XML response from Tally
 * @param productCode - Original product code for reference
 * @returns Parsed stock data
 */
function parseTallyStockResponse(xmlResponse: string, productCode: string): any {
  console.log('🔍 Parsing Tally XML response...')
  
  // Check for error in response
  if (xmlResponse.includes('<ERROR>') || xmlResponse.includes('</ERROR>')) {
    const errorMatch = xmlResponse.match(/<ERROR[^>]*>(.*?)<\/ERROR>/i)
    throw new Error(`Tally error: ${errorMatch ? errorMatch[1] : 'Unknown error'}`)
  }

  // Extract product name
  const nameMatch = xmlResponse.match(/<NAME[^>]*>(.*?)<\/NAME>/i)
  
  // Extract closing balance (stock quantity)
  const stockMatch = xmlResponse.match(/<CLOSINGBALANCE[^>]*>(.*?)<\/CLOSINGBALANCE>/i)
  
  // Extract unit
  const unitMatch = xmlResponse.match(/<BASEUNITS[^>]*>(.*?)<\/BASEUNITS>/i)

  if (!nameMatch || !stockMatch) {
    console.error('Product not found in Tally response')
    throw new Error(`Product with code "${productCode}" not found in Tally`)
  }

  const stockValue = parseFloat(stockMatch[1].trim()) || 0

  const result = {
    productCode: productCode,
    productName: nameMatch[1].trim(),
    currentStock: stockValue,
    unit: unitMatch ? unitMatch[1].trim() : 'Nos',
  }

  console.log('✅ Parsed stock data:', result)
  return result
}

/**
 * Escape XML special characters to prevent injection
 */
function escapeXml(unsafe: string): string {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

/* 
 * DEPLOYMENT INSTRUCTIONS:
 * 
 * 1. Install Supabase CLI:
 *    npm install -g supabase
 * 
 * 2. Login to Supabase:
 *    supabase login
 * 
 * 3. Link your project:
 *    supabase link --project-ref your-project-ref
 * 
 * 4. Deploy this function:
 *    supabase functions deploy check-tally-stock
 * 
 * 5. Test locally:
 *    supabase functions serve check-tally-stock
 * 
 * 6. Test with curl:
 *    curl -X POST http://localhost:54321/functions/v1/check-tally-stock \
 *      -H "Content-Type: application/json" \
 *      -d '{
 *        "productCode": "PROD001",
 *        "tallyServerUrl": "localhost",
 *        "tallyPort": 9000,
 *        "companyName": "Your Company Name"
 *      }'
 */
