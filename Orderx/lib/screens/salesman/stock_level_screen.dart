import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:Orderx/services/stock_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart' as provider;
import 'package:Orderx/widgets/company_display_widget.dart';

class StockLevelScreen extends StatefulWidget {
  const StockLevelScreen({super.key});

  @override
  State<StockLevelScreen> createState() => _StockLevelScreenState();
}

class _StockLevelScreenState extends State<StockLevelScreen> {
  final ProductService _productService = ProductService();
  final StockNotificationService _notificationService = StockNotificationService();
  final TextEditingController _searchController = TextEditingController();
  
  List<ProductModel> _products = [];
  List<ProductModel> _filteredProducts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final Set<String> _sendingNotifications = {};

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      
      print('🔍 Stock Level Screen - Loading products');
      print('📊 Selected Company ID: $companyId');
      print('👤 Current User: ${authProvider.currentUser?.name}');
      
      final products = await _productService.getProducts(companyId: companyId);
      
      print('✅ Loaded ${products.length} products for company: $companyId');
      
      setState(() {
        _products = products;
        _filteredProducts = products;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading products: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading products: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products.where((product) {
          return product.productName
                  .toLowerCase()
                  .contains(query.toLowerCase()) ||
              (product.productCode
                      ?.toLowerCase()
                      .contains(query.toLowerCase()) ??
                  false);
        }).toList();
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _filterProducts('');
  }

  String _getStockStatus(ProductModel product) {
    if (product.stock == 0) {
      return 'Out of Stock';
    } else if (product.stock <= 10) {
      return 'Low Stock';
    } else {
      return 'In Stock';
    }
  }

  Color _getStockStatusColor(ProductModel product) {
    if (product.stock == 0) {
      return AppTheme.error;
    } else if (product.stock <= 10) {
      return AppTheme.warning;
    } else {
      return AppTheme.success;
    }
  }

  Future<void> _sendStockNotification(ProductModel product) async {
    // Only allow notifications for low stock or out of stock items
    if (product.stock > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This item is in stock. Notifications are only for low or out of stock items.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _sendingNotifications.add(product.id);
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final user = authProvider.currentUser;
      final companyId = authProvider.selectedCompanyId;
      
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Determine notification type
      final notificationType = product.stock == 0 ? 'out_of_stock' : 'low_stock';

      await _notificationService.sendStockNotification(
        productId: product.id,
        productName: product.productName,
        stockLevel: product.stock,
        notificationType: notificationType,
        salesmanId: user.id,
        salesmanName: user.name,
        companyId: companyId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock alert sent to admin for ${product.productName}'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingNotifications.remove(product.id);
        });
      }
    }
  }

  Widget _buildProductCard(ProductModel product) {
    final stockStatus = _getStockStatus(product);
    final statusColor = _getStockStatusColor(product);
    final currencyFormatter = NumberFormat("#,##,##0", "en_IN");

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Product Image or Icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                image: product.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(product.imageUrl!),
                        fit: BoxFit.cover,
                        colorFilter: product.stock == 0
                            ? const ColorFilter.mode(
                                Colors.grey,
                                BlendMode.saturation,
                              )
                            : null,
                      )
                    : null,
                color: product.imageUrl == null
                    ? (product.stock == 0
                        ? Colors.grey.withOpacity(0.3)
                        : AppTheme.primaryBlue.withOpacity(0.1))
                    : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: product.stock == 0
                      ? Colors.grey
                      : AppTheme.primaryBlue.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: product.imageUrl == null
                  ? Icon(
                      Icons.inventory_2,
                      color: product.stock == 0
                          ? Colors.grey
                          : AppTheme.primaryBlue,
                      size: 30,
                    )
                  : null,
            ),
            const SizedBox(width: 16),

            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Name
                  Text(
                    product.productName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: product.stock == 0 ? Colors.grey : Colors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Product Code
                  if (product.productCode != null)
                    Text(
                      'Code: ${product.productCode}',
                      style: TextStyle(
                        fontSize: 12,
                        color: product.stock == 0 ? Colors.grey : AppTheme.grey,
                      ),
                    ),
                  const SizedBox(height: 4),

                  // Price
                  Text(
                    '₹${currencyFormatter.format(product.price)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: product.stock == 0
                          ? Colors.grey
                          : AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),

            // Stock Information
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Stock Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    stockStatus,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Stock Quantity - Show real-time stock
                FutureBuilder<double>(
                  future: _productService.getCurrentStock(product.id),
                  builder: (context, snapshot) {
                    final currentStock = snapshot.data ?? product.stock;
                    return Text(
                      'Qty: $currentStock',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: currentStock == 0 ? Colors.grey : Colors.black,
                      ),
                    );
                  },
                ),

                // Unit
                Text(
                  product.unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: product.stock == 0 ? Colors.grey : AppTheme.grey,
                  ),
                ),
                
                // Notify Admin Button (only for low stock or out of stock)
                if (product.stock <= 10) ...[
                  const SizedBox(height: 8),
                  _sendingNotifications.contains(product.id)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          onPressed: () => _sendStockNotification(product),
                          icon: const Icon(Icons.notifications_active),
                          iconSize: 20,
                          color: statusColor,
                          tooltip: 'Notify Admin',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList(
    List<ProductModel> products, {
    required String emptyLabel,
    required String emptySearchLabel,
  }) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? emptyLabel : emptySearchLabel,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: products.length,
        itemBuilder: (context, index) {
          return _buildProductCard(products[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allProducts = _filteredProducts;
    final inStockProducts = allProducts.where((p) => p.stock > 10).toList();
    final lowStockProducts = allProducts.where((p) => p.stock > 0 && p.stock <= 10).toList();
    final outOfStockProducts = allProducts.where((p) => p.stock == 0).toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Stock Level'),
              CompanyDisplayWidget(),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadProducts,
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'In Stock'),
              Tab(text: 'Low Stock'),
              Tab(text: 'Out of Stock'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: _filterProducts,
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.1),
                ),
              ),
            ),

            // Stock Summary
            if (!_isLoading)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryItem(
                      'Total Products',
                      '${allProducts.length}',
                      AppTheme.primaryBlue,
                    ),
                    _buildSummaryItem(
                      'In Stock',
                      '${inStockProducts.length}',
                      AppTheme.success,
                    ),
                    _buildSummaryItem(
                      'Low Stock',
                      '${lowStockProducts.length}',
                      AppTheme.warning,
                    ),
                    _buildSummaryItem(
                      'Out of Stock',
                      '${outOfStockProducts.length}',
                      AppTheme.error,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Products List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _buildProductList(
                          allProducts,
                          emptyLabel: 'No products found',
                          emptySearchLabel: 'No products match your search',
                        ),
                        _buildProductList(
                          inStockProducts,
                          emptyLabel: 'No in-stock products found',
                          emptySearchLabel: 'No in-stock products match your search',
                        ),
                        _buildProductList(
                          lowStockProducts,
                          emptyLabel: 'No low stock products found',
                          emptySearchLabel: 'No low stock products match your search',
                        ),
                        _buildProductList(
                          outOfStockProducts,
                          emptyLabel: 'No out of stock products found',
                          emptySearchLabel: 'No out of stock products match your search',
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.grey,
          ),
        ),
      ],
    );
  }
}
