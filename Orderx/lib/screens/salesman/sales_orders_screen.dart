import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/salesman/order_details_screen.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/services/company_selection_service.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/error_state_widget.dart';

class SalesOrdersScreen extends StatefulWidget {
  const SalesOrdersScreen({super.key});

  @override
  State<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends State<SalesOrdersScreen> {
  final OrderService _orderService = OrderService();
  List<OrderModel> _allOrders = [];
  List<OrderModel> _filteredOrders = [];
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  AuthProvider? _authProvider;
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authProvider = context.read<AuthProvider>();
      _authProvider?.addListener(_onAuthProviderChanged);
    });
    _searchController.addListener(_filterOrders);
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthProviderChanged);
    _searchController.removeListener(_filterOrders);
    _searchController.dispose();
    super.dispose();
  }

  void _onAuthProviderChanged() {
    if (!mounted) return;
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    print('🔄 SalesOrdersScreen: _loadOrders called');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.currentUser != null) {
        final orders = await _orderService.getOrdersBySalesman(
          authProvider.currentUser!.id,
          companyId: authProvider.selectedCompanyId,
        );

        print('🔄 SalesOrdersScreen: Received ${orders.length} orders');
        if (mounted) {
          setState(() {
            _allOrders = orders;
            _filteredOrders = orders;
            _isLoading = false;
          });
          print('🔄 SalesOrdersScreen: UI updated with ${orders.length} orders');
        }
      }
    } catch (e) {
      print('Error loading orders: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorHandler.getFriendlyErrorMessage(e);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _filterOrders() {
    if (!mounted) return;

    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredOrders = _allOrders.where((order) {
        // 1. Date Range Filter
        if (_selectedDateRange != null) {
          final orderDate = order.orderDate;
          final start = _selectedDateRange!.start;
          final end = _selectedDateRange!.end.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
          if (orderDate.isBefore(start) || orderDate.isAfter(end)) {
            return false;
          }
        }

        // 2. Text Search Filter
        if (query.isEmpty) return true;

        if (order.orderNumber.toLowerCase().contains(query)) return true;
        if (order.customerName != null && order.customerName!.toLowerCase().contains(query)) return true;
        if (order.customerMobile != null && order.customerMobile!.contains(query)) return true;
        if (order.customerGst != null && order.customerGst!.toLowerCase().contains(query)) return true;
        if (order.status.toLowerCase().contains(query)) return true;
        if (query.length >= 2 && order.netAmount.toString().contains(query)) return true;

        return false;
      }).toList();
    });
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

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _filterOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Orders'),
        actions: [
          IconButton(
            icon: Icon(_selectedDateRange != null ? Icons.filter_alt : Icons.filter_alt_outlined),
            color: _selectedDateRange != null ? AppTheme.primaryBlue : null,
            tooltip: 'Filter by date',
            onPressed: _pickDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh orders',
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by order #, name, mobile, GST, status...',
                hintStyle: const TextStyle(color: AppTheme.grey, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.primaryBlue),
                suffixIcon: _searchController.text.trim().isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterOrders();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          // orders List
          if (_selectedDateRange != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 16, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Text(
                    '${DateFormat('MMM d, yyyy').format(_selectedDateRange!.start)} - ${DateFormat('MMM d, yyyy').format(_selectedDateRange!.end)}',
                    style: const TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      setState(() => _selectedDateRange = null);
                      _filterOrders();
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Text(
                        'Clear filter',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? _buildLoadingIndicator()
                : _errorMessage != null
                    ? ErrorStateWidget(
                        message: _errorMessage!,
                        onRetry: _loadOrders,
                      )
                    : _filteredOrders.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredOrders.length,
                          itemBuilder: (context, index) {
                            final order = _filteredOrders[index];
                            return _OrderCard(
                              order: order,
                              onPrint: () => _printOrder(order),
                              onShare: () => _shareOrder(order),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated loading icon
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1500),
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.8 + (value * 0.2),
                child: Opacity(
                  opacity: 0.5 + (value * 0.5),
                  child: const Icon(
                    Icons.receipt_long,
                    size: 80,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              );
            },
            onEnd: () {
              if (mounted && _isLoading) {
                setState(() {}); // Restart animation
              }
            },
          ),
          const SizedBox(height: 24),

          // Animated loading text
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: 3),
            duration: const Duration(milliseconds: 1500),
            builder: (context, value, child) {
              String dots = '.' * value;
              return Text(
                'Loading your orders$dots',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
              );
            },
            onEnd: () {
              if (mounted && _isLoading) {
                setState(() {}); // Restart animation
              }
            },
          ),
          const SizedBox(height: 12),

          // Subtitle
          Text(
            'Please wait, this will take just a moment',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.grey,
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 32),

          // Progress indicator
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearchQuery ? Icons.search_off : Icons.receipt_long_outlined,
            size: 80,
            color: AppTheme.grey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearchQuery ? 'No orders found' : 'No orders yet',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.grey,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearchQuery
                ? 'Try searching with different keywords'
                : 'Start creating orders to see them here',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.grey,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onPrint;
  final VoidCallback onShare;

  const _OrderCard({
    required this.order,
    required this.onPrint,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderDetailsScreen(order: order),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderNumber,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryBlue,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: AppTheme.grey,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                DateFormat('MMM dd, yyyy - hh:mm a')
                                    .format(order.createdAt.toLocal()),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.grey,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (order.updatedAt != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.withOpacity(0.5), width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note,
                              size: 12, color: Colors.orange),
                          SizedBox(width: 3),
                          Text(
                            'Edited',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              // Customer Details
              if (order.customerName != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.lightGrey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person,
                              size: 16, color: AppTheme.primaryBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              order.customerName!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (order.customerMobile != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone,
                                size: 14, color: AppTheme.grey),
                            const SizedBox(width: 8),
                            Text(
                              order.customerMobile!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (order.customerGst != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.receipt,
                                size: 14, color: AppTheme.grey),
                            const SizedBox(width: 8),
                            Text(
                              order.customerGst!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Amount',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.grey,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${order.netAmount.toStringAsFixed(2)}',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.print, size: 20, color: AppTheme.grey),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: onPrint,
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, size: 20, color: AppTheme.grey),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: onShare,
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: AppTheme.grey,
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
  }
}


