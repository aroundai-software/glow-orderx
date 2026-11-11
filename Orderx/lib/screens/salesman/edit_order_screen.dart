import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class EditOrderScreen extends StatefulWidget {
  final OrderModel order;
  final List<OrderItemModel> items;

  const EditOrderScreen({
    super.key,
    required this.order,
    required this.items,
  });

  @override
  State<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends State<EditOrderScreen> {
  final OrderService _orderService = OrderService();
  final ProductService _productService = ProductService();
  late List<OrderItemModel> _editableItems;
  late List<TextEditingController> _qtyControllers;
  late List<TextEditingController> _rateControllers;
  late List<TextEditingController> _discountControllers;
  late TextEditingController _notesController;
  late TextEditingController _shippingAddressController;
  bool _isUpdating = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _editableItems = widget.items
        .map((item) => OrderItemModel(
              id: item.id,
              orderId: item.orderId,
              productId: item.productId,
              ItemName: item.ItemName,
              PartNumber: item.PartNumber,
              hsn: item.hsn,
              ItemQuantity: item.ItemQuantity,
              ItemRate: item.ItemRate,
              GstRate: item.GstRate,
              gstAmount: item.gstAmount,
              totalAmount: item.totalAmount,
              discountPercentage: item.discountPercentage,
              discountAmount: item.discountAmount,
            ))
        .toList();
    _qtyControllers = _editableItems
        .map((item) =>
            TextEditingController(text: _formatQty(item.ItemQuantity)))
        .toList();
    _rateControllers = _editableItems
        .map((item) =>
            TextEditingController(text: item.ItemRate.toStringAsFixed(2)))
        .toList();
    _discountControllers = _editableItems
        .map((item) => TextEditingController(
            text: item.discountPercentage > 0
                ? item.discountPercentage.toStringAsFixed(2)
                : ''))
        .toList();
    _notesController = TextEditingController(text: widget.order.notes ?? '');
    _shippingAddressController =
        TextEditingController(text: widget.order.shippingAddress ?? '');
  }

  @override
  void dispose() {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    for (final c in _rateControllers) {
      c.dispose();
    }
    for (final c in _discountControllers) {
      c.dispose();
    }
    _notesController.dispose();
    _shippingAddressController.dispose();
    super.dispose();
  }

  String _formatQty(double qty) =>
      qty == qty.truncateToDouble() ? qty.toInt().toString() : qty.toString();

  void _updateQuantity(int index, double newQuantity) {
    if (newQuantity < 0) return;

    setState(() {
      if (newQuantity == 0) {
        _editableItems.removeAt(index);
        _qtyControllers[index].dispose();
        _rateControllers[index].dispose();
        _discountControllers[index].dispose();
        _qtyControllers.removeAt(index);
        _rateControllers.removeAt(index);
        _discountControllers.removeAt(index);
      } else {
        _qtyControllers[index].text = _formatQty(newQuantity);
        _recalculateItem(index);
      }
      _hasChanges = true;
    });
  }

  void _updateRate(int index, double newRate) {
    if (newRate < 0) return;
    setState(() {
      _recalculateItem(index);
      _hasChanges = true;
    });
  }

  void _updateDiscount(int index, double newDiscount) {
    if (newDiscount < 0 || newDiscount > 100) return;
    setState(() {
      _recalculateItem(index);
      _hasChanges = true;
    });
  }

  void _recalculateItem(int index) {
    final item = _editableItems[index];
    final qty = double.tryParse(_qtyControllers[index].text) ?? item.ItemQuantity;
    final rate = double.tryParse(_rateControllers[index].text) ?? item.ItemRate;
    final discountPercent = double.tryParse(_discountControllers[index].text) ?? 0;
    final gstRate = item.GstRate;

    final subtotal = rate * qty;
    final discountAmount = (subtotal * discountPercent) / 100;
    final discountedSubtotal = subtotal - discountAmount;
    final gstAmount = (discountedSubtotal * gstRate) / 100;
    final total = discountedSubtotal + gstAmount;

    _editableItems[index] = OrderItemModel(
      id: item.id,
      orderId: item.orderId,
      productId: item.productId,
      ItemName: item.ItemName,
      PartNumber: item.PartNumber,
      hsn: item.hsn,
      ItemQuantity: qty,
      ItemRate: rate,
      GstRate: gstRate,
      gstAmount: gstAmount,
      totalAmount: total,
      discountPercentage: discountPercent,
      discountAmount: discountAmount,
    );
  }

  Future<void> _showAddItemDialog() async {
  List<ProductModel> allProducts = [];
  List<ProductModel> filteredProducts = [];
  ProductModel? selectedProduct;
  final searchController = TextEditingController();
  bool isLoadingProducts = true;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        // Load products once, on first build of the dialog
        if (isLoadingProducts) {
          _productService
              .getProducts(
                  companyId: widget.order.companyId ??
                      context.read<AuthProvider>().selectedCompanyId)
              .then((products) {
            allProducts = products;
            filteredProducts = products;
            isLoadingProducts = false;
            setDialogState(() {});
          }).catchError((e) {
            print('Error loading products: $e');
            isLoadingProducts = false;
            setDialogState(() {});
          });
          isLoadingProducts = false; // prevent re-triggering the future on every rebuild
          isLoadingProducts = true; // (kept true until the future completes above)
        }

        void filter(String query) {
          final q = query.toLowerCase();
          setDialogState(() {
            filteredProducts = q.isEmpty
                ? allProducts
                : allProducts.where((p) {
                    return p.productName.toLowerCase().contains(q) ||
                        (p.productCode?.toLowerCase().contains(q) ?? false);
                  }).toList();
            // Clear selection if it's no longer in the filtered list
            if (selectedProduct != null &&
                !filteredProducts.contains(selectedProduct)) {
              selectedProduct = null;
            }
          });
        }

        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
              maxWidth: 480,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Add Product',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by name or code...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                filter('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    onChanged: filter,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: isLoadingProducts
                        ? const Center(child: CircularProgressIndicator())
                        : filteredProducts.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No products found',
                                    style: TextStyle(color: AppTheme.grey),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = filteredProducts[index];
                                  final isSelected = selectedProduct == product;
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 3),
                                    color: isSelected
                                        ? AppTheme.primaryBlue.withOpacity(0.1)
                                        : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: isSelected
                                            ? AppTheme.primaryBlue
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      title: Text(
                                        product.productName,
                                        style: const TextStyle(fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${product.productCode ?? "N/A"} • ₹${product.price.toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: isSelected
                                          ? const Icon(Icons.check_circle,
                                              color: AppTheme.primaryBlue)
                                          : null,
                                      onTap: () {
                                        setDialogState(() => selectedProduct = product);
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedProduct != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.success.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${selectedProduct!.productName} — ₹${selectedProduct!.price.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                        onPressed: selectedProduct != null
                            ? () {
                                Navigator.pop(context, true);
                                _addProductToOrder(selectedProduct!);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  searchController.dispose();
}

  void _addProductToOrder(ProductModel product) {
    setState(() {
      final newItem = OrderItemModel(
        id: '', // New items have empty ID
        orderId: widget.order.id,
        productId: product.id,
        ItemName: product.productName,
        PartNumber: product.productCode,
        hsn: product.hsn,
        ItemQuantity: 1,
        ItemRate: product.price,
        GstRate: product.gstRate,
        gstAmount: (product.price * product.gstRate) / 100,
        totalAmount: product.price + (product.price * product.gstRate) / 100,
        discountPercentage: 0,
        discountAmount: 0,
      );

      _editableItems.add(newItem);
      _qtyControllers.add(TextEditingController(text: '1'));
      _rateControllers.add(TextEditingController(text: product.price.toStringAsFixed(2)));
      _discountControllers.add(TextEditingController(text: ''));
      _hasChanges = true;
    });
  }

  double _calculateOrderTotal() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + item.totalAmount,
    );
  }

  double _calculateOrderGst() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + item.gstAmount,
    );
  }

  double _calculateOrderSubtotal() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.totalAmount - item.gstAmount),
    );
  }

  Future<void> _saveChanges() async {
    if (_editableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order must have at least one item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Flush all typed values from text fields
    for (int i = 0; i < _editableItems.length; i++) {
      _recalculateItem(i);
    }

    setState(() => _isUpdating = true);

    try {
      final newSubtotal = _calculateOrderSubtotal();
      final newGst = _calculateOrderGst();
      final newNetAmount = _calculateOrderTotal();

      print('Saving order with:');
      print('Subtotal: $newSubtotal');
      print('GST: $newGst');
      print('Net Amount: $newNetAmount');
      print('Items: ${_editableItems.length}');

      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      await _orderService.updateOrder(
        orderId: widget.order.id,
        items: _editableItems,
        totalAmount: newSubtotal,
        gstAmount: newGst,
        netAmount: newNetAmount,
        notes: _notesController.text.trim(),
        shippingAddress: _shippingAddressController.text.trim(),
        companyId: companyId,
      );

      if (!mounted) return;

      setState(() => _isUpdating = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Return to previous screen with success
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.pop(context, true);
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isUpdating = false);

      print('Error updating order: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating order: ${e.toString()}'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _showDeleteConfirmation(int index) async {
    final itemName = _editableItems[index].ItemName;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove $itemName from order?'),
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
        _qtyControllers[index].dispose();
        _rateControllers[index].dispose();
        _discountControllers[index].dispose();
        _qtyControllers.removeAt(index);
        _rateControllers.removeAt(index);
        _discountControllers.removeAt(index);
        _editableItems.removeAt(index);
        _hasChanges = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Order'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isUpdating
              ? null
              : () {
                  if (_hasChanges) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Discard Changes?'),
                        content: const Text(
                            'You have unsaved changes. Are you sure you want to discard them?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.error,
                            ),
                            child: const Text('Discard'),
                          ),
                        ],
                      ),
                    );
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
      ),
      body: _isUpdating
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Updating order...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${widget.order.orderNumber}',
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
                            'Customer: ${widget.order.customerName ?? 'Walk-in'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Created: ${DateFormat('MMM dd, yyyy - hh:mm a').format(widget.order.createdAt)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Items List
                  Text(
                    'Order Items (${_editableItems.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_editableItems.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No items in order',
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
                        final item = _editableItems[index];
                        return _buildEditableItemCard(context, item, index);
                      },
                    ),
                  const SizedBox(height: 12),
                  // Add Item Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showAddItemDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('ADD ITEM'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: BorderSide(color: AppTheme.primaryBlue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Shipping Address Section
                  Text(
                    'Shipping Address (Optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _shippingAddressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter shipping address... ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (value) {
                      setState(() => _hasChanges = true);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Notes Section
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (value) {
                      setState(() => _hasChanges = true);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Summary Card
                  Card(
                    color: AppTheme.primaryBlue.withOpacity(0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildSummaryRow(
                            'Subtotal',
                            '₹${_calculateOrderSubtotal().toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'GST',
                            '₹${_calculateOrderGst().toStringAsFixed(2)}',
                          ),
                          const Divider(height: 24),
                          _buildSummaryRow(
                            'Total',
                            '₹${_calculateOrderTotal().toStringAsFixed(2)}',
                            isBold: true,
                            isLarge: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Save Button
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
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }

  Widget _buildEditableItemCard(
      BuildContext context, OrderItemModel item, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.ItemName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${item.PartNumber ?? "N/A"}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.grey,
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
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Quantity, Rate, and Discount Editors
            Row(
              children: [
                // Quantity
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quantity',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            color: AppTheme.primaryBlue,
                            onPressed: () {
                              final qty = double.tryParse(_qtyControllers[index].text) ?? item.ItemQuantity;
                              _updateQuantity(index, qty - 1);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 50,
                            child: TextField(
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                              ),
                              controller: _qtyControllers[index],
                              onChanged: (value) {
                                setState(() => _hasChanges = true);
                              },
                              onSubmitted: (value) {
                                final qty = double.tryParse(value);
                                if (qty != null && qty > 0) {
                                  _updateQuantity(index, qty);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: AppTheme.primaryBlue,
                            onPressed: () {
                              final qty = double.tryParse(_qtyControllers[index].text) ?? item.ItemQuantity;
                              _updateQuantity(index, qty + 1);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Rate
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rate (₹)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.grey),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        controller: _rateControllers[index],
                        onChanged: (value) {
                          setState(() => _hasChanges = true);
                        },
                        onSubmitted: (value) {
                          final rate = double.tryParse(value);
                          if (rate != null && rate >= 0) {
                            _updateRate(index, rate);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Discount
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Disc %',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.grey),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        controller: _discountControllers[index],
                        onChanged: (value) {
                          setState(() => _hasChanges = true);
                        },
                        onSubmitted: (value) {
                          final discount = double.tryParse(value);
                          if (discount != null && discount >= 0 && discount <= 100) {
                            _updateDiscount(index, discount);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Amount display
            Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${(item.totalAmount - item.gstAmount).toStringAsFixed(2)} (excl. GST)',
                    style: const TextStyle(fontSize: 11, color: AppTheme.grey),
                  ),
                  Text(
                    '₹${item.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
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
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isLarge ? 16 : 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLarge ? 18 : 14,
            color: isBold ? AppTheme.primaryBlue : AppTheme.darkGrey,
          ),
        ),
      ],
    );
  }
}
