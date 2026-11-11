import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/invoice_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/invoice_service.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class EditInvoiceScreen extends StatefulWidget {
  final InvoiceModel invoice;
  final List<InvoiceItemModel> items;

  const EditInvoiceScreen({
    super.key,
    required this.invoice,
    required this.items,
  });

  @override
  State<EditInvoiceScreen> createState() => _EditInvoiceScreenState();
}

class _EditInvoiceScreenState extends State<EditInvoiceScreen> {
  final InvoiceService _invoiceService = InvoiceService();
  final ProductService _productService = ProductService();
  final AdminSettingsService _settingsService = AdminSettingsService();

  late List<InvoiceItemModel> _editableItems;
  late TextEditingController _notesController;
  late TextEditingController _shippingAddressController;
  bool _isUpdating = false;
  bool _hasChanges = false;

  // Order-level discount
  double _orderDiscountPercentage = 0.0;
  late TextEditingController _orderDiscountController;

  // Flags from admin settings
  bool _allowItemDiscounts = true;
  bool _allowOrderDiscounts = true;
  bool _allowOrderEditing = true;
  bool _settingsLoaded = false;
  int _editWindowMinutes = 30;

  // Add-product search
  final TextEditingController _productSearchController =
      TextEditingController();
  List<ProductModel> _searchResults = [];
  bool _isSearching = false;
  bool _showAddProduct = false;

  @override
  void initState() {
    super.initState();
    _editableItems = widget.items
        .map((item) => InvoiceItemModel(
              id: item.id,
              invoiceId: item.invoiceId,
              productId: item.productId,
              productName: item.productName,
              productCode: item.productCode,
              hsn: item.hsn,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              gstRate: item.gstRate,
              gstAmount: item.gstAmount,
              totalAmount: item.totalAmount,
              discountPercentage: item.discountPercentage,
              discountAmount: item.discountAmount,
              categoryDiscountPercentage: item.categoryDiscountPercentage,
              vtNumber: item.vtNumber,
              mrp: item.mrp,
              cashDiscountAmount: item.cashDiscountAmount,
              orderDiscountAmount: item.orderDiscountAmount,
              itemDiscountAmount: item.itemDiscountAmount,
              offerDiscountAmount: item.offerDiscountAmount,
            ))
        .toList();
    _notesController = TextEditingController(text: widget.invoice.notes ?? '');
    _shippingAddressController =
        TextEditingController(text: widget.invoice.shippingAddress ?? '');
    _orderDiscountPercentage = widget.invoice.invoiceDiscountPercentage;
    _orderDiscountController = TextEditingController(
        text: _orderDiscountPercentage > 0
            ? _orderDiscountPercentage.toStringAsFixed(1)
            : '');
    _loadAdminSettings();
  }

  Future<void> _loadAdminSettings() async {
    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId!;
      final settings = await _settingsService.getAdminSettings(companyId);
      final minutes = await _settingsService.getOrderEditWindowMinutes(companyId);
      if (mounted) {
        setState(() {
          _allowItemDiscounts = settings.allowItemDiscounts;
          _allowOrderDiscounts = settings.allowOrderDiscounts;
          _allowOrderEditing = settings.allowOrderEditing;
          _editWindowMinutes = minutes;
          _settingsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _settingsLoaded = true);
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _shippingAddressController.dispose();
    _orderDiscountController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  InvoiceItemModel _recalcItem(InvoiceItemModel item,
      {double? newQty, double? newItemDiscountPct}) {
    final qty = newQty ?? item.quantity;
    final discPct = newItemDiscountPct ?? item.discountPercentage;
    final basePrice = item.unitPrice * qty;
    final discAmt = basePrice * discPct / 100;
    final afterDisc = basePrice - discAmt;
    final gstAmt = afterDisc * item.gstRate / 100;
    final total = afterDisc + gstAmt;
    return InvoiceItemModel(
      id: item.id,
      invoiceId: item.invoiceId,
      productId: item.productId,
      productName: item.productName,
      productCode: item.productCode,
      hsn: item.hsn,
      quantity: qty,
      unitPrice: item.unitPrice,
      gstRate: item.gstRate,
      gstAmount: gstAmt,
      totalAmount: total,
      discountPercentage: discPct,
      discountAmount: discAmt,
      categoryDiscountPercentage: item.categoryDiscountPercentage,
      vtNumber: item.vtNumber,
      mrp: item.mrp,
      cashDiscountAmount: item.cashDiscountAmount,
      orderDiscountAmount: item.orderDiscountAmount,
      itemDiscountAmount: discAmt,
      offerDiscountAmount: item.offerDiscountAmount,
    );
  }

  void _updateQuantity(int index, double newQuantity) {
    if (newQuantity < 0) return;
    setState(() {
      if (newQuantity == 0) {
        _editableItems.removeAt(index);
      } else {
        _editableItems[index] =
            _recalcItem(_editableItems[index], newQty: newQuantity);
      }
      _hasChanges = true;
    });
  }

  void _updateItemDiscount(int index, double discountPct) {
    setState(() {
      _editableItems[index] =
          _recalcItem(_editableItems[index], newItemDiscountPct: discountPct);
      _hasChanges = true;
    });
  }

  double get _itemsSubtotalBeforeOrderDiscount {
    return _editableItems.fold<double>(
        0.0, (sum, item) => sum + item.totalAmount);
  }

  double get _orderDiscountAmount {
    return _itemsSubtotalBeforeOrderDiscount * _orderDiscountPercentage / 100;
  }

  double get _grandTotal {
    return _itemsSubtotalBeforeOrderDiscount - _orderDiscountAmount;
  }

  double _calculateInvoiceGst() {
    return _editableItems.fold<double>(
        0.0, (sum, item) => sum + item.gstAmount);
  }

  double _calculateInvoiceSubtotal() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.totalAmount - item.gstAmount),
    );
  }

  Future<void> _searchProducts(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await _productService.searchProducts(query);
      if (mounted)
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _addProductToInvoice(ProductModel product) {
    final existing =
        _editableItems.indexWhere((i) => i.productId == product.id);
    if (existing >= 0) {
      _updateQuantity(existing, _editableItems[existing].quantity + 1.0);
    } else {
      final basePrice = product.price * 1;
      final discPct = product.discountPercentage;
      final discAmt = basePrice * discPct / 100;
      final afterDisc = basePrice - discAmt;
      final gstAmt = afterDisc * product.gstRate / 100;
      final total = afterDisc + gstAmt;
      final newItem = InvoiceItemModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        invoiceId: widget.invoice.id,
        productId: product.id,
        productName: product.productName,
        productCode: product.productCode,
        hsn: product.hsn,
        quantity: 1,
        unitPrice: product.price,
        gstRate: product.gstRate,
        gstAmount: gstAmt,
        totalAmount: total,
        discountPercentage: discPct,
        discountAmount: discAmt,
        mrp: product.mrp,
        itemDiscountAmount: discAmt,
      );
      setState(() {
        _editableItems.add(newItem);
        _hasChanges = true;
      });
    }
    setState(() {
      _showAddProduct = false;
      _productSearchController.clear();
      _searchResults = [];
    });
  }

  Future<void> _saveChanges() async {
    if (!_settingsLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading settings, please wait...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (widget.invoice.syncedToTally) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('This Order has been billed in Tally and cannot be edited'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    // Toggle ON → enforce time window. Toggle OFF → editable until billed (already checked above).
    if (_allowOrderEditing &&
        !widget.invoice.canEdit(
            editWindowMinutes: _editWindowMinutes, useTimeWindow: true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order edit window has expired'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (_editableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order must have at least one item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUpdating = true);

    try {
      final newSubtotal = _calculateInvoiceSubtotal();
      final newGst = _calculateInvoiceGst();
      final newNetAmount = _grandTotal + newGst;
      final authProvider = context.read<AuthProvider>();

      await _invoiceService.updateInvoice(
        invoiceId: widget.invoice.id,
        items: _editableItems,
        totalAmount: newSubtotal,
        gstAmount: newGst,
        netAmount: newNetAmount,
        orderDiscountPercentage: _orderDiscountPercentage,
        orderDiscountAmount: _orderDiscountAmount,
        notes: _notesController.text.trim(),
        shippingAddress: _shippingAddressController.text.trim(),
        companyId: authProvider.selectedCompanyId ?? widget.invoice.companyId,
      );

      if (!mounted) return;

      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order updated successfully!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating Order: ${e.toString()}'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _showDeleteConfirmation(int index) async {
    final itemName = _editableItems[index].productName;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove $itemName from Orders?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _editableItems.removeAt(index);
        _hasChanges = true;
      });
    }
  }

  Future<void> _handleBack() async {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Order'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isUpdating ? null : _handleBack,
        ),
      ),
      body: _isUpdating
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Updating Order...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Invoice header
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invoice #${widget.invoice.invoiceNumber}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Customer: ${widget.invoice.customerName ?? 'Walk-in'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Created: ${DateFormat('MMM dd, yyyy - hh:mm a').format(widget.invoice.createdAt.toLocal())}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Items header + Add button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Invoice Items (${_editableItems.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _showAddProduct = !_showAddProduct;
                          if (!_showAddProduct) {
                            _productSearchController.clear();
                            _searchResults = [];
                          }
                        }),
                        icon: Icon(
                          _showAddProduct ? Icons.close : Icons.add,
                          color: AppTheme.primaryBlue,
                        ),
                        label: Text(
                          _showAddProduct ? 'Cancel' : 'Add Item',
                          style: const TextStyle(color: AppTheme.primaryBlue),
                        ),
                      ),
                    ],
                  ),

                  // Add product search panel
                  if (_showAddProduct) _buildAddProductPanel(),

                  const SizedBox(height: 8),
                  if (_editableItems.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No items in invoice',
                          style: TextStyle(color: AppTheme.grey),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _editableItems.length,
                      itemBuilder: (context, index) {
                        return _buildEditableItemCard(
                            context, _editableItems[index], index);
                      },
                    ),

                  // Order discount
                  if (_allowOrderDiscounts) ...[
                    const SizedBox(height: 16),
                    _buildOrderDiscountRow(),
                  ],

                  const SizedBox(height: 20),
                  Text(
                    'Shipping Address (Optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _shippingAddressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter shipping address...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (_) => setState(() => _hasChanges = true),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Notes (Optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Add any additional notes...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (_) => setState(() => _hasChanges = true),
                  ),
                  const SizedBox(height: 20),

                  // Summary card
                  Card(
                    color: AppTheme.primaryBlue.withOpacity(0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildSummaryRow(
                            'Items Total',
                            '₹${_itemsSubtotalBeforeOrderDiscount.toStringAsFixed(2)}',
                          ),
                          if (_orderDiscountPercentage > 0) ...[
                            const SizedBox(height: 8),
                            _buildSummaryRow(
                              'Order Discount (${_orderDiscountPercentage.toStringAsFixed(1)}%)',
                              '-₹${_orderDiscountAmount.toStringAsFixed(2)}',
                              isDiscount: true,
                            ),
                          ],
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'GST',
                            '₹${_calculateInvoiceGst().toStringAsFixed(2)}',
                          ),
                          const Divider(height: 24),
                          _buildSummaryRow(
                            'Grand Total',
                            '₹${_grandTotal.toStringAsFixed(2)}',
                            isBold: true,
                            isLarge: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _saveChanges,
                      icon: const Icon(Icons.save),
                      label: const Text('SAVE CHANGES'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildAddProductPanel() {
    return Card(
      color: AppTheme.primaryBlue.withOpacity(0.04),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _productSearchController,
              decoration: InputDecoration(
                hintText: 'Search product by name or code...',
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.primaryBlue),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (q) => _searchProducts(q),
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount:
                    _searchResults.length > 8 ? 8 : _searchResults.length,
                itemBuilder: (context, i) {
                  final p = _searchResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(p.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Code: ${p.productCode ?? '-'}  |  ₹${p.price.toStringAsFixed(2)}  |  GST: ${p.gstRate}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle,
                          color: AppTheme.primaryBlue),
                      onPressed: () => _addProductToInvoice(p),
                    ),
                    onTap: () => _addProductToInvoice(p),
                  );
                },
              ),
            ] else if (_productSearchController.text.trim().isNotEmpty &&
                !_isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No products found',
                    style: TextStyle(color: AppTheme.grey)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderDiscountRow() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.discount_outlined,
                color: AppTheme.primaryBlue, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Order Discount (%)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _orderDiscountController,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: '%',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (val) {
                  final pct = double.tryParse(val) ?? 0.0;
                  setState(() {
                    _orderDiscountPercentage = pct.clamp(0.0, 100.0);
                    _hasChanges = true;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableItemCard(
    BuildContext context,
    InvoiceItemModel item,
    int index,
  ) {
    final discountController = TextEditingController(
      text: item.discountPercentage > 0
          ? item.discountPercentage.toStringAsFixed(1)
          : '',
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name + delete
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Code: ${item.productCode ?? "N/A"}',
                        style:
                            const TextStyle(fontSize: 11, color: AppTheme.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${item.unitPrice.toStringAsFixed(2)} per unit  |  GST: ${item.gstRate}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: AppTheme.error,
                  onPressed: () => _showDeleteConfirmation(index),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Quantity + Discount + Amount row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Quantity controls
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Qty',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.grey),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () =>
                              _updateQuantity(index, item.quantity - 1.0),
                          child: const Icon(Icons.remove_circle_outline,
                              color: AppTheme.primaryBlue, size: 26),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 44,
                          child: TextField(
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 6),
                            ),
                            controller: TextEditingController(
                                text: item.quantity ==
                                        item.quantity.truncateToDouble()
                                    ? item.quantity.toInt().toString()
                                    : item.quantity.toString()),
                            onSubmitted: (v) {
                              final qty = double.tryParse(v);
                              if (qty != null && qty > 0)
                                _updateQuantity(index, qty);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () =>
                              _updateQuantity(index, item.quantity + 1.0),
                          child: const Icon(Icons.add_circle_outline,
                              color: AppTheme.primaryBlue, size: 26),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(width: 12),

                // Item discount field (only if allowed)
                if (_allowItemDiscounts) ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Item Disc %',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.grey),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: discountController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            hintText: '0',
                            suffixText: '%',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                          ),
                          onSubmitted: (v) {
                            final pct =
                                (double.tryParse(v) ?? 0.0).clamp(0.0, 100.0);
                            _updateItemDiscount(index, pct);
                          },
                          onEditingComplete: () {
                            final pct =
                                (double.tryParse(discountController.text) ??
                                        0.0)
                                    .clamp(0.0, 100.0);
                            _updateItemDiscount(index, pct);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // Amount column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Amount',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.grey),
                    ),
                    const SizedBox(height: 6),
                    if (item.discountPercentage > 0) ...[
                      Text(
                        '₹${(item.unitPrice * item.quantity).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.grey,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      Text(
                        '-₹${item.discountAmount.toStringAsFixed(2)} (${item.discountPercentage.toStringAsFixed(1)}%)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                    Text(
                      '₹${item.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppTheme.primaryBlue,
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

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    bool isLarge = false,
    bool isDiscount = false,
  }) {
    final Color valueColor = isDiscount
        ? Colors.orange
        : (isBold ? AppTheme.primaryBlue : AppTheme.darkGrey);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isLarge ? 16 : 14,
            color: isDiscount ? Colors.orange : null,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLarge ? 18 : 14,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
