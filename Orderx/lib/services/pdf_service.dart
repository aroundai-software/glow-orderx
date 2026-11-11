import 'dart:io';
import 'dart:typed_data';

import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:Orderx/utils/number_to_words.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/utils/pdf_downloader_stub.dart'
    if (dart.library.html) 'package:Orderx/utils/pdf_downloader_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:Orderx/models/admin_settings.dart';
import 'package:Orderx/models/activity_log_model.dart';
import 'package:Orderx/services/admin_settings_service.dart';

class PdfService {

  Future<Uint8List> generateOrderPdf(
    OrderModel order,
    List<OrderItemModel> items, {
    TallyCompanyModel? company,
    String? companyName,
    AdminSettings? settings,
    String documentTitle = 'SALES ORDER',
  }) async {
    try {
      if (settings == null && order.companyId != null && order.companyId!.isNotEmpty) {
        try {
          settings = await AdminSettingsService().getAdminSettings(order.companyId!);
        } catch (e) {
          print('Error fetching settings for PDF: $e');
        }
      }
      final pdf = pw.Document();

      // Load Roboto Bold font dynamically to support the Indian Rupee symbol (₹)
      pw.Font? rupeeFont;
      try {
        rupeeFont = await PdfGoogleFonts.robotoBold();
      } catch (e) {
        // Fallback to null if offline, we'll use Rs. instead
      }

      Uint8List? logoBytes;
      // try {
      //   final ByteData data = await rootBundle.load('assets/images/sip_logo.png');
      //   logoBytes = data.buffer.asUint8List();
      // } catch (e) {
      //   logoBytes = null;
      // }
      logoBytes = null;
      final String finalCompanyName = companyName ?? company?.companyName ?? 'YOUR COMPANY NAME';
      final String companyGst = settings?.invoiceGst ?? company?.gstNumber ?? 'YOURGSTIN12345';
      final String companyGstCode = companyGst.length >= 2 ? companyGst.substring(0, 2) : '00';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) {
            return [
              pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(documentTitle, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
              ),
              
              _buildHeaderGrid(logoBytes, order, finalCompanyName, companyGst, companyGstCode, settings),
              ..._buildItemsTable(items, order, rupeeFont, companyGstCode),
              _buildFooterGrid(order, items, finalCompanyName, settings),
            ];
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      rethrow;
    }
  }

  pw.Widget _buildHeaderGrid(Uint8List? logoBytes, OrderModel order, String companyName, String companyGst, String companyGstCode, AdminSettings? settings) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
      },
      border: const pw.TableBorder(
        top: pw.BorderSide(color: PdfColors.black, width: 0.5),
        left: pw.BorderSide(color: PdfColors.black, width: 0.5),
        right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
        verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
      ),
      children: [
        pw.TableRow(
          children: [
            // Left Column
            pw.Container(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Company Details
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoBytes != null)
                          pw.Container(
                            width: 45,
                            height: 45,
                            margin: const pw.EdgeInsets.only(right: 8),
                            child: pw.Image(
                              pw.MemoryImage(logoBytes),
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(companyName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              pw.SizedBox(height: 2),
                              pw.Text(settings?.invoiceAddressLine1 ?? 'Your Company Address Line 1', style: const pw.TextStyle(fontSize: 8)),
                              pw.SizedBox(height: 1),
                              pw.Text(settings?.invoiceAddressLine2 ?? 'Your Company Address Line 2', style: const pw.TextStyle(fontSize: 8)),
                              pw.SizedBox(height: 1),
                              pw.Text(settings?.invoiceCityStatePin ?? 'City, State\nPincode: 000000', style: const pw.TextStyle(fontSize: 8)),
                              pw.SizedBox(height: 1),
                              pw.Text('GSTIN/UIN: $companyGst', style: const pw.TextStyle(fontSize: 8)),
                              pw.SizedBox(height: 1),
                              pw.Text(_getStateFromGst(companyGst), style: const pw.TextStyle(fontSize: 8)),
                              if (settings?.contactPhone != null && settings!.contactPhone!.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text('Phone: ${settings.contactPhone}', style: const pw.TextStyle(fontSize: 8)),
                              ],
                              if (settings?.contactEmail != null && settings!.contactEmail!.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text('Email: ${settings.contactEmail}', style: const pw.TextStyle(fontSize: 8)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                  // Buyer Details
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Buyer (Bill to)', style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(height: 2),
                        if (order.customerName != null && order.customerName!.isNotEmpty)
                          pw.Text(order.customerName!, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2),
                        pw.Text(order.customerAddress ?? '', style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(height: 2),
                        if (_getStateFromGst(order.customerGst).isNotEmpty)
                          pw.Text(_getStateFromGst(order.customerGst), style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(height: 2),
                        pw.Text('Contact        : ${order.customerMobile ?? ''}', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Right Column
            pw.Column(
              children: [
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Container(padding: const pw.EdgeInsets.all(6), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Voucher No.', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.orderNumber, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                        pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Dated', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(DateFormat('d-MMM-yy').format(order.orderDate), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Container(padding: const pw.EdgeInsets.all(6), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Mode/Terms of Payment', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.ledger, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                        pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Other References', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text('', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Buyer\'s Ref./Order No.', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.orderNumber, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Container(padding: const pw.EdgeInsets.all(6), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Dispatched through', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.dispatchedThrough ?? '', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                        pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Destination', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.destination ?? '', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  width: double.infinity,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Terms of Delivery', style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 35), // Space for terms
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  List<pw.Widget> _buildItemsTable(List<OrderItemModel> items, OrderModel order, pw.Font? rupeeFont, String companyGstCode) {
    final double tableSubtotal = items.fold(0.0, (sum, it) {
      final baseAmount = it.totalAmount - it.gstAmount;
      return sum + (baseAmount < 0 ? 0 : baseAmount);
    });

    final double unroundedTotal = tableSubtotal - order.orderDiscountAmount + order.gstAmount;
    final RoundOffResult roundOff = calculateRoundOff(unroundedTotal);
    final double roundedGrandTotal = roundOff.roundedTotal;
    
    final headers = ['Sl\nNo.', 'Description of Goods', 'Due on', 'Quantity', 'Rate', 'per', 'Disc. %', 'Amount'];

    List<pw.TableRow> itemRows = [];
    List<pw.TableRow> totalRows = [];
    
    // Header Row with bottom border
    itemRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5)),
        ),
        children: headers.map((h) => _buildTableCell(h, align: pw.TextAlign.center, isHeader: true)).toList(),
      )
    );

    int totalQty = 0;
    // Item Rows (no horizontal border, just right vertical borders)
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final totalWithGst = item.totalAmount;
      double amountExcludingGst = totalWithGst - item.gstAmount;
      if (amountExcludingGst < 0) amountExcludingGst = 0;
      totalQty += item.ItemQuantity.toInt();

      itemRows.add(
        pw.TableRow(
          children: [
            _buildTableCell('${i + 1}', align: pw.TextAlign.center),
            _buildTableCell(item.ItemName, align: pw.TextAlign.left, isBold: true),
            _buildTableCell(DateFormat('d-MMM-yy').format(order.orderDate), align: pw.TextAlign.center, isItalic: true),
            _buildTableCell('${item.ItemQuantity.toStringAsFixed(0)} nos', align: pw.TextAlign.right, isBold: true),
            _buildTableCell(item.ItemRate.toStringAsFixed(2), align: pw.TextAlign.right),
            _buildTableCell('nos', align: pw.TextAlign.center),
            _buildTableCell(item.discountPercentage > 0 ? item.discountPercentage.toStringAsFixed(2) : '', align: pw.TextAlign.center),
            _buildTableCell(amountExcludingGst.toStringAsFixed(2), align: pw.TextAlign.right, isBold: true),
          ]
        )
      );
    }
    
    // Add empty rows to pad the table and push footer down
    final int minRows = 8; // Reduced to 8 to comfortably fit on a single page layout
    final int emptyRowsNeeded = minRows - items.length;
    if (emptyRowsNeeded > 0) {
      for (int i = 0; i < emptyRowsNeeded; i++) {
        itemRows.add(
          pw.TableRow(
            children: [
              _buildTableCell(''),
              _buildTableCell(''),
              _buildTableCell(''),
              _buildTableCell(''),
              _buildTableCell(''),
              _buildTableCell(''),
              _buildTableCell(''),
              _buildTableCell(''),
            ]
          )
        );
      }
    } else {
      // If we have many items, just add one empty padding row so items don't touch subtotals
      itemRows.add(
        pw.TableRow(
          children: List.generate(8, (index) => _buildTableCell('', padding: const pw.EdgeInsets.only(top: 20)))
        )
      );
    }

    // Subtotal Row (Line above the amount only!)
    itemRows.add(
      pw.TableRow(
        children: [
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            alignment: pw.Alignment.centerRight,
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 0.5)),
            ),
            child: pw.Text(tableSubtotal.toStringAsFixed(2), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ),
        ]
      )
    );

    // Order Discount Row
    if (order.orderDiscountAmount > 0) {
      itemRows.add(
        pw.TableRow(
          children: [
            _buildTableCell(''),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Discount', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
            ),
            _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('-${order.orderDiscountAmount.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
          ]
        )
      );
    }

    // Dynamic GST Calculation (CGST/SGST vs IGST)
    if (order.gstAmount > 0) {
      bool isLocal = true; // Default to local (Intra-state)
      if (order.customerGst != null && order.customerGst!.trim().length >= 2) {
        final customerGstCode = order.customerGst!.trim().substring(0, 2);
        if (customerGstCode != companyGstCode) {
          isLocal = false; // Inter-state
        }
      }

      if (isLocal) {
        final halfGst = order.gstAmount / 2;
        // CGST Row
        itemRows.add(
          pw.TableRow(
            children: [
              _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('CGST', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
              ),
              _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(halfGst.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
            ]
          )
        );
        // SGST Row
        itemRows.add(
          pw.TableRow(
            children: [
              _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('SGST', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
              ),
              _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(halfGst.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
            ]
          )
        );
      } else {
        // IGST Row
        itemRows.add(
          pw.TableRow(
            children: [
              _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('IGST', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
              ),
              _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(order.gstAmount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
            ]
          )
        );
      }
    }

    // Round Off Row
    final formattedRoundOff = roundOff.formattedRoundOff;
    final isDeduction = formattedRoundOff.startsWith('-');
    final displayValue = isDeduction ? formattedRoundOff : '+${formattedRoundOff.replaceFirst('+', '')}';
    final prefixText = isDeduction ? 'Less :' : 'Add :';

    itemRows.add(
      pw.TableRow(
        children: [
          _buildTableCell(''),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(prefixText, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
                pw.Text('Round Off', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
              ]
            ),
          ),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(displayValue, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ),
        ]
      )
    );

    // Padding before total
    itemRows.add(
      pw.TableRow(
        children: List.generate(8, (index) => pw.SizedBox(height: 10))
      )
    );

    // Final Total Row (Has top border)
    totalRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 0.5)),
        ),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Total', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.SizedBox(),
          pw.SizedBox(),
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            alignment: pw.Alignment.centerRight,
            decoration: const pw.BoxDecoration(
              border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5)), // Add right border to separate quantity and rate area
            ),
            child: pw.Text('$totalQty nos', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(),
          pw.SizedBox(),
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5)),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              rupeeFont != null ? '₹ ${roundedGrandTotal.toStringAsFixed(2)}' : 'Rs. ${roundedGrandTotal.toStringAsFixed(2)}', 
              textAlign: pw.TextAlign.right, 
              style: pw.TextStyle(
                font: rupeeFont, // This renders the Rupee symbol perfectly if loaded
                fontSize: 9, 
                fontWeight: pw.FontWeight.bold,
              )
            ),
          ),
        ]
      )
    );

    final columnWidths = const {
      0: pw.FlexColumnWidth(0.5),
      1: pw.FlexColumnWidth(3.0),
      2: pw.FlexColumnWidth(1.2),
      3: pw.FlexColumnWidth(1.0),
      4: pw.FlexColumnWidth(0.8),
      5: pw.FlexColumnWidth(0.5),
      6: pw.FlexColumnWidth(0.8),
      7: pw.FlexColumnWidth(1.2),
    };

    return [
      pw.Table(
        border: const pw.TableBorder(
          left: pw.BorderSide(color: PdfColors.black, width: 0.5),
          right: pw.BorderSide(color: PdfColors.black, width: 0.5),
          verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
        columnWidths: columnWidths,
        children: itemRows,
      ),
      pw.Table(
        border: const pw.TableBorder(
          left: pw.BorderSide(color: PdfColors.black, width: 0.5),
          right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
        columnWidths: columnWidths,
        children: totalRows,
      ),
    ];
  }

  String _getStateFromGst(String? gst) {
    if (gst == null || gst.trim().length < 2) return '';
    final code = gst.trim().substring(0, 2);
    final states = {
      '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh',
      '05': 'Uttarakhand', '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan',
      '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh',
      '13': 'Nagaland', '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura',
      '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand',
      '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat',
      '25': 'Daman & Diu', '26': 'Dadra & Nagar Haveli', '27': 'Maharashtra',
      '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep', '32': 'Kerala',
      '33': 'Tamil Nadu', '34': 'Puducherry', '35': 'Andaman & Nicobar Islands',
      '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh'
    };
    final stateName = states[code];
    if (stateName != null) {
      return 'State : $stateName, Code : $code';
    }
    return '';
  }

  pw.Widget _buildTableCell(String text, {
    pw.TextAlign align = pw.TextAlign.left, 
    bool isBold = false, 
    bool isItalic = false,
    bool isHeader = false,
    bool isLast = false,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(4),
  }) {
    return pw.Container(
      padding: padding,
      child: text.isEmpty ? pw.SizedBox() : pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8, 
          fontWeight: isBold || isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
        ),
      ),
    );
  }

  pw.Widget _buildFooterGrid(OrderModel order, List<OrderItemModel> items, String companyName, AdminSettings? settings) {
    final double tableSubtotal = items.fold(0.0, (sum, it) {

      final baseAmount = it.totalAmount - it.gstAmount;
      return sum + (baseAmount < 0 ? 0 : baseAmount);
    });
    final double unroundedTotal = tableSubtotal - order.orderDiscountAmount + order.gstAmount;
    final RoundOffResult roundOff = calculateRoundOff(unroundedTotal);
    final double roundedGrandTotal = roundOff.roundedTotal;

    final String amountInWords = NumberToWords.convertAmount(roundedGrandTotal);

    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.black, width: 0.5),
          left: pw.BorderSide(color: PdfColors.black, width: 0.5),
          right: pw.BorderSide(color: PdfColors.black, width: 0.5),
          bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
        // Top Row: Amount in words & E.&O.E
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Amount Chargeable (in words)', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(amountInWords, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ]
              ),
              pw.Text('E. & O.E', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
            ]
          )
        ),
        
        pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
        
        // Split section via Table
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          },
          border: const pw.TableBorder(
            verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
          ),
          children: [
            pw.TableRow(
              children: [
                // Left: PAN & Declaration
                pw.Container(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Row(
                          children: [
                            pw.Text('Company\'s PAN', style: const pw.TextStyle(fontSize: 8)),
                            pw.SizedBox(width: 40),
                            pw.Text(': ${settings?.invoicePan ?? 'YOURPAN123'}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                      pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Declaration', style: pw.TextStyle(fontSize: 8, decoration: pw.TextDecoration.underline)),
                            pw.Text('This Proforma invoice will be valid for 1 week after its\ndate of issuance.', style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ),
                    ]
                  )
                ),
                // Right: Bank details & Signatory
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Company\'s Bank Details', style: const pw.TextStyle(fontSize: 8)),
                          pw.Row(children: [pw.Container(width: 80, child: pw.Text('Bank Name', style: const pw.TextStyle(fontSize: 8))), pw.Text(': ${settings?.invoiceBankName ?? 'Your Bank Name'}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))]),
                          pw.Row(children: [pw.Container(width: 80, child: pw.Text('A/c No.', style: const pw.TextStyle(fontSize: 8))), pw.Text(': ${settings?.invoiceBankAccount ?? '000000000000'}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))]),
                          pw.Row(children: [pw.Container(width: 80, child: pw.Text('IFS Code', style: const pw.TextStyle(fontSize: 8))), pw.Text(': ${settings?.invoiceBankIfsc ?? 'YOUR000000'}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))]),
                        ],
                      ),
                    ),
                    pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      width: double.infinity,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('for $companyName', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 30),
                          pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                  ]
                )
              ]
            )
          ]
        ),
        pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
        pw.Center(
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('This is a Computer Generated Document', style: const pw.TextStyle(fontSize: 8))
          )
        )
      ],
    ));
  }

  Future<Uint8List> generateActivityReportPdf({
    required String title,
    required String periodLabel,
    required String salesmanLabel,
    required List<ActivityLog> logs,
  }) async {
    final pdf = pw.Document();
    final dateFmt = DateFormat('dd MMM yyyy');
    final timeFmt = DateFormat('hh:mm a');
    final reports = groupActivityLogs(logs);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Period: $periodLabel',
                style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Salesman: $salesmanLabel',
                style: const pw.TextStyle(fontSize: 10)),
            pw.Text(
              'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.Divider(thickness: 1),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ),
        build: (context) {
          if (reports.isEmpty) {
            return [pw.Text('No activity found for this period.')];
          }

          return [
            pw.Text(
              '${reports.length} salesman  ·  '
              '${logs.where((l) => l.type == ActivityLogType.login).length} login  ·  '
              '${logs.where((l) => l.type == ActivityLogType.logout).length} logout  ·  '
              '${logs.where((l) => l.type == ActivityLogType.orderCreated).length} orders',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
            ...reports.expand((report) {
              return [
                pw.Container(
                  width: double.infinity,
                  color: PdfColors.blue50,
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: pw.Text(
                    report.mobile == null || report.mobile!.isEmpty
                        ? report.salesmanName
                        : '${report.salesmanName}  (${report.mobile})',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                ...report.days.map((day) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          dateFmt.format(day.day),
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Login: ${day.firstLogin == null ? '-' : timeFmt.format(day.firstLogin!)}'
                          '${day.logins.length > 1 ? '  (${day.logins.length} times)' : ''}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text(
                          day.stillLoggedIn
                              ? 'Logout: Still logged in'
                              : 'Logout: ${day.lastLogout == null ? '-' : timeFmt.format(day.lastLogout!)}'
                                  '${day.logouts.length > 1 ? '  (${day.logouts.length} times)' : ''}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        if (day.orders.isEmpty)
                          pw.Text('Orders: none',
                              style: const pw.TextStyle(fontSize: 9))
                        else ...[
                          pw.SizedBox(height: 4),
                          pw.TableHelper.fromTextArray(
                            headers: ['Order No', 'Customer', 'Time', 'Amount'],
                            headerStyle: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            cellStyle: const pw.TextStyle(fontSize: 8),
                            headerDecoration: const pw.BoxDecoration(
                              color: PdfColors.grey200,
                            ),
                            cellAlignments: {
                              2: pw.Alignment.center,
                              3: pw.Alignment.centerRight,
                            },
                            data: day.orders
                                .map((o) => [
                                      o.orderNumber ?? '-',
                                      o.customerName ?? 'Walk-in',
                                      timeFmt.format(o.timestamp),
                                      o.orderAmount == null
                                          ? '-'
                                          : 'Rs. ${o.orderAmount!.toStringAsFixed(2)}',
                                    ])
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                pw.SizedBox(height: 8),
              ];
            }),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> sharePdf(Uint8List pdfBytes, String orderNumber, {String filenamePrefix = 'Order_'}) async {
    try {
      final sanitizedOrderNumber = orderNumber.replaceAll('/', '_').replaceAll('\\', '_');
      final filename = '$filenamePrefix$sanitizedOrderNumber.pdf';

      if (kIsWeb) {
        await downloadPdfOnWeb(filename, pdfBytes);
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await Printing.sharePdf(bytes: pdfBytes, filename: filename);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(pdfBytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Invoice $orderNumber',
          text: 'Please find attached invoice $orderNumber',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> printPdf(Uint8List pdfBytes) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }
}
