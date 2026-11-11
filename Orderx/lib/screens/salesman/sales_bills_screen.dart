import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/invoice_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/salesman/invoice_details_screen.dart';
import 'package:Orderx/services/invoice_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SalesBillsScreen extends StatefulWidget {
  const SalesBillsScreen({super.key});

  @override
  State<SalesBillsScreen> createState() => _SalesBillsScreenState();
}

class _SalesBillsScreenState extends State<SalesBillsScreen> {
  final InvoiceService _invoiceService = InvoiceService();

  List<InvoiceModel> _allInvoices = [];
  List<InvoiceModel> _filteredInvoices = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterInvoices);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInvoices());
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterInvoices);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.currentUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final invoices = await _invoiceService.getTallySyncedInvoicesBySalesman(
        authProvider.currentUser!.id,
        companyId: authProvider.selectedCompanyId,
      );

      if (!mounted) return;
      setState(() {
        _allInvoices = invoices;
        _filteredInvoices = invoices;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading bills: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _filterInvoices() {
    if (!mounted) return;
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() => _filteredInvoices = _allInvoices);
      return;
    }

    setState(() {
      _filteredInvoices = _allInvoices.where((inv) {
        if (inv.invoiceNumber.toLowerCase().contains(query)) return true;
        if (inv.customerName != null &&
            inv.customerName!.toLowerCase().contains(query)) return true;
        if (inv.customerMobile != null && inv.customerMobile!.contains(query))
          return true;
        if (inv.customerGst != null &&
            inv.customerGst!.toLowerCase().contains(query)) return true;
        if (query.length >= 2 && inv.netAmount.toString().contains(query)) {
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
        title: const Text('Sales Bills'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadInvoices,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by Orders #, customer, mobile, GST...',
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
                    color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _filteredInvoices.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadInvoices,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _filteredInvoices.length,
                          itemBuilder: (context, index) =>
                              _SalesBillCard(invoice: _filteredInvoices[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading Tally bills...'),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.receipt_long_outlined,
            size: 80,
            color: AppTheme.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery ? 'No bills match your search' : 'No Tally bills yet',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.grey,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            hasQuery
                ? 'Try different keywords'
                : 'Bills synced from Tally will appear here',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SalesBillCard extends StatelessWidget {
  final InvoiceModel invoice;

  const _SalesBillCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('MMM dd, yyyy - hh:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceDetailsScreen(invoice: invoice),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: invoice number + Tally badge
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
                            const Icon(Icons.calendar_today,
                                size: 13, color: AppTheme.grey),
                            const SizedBox(width: 4),
                            Text(
                              dateFormatter
                                  .format(invoice.invoiceDate.toLocal()),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Tally synced badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.teal.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync, size: 12, color: Colors.teal),
                        const SizedBox(width: 4),
                        const Text(
                          'Tally Synced',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Customer details
              if (invoice.customerName != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
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
                              size: 15, color: AppTheme.primaryBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              invoice.customerName!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      if (invoice.customerMobile != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone,
                                size: 13, color: AppTheme.grey),
                            const SizedBox(width: 8),
                            Text(
                              invoice.customerMobile!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.grey),
                            ),
                          ],
                        ),
                      ],
                      if (invoice.customerGst != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.receipt,
                                size: 13, color: AppTheme.grey),
                            const SizedBox(width: 8),
                            Text(
                              invoice.customerGst!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.grey),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // Tally sync date
              if (invoice.tallySyncDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.update, size: 13, color: AppTheme.grey),
                    const SizedBox(width: 6),
                    Text(
                      'Synced on ${dateFormatter.format(invoice.tallySyncDate!.toLocal())}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.grey),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Amount + arrow
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Net Amount',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.grey),
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
                  const Icon(Icons.arrow_forward_ios,
                      size: 16, color: AppTheme.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
