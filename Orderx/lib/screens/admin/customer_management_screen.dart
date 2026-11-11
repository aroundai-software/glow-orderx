// lib/screens/admin/customer_management_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/error_state_widget.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  final CustomerService _service = CustomerService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CustomerModel> _customers = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  String _searchQuery = '';
  Timer? _debounceTimer;
  int _totalCustomerCount = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refreshCustomers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMore && _searchQuery.isEmpty) {
        _loadMoreCustomers();
      }
    }
  }

  Future<void> _refreshCustomers() async {
    setState(() {
      _customers = [];
      _currentPage = 0;
      _hasMore = true;
      _isLoading = true;
      _errorMessage = null;
      _totalCustomerCount = 0;
    });

    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;
    final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;
    
    try {
      final customers = await _service.getAllCustomersPaginated(
        companyId: effectiveCompanyId,
        page: 0,
        limit: 1000,
      );

      final totalCount = await _service.getTotalCustomerCount(companyId: effectiveCompanyId);

      if (mounted) {
        setState(() {
          _customers = customers;
          _hasMore = customers.length >= 1000;
          _totalCustomerCount = totalCount;
          _isLoading = false;
        });
      }
    } catch (e) {
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

  Future<void> _loadMoreCustomers() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;

      final nextPage = _currentPage + 1;
      final newCustomers = await _service.getAllCustomersPaginated(
        companyId: effectiveCompanyId,
        page: nextPage,
        limit: 1000,
      );

      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _customers.addAll(newCustomers);
          _hasMore = newCustomers.length >= 1000;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _searchCustomers(String query) async {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      _refreshCustomers();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;

      setState(() {
        _searchQuery = query;
        _isLoading = true;
        _errorMessage = null;
      });

      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;

      try {
        final results = await _service.searchCustomers(query, companyId: effectiveCompanyId);
        if (mounted) {
          setState(() {
            _customers = results;
            _totalCustomerCount = results.length;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = ErrorHandler.getFriendlyErrorMessage(e);
          });
        }
      }
    });
  }

  Future<void> _showAddCustomerDialog() async {
    await _showCustomerFormDialog(
      title: 'Add New Customer',
      onSave: (customer) async {
        try {
          await _service.addCustomer(
            customerName: customer.customerName,
            mobileNumber: customer.mobileNumber,
            address: customer.address,
            city: customer.city,
            state: customer.state,
            pincode: customer.pincode,
            gstNumber: customer.gstNumber,
            createdBy: null,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Customer added successfully!')),
            );
            _refreshCustomers();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}')),
            );
          }
        }
      },
    );
  }

  Future<void> _showEditCustomerDialog(CustomerModel customer) async {
    await _showCustomerFormDialog(
      title: 'Edit Customer',
      customer: customer,
      onSave: (updatedCustomer) async {
        try {
          await _service.updateCustomer(
            id: customer.id,
            customerName: updatedCustomer.customerName,
            mobileNumber: updatedCustomer.mobileNumber,
            address: updatedCustomer.address,
            city: updatedCustomer.city,
            state: updatedCustomer.state,
            pincode: updatedCustomer.pincode,
            gstNumber: updatedCustomer.gstNumber,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Customer updated successfully!')),
            );
            _refreshCustomers();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}')),
            );
          }
        }
      },
    );
  }

  Future<void> _deleteCustomer(CustomerModel customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Are you sure you want to delete "${customer.customerName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _service.deleteCustomer(customer.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Customer deleted!')),
          );
          _refreshCustomers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting customer: $e')),
          );
        }
      }
    }
  }

  Future<void> _showCustomerFormDialog({
    required String title,
    CustomerModel? customer,
    required Future<void> Function(CustomerModel customer) onSave,
  }) async {
    final nameController = TextEditingController(text: customer?.customerName);
    final mobileController = TextEditingController(text: customer?.mobileNumber);
    final addressController = TextEditingController(text: customer?.address);
    final cityController = TextEditingController(text: customer?.city);
    final stateController = TextEditingController(text: customer?.state);
    final pincodeController = TextEditingController(text: customer?.pincode);
    final gstController = TextEditingController(text: customer?.gstNumber);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Customer Name *',
                          border: OutlineInputBorder(),
                        ),
                        autofocus: customer == null,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: mobileController,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: cityController,
                              decoration: const InputDecoration(
                                labelText: 'City',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: stateController,
                              decoration: const InputDecoration(
                                labelText: 'State',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: pincodeController,
                              decoration: const InputDecoration(
                                labelText: 'Pincode',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: gstController,
                              decoration: const InputDecoration(
                                labelText: 'GST Number',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Customer name is required')),
                      );
                      return;
                    }

                    setState(() => isSaving = true);
                    try {
                      final customerData = CustomerModel(
                        id: customer?.id ?? '',
                        customerName: name,
                        mobileNumber: mobileController.text.trim().isNotEmpty ? mobileController.text.trim() : null,
                        address: addressController.text.trim().isNotEmpty ? addressController.text.trim() : null,
                        city: cityController.text.trim().isNotEmpty ? cityController.text.trim() : null,
                        state: stateController.text.trim().isNotEmpty ? stateController.text.trim() : null,
                        pincode: pincodeController.text.trim().isNotEmpty ? pincodeController.text.trim() : null,
                        gstNumber: gstController.text.trim().isNotEmpty ? gstController.text.trim() : null,
                        createdBy: null,
                        createdAt: customer?.createdAt ?? DateTime.now(),
                        updatedAt: DateTime.now(),
                      );
                      await onSave(customerData);
                      Navigator.pop(context);
                    } finally {
                      if (mounted) setState(() => isSaving = false);
                    }
                  },
                  child: isSaving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Management'),
        actions: [
          GlobalCompanySwitcher(onCompanyChanged: _refreshCustomers),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCustomers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or mobile...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _refreshCustomers();
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                if (value.isEmpty) {
                  _refreshCustomers();
                } else {
                  _searchCustomers(value);
                }
              },
            ),
          ),
          // Customer Count
          if (!_isLoading && _errorMessage == null)
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
          if (!_isLoading && _errorMessage == null)
            const SizedBox(height: 8),
          // Customer List
          Expanded(
            child: _isLoading && _customers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null && _customers.isEmpty
                    ? ErrorStateWidget(
                        message: _errorMessage!,
                        onRetry: _refreshCustomers,
                      )
                    : _customers.isEmpty
                        ? const Center(child: Text('No customers found'))
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _customers.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _customers.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }

                          final customer = _customers[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(customer.customerName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (customer.mobileNumber != null)
                                    Text(customer.mobileNumber!),
                                  if (customer.address != null)
                                    Text(
                                      '${customer.address ?? ''}, ${customer.city ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              trailing: PopupMenuButton(
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditCustomerDialog(customer);
                                  } else if (value == 'delete') {
                                    _deleteCustomer(customer);
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      // floatingActionButton: Provider.of<AuthProvider>(context).selectedCompanyId == 'ALL'
      //     ? FloatingActionButton(
      //         onPressed: () {
      //           ScaffoldMessenger.of(context).showSnackBar(
      //             const SnackBar(content: Text('Please select a specific company to add customers')),
      //           );
      //         },
      //         backgroundColor: Colors.grey,
      //         child: const Icon(Icons.add, color: Colors.white),
      //       )
      //     : FloatingActionButton(
      //         onPressed: _showAddCustomerDialog,
      //         backgroundColor: AppTheme.primaryBlue,
      //         child: const Icon(Icons.add, color: Colors.white),
      //       ),
    );
  }
}