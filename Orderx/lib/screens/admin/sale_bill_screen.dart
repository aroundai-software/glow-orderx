import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/sale_bill_model.dart';
import 'package:Orderx/services/sale_bill_service.dart';

import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class SaleBillScreen extends StatefulWidget {
  const SaleBillScreen({super.key});

  @override
  State<SaleBillScreen> createState() => _SaleBillScreenState();
}

class _SaleBillScreenState extends State<SaleBillScreen>
    with SingleTickerProviderStateMixin {
  final SaleBillService _saleBillService = SaleBillService();
  final TextEditingController _searchController = TextEditingController();

  List<SaleBillModel> _allBills = [];
  List<SaleBillModel> _filteredBills = [];
  bool _isLoading = true;
  String _searchQuery = '';
  late TabController _tabController;
  Map<String, int> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadSaleBills();
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
      _filterBills();
    }
  }

  Future<void> _loadSaleBills() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;

      final bills = await _saleBillService.getAllSaleBills(companyId: effectiveCompanyId);
      final stats = await _saleBillService.getSaleBillStats(companyId: effectiveCompanyId);

      if (mounted) {
        setState(() {
          _allBills = bills;
          _stats = stats;
          _filterBills();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading sale bills: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _filterBills() {
    List<SaleBillModel> filtered = _allBills;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((bill) =>
              bill.orderNumber
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              (bill.invoiceNumber
                      ?.toLowerCase()
                      .contains(_searchQuery.toLowerCase()) ??
                  false))
          .toList();
    }

    // Filter by tab selection
    switch (_tabController.index) {
      case 0: // All
        break;
      case 1: // Pending
        filtered = filtered.where((bill) => bill.status == 'Pending').toList();
        break;
      case 2: // Completed
        filtered =
            filtered.where((bill) => bill.status == 'Completed').toList();
        break;
      case 3: // Cancelled
        filtered =
            filtered.where((bill) => bill.status == 'Cancelled').toList();
        break;
    }

    setState(() {
      _filteredBills = filtered;
    });
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppTheme.success;
      case 'pending':
        return AppTheme.warning;
      case 'cancelled':
        return AppTheme.error;
      default:
        return AppTheme.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.receipt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale Bills'),
        actions: [
          GlobalCompanySwitcher(onCompanyChanged: _loadSaleBills),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSaleBills,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'All (${_stats['total'] ?? 0})'),
            Tab(text: 'Pending (${_stats['pending'] ?? 0})'),
            Tab(text: 'Completed (${_stats['completed'] ?? 0})'),
            Tab(text: 'Cancelled (${_stats['cancelled'] ?? 0})'),
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
                hintText: 'Search by order or invoice number...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _filterBills();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _filterBills();
              },
            ),
          ),

          // Bills List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadSaleBills,
                    child: _filteredBills.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.4,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.receipt_long_outlined,
                                        size: 64,
                                        color: AppTheme.grey
                                            .withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _searchQuery.isNotEmpty
                                            ? 'No bills found matching "$_searchQuery"'
                                            : 'No sale bills found',
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
                            itemCount: _filteredBills.length,
                            itemBuilder: (context, index) {
                              final bill = _filteredBills[index];
                              return _buildBillCard(bill, dateFormat);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillCard(SaleBillModel bill, DateFormat dateFormat) {
    final statusColor = _getStatusColor(bill.status);
    final statusIcon = _getStatusIcon(bill.status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Icon(
            statusIcon,
            color: statusColor,
          ),
        ),
        title: Text(
          'Order: ${bill.orderNumber}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bill.invoiceNumber != null)
              Text('Invoice: ${bill.invoiceNumber}'),
            Text('Date: ${dateFormat.format(bill.date)}'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                bill.status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          _showBillDetails(bill);
        },
      ),
    );
  }

  void _showBillDetails(SaleBillModel bill) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final statusColor = _getStatusColor(bill.status);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Order: ${bill.orderNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Order Number', bill.orderNumber),
            if (bill.invoiceNumber != null)
              _buildDetailRow('Invoice Number', bill.invoiceNumber!),
            _buildDetailRow('Date', dateFormat.format(bill.date)),
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
                    bill.status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (bill.createdAt != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow(
                'Created At',
                DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt!),
              ),
            ],
          ],
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
