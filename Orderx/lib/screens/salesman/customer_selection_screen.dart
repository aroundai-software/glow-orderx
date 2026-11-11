import 'dart:async';

import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/connectivity_provider.dart';
import 'package:Orderx/providers/offline_data_provider.dart';
import 'package:Orderx/widgets/add_customer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CustomerSelectionScreen extends StatefulWidget {
  const CustomerSelectionScreen({super.key});

  @override
  State<CustomerSelectionScreen> createState() => _CustomerSelectionScreenState();
}

class _CustomerSelectionScreenState extends State<CustomerSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<CustomerModel> _allCustomers = [];
  List<CustomerModel> _filteredCustomers = [];
  bool _isLoading = true;
  String? _error;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _openAddCustomerDialog([String? prefilledName]) async {
    final newCustomer = await showDialog<CustomerModel>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddCustomerDialog(
        initialName: prefilledName,
      ),
    );

    if (newCustomer != null && mounted) {
      setState(() {
        _allCustomers.insert(0, newCustomer);
        _filteredCustomers = List<CustomerModel>.from(_allCustomers);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Customer "${newCustomer.customerName}" created!'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );

      // Auto-select the newly created customer for this order
      Navigator.pop(context, newCustomer);
    }
  }

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final authProvider = context.read<AuthProvider>();
      String? companyId = authProvider.selectedCompanyId ?? authProvider.currentUser?.companyId;
      print('🔍 CustomerSelectionScreen: Loading customers for companyId=$companyId');
      final isOnline = context.read<ConnectivityProvider>().isOnline;
      print('🔍 CustomerSelectionScreen: Online status=$isOnline');
      final customers = await context.read<OfflineDataProvider>().fetchCustomers(
            companyId: companyId,
            preferOnline: isOnline,
          );
      print('🔍 CustomerSelectionScreen: Loaded ${customers.length} customers');
      if (!mounted) return;
      setState(() {
        _allCustomers = customers;
        _filteredCustomers = customers;
        _isLoading = false;
      });
      print('🔍 CustomerSelectionScreen: State updated with ${_allCustomers.length} total customers');
    } catch (e) {
      print('❌ CustomerSelectionScreen: Error loading customers: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      print('🔍 CustomerSelectionScreen: Search cleared, showing all ${_allCustomers.length} customers');
      setState(() => _filteredCustomers = List<CustomerModel>.from(_allCustomers));
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      print('🔍 CustomerSelectionScreen: Searching for "$trimmed" in ${_allCustomers.length} customers');
      final scored = _allCustomers
          .map((c) => (customer: c, score: _customerSearchScore(c, trimmed)))
          .where((e) => e.score >= 0)
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      print('🔍 CustomerSelectionScreen: Found ${scored.length} matching customers');
      if (scored.isNotEmpty) {
        print('🔍 Top matches: ${scored.take(5).map((e) => '${e.customer.customerName} (score=${e.score})').join(', ')}');
      }
      setState(() => _filteredCustomers = scored.map((e) => e.customer).toList());
    });
  }

  int _customerSearchScore(CustomerModel customer, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return -1;
    final normalizedQuery = _normalizeSearch(query);
    final queryTokens = _tokenize(query);
    final name = customer.customerName.toLowerCase();
    final normalizedName = _normalizeSearch(name);
    final mobile = (customer.mobileNumber ?? '').toLowerCase();
    final city = (customer.city ?? '').toLowerCase();
    final address = (customer.address ?? '').toLowerCase();

    if (name.contains(query)) return 100;
    if (normalizedQuery.isNotEmpty && normalizedName.contains(normalizedQuery)) return 95;
    if (mobile.contains(query)) return 90;
    if (city.contains(query) || address.contains(query)) return 75;
    
    if (queryTokens.length > 1) {
      final nameTokens = _tokenize(name);
      final cityTokens = _tokenize(city);
      final addressTokens = _tokenize(address);
      
      final nameMatches = queryTokens.where(
        (qt) => nameTokens.any((nt) => nt.startsWith(qt)),
      ).length;
      
      if (nameMatches == queryTokens.length) return 85;
      
      final cityMatches = queryTokens.where(
        (qt) => cityTokens.any((ct) => ct.startsWith(qt)),
      ).length;
      
      final addressMatches = queryTokens.where(
        (qt) => addressTokens.any((at) => at.startsWith(qt)),
      ).length;
      
      if (cityMatches == queryTokens.length || addressMatches == queryTokens.length) return 70;
    } else if (queryTokens.length == 1) {
      final qt = queryTokens[0];
      final nameTokens = _tokenize(name);
      if (nameTokens.any((nt) => nt.startsWith(qt))) return 80;
      
      final cityTokens = _tokenize(city);
      final addressTokens = _tokenize(address);
      if (cityTokens.any((ct) => ct.startsWith(qt)) || addressTokens.any((at) => at.startsWith(qt))) return 65;
    }
    return -1;
  }

  String _normalizeSearch(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  List<String> _tokenize(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();

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
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
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
                          hintText: 'Search customers by name, phone or city...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.15),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1, color: AppTheme.primaryBlue),
                      tooltip: 'Add New Customer',
                      onPressed: () => _openAddCustomerDialog(_searchController.text.trim()),
                    ),
                  ],
                ),
              ),
              if (!_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_filteredCustomers.length} Customers Found',
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
                    : _error != null
                        ? _buildErrorState()
                        : _filteredCustomers.isEmpty
                            ? _buildEmptyState(context)
                            : ListView.separated(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                itemBuilder: (context, index) {
                                  final customer = _filteredCustomers[index];
                                  return InkWell(
                                    onTap: () =>
                                        Navigator.pop(context, customer),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color:
                                              Colors.black.withOpacity(0.08),
                                          width: 0.8,
                                        ),
                                        color: Colors.white,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor:
                                                AppTheme.primaryBlue
                                                    .withOpacity(0.1),
                                            child: Text(
                                              customer.customerName.isNotEmpty
                                                  ? customer.customerName[0]
                                                      .toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                color: AppTheme.primaryBlue,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  customer.customerName,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                if (customer.mobileNumber !=
                                                    null)
                                                  Text(
                                                    customer.mobileNumber!,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: AppTheme.grey,
                                                    ),
                                                  ),
                                                Text(
                                                  _formatLocation(customer),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppTheme.darkGrey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.chevron_right,
                                              color: Colors.black54, size: 18),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemCount: _filteredCustomers.length,
                              ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openAddCustomerDialog(_searchController.text.trim()),
          backgroundColor: AppTheme.primaryBlue,
          icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
          label: const Text(
            'New Customer',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final hasSearch = _searchController.text.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: AppTheme.primaryBlue.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              hasSearch
                  ? 'No customers match your search.'
                  : 'No customers found.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.grey,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _openAddCustomerDialog(_searchController.text.trim()),
              icon: const Icon(Icons.add, size: 20),
              label: Text(
                hasSearch
                    ? 'Add "${_searchController.text.trim()}" as New Customer'
                    : 'Add New Customer',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 12),
          const Text(
            'Failed to load customers.',
            style: TextStyle(color: AppTheme.error),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadCustomers,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _formatLocation(CustomerModel customer) {
    final parts = [customer.city, customer.state, customer.address]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'No location';
    return parts.join(' • ');
  }
}
