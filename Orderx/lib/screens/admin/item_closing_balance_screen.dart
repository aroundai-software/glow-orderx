import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/item_closing_balance_model.dart';
import 'package:Orderx/services/item_closing_balance_service.dart';

import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class ItemClosingBalanceScreen extends StatefulWidget {
  const ItemClosingBalanceScreen({super.key});

  @override
  State<ItemClosingBalanceScreen> createState() =>
      _ItemClosingBalanceScreenState();
}

class _ItemClosingBalanceScreenState extends State<ItemClosingBalanceScreen>
    with SingleTickerProviderStateMixin {
  final ItemClosingBalanceService _itemService = ItemClosingBalanceService();
  final TextEditingController _searchController = TextEditingController();

  List<ItemClosingBalanceModel> _allItems = [];
  List<ItemClosingBalanceModel> _filteredItems = [];
  bool _isLoading = true;
  String _searchQuery = '';
  late TabController _tabController;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadItems();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _filterItems();
    }
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;

      final items = await _itemService.getAllItemClosingBalances(companyId: effectiveCompanyId);
      final stats = await _itemService.getItemStats(companyId: effectiveCompanyId);

      if (mounted) {
        setState(() {
          _allItems = items;
          _stats = stats;
          _filterItems();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading items: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _filterItems() {
    List<ItemClosingBalanceModel> filtered = _allItems;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((item) =>
              item.itemName
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              (item.partNumber
                      ?.toLowerCase()
                      .contains(_searchQuery.toLowerCase()) ??
                  false) ||
              (item.godown
                      ?.toLowerCase()
                      .contains(_searchQuery.toLowerCase()) ??
                  false))
          .toList();
    }

    // Filter by tab selection
    switch (_tabController.index) {
      case 0: // All
        break;
      case 1: // In Stock
        filtered = filtered.where((item) => item.isInStock).toList();
        break;
      case 2: // Low Stock
        filtered = filtered.where((item) => item.isLowStock).toList();
        break;
      case 3: // Out of Stock
        filtered = filtered.where((item) => item.isOutOfStock).toList();
        break;
    }

    setState(() {
      _filteredItems = filtered;
    });
  }

  Color _getStockStatusColor(ItemClosingBalanceModel item) {
    if (item.isOutOfStock) return AppTheme.error;
    if (item.isLowStock) return AppTheme.warning;
    return AppTheme.success;
  }

  String _getStockStatus(ItemClosingBalanceModel item) {
    if (item.isOutOfStock) return 'Out of Stock';
    if (item.isLowStock) return 'Low Stock';
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat("#,##,##0.##", "en_IN");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Closing Balance'),
        actions: [
          GlobalCompanySwitcher(onCompanyChanged: _loadItems),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'All (${_stats['total_items'] ?? 0})'),
            Tab(text: 'In Stock (${_stats['in_stock_count'] ?? 0})'),
            Tab(text: 'Low (${_stats['low_stock_count'] ?? 0})'),
            Tab(text: 'Out (${_stats['out_of_stock_count'] ?? 0})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by item name, part number or godown...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _filterItems();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _filterItems();
              },
            ),
          ),

          // Summary Card
          if (!_isLoading && _stats.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem(
                    'Total Closing Qty',
                    numberFormat.format(_stats['total_closing_quantity'] ?? 0),
                    AppTheme.primaryBlue,
                  ),
                  _buildSummaryItem(
                    'Salable Qty',
                    numberFormat.format(_stats['total_salable_quantity'] ?? 0),
                    AppTheme.success,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadItems,
                    child: _filteredItems.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.3,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.inventory_2_outlined,
                                        size: 64,
                                        color: AppTheme.grey
                                            .withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _searchQuery.isNotEmpty
                                            ? 'No items found matching "$_searchQuery"'
                                            : 'No items found',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: AppTheme.grey,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = _filteredItems[index];
                              return _buildItemCard(item, numberFormat);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
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

  Widget _buildItemCard(
      ItemClosingBalanceModel item, NumberFormat numberFormat) {
    final statusColor = _getStockStatusColor(item);
    final stockStatus = _getStockStatus(item);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Icon(
            Icons.inventory_2,
            color: statusColor,
          ),
        ),
        title: Text(
          item.itemName,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.partNumber != null) Text('Part No: ${item.partNumber}'),
            if (item.godown != null) Text('Godown: ${item.godown}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    stockStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              numberFormat.format(item.closingQuantity),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            const Text(
              'Closing Qty',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.grey,
              ),
            ),
          ],
        ),
        onTap: () {
          _showItemDetails(item, numberFormat);
        },
      ),
    );
  }

  void _showItemDetails(
      ItemClosingBalanceModel item, NumberFormat numberFormat) {
    final statusColor = _getStockStatusColor(item);
    final stockStatus = _getStockStatus(item);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          item.itemName,
          style: const TextStyle(fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.partNumber != null)
                _buildDetailRow('Part Number', item.partNumber!),
              if (item.godown != null) _buildDetailRow('Godown', item.godown!),
              if (item.batchNames != null)
                _buildDetailRow('Batch Names', item.batchNames!),
              const SizedBox(height: 12),
              const Text('Stock Information',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildDetailRow('Closing Quantity',
                  numberFormat.format(item.closingQuantity)),
              _buildDetailRow('Closing Alt Qty',
                  numberFormat.format(item.closingAltQuantity)),
              _buildDetailRow(
                  'Salable Qty', numberFormat.format(item.salableQty)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Status: ',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      stockStatus,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
