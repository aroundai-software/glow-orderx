import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/screens/salesman/edit_order_screen.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/services/invoice_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class OrderDetailsScreen extends StatefulWidget {
  final OrderModel order;

  const OrderDetailsScreen({super.key, required this.order});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final OrderService _orderService = OrderService();
  final InvoiceService _invoiceService = InvoiceService();
  final PdfService _pdfService = PdfService();
  final TallyCompanyService _companyService = TallyCompanyService();

  List<OrderItemModel> _items = [];
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  late OrderModel _currentOrder;

  // Edit window — loaded from admin settings
  int _editWindowMinutes = 30;
  bool _allowOrderEditing = true;
  bool _settingsLoaded = false;

  // Countdown timer — ticks every second so remaining time stays live
  Timer? _countdownTimer;

  // True if a sale_bill record exists
  bool _isBilled = false;

  bool get _canEditOrder {
    if (_currentOrder.syncedToTally) return false;
    if (_isBilled) return false;
    if (!_allowOrderEditing) return true; // toggle OFF = editable until billed
    return _isWithinInitialEditWindow();
  }

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _loadItems();
    _loadEditSettings();
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

  Future<void> _loadEditSettings() async {
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
    } catch (e) {
      print('🔧 Debug: Error loading edit settings: $e');
      if (mounted) {
        setState(() => _settingsLoaded = true);
        _startCountdown();
      }
    }
  }

  Future<void> _refreshOrderStatus() async {
    try {
      final updatedOrder = await _orderService.getOrderById(_currentOrder.id);
      if (updatedOrder != null && mounted) {
        setState(() {
          _currentOrder = updatedOrder;
        });
      }
    } catch (e) {
      print('Error refreshing order status: $e');
    }
  }

  Future<void> _loadItems() async {
    final items = await _orderService.getOrderItems(_currentOrder.id);
    
    bool billed = false;
    try {
      billed = await _invoiceService.checkOrderBilledInTally(_currentOrder.orderNumber);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _items = items;
        _isBilled = billed;
        _isLoading = false;
      });
    }
  }

  bool _isWithinInitialEditWindow() {
    final now = DateTime.now();
    final createdAtLocal = _currentOrder.createdAt.isUtc
        ? DateTime(
            _currentOrder.createdAt.year,
            _currentOrder.createdAt.month,
            _currentOrder.createdAt.day,
            _currentOrder.createdAt.hour,
            _currentOrder.createdAt.minute,
            _currentOrder.createdAt.second,
          )
        : _currentOrder.createdAt;
    final windowEnd = createdAtLocal.add(Duration(minutes: _editWindowMinutes));
    return now.isBefore(windowEnd);
  }

  Duration? _getInitialWindowRemaining() {
    if (!_isWithinInitialEditWindow()) return null;
    final now = DateTime.now();
    final createdAtLocal = _currentOrder.createdAt.isUtc
        ? DateTime(
            _currentOrder.createdAt.year,
            _currentOrder.createdAt.month,
            _currentOrder.createdAt.day,
            _currentOrder.createdAt.hour,
            _currentOrder.createdAt.minute,
            _currentOrder.createdAt.second,
          )
        : _currentOrder.createdAt;
    final windowEnd = createdAtLocal.add(Duration(minutes: _editWindowMinutes));
    return windowEnd.difference(now);
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return 'Expired';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    } else if (minutes > 0) {
      return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
    } else {
      return '${seconds}s';
    }
  }

  Future<void> _editOrder() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to edit'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_canEditOrder) {
      if (_currentOrder.syncedToTally) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This order has been billed in Tally and cannot be edited'),
            backgroundColor: AppTheme.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Edit window has expired'),
            backgroundColor: AppTheme.error,
          ),
        );
        await _refreshOrderStatus();
      }
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditOrderScreen(
          order: _currentOrder,
          items: _items,
        ),
      ),
    );

    if (result == true && mounted) {
      await _refreshOrderStatus();
      await _loadItems();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order updated successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
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
      final companyId = _currentOrder.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for salesman PDF share: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        _currentOrder,
        _items,
        company: company,
        companyName: _currentOrder.companyName,
      );

      if (!mounted) return;
      setState(() => _isGeneratingPdf = false);
      await _pdfService.sharePdf(pdfBytes, _currentOrder.orderNumber);
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
      final companyId = _currentOrder.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for salesman PDF print: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        _currentOrder,
        _items,
        company: company,
        companyName: _currentOrder.companyName,
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
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                setState(() => _isLoading = true);
                await _refreshOrderStatus();
                await _loadItems();
              },
              tooltip: 'Refresh',
            ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _isGeneratingPdf ? null : _printOrder,
              tooltip: 'Print',
            ),
          if (!_isLoading && _items.isNotEmpty && (!_canEditOrder || _isBilled))
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _isGeneratingPdf ? null : _shareOrder,
              tooltip: 'Share Order',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // ── Scrollable content ──
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
                      _buildSummaryCard(),
                      // Extra bottom padding so content isn't hidden behind the bar
                      const SizedBox(height: 140),
                    ],
                  ),
                ),

                // ── PDF loading overlay ──
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

                // ── Edit permission bar pinned at bottom ──
                if (_settingsLoaded)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildEditPermissionBar(),
                  ),
              ],
            ),

    );
  }

  // ── Bottom bar replacing the old card ──
  Widget _buildEditPermissionBar() {
    // If billed in Tally, show no banner
    if (_isBilled || _currentOrder.syncedToTally) {
      return const SizedBox.shrink();
    }

    // Within edit window — show countdown + Edit + Share buttons
    if (_isWithinInitialEditWindow()) {
      final remaining = _getInitialWindowRemaining();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppTheme.success,
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -2)),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.edit, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'You Can Edit This Order',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (remaining != null)
                    Text(
                      'Time remaining: ${_formatDuration(remaining)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isGeneratingPdf ? null : _editOrder,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.success,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isGeneratingPdf ? null : _shareOrder,
              icon: _isGeneratingPdf
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
                    )
                  : const Icon(Icons.share, size: 16),
              label: const Text('Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      );
    }

    // Edit window expired — show nothing
    return const SizedBox.shrink();
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
              DateFormat('MMM dd, yyyy - hh:mm a').format(_currentOrder.orderDate),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.access_time,
              'Created At',
              DateFormat('MMM dd, yyyy - hh:mm a').format(_currentOrder.createdAt),
            ),
            if (_currentOrder.updatedAt != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.update,
                'Edited At',
                DateFormat('MMM dd, yyyy - hh:mm a').format(_currentOrder.updatedAt!),
              ),
            ],
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
            _buildInfoRow(Icons.person, 'Name', _currentOrder.customerName ?? 'N/A'),
            if (_currentOrder.customerMobile != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.phone, 'Mobile', _currentOrder.customerMobile!),
            ],
            if (_currentOrder.customerAddress != null &&
                _currentOrder.customerAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.location_on, 'Address', _currentOrder.customerAddress!),
            ],
            if (_currentOrder.shippingAddress != null &&
                _currentOrder.shippingAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                  Icons.local_shipping, 'Shipping Address', _currentOrder.shippingAddress!),
            ],
            if (_currentOrder.customerGst != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.receipt, 'GST Number', _currentOrder.customerGst!),
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
                  child: const Icon(Icons.inventory_2, color: AppTheme.primaryBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.ItemName,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${item.PartNumber ?? "N/A"}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.grey),
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
                _buildItemDetail('Rate', '₹${(item.ItemRate > 0 ? item.ItemRate : ((item.totalAmount - item.gstAmount + item.discountAmount) / (item.ItemQuantity > 0 ? item.ItemQuantity : 1))).toStringAsFixed(2)}'),
                if (item.discountPercentage > 0)
                  _buildItemDetail('Disc', '${item.discountPercentage.toStringAsFixed(1)}%'),
                _buildItemDetail('GST', '${item.GstRate}%'),
                _buildItemDetail('Total', '₹${(item.totalAmount - item.gstAmount).toStringAsFixed(2)}',
                    isBold: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final double grossSubtotal = _items.fold(0.0, (sum, item) => sum + ((item.ItemRate > 0 ? item.ItemRate : ((item.totalAmount - item.gstAmount + item.discountAmount) / (item.ItemQuantity > 0 ? item.ItemQuantity : 1))) * item.ItemQuantity));
    final double itemDiscountTotal = grossSubtotal - _currentOrder.subtotalBeforeDiscount;
    final bool hasItemDiscount = itemDiscountTotal > 0.01;
    final bool hasOrderDiscount = _currentOrder.orderDiscountAmount > 0;

    return Card(
      color: AppTheme.primaryBlue.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSummaryRow(
              hasItemDiscount ? 'Subtotal (Gross)' : 'Subtotal',
              '₹${grossSubtotal.toStringAsFixed(2)}',
            ),
            if (hasItemDiscount) ...[
              const SizedBox(height: 8),
              _buildSummaryRow(
                'Item Discount',
                '-₹${itemDiscountTotal.toStringAsFixed(2)}',
                isDiscount: true,
              ),
              if (!hasOrderDiscount) ...[
                const SizedBox(height: 8),
                _buildSummaryRow(
                  'Subtotal After Discount',
                  '₹${_currentOrder.subtotalBeforeDiscount.toStringAsFixed(2)}',
                ),
              ],
            ],
            if (hasOrderDiscount) ...[
              if (hasItemDiscount) ...[
                 const SizedBox(height: 8),
                 _buildSummaryRow(
                   'Subtotal (After Item Discount)',
                   '₹${_currentOrder.subtotalBeforeDiscount.toStringAsFixed(2)}',
                 ),
              ],
              const SizedBox(height: 8),
              _buildSummaryRow(
                'Order Discount (${_currentOrder.orderDiscountPercentage.toStringAsFixed(1)}%)',
                '-₹${_currentOrder.orderDiscountAmount.toStringAsFixed(2)}',
                isDiscount: true,
              ),
              const SizedBox(height: 8),
              _buildSummaryRow(
                'Subtotal After All Discounts',
                '₹${_currentOrder.totalAmount.toStringAsFixed(2)}',
              ),
            ],
            const SizedBox(height: 8),
            _buildSummaryRow(
              'GST Amount',
              '₹${_currentOrder.gstAmount.toStringAsFixed(2)}',
            ),
            if (calculateRoundOff(_currentOrder.totalAmount + _currentOrder.gstAmount).numericRoundOff != 0) ...[
              const SizedBox(height: 6),
              _buildSummaryRow(
                'Round Off',
                calculateRoundOff(_currentOrder.totalAmount + _currentOrder.gstAmount).formattedRoundOff,
              ),
            ],
            const Divider(height: 24),
            _buildSummaryRow(
              'Grand Total',
              '₹${calculateRoundOff(_currentOrder.netAmount).roundedTotal.toStringAsFixed(2)}',
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
        Icon(icon, size: 20, color: AppTheme.primaryBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.grey),
              ),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBold ? AppTheme.primaryBlue : null,
              ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    bool isLarge = false,
    bool isDiscount = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: isLarge ? 18 : null,
                color: isDiscount ? AppTheme.success : null,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: isLarge ? 22 : null,
                color: isDiscount
                    ? AppTheme.success
                    : isBold
                        ? AppTheme.primaryBlue
                        : AppTheme.darkGrey,
              ),
        ),
      ],
    );
  }
}