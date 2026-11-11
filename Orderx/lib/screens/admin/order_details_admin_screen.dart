import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/services/tally_company_service.dart';

class OrderDetailsAdminScreen extends StatefulWidget {
  final OrderModel order;

  const OrderDetailsAdminScreen({super.key, required this.order});

  @override
  State<OrderDetailsAdminScreen> createState() =>
      _OrderDetailsAdminScreenState();
}

class _OrderDetailsAdminScreenState extends State<OrderDetailsAdminScreen> {
  final OrderService _orderService = OrderService();
  final PdfService _pdfService = PdfService();
  final TallyCompanyService _companyService = TallyCompanyService();
  List<OrderItemModel> _items = [];
  bool _isLoading = true;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await _orderService.getOrderItems(widget.order.id);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _shareOrder() async {
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
      final companyId = widget.order.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for admin PDF share: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        widget.order,
        _items,
        company: company,
        companyName: widget.order.companyName,
      );

      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);

      await _pdfService.sharePdf(pdfBytes, widget.order.orderNumber);
    } catch (e) {
      print('Error sharing: $e');
      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing order: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _printOrder() async {
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
      final companyId = widget.order.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for admin PDF print: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        widget.order,
        _items,
        company: company,
        companyName: widget.order.companyName,
      );
      await _pdfService.printPdf(pdfBytes);

      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error printing order: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _isGeneratingPdf ? null : _printOrder,
              tooltip: 'Print',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Order Header
                      _buildOrderInfoCard(),
                      const SizedBox(height: 16),

                      // Customer Info
                      if (widget.order.customerName != null)
                        _buildCustomerInfoCard(),
                      if (widget.order.customerName != null)
                        const SizedBox(height: 16),

                      // Order Items
                      Text(
                        'Order Items',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),

                      if (_items.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No items found'),
                          ),
                        )
                      else
                        ..._items.map((item) => _buildItemCard(item)),

                      const SizedBox(height: 16),

                      // Summary
                      _buildSummaryCard(),

                      const SizedBox(height: 100),
                    ],
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
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
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
                  onPressed: _shareOrder,
                  icon: const Icon(Icons.share),
                  label: const Text('Share Order'),
                  backgroundColor: AppTheme.primaryBlue,
                )
              : null,
    );
  }

  Widget _buildOrderInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.order.orderNumber,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Date',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM dd, yyyy - hh:mm a')
                          .format(widget.order.orderDate),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.order.status == 'completed'
                            ? AppTheme.success.withOpacity(0.1)
                            : AppTheme.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: widget.order.status == 'completed'
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                      ),
                      child: Text(
                        widget.order.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: widget.order.status == 'completed'
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Name', widget.order.customerName ?? 'N/A'),
            if (widget.order.customerMobile != null)
              _buildInfoRow('Mobile', widget.order.customerMobile!),
            if (widget.order.customerGst != null)
              _buildInfoRow('GST Number', widget.order.customerGst!),
            if (widget.order.customerAddress != null)
              _buildInfoRow('Address', widget.order.customerAddress!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.grey,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(OrderItemModel item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.ItemName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (item.PartNumber != null)
                        Text(
                          'Code: ${item.PartNumber}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.grey,
                                  ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Qty: ${item.ItemQuantity}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '₹${(item.ItemRate > 0 ? item.ItemRate : ((item.totalAmount - item.gstAmount + item.discountAmount) / (item.ItemQuantity > 0 ? item.ItemQuantity : 1))).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'GST: ${item.GstRate}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.grey,
                      ),
                ),
                Text(
                  '₹${(item.totalAmount - item.gstAmount).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final subtotal = _items.fold<double>(
      0,
      (sum, item) => sum + ((item.ItemRate > 0 ? item.ItemRate : ((item.totalAmount - item.gstAmount + item.discountAmount) / (item.ItemQuantity > 0 ? item.ItemQuantity : 1))) * item.ItemQuantity),
    );
    final gstTotal = _items.fold<double>(
      0,
      (sum, item) => sum + item.gstAmount,
    );

    return Card(
      color: AppTheme.primaryBlue.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildSummaryRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),
            _buildSummaryRow('GST', '₹${gstTotal.toStringAsFixed(2)}'),
            if (widget.order.orderDiscountAmount > 0)
              _buildSummaryRow(
                'Discount',
                '-₹${widget.order.orderDiscountAmount.toStringAsFixed(2)}',
                isDiscount: true,
              ),
            const Divider(height: 16),
            _buildSummaryRow(
              'Total',
              '₹${widget.order.netAmount.toStringAsFixed(2)}',
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false, bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: isDiscount ? AppTheme.success : AppTheme.primaryBlue,
                ),
          ),
        ],
      ),
    );
  }
}
