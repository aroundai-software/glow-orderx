import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/outstanding_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/admin/completed_customer_history_screen.dart';
import 'package:Orderx/services/outstanding_followup_service.dart';
import 'package:Orderx/services/outstanding_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class CompletedCustomersScreen extends StatefulWidget {
  const CompletedCustomersScreen({super.key});

  @override
  State<CompletedCustomersScreen> createState() => _CompletedCustomersScreenState();
}

class _CompletedCustomersScreenState extends State<CompletedCustomersScreen> {
  final OutstandingService _outstandingService = OutstandingService();
  final OutstandingFollowUpService _followUpService = OutstandingFollowUpService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';

  Map<String, OutstandingFollowUpMeta> _followUps = {};
  List<_CompletedCustomerSummary> _customers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      final outstanding = await _outstandingService.getAllOutstanding(
        companyId: companyId,
        limit: 1000000,
      );
      final followUps = await _followUpService.getAll();
      final customers = _buildCompletedCustomers(outstanding, followUps);

      if (!mounted) return;
      setState(() {
        _followUps = followUps;
        _customers = customers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading completed: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  List<_CompletedCustomerSummary> _buildCompletedCustomers(
    List<OutstandingModel> outstanding,
    Map<String, OutstandingFollowUpMeta> followUps,
  ) {
    final Map<String, List<OutstandingModel>> grouped = {};
    for (final item in outstanding) {
      grouped.putIfAbsent(item.customerName, () => []).add(item);
    }

    final List<_CompletedCustomerSummary> result = [];

    for (final entry in grouped.entries) {
      final customerName = entry.key;
      final items = entry.value;

      int pendingInvoices = 0;
      int paidInvoices = 0;
      int totalFollowUps = 0;
      DateTime? lastPaymentAt;
      DateTime? lastFollowedUpAt;

      for (final inv in items) {
        final meta = followUps[inv.id];
        final paid = inv.closingBalance <= 0 || meta?.paymentReceived == true;
        final pending = inv.closingBalance > 0 && meta?.paymentReceived != true;

        if (pending) pendingInvoices++;
        if (paid) paidInvoices++;

        totalFollowUps += meta?.followUpCount ?? 0;

        final paidAt = meta?.paymentReceivedAt;
        if (paidAt != null) {
          if (lastPaymentAt == null || paidAt.isAfter(lastPaymentAt)) {
            lastPaymentAt = paidAt;
          }
        }

        final fAt = meta?.lastFollowedUpAt;
        if (fAt != null) {
          if (lastFollowedUpAt == null || fAt.isAfter(lastFollowedUpAt)) {
            lastFollowedUpAt = fAt;
          }
        }
      }

      if (pendingInvoices == 0) {
        result.add(
          _CompletedCustomerSummary(
            customerName: customerName,
            invoices: items,
            paidInvoices: paidInvoices,
            totalInvoices: items.length,
            totalFollowUps: totalFollowUps,
            lastPaymentAt: lastPaymentAt,
            lastFollowedUpAt: lastFollowedUpAt,
          ),
        );
      }
    }

    result.sort((a, b) {
      final ap = a.lastPaymentAt;
      final bp = b.lastPaymentAt;
      if (ap == null && bp == null) return a.customerName.compareTo(b.customerName);
      if (ap == null) return 1;
      if (bp == null) return -1;
      return bp.compareTo(ap);
    });

    return result;
  }

  List<_CompletedCustomerSummary> get _filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    final q = _searchQuery.toLowerCase();
    return _customers.where((c) => c.customerName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text('Completed (${_customers.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customer...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filteredCustomers.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 180),
                              Center(child: Text('No completed customers found')),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _filteredCustomers.length,
                            itemBuilder: (context, index) {
                              final customer = _filteredCustomers[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: ListTile(
                                  title: Text(
                                    customer.customerName,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text('Invoices: ${customer.totalInvoices}  |  Follow-ups: ${customer.totalFollowUps}'),
                                      if (customer.lastPaymentAt != null)
                                        Text('Last paid: ${dateTimeFormat.format(customer.lastPaymentAt!.toLocal())}'),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CompletedCustomerHistoryScreen(
                                          customerName: customer.customerName,
                                          invoices: customer.invoices,
                                          followUps: _followUps,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CompletedCustomerSummary {
  final String customerName;
  final List<OutstandingModel> invoices;
  final int totalInvoices;
  final int paidInvoices;
  final int totalFollowUps;
  final DateTime? lastPaymentAt;
  final DateTime? lastFollowedUpAt;

  const _CompletedCustomerSummary({
    required this.customerName,
    required this.invoices,
    required this.totalInvoices,
    required this.paidInvoices,
    required this.totalFollowUps,
    required this.lastPaymentAt,
    required this.lastFollowedUpAt,
  });
}
