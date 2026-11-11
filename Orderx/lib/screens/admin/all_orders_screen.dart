import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/services/company_selection_service.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:Orderx/screens/admin/order_details_admin_screen.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/error_state_widget.dart';

class AllOrdersScreen extends StatefulWidget {
  const AllOrdersScreen({super.key});

  @override
  State<AllOrdersScreen> createState() => _AllOrdersScreenState();
}

class _AllOrdersScreenState extends State<AllOrdersScreen> {
  final OrderService _orderService = OrderService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Data
  final List<OrderModel> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;

  // Filters
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _itemSearchController = TextEditingController();
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();
  
  DateTime? _startDate;
  DateTime? _endDate;

  // Debouncing for text search not strictly needed if we rely on "Apply" button or keyboard submission, 
  // but let's stick to "Apply" in drawer for complex filters and instant search for the main bar.

  @override
  void initState() {
    super.initState();
    _loadOrders(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _itemSearchController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadOrders();
    }
  }

  Future<void> _loadOrders({bool reset = false}) async {
    if (_isLoading) return;
    
    print('🔄 AllOrdersScreen: _loadOrders called (reset: $reset)');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (reset) {
        _orders.clear();
        _currentPage = 1;
        _hasMore = true;
      }
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final String? selectedCompanyId = authProvider.selectedCompanyId;
      final String? effectiveCompanyId = (selectedCompanyId == 'ALL') ? null : selectedCompanyId;
      print('🔄 AllOrdersScreen: selectedCompanyId: $selectedCompanyId, effectiveCompanyId: $effectiveCompanyId');

      final double? minAmount = double.tryParse(_minAmountController.text);
      final double? maxAmount = double.tryParse(_maxAmountController.text);

      final newOrders = await _orderService.getOrdersWithFilters(
        companyId: effectiveCompanyId,
        page: _currentPage,
        pageSize: _pageSize,
        searchQuery: _searchController.text.trim(),
        itemName: _itemSearchController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        minAmount: minAmount,
        maxAmount: maxAmount,
      );

      print('🔄 AllOrdersScreen: Received ${newOrders.length} orders from service');

      if (mounted) {
        setState(() {
          if (newOrders.length < _pageSize) {
            _hasMore = false;
          }
          _orders.addAll(newOrders);
          _currentPage++;
          _isLoading = false;
        });
        print('🔄 AllOrdersScreen: UI updated, total orders: ${_orders.length}');
      }
    } catch (e) {
      print('❌ AllOrdersScreen: Error loading orders: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorHandler.getFriendlyErrorMessage(e);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage!)),
        );
      }
    }
  }

  void _applyFilters() {
    Navigator.of(context).pop(); // Close drawer
    _loadOrders(reset: true);
  }

  void _resetFilters() {
    _itemSearchController.clear();
    _minAmountController.clear();
    _maxAmountController.clear();
    // Keep main search query? Usually reset clears everything in the drawer.
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    // Don't close drawer immediately so user can see it's cleared? Or close and reload.
    // Let's reload.
    _applyFilters();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _shareOrder(OrderModel order) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)));
    try {
      final items = await _orderService.getOrderItems(order.id);
      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items to share'), backgroundColor: Colors.orange));
        return;
      }
      TallyCompanyModel? company;
      var settings;
      if (order.companyId != null && order.companyId!.isNotEmpty) {
        final companyData = await CompanySelectionService().getCompanyById(order.companyId!);
        if (companyData != null) {
          company = TallyCompanyModel.fromJson(companyData);
        }
        settings = await AdminSettingsService().getAdminSettings(order.companyId!);
      }
      final pdfBytes = await PdfService().generateOrderPdf(order, items, company: company, companyName: order.companyName, settings: settings);
      await PdfService().sharePdf(pdfBytes, order.orderNumber);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sharing: $e'), backgroundColor: AppTheme.error));
    }
  }

  Future<void> _printOrder(OrderModel order) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)));
    try {
      final items = await _orderService.getOrderItems(order.id);
      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items to print'), backgroundColor: Colors.orange));
        return;
      }
      TallyCompanyModel? company;
      var settings;
      if (order.companyId != null && order.companyId!.isNotEmpty) {
        final companyData = await CompanySelectionService().getCompanyById(order.companyId!);
        if (companyData != null) {
          company = TallyCompanyModel.fromJson(companyData);
        }
        settings = await AdminSettingsService().getAdminSettings(order.companyId!);
      }
      final pdfBytes = await PdfService().generateOrderPdf(order, items, company: company, companyName: order.companyName, settings: settings);
      await PdfService().printPdf(pdfBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error printing: $e'), backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('All Orders'),
        actions: [
          GlobalCompanySwitcher(onCompanyChanged: () => _loadOrders(reset: true)),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadOrders(reset: true),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list_alt),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Filters',
          ),
        ],
      ),
      endDrawer: Drawer(
        width: 300,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
              color: AppTheme.primaryBlue,
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    'Filter Orders',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                   // Date Range
                  const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selectDateRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range, color: AppTheme.grey, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _startDate == null
                                  ? 'Select Dates'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}',
                              style: TextStyle(
                                color: _startDate == null ? AppTheme.grey : Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const Divider(height: 32),

                  // Item Name
                  const Text('Contains Item', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _itemSearchController,
                    decoration: const InputDecoration(
                      hintText: 'e.g., Chicken',
                      prefixIcon: Icon(Icons.shopping_basket_outlined),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),

                  const Divider(height: 32),

                  // Amount Range
                  const Text('Amount Range', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Min',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('-'),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _maxAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Max',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resetFilters,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _applyFilters,
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Main Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search order #, customer name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _loadOrders(reset: true), // Trigger search manually
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _loadOrders(reset: true),
            ),
          ),

          // Active Filters Chips (Optional visual feedback)
          if (_startDate != null || _itemSearchController.text.isNotEmpty || _minAmountController.text.isNotEmpty)
             SingleChildScrollView(
               scrollDirection: Axis.horizontal,
               padding: const EdgeInsets.symmetric(horizontal: 16),
               child: Row(
                 children: [
                   if (_startDate != null)
                     Padding(
                       padding: const EdgeInsets.only(right: 8),
                       child: Chip(
                         label: Text('${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}'),
                         onDeleted: () {
                           setState(() {
                             _startDate = null;
                             _endDate = null;
                           });
                           _loadOrders(reset: true);
                         },
                       ),
                     ),
                   if (_itemSearchController.text.isNotEmpty)
                     Padding(
                       padding: const EdgeInsets.only(right: 8),
                       child: Chip(
                         label: Text('Item: ${_itemSearchController.text}'),
                         onDeleted: () {
                           _itemSearchController.clear();
                           _loadOrders(reset: true);
                         },
                       ),
                     ),
                   if (_minAmountController.text.isNotEmpty)
                      Padding(
                       padding: const EdgeInsets.only(right: 8),
                       child: Chip(
                         label: Text('Min: ₹${_minAmountController.text}'),
                         onDeleted: () {
                           _minAmountController.clear();
                           _loadOrders(reset: true);
                         },
                       ),
                     ),
                 ],
               ),
             ),

          // Orders List
          Expanded(
            child: _isLoading && _orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null && _orders.isEmpty
                    ? ErrorStateWidget(
                        message: _errorMessage!,
                        onRetry: () => _loadOrders(reset: true),
                      )
                    : _orders.isEmpty && !_isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: AppTheme.grey.withOpacity(0.5),
                        ),
                         const SizedBox(height: 16),
                        Text(
                          'No orders found',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                        ),
                        if (_startDate != null || _searchController.text.isNotEmpty || _itemSearchController.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton(
                              onPressed: _resetFilters,
                              child: const Text('Clear Filters'),
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _orders.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _orders.length) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final order = _orders[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OrderDetailsAdminScreen(
                                  order: order,
                                ),
                              ),
                            );
                          },
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
                                        order.orderNumber,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    _buildBillingBadge(order.syncedToTally),
                                  ],
                                ),
                                if (order.companyName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.business, size: 14, color: AppTheme.primaryBlue),
                                        const SizedBox(width: 4),
                                        Text(
                                          order.companyName!,
                                          style: const TextStyle(
                                            color: AppTheme.primaryBlue,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (order.salesmanName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.badge, size: 14, color: AppTheme.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Salesman: ${order.salesmanName}',
                                          style: const TextStyle(
                                            color: AppTheme.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 16, color: AppTheme.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        order.customerName ?? 'Unknown Customer',
                                        style: const TextStyle(color: AppTheme.grey),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (order.customerMobile != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.phone_android, size: 16, color: AppTheme.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          order.customerMobile!,
                                          style: const TextStyle(color: AppTheme.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          DateFormat('MMM dd, yyyy h:mm a').format(order.orderDate),
                                          style: const TextStyle(
                                            color: AppTheme.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.print, size: 20, color: AppTheme.grey),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          onPressed: () => _printOrder(order),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.share, size: 20, color: AppTheme.grey),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          onPressed: () => _shareOrder(order),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '₹${order.netAmount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingBadge(bool billed) {
    final color = billed ? AppTheme.success : AppTheme.warning;
    final label = billed ? 'Billed' : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
