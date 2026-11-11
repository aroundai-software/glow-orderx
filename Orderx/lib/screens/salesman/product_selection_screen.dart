import 'dart:async';

import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/cart_provider.dart';
import 'package:Orderx/providers/connectivity_provider.dart';
import 'package:Orderx/providers/offline_data_provider.dart';
import 'package:Orderx/screens/salesman/cart_screen.dart';
import 'package:Orderx/screens/salesman/product_details_screen.dart';
import 'package:Orderx/screens/salesman/qr_scanner_screen.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProductSelectionScreen extends StatefulWidget {
  final CustomerModel? preSelectedCustomer;
  final bool canScanQr;
  final bool isSelectionMode;

  const ProductSelectionScreen({
    super.key,
    this.preSelectedCustomer,
    this.canScanQr = false,
    this.isSelectionMode = false,
  });

  @override
  State<ProductSelectionScreen> createState() => _ProductSelectionScreenState();
}

class _ProductSelectionScreenState extends State<ProductSelectionScreen> {
  final ProductService _productService = ProductService();
  final AdminSettingsService _settingsService = AdminSettingsService();
  final TextEditingController _searchController = TextEditingController();

  List<ProductModel> _searchResults = [];
  bool _isSearching = false;
  bool _isInitialLoading = true;
  Timer? _debounceTimer;
  bool _hasLoadedOnce = false;
  bool _hideStockQuantity = false;

  @override
  void initState() {
    super.initState();
    _loadStockVisibilitySetting();
    // Perform initial empty search to show all products
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performSearch('');
    });
  }

  void _loadStockVisibilitySetting() async {
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId ?? authProvider.currentUser?.companyId;
    if (companyId != null) {
      final hide = await _settingsService.shouldHideStockQuantityFromSalesman(companyId);
      if (mounted) {
        setState(() {
          _hideStockQuantity = hide;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh products when screen becomes visible (e.g., after returning from cart)
    // Only refresh after the initial load to prevent excessive refreshes
    if (_hasLoadedOnce) {
      print('🔄 ProductSelectionScreen: didChangeDependencies triggered, refreshing products');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Force refresh product cache to get updated stock
        final authProvider = context.read<AuthProvider>();
        String? companyId = authProvider.selectedCompanyId;
        if (companyId == null && authProvider.currentUser?.companyId != null) {
          companyId = authProvider.currentUser!.companyId;
        }
        if (companyId != null) {
          print('🔄 ProductSelectionScreen: Calling refreshProductCache for company $companyId');
          await context.read<OfflineDataProvider>().refreshProductCache(companyId: companyId);
          print('🔄 ProductSelectionScreen: Cache refresh completed');
        }
        // Then perform search with updated cache
        print('🔄 ProductSelectionScreen: Performing search with query "${_searchController.text.trim()}"');
        _performSearch(_searchController.text.trim());
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _performSearch('');
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() => _isSearching = true);
    try {
      final authProvider = context.read<AuthProvider>();
      String? companyId = authProvider.selectedCompanyId;
      final isOnline = context.read<ConnectivityProvider>().isOnline;

      // Recovery if companyId is missing
      if (companyId == null && authProvider.currentUser?.companyId != null) {
        companyId = authProvider.currentUser!.companyId;
        debugPrint('♻️ ProductSelection: Recovered companyId: $companyId');
      }

      final results = await context.read<OfflineDataProvider>().searchProducts(
            query,
            companyId: companyId,
            preferOnline: isOnline,
          );

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _isInitialLoading = false;
        _hasLoadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _isInitialLoading = false;
        _searchResults = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: ${e.toString()}')),
      );
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _performSearch('');
  }

  Future<void> _openProductDetails(ProductModel product) async {
    await ProductDetailsDialog.show(
      context,
      product: product,
      customer: widget.preSelectedCustomer,
    );
    if (!mounted) return;
    if (_searchController.text.trim().isNotEmpty) {
      _performSearch(_searchController.text.trim());
    }
  }

  Future<void> _scanAndFetchProduct() async {
    if (!widget.canScanQr || !mounted) return;
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );
    if (scannedCode != null && mounted) {
      await _fetchAndShowProduct(scannedCode);
    }
  }

  Future<void> _fetchAndShowProduct(String code) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      // Try to find the product in cache first if it's a code scan
      final products = await context
          .read<OfflineDataProvider>()
          .getCachedProducts(companyId: companyId);
      ProductModel? product;
      try {
        product = products.firstWhere(
          (p) => p.productCode == code || p.vtNumber == code,
        );
      } catch (_) {
        // Fallback to online if not found in cache and isOnline
        if (context.read<ConnectivityProvider>().isOnline) {
          product = await _productService.getProductByCode(code,
              companyId: companyId);
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      if (product != null) {
        await _openProductDetails(product);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product not found in this company.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _openCart() async {
    final orderCreated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CartScreen(
          preSelectedCustomer: widget.preSelectedCustomer,
        ),
      ),
    );

    if (orderCreated == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search by Item Code or Name...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _buildSuffixIcon(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14.0),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.15),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14.0,
                            horizontal: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!widget.isSelectionMode)
                      AppBarCartButton(onPressed: _openCart),
                  ],
                ),
              ),
              if (!_isInitialLoading && !_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_searchResults.length} Products Found',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              if (!_isInitialLoading && !_isSearching)
                const SizedBox(height: 8),
              Expanded(
                child: _isInitialLoading || _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _searchResults.isEmpty
                        ? _buildEmptyState()
                        : _buildResultList(),
              ),
              Consumer<CartProvider>(
                builder: (context, cartProvider, child) {
                  if (cartProvider.itemCount == 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Card(
                      color: AppTheme.success.withOpacity(0.1),
                      child: ListTile(
                        leading: const Icon(Icons.shopping_cart,
                            color: AppTheme.success, size: 32),
                        title: Text(
                          'Current Cart',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        subtitle: Text(
                          '${cartProvider.totalQuantity == cartProvider.totalQuantity.truncateToDouble() ? cartProvider.totalQuantity.toInt() : cartProvider.totalQuantity} items • ₹${cartProvider.grandTotal.toStringAsFixed(2)}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios,
                            color: AppTheme.success, size: 18),
                        onTap: _openCart,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildSuffixIcon() {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_searchController.text.isNotEmpty) {
      return IconButton(
        icon: const Icon(Icons.clear),
        onPressed: _clearSearch,
        tooltip: 'Clear Search',
      );
    }

    return null;
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2,
                size: 64, color: AppTheme.primaryBlue.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              hasSearch
                  ? 'No products match your search.'
                  : 'No products found.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultList() {
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.4),
      itemBuilder: (context, index) {
        final product = _searchResults[index];
        final isOutOfStock = product.stock <= 0;
        final showOutOfStock = !_hideStockQuantity && isOutOfStock;

        return InkWell(
          onTap: () => _openProductDetails(product),
          child: Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: Colors.black.withOpacity(0.12), width: 0.8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductThumbnail(
                  imageUrl: product.imageUrl,
                  isOutOfStock: showOutOfStock,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              product.productName,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color:
                                    showOutOfStock ? Colors.grey : Colors.black,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (showOutOfStock) _OutOfStockBadge(),
                        ],
                      ),
                      const SizedBox(height: 0.5),
                      Row(
                        children: [
                          Text(
                            product.hsn ?? 'No HSN',
                            style: TextStyle(
                              fontSize: 10,
                              color: isOutOfStock ? Colors.grey : AppTheme.grey,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'GST: ${product.gstRate.toStringAsFixed(product.gstRate.truncateToDouble() == product.gstRate ? 0 : 1)}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: isOutOfStock ? Colors.grey : AppTheme.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (!_hideStockQuantity)
                        Text(
                          'Stock: ${product.stock}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isOutOfStock
                              ? Colors.orange
                              : AppTheme.primaryBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${product.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isOutOfStock ? Colors.grey : Colors.black,
                      ),
                    ),
                    Text(
                      '₹${(product.price + (product.price * product.gstRate / 100)).toStringAsFixed(2)} incl. GST',
                      style: TextStyle(
                        fontSize: 8.5,
                        color: isOutOfStock ? Colors.grey : AppTheme.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  final String? imageUrl;
  final bool isOutOfStock;

  const _ProductThumbnail({
    required this.imageUrl,
    required this.isOutOfStock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: isOutOfStock ? Colors.grey.withOpacity(0.2) : AppTheme.lightGrey,
        borderRadius: BorderRadius.zero,
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
                colorFilter: isOutOfStock
                    ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                    : null,
              )
            : null,
      ),
      child: imageUrl == null
          ? Icon(
              Icons.inventory_2,
              color: isOutOfStock ? Colors.grey : AppTheme.primaryBlue,
            )
          : null,
    );
  }
}

class _OutOfStockBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.error, width: 0.8),
      ),
      child: const Text(
        'Out of Stock',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppTheme.error,
        ),
      ),
    );
  }
}
