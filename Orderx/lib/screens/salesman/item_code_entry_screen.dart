import 'dart:async';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/cart_provider.dart';
import 'package:Orderx/screens/salesman/cart_screen.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import this for text formatters
import 'package:provider/provider.dart';

class ItemCodeEntryScreen extends StatefulWidget {
  const ItemCodeEntryScreen({super.key});

  @override
  State<ItemCodeEntryScreen> createState() => _ItemCodeEntryScreenState();
}

class _ItemCodeEntryScreenState extends State<ItemCodeEntryScreen> {
  final _codeController = TextEditingController();
  final _productService = ProductService();
  bool _isLoading = false;
  List<ProductModel> _searchResults = [];
  Timer? _debounceTimer;

  @override
  void dispose() {
    _codeController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }
    
    // Show searching indicator immediately
    setState(() => _isLoading = true);
    
    // Debounce: wait 400ms after user stops typing
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query);
    });
  }
  
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final results = await _productService.searchProducts(query.trim(), companyId: companyId);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No products found for this query.')),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: ${e.toString()}')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showProductDialog(ProductModel product) async {
    double quantity = 1.0;
    // Create a controller for the TextField
    final quantityController = TextEditingController(text: quantity.toString());

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Calculations remain the same and will update when state changes
            final totalPrice = product.price * quantity;
            final productGstRate = product.gstRate;
            final gstAmount = totalPrice * productGstRate / 100;
            final totalWithGst = totalPrice + gstAmount;

            return AlertDialog(
              title: Text(product.productName),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Code: ${product.productCode ?? "N/A"}',
                        style: const TextStyle(color: AppTheme.grey)),
                    const SizedBox(height: 16),
                    Text('Price: ₹${product.price.toStringAsFixed(2)}'),
                    Text('GST: ${product.gstRate}%'),
                    const Divider(height: 24),
                    const Text('Quantity:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () {
                            if (quantity > 1) {
                              setDialogState(() {
                                quantity--;
                                quantityController.text = quantity.toString();
                              });
                            }
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                          color: AppTheme.primaryBlue,
                        ),
                        // REPLACED: Container with Text is now a TextField
                        SizedBox(
                          width: 60,
                          height: 40,
                          child: TextField(
                            controller: quantityController,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              filled: true,
                              fillColor: AppTheme.lightGrey,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (text) {
                              // Update the quantity and recalculate in real-time
                              setDialogState(() {
                                // Use 0 if the field is empty to avoid calculation errors
                                quantity = double.tryParse(text) ?? 0.0;
                              });
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setDialogState(() {
                              quantity++;
                              quantityController.text = quantity.toString();
                            });
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          color: AppTheme.primaryBlue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal:'),
                              Text('₹${totalPrice.toStringAsFixed(2)}'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('GST (${product.gstRate}%):'),
                              Text('₹${gstAmount.toStringAsFixed(2)}'),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total:',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                '₹${totalWithGst.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  // Disable button if quantity is 0
                  onPressed: quantity > 0
                      ? () {
                    context.read<CartProvider>().addItem(product, quantity: quantity.toDouble());
                    Navigator.pop(dialogContext);

                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${product.productName} x$quantity added to cart'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                      : null, // This disables the button
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add to Cart'),
                ),
              ],
            );
          },
        );
      },
    );

    // Dispose the controller after the dialog is closed
    quantityController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Item Code'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CartScreen()),
                  );
                },
              ),
              if (cartProvider.itemCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '${cartProvider.itemCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: 'Item Code',
                hintText: 'Enter product code or name',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryBlue),
                suffixIcon: _isLoading
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : null,
              ),
              onChanged: _onSearchChanged,
              onSubmitted: (value) => _performSearch(value),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : () => _performSearch(_codeController.text),
                icon: const Icon(Icons.search),
                label: const Text('SEARCH'),
              ),
            ),
            const SizedBox(height: 24),
            if (_searchResults.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Search Results',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final product = _searchResults[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.inventory_2,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                        title: Text(product.productName),
                        subtitle: Text(product.productCode ?? 'No code'),
                        trailing: Text(
                          '₹${product.price.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                        onTap: () => _showProductDialog(product),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}