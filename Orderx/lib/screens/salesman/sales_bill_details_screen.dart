import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/services/sale_bill_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SalesBillDetailsScreen extends StatefulWidget {
  final OrderModel order;

  const SalesBillDetailsScreen({super.key, required this.order});

  @override
  State<SalesBillDetailsScreen> createState() => _SalesBillDetailsScreenState();
}

class _SalesBillDetailsScreenState extends State<SalesBillDetailsScreen> {
  final OrderService _orderService = OrderService();
  final PdfService _pdfService = PdfService();
  final TallyCompanyService _companyService = TallyCompanyService();
  final SaleBillService _saleBillService = SaleBillService();

  List<OrderItemModel> _items = [];
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  late OrderModel _currentOrder;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await _orderService.getOrderItems(_currentOrder.id);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _convertToSaleBill() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to bill'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      // 1) Create / record sale bill entry in database
      try {
        await _saleBillService.createSaleBillForOrder(
          _currentOrder,
          companyId: _currentOrder.companyId,
        );
      } catch (e) {
        print('Error creating sale bill entry: $e');
        if (mounted) {
          setState(() => _isGeneratingPdf = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Failed to save sale bill to server: ${e.toString()}'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      // 2) Load company info for PDF header (if available)
      TallyCompanyModel? company;
      final companyId = _currentOrder.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for sales bill: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        _currentOrder,
        _items,
        company: company,
        companyName: _currentOrder.companyName,
        documentTitle: 'SALE BILL', // ✅ Custom Title
      );

      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);

      // 3) Share the generated PDF so it can be sent via apps (WhatsApp, email, etc.)
      await _pdfService.sharePdf(pdfBytes, _currentOrder.orderNumber);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale Bill generated and ready to share'),
          backgroundColor: AppTheme.success,
        ),
      );

    } catch (e) {
      print('Error generating bill: $e');
      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating bill: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Bill Details'),
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
                      _buildOrderInfoCard(),
                      const SizedBox(height: 16),
                      if (_currentOrder.customerName != null)
                        _buildCustomerInfoCard(),
                      if (_currentOrder.customerName != null)
                        const SizedBox(height: 16),
                      Text(
                        'Bill Items',
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
                            'Generating Sale Bill...',
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
      bottomNavigationBar: !_isLoading && !_isGeneratingPdf && _items.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton.icon(
                  onPressed: _convertToSaleBill,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Convert to Sale Bill'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _currentOrder.orderNumber,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.calendar_today,
              'Order Date',
              DateFormat('MMM dd, yyyy - hh:mm a')
                  .format(_currentOrder.orderDate),
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
              'Customer Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.person,
              'Name',
              _currentOrder.customerName ?? 'N/A',
            ),
            if (_currentOrder.customerMobile != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.phone,
                'Mobile',
                _currentOrder.customerMobile!,
              ),
            ],
            if (_currentOrder.customerAddress != null &&
                _currentOrder.customerAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.location_on,
                'Address',
                _currentOrder.customerAddress!,
              ),
            ],
            if (_currentOrder.shippingAddress != null &&
                _currentOrder.shippingAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.local_shipping,
                'Shipping Address',
                _currentOrder.shippingAddress!,
              ),
            ],
            if (_currentOrder.customerGst != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.receipt,
                'GST Number',
                _currentOrder.customerGst!,
              ),
            ],
          ],
        ),
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
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.ItemName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${item.PartNumber ?? "N/A"}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.grey,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildItemDetail('Qty', item.ItemQuantity == item.ItemQuantity.truncateToDouble() ? item.ItemQuantity.toInt().toString() : item.ItemQuantity.toString()),
                _buildItemDetail(
                    'Rate', '₹${item.ItemRate.toStringAsFixed(2)}'),
                _buildItemDetail('GST', '${item.GstRate}%'),
                _buildItemDetail(
                  'Total',
                  '₹${item.totalAmount.toStringAsFixed(2)}',
                  isBold: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      color: AppTheme.primaryBlue.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSummaryRow(
              'Subtotal',
              '₹${_currentOrder.subtotalBeforeDiscount.toStringAsFixed(2)}',
            ),
            if (_currentOrder.orderDiscountAmount > 0) ...[
              const SizedBox(height: 8),
              _buildSummaryRow(
                'Discount (${_currentOrder.orderDiscountPercentage.toStringAsFixed(1)}%)',
                '-₹${_currentOrder.orderDiscountAmount.toStringAsFixed(2)}',
                isDiscount: true,
              ),
            ],
            const SizedBox(height: 8),
            _buildSummaryRow(
              'GST',
              '₹${_currentOrder.gstAmount.toStringAsFixed(2)}',
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
            _buildSummaryRow(
              'Net Amount',
              '₹${_currentOrder.netAmount.toStringAsFixed(2)}',
              isBold: true,
              isLarge: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.grey,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemDetail(String label, String value, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.grey,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isBold ? AppTheme.primaryBlue : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false, bool isLarge = false, bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isLarge ? 16 : 14,
            color: isDiscount ? AppTheme.success : Colors.black87,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: isLarge ? 18 : 14,
            color: isDiscount
                ? AppTheme.success
                : (isLarge ? AppTheme.primaryBlue : Colors.black87),
          ),
        ),
      ],
    );
  }
}
