import 'dart:async';

import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/invoice_model.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/screens/salesman/edit_invoice_screen.dart';
import 'package:Orderx/services/invoice_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:intl/intl.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  final InvoiceModel invoice;

  const InvoiceDetailsScreen({super.key, required this.invoice});

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  final InvoiceService _invoiceService = InvoiceService();
  final PdfService _pdfService = PdfService();
  final TallyCompanyService _companyService = TallyCompanyService();

  late InvoiceModel _currentInvoice;
  List<InvoiceItemModel> _items = [];
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  int _editWindowMinutes = 30;
  bool _allowOrderEditing = true;
  bool _settingsLoaded = false;

  /// True if a sale_bill record exists for this order — blocks editing regardless
  /// of the synced_to_tally flag (which may not be updated reliably by the trigger).
  bool _isBilled = false;

  // Countdown timer — ticks every second so remaining time stays live
  Timer? _countdownTimer;

  bool get _canEditInvoice {
    if (_currentInvoice.syncedToTally) return false;
    if (_isBilled) return false; // billed in Tally — no edits allowed
    if (!_allowOrderEditing) return true;
    final now = DateTime.now().toUtc();
    final windowEnd =
        _currentInvoice.createdAt.toUtc().add(Duration(minutes: _editWindowMinutes));
    return now.isBefore(windowEnd) || _currentInvoice.hasAdminEditPermission;
  }

  @override
  void initState() {
    super.initState();
    _currentInvoice = widget.invoice;
    _loadItems();
    _loadEditWindow();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadEditWindow() async {
    try {
      final svc = AdminSettingsService();
      final companyId = context.read<AuthProvider>().selectedCompanyId!;
      final minutes = await svc.getOrderEditWindowMinutes(companyId);
      final settings = await svc.getAdminSettings(companyId);
      if (mounted) {
        setState(() {
          _editWindowMinutes = minutes;
          _allowOrderEditing = settings.allowOrderEditing;
          _settingsLoaded = true;
        });
        _startCountdown();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _settingsLoaded = true);
        _startCountdown();
      }
    }
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      // Reload both the invoice header (for updated totals) and items
      final allInvoices = await _invoiceService.getInvoicesBySalesman(
        _currentInvoice.salesmanId,
        companyId: _currentInvoice.companyId,
      );
      final updated =
          allInvoices.where((inv) => inv.id == _currentInvoice.id).firstOrNull;

      final items = await _invoiceService.getInvoiceItems(_currentInvoice.id);

      // Check sale_bill table directly — the trigger may not always update
      // synced_to_tally, so we do our own authoritative lookup.
      bool billedInTally = false;
      try {
        final billCheck = await _invoiceService.checkOrderBilledInTally(
          _currentInvoice.invoiceNumber,
        );
        billedInTally = billCheck;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        if (updated != null) _currentInvoice = updated;
        _items = items;
        _isBilled = billedInTally;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading invoice items: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // Convert InvoiceModel to OrderModel for PDF generation (reuse existing PdfService)
  OrderModel _toOrderModel(InvoiceModel inv) {
    return OrderModel(
      id: inv.id,
      orderNumber: inv.invoiceNumber,
      customerId: inv.customerId,
      customerName: inv.customerName,
      salesmanId: inv.salesmanId,
      orderDate: inv.invoiceDate,
      subtotalBeforeDiscount: inv.subtotalBeforeDiscount,
      orderDiscountAmount: inv.invoiceDiscountAmount,
      orderDiscountPercentage: inv.invoiceDiscountPercentage,
      totalAmount: inv.totalAmount,
      gstAmount: inv.gstAmount,
      netAmount: inv.netAmount,
      status: inv.status,
      notes: inv.notes,
      syncedToTally: inv.syncedToTally,
      tallySyncDate: inv.tallySyncDate,
      createdAt: inv.createdAt,
      updatedAt: inv.updatedAt,
      customerMobile: inv.customerMobile,
      customerAddress: inv.customerAddress,
      customerGst: inv.customerGst,
      shippingAddress: inv.shippingAddress,
      remarks: inv.remarks,
      companyId: inv.companyId,
      companyName: inv.companyName,
      ledger: inv.ledger,
    );
  }

  // Map invoice items to order items for PDF service
  List<OrderItemModel> _toOrderItems(List<InvoiceItemModel> items) {
    return items.map((i) {
      final double itemDisc = (i.itemDiscountAmount != 0)
          ? i.itemDiscountAmount
          : (i.discountAmount);
      return OrderItemModel(
        id: i.id,
        orderId: i.invoiceId,
        productId: i.productId,
        ItemName: i.productName,
        PartNumber: i.productCode,
        vtNumber: i.vtNumber,
        hsn: i.hsn,
        ItemQuantity: i.quantity,
        ItemRate: i.unitPrice,
        GstRate: i.gstRate,
        gstAmount: i.gstAmount,
        totalAmount: i.totalAmount,
        discountPercentage: i.discountPercentage,
        discountAmount: i.discountAmount,
        mrp: i.mrp,
        cashDiscountAmount: i.cashDiscountAmount,
        offerDiscountAmount: i.offerDiscountAmount,
        itemDiscountAmount: itemDisc,
      );
    }).toList();
  }

  Future<void> _shareInvoice() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to share'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);
    try {
      TallyCompanyModel? company;
      final companyId = _currentInvoice.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for invoice PDF share: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        _toOrderModel(_currentInvoice),
        _toOrderItems(_items),
        company: company,
        companyName: _currentInvoice.companyName,
        documentTitle: 'SALES ORDER',
      );

      if (!mounted) return;
      setState(() => _isGeneratingPdf = false);
      await _pdfService.sharePdf(pdfBytes, _currentInvoice.invoiceNumber,
          filenamePrefix: 'Invoice_');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingPdf = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing invoice: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _printInvoice() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to print'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);
    try {
      TallyCompanyModel? company;
      final companyId = _currentInvoice.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for invoice PDF print: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        _toOrderModel(_currentInvoice),
        _toOrderItems(_items),
        company: company,
        companyName: _currentInvoice.companyName,
        documentTitle: 'SALES ORDER',
      );

      await _pdfService.printPdf(pdfBytes);

      if (!mounted) return;
      setState(() => _isGeneratingPdf = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingPdf = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error printing invoice: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _editInvoice() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to edit'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_canEditInvoice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invoice edit window has expired'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditInvoiceScreen(
          invoice: _currentInvoice,
          items: _items,
        ),
      ),
    );

    if (result == true && mounted) {
      await _loadItems();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invoice updated successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], // light grey background behind the paper
      appBar: AppBar(
        title: const Text('Sale Bill'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loadItems,
            ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _isGeneratingPdf ? null : _printInvoice,
              tooltip: 'Print',
            ),
          if (!_isLoading && _canEditInvoice)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _isGeneratingPdf ? null : _editInvoice,
              tooltip: 'Edit Invoice',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 800), // constrain width for tablets
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPaperHeader(),
                          _buildBilledToSection(),
                          _buildItemsTable(),
                          _buildPaperSummary(),
                          if (_currentInvoice.notes != null && _currentInvoice.notes!.isNotEmpty)
                            _buildNotesSection(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isGeneratingPdf)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Generating PDF...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton:
          !_isLoading && !_isGeneratingPdf && _items.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _shareInvoice,
                  icon: const Icon(Icons.share),
                  label: const Text('Share Invoice'),
                  backgroundColor: AppTheme.primaryBlue,
                )
              : null,
    );
  }

  Widget _buildPaperHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppTheme.primaryBlue,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentInvoice.companyName ?? 'Sale Bill',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'INVOICE NO: ${_currentInvoice.invoiceNumber}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white.withOpacity(0.9),
                            letterSpacing: 1.1,
                          ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'DATE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withOpacity(0.7),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd MMM yyyy').format(_currentInvoice.invoiceDate.toLocal()),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBilledToSection() {
    if (_currentInvoice.customerName == null) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BILLED TO',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.grey,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentInvoice.customerName!,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
          ),
          const SizedBox(height: 8),
          if (_currentInvoice.customerAddress != null && _currentInvoice.customerAddress!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _currentInvoice.customerAddress!,
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          if (_currentInvoice.customerMobile != null && _currentInvoice.customerMobile!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Phone: ${_currentInvoice.customerMobile}',
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          if (_currentInvoice.customerGst != null && _currentInvoice.customerGst!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'GSTIN: ${_currentInvoice.customerGst}',
                style: const TextStyle(color: Colors.black87),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: Colors.grey[50],
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('ITEM', style: _tableHeaderStyle()),
              ),
              Expanded(
                flex: 1,
                child: Text('QTY', style: _tableHeaderStyle(), textAlign: TextAlign.right),
              ),
              Expanded(
                flex: 2,
                child: Text('RATE', style: _tableHeaderStyle(), textAlign: TextAlign.right),
              ),
              Expanded(
                flex: 2,
                child: Text('TOTAL', style: _tableHeaderStyle(), textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        // Table Rows
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No items found')),
          )
        else
          ..._items.map((item) {
            final qtyStr = item.quantity == item.quantity.truncateToDouble() 
                ? item.quantity.toInt().toString() 
                : item.quantity.toString();
            
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                        if (item.hsn != null && item.hsn!.isNotEmpty)
                          Text(
                            'HSN: ${item.hsn}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(qtyStr, textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('₹${item.unitPrice.toStringAsFixed(2)}', textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '₹${item.totalAmount.toStringAsFixed(2)}', 
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  TextStyle _tableHeaderStyle() {
    return const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Colors.black54,
      letterSpacing: 0.5,
    );
  }

  Widget _buildPaperSummary() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 250,
            child: Column(
              children: [
                _buildSummaryRow(
                  'Subtotal',
                  '₹${_currentInvoice.subtotalBeforeDiscount.toStringAsFixed(2)}',
                ),
                if (_currentInvoice.invoiceDiscountAmount > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'Discount (${_currentInvoice.invoiceDiscountPercentage.toStringAsFixed(1)}%)',
                    '-₹${_currentInvoice.invoiceDiscountAmount.toStringAsFixed(2)}',
                    isDiscount: true,
                  ),
                ],
                const SizedBox(height: 8),
                _buildSummaryRow(
                  'GST',
                  '₹${_currentInvoice.gstAmount.toStringAsFixed(2)}',
                ),
                if (calculateRoundOff(_currentInvoice.totalAmount + _currentInvoice.gstAmount).numericRoundOff != 0) ...[
                  const SizedBox(height: 6),
                  _buildSummaryRow(
                    'Round Off',
                    calculateRoundOff(_currentInvoice.totalAmount + _currentInvoice.gstAmount).formattedRoundOff,
                  ),
                ],
                const Divider(height: 24, thickness: 1),
                _buildSummaryRow(
                  'Grand Total',
                  '₹${calculateRoundOff(_currentInvoice.netAmount).roundedTotal.toStringAsFixed(2)}',
                  isBold: true,
                  isLarge: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NOTES',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.grey,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _currentInvoice.notes!,
            style: const TextStyle(color: Colors.black87, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    bool isLarge = false,
    bool isDiscount = false,
  }) {
    final Color valueColor = isDiscount ? AppTheme.success : Colors.black87;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.black54,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isLarge ? 16 : 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isLarge ? 18 : 14,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildEditWindowCard() => const SizedBox.shrink();
}
