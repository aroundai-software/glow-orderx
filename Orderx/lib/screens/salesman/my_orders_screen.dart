import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/invoice_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/salesman/invoice_details_screen.dart';
import 'package:Orderx/services/invoice_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/error_state_widget.dart';
import 'package:intl/intl.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final InvoiceService _invoiceService = InvoiceService();
  List<InvoiceModel> _allInvoices = [];
  List<InvoiceModel> _filteredInvoices = [];
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authProvider = context.read<AuthProvider>();
      _authProvider?.addListener(_onAuthProviderChanged);
      _loadInvoices();
    });
    _searchController.addListener(_filterInvoices);
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthProviderChanged);
    _searchController.removeListener(_filterInvoices);
    _searchController.dispose();
    super.dispose();
  }

  void _onAuthProviderChanged() {
    if (!mounted) return;
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.currentUser != null) {
        final invoices = await _invoiceService.getInvoicesBySalesman(
          authProvider.currentUser!.id,
          companyId: authProvider.selectedCompanyId,
        );

        if (mounted) {
          setState(() {
            _allInvoices = invoices;
            _filteredInvoices = invoices;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading invoices: $e');
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

  void _filterInvoices() {
    if (!mounted) return;

    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _filteredInvoices = _allInvoices;
      });
      return;
    }

    setState(() {
      _filteredInvoices = _allInvoices.where((invoice) {
        // Search by invoice number
        if (invoice.invoiceNumber.toLowerCase().contains(query)) {
          return true;
        }

        // Search by customer name
        if (invoice.customerName != null &&
            invoice.customerName!.toLowerCase().contains(query)) {
          return true;
        }

        // Search by customer mobile
        if (invoice.customerMobile != null &&
            invoice.customerMobile!.contains(query)) {
          return true;
        }

        // Search by customer GST
        if (invoice.customerGst != null &&
            invoice.customerGst!.toLowerCase().contains(query)) {
          return true;
        }

        // Search by status
        if (invoice.status.toLowerCase().contains(query)) {
          return true;
        }

        // Search by amount (numeric)
        if (query.length >= 2 && invoice.netAmount.toString().contains(query)) {
          return true;
        }

        return false;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Invoices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh invoices',
            onPressed: _loadInvoices,
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
                hintText: 'Search by invoice #, name, mobile, GST, status...',
                hintStyle: const TextStyle(color: AppTheme.grey, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.primaryBlue),
                suffixIcon: _searchController.text.trim().isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterInvoices();
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
          // Invoices List
          Expanded(
            child: _isLoading
                ? _buildLoadingIndicator()
                : _errorMessage != null
                    ? ErrorStateWidget(
                        message: _errorMessage!,
                        onRetry: _loadInvoices,
                      )
                    : _filteredInvoices.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                        onRefresh: _loadInvoices,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredInvoices.length,
                          itemBuilder: (context, index) {
                            final invoice = _filteredInvoices[index];
                            return _InvoiceCard(invoice: invoice);
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
                'Loading your invoices$dots',
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
            hasSearchQuery ? 'No invoices found' : 'No invoices yet',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.grey,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearchQuery
                ? 'Try searching with different keywords'
                : 'Start creating invoices to see them here',
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

class _InvoiceCard extends StatelessWidget {
  final InvoiceModel invoice;

  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InvoiceDetailsScreen(invoice: invoice),
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
                          invoice.invoiceNumber,
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
                            Text(
                              DateFormat('MMM dd, yyyy - hh:mm a')
                                  .format(invoice.invoiceDate.toLocal()),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.grey,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (invoice.isEdited)
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
              if (invoice.customerName != null) ...[
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
                              invoice.customerName!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (invoice.customerMobile != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone,
                                size: 14, color: AppTheme.grey),
                            const SizedBox(width: 8),
                            Text(
                              invoice.customerMobile!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (invoice.customerGst != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.receipt,
                                size: 14, color: AppTheme.grey),
                            const SizedBox(width: 8),
                            Text(
                              invoice.customerGst!,
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
                        '₹${invoice.netAmount.toStringAsFixed(2)}',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ],
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppTheme.grey,
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
