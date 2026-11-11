import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/widgets/company_display_widget.dart';
import 'package:Orderx/widgets/add_customer_dialog.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final CustomerService _customerService = CustomerService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CustomerModel> _customers = [];
  List<CustomerModel> _filteredCustomers = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  String _searchQuery = '';
  int _searchRequestId = 0;
  int _totalCustomerCount = 0;
  int _trueTotalCustomerCount = 0;
  Timer? _debounceTimer;
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authProvider = context.read<AuthProvider>();
      _authProvider?.addListener(_onAuthProviderChanged);
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthProviderChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onAuthProviderChanged() {
    if (!mounted) return;
    _resetAndLoad();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMore && _searchQuery.isEmpty) {
        _loadMoreCustomers();
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      print('🔍 Customers Screen - Initial load');
      print('📊 Selected Company ID: $companyId');

      final results = await Future.wait([
        _customerService.getAllCustomersPaginated(
          companyId: companyId,
          page: 0,
          limit: 1000,
        ),
        _customerService.getTotalCustomerCount(companyId: companyId),
      ]);

      if (mounted) {
        setState(() {
          _customers = results[0] as List<CustomerModel>;
          _trueTotalCustomerCount = results[1] as int;
          _totalCustomerCount = _trueTotalCustomerCount;
          _filteredCustomers = _customers;
          _currentPage = 0;
          _hasMore = _customers.length >= 1000;
          _isLoading = false;
        });
      }
    } catch (e) {
      _handleError(e);
    }
  }

  Future<void> _loadMoreCustomers() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      final nextPage = _currentPage + 1;
      final newCustomers = await _customerService.getAllCustomersPaginated(
        companyId: companyId,
        page: nextPage,
        limit: 1000,
      );

      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _customers.addAll(newCustomers);
          _filteredCustomers = _customers;
          _hasMore = newCustomers.length >= 1000;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
      print('❌ Error loading more customers: $e');
    }
  }

  Future<void> _resetAndLoad() async {
    setState(() {
      _customers = [];
      _filteredCustomers = [];
      _currentPage = 0;
      _hasMore = true;
      _totalCustomerCount = 0;
      _trueTotalCustomerCount = 0;
    });
    await _loadInitialData();
  }

  void _handleError(Object e) {
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _filterCustomers(String query) {
    // Cancel previous timer
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      _searchRequestId++;
      setState(() {
        _searchQuery = '';
        _filteredCustomers = _customers;
        _totalCustomerCount = _trueTotalCustomerCount;
        _isLoading = false;
      });
      return;
    }

    // Debounce search for 500ms
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final requestId = ++_searchRequestId;

      setState(() {
        _searchQuery = trimmed;
        _isLoading = true;
      });

      try {
        final authProvider = context.read<AuthProvider>();
        final companyId = authProvider.selectedCompanyId;

        final results = await _customerService.searchCustomers(
          trimmed,
          companyId: companyId,
        );

        if (mounted && requestId == _searchRequestId) {
          setState(() {
            _filteredCustomers = results;
            _totalCustomerCount = results.length;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted && requestId == _searchRequestId) {
          _handleError(e);
        }
      }
    });
  }

  Future<void> _showAddCustomerDialog() async {
    final CustomerModel? newCustomer = await showDialog<CustomerModel>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddCustomerDialog(),
    );

    if (newCustomer != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Customer "${newCustomer.customerName}" added successfully!'),
          backgroundColor: AppTheme.success,
        ),
      );
      _resetAndLoad();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Customers'),
            CompanyDisplayWidget(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh customers',
            onPressed: _resetAndLoad,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or city',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryBlue),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppTheme.lightGrey,
              ),
              onChanged: _filterCustomers,
            ),
          ),
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$_totalCustomerCount Customers Found',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          if (!_isLoading)
            const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _resetAndLoad,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredCustomers.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _filteredCustomers.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final customer = _filteredCustomers[index];
                            return _CustomerCard(customer: customer);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddCustomerDialog,
              icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
              label: const Text(
                'Add Customer',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppTheme.primaryBlue,
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: AppTheme.grey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No customers found',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: AppTheme.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the search or add a new customer',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.grey),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final CustomerModel customer;
  const _CustomerCard({required this.customer});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                  child: Text(
                    customer.customerName.isNotEmpty
                        ? customer.customerName[0].toUpperCase()
                        : 'C',
                    style: const TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.customerName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (customer.mobileNumber != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone, size: 14, color: AppTheme.grey),
                            const SizedBox(width: 4),
                            Text(
                              customer.mobileNumber!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.grey),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (customer.fullAddress.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, size: 16, color: AppTheme.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      customer.fullAddress,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            if (customer.gstNumber != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'GST: ${customer.gstNumber}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
