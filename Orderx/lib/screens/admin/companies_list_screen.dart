import 'package:flutter/material.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class CompaniesListScreen extends StatefulWidget {
  const CompaniesListScreen({super.key});

  @override
  State<CompaniesListScreen> createState() => _CompaniesListScreenState();
}

class _CompaniesListScreenState extends State<CompaniesListScreen>
    with SingleTickerProviderStateMixin {
  final TallyCompanyService _companyService = TallyCompanyService();
  List<TallyCompanyModel> _allCompanies = [];
  List<TallyCompanyModel> _filteredCompanies = [];
  bool _isLoading = true;
  String _searchQuery = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCompanies();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthProvider>();
      final company = await _companyService.resolveCompany(
        auth.currentUser?.companyId ?? auth.selectedCompanyId,
      );
      final companies = company != null ? [company] : <TallyCompanyModel>[];
      if (mounted) {
        setState(() {
          _allCompanies = companies;
          _filterCompanies();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading companies: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _filterCompanies() {
    List<TallyCompanyModel> filtered = _allCompanies;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((company) =>
              company.companyName
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              company.companyNumber
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              (company.city
                      ?.toLowerCase()
                      .contains(_searchQuery.toLowerCase()) ??
                  false))
          .toList();
    }

    // Filter by tab selection
    switch (_tabController.index) {
      case 0: // All
        break;
      case 1: // Active
        filtered = filtered.where((company) => company.isActive).toList();
        break;
      case 2: // Inactive
        filtered = filtered.where((company) => !company.isActive).toList();
        break;
    }

    setState(() {
      _filteredCompanies = filtered;
    });
  }

  Future<void> _toggleCompanyStatus(TallyCompanyModel company) async {
    try {
      await _companyService.updateCompany(
        id: company.id,
        isActive: !company.isActive,
      );

      // Reload companies to reflect changes
      await _loadCompanies();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(company.isActive
                ? 'Company deactivated successfully'
                : 'Company activated successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating company: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showCompanyDetails(TallyCompanyModel company) {
    showDialog(
      context: context,
      builder: (context) => CompanyDetailsDialog(company: company),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _allCompanies.where((c) => c.isActive).length;
    final inactiveCount = _allCompanies.where((c) => !c.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Companies'),
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) => _filterCompanies(),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'All (${_allCompanies.length})'),
            Tab(text: 'Active ($activeCount)'),
            Tab(text: 'Inactive ($inactiveCount)'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search companies...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _filterCompanies();
              },
            ),
          ),

          // Companies List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadCompanies,
                    child: _filteredCompanies.isEmpty
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
                                        Icons.business_outlined,
                                        size: 64,
                                        color: AppTheme.grey
                                            .withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _searchQuery.isNotEmpty
                                            ? 'No companies found matching "$_searchQuery"'
                                            : 'No companies found',
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
                            itemCount: _filteredCompanies.length,
                            itemBuilder: (context, index) {
                              final company = _filteredCompanies[index];
                              return _buildCompanyCard(company);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyCard(TallyCompanyModel company) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: company.isActive
              ? AppTheme.success.withValues(alpha: 0.1)
              : AppTheme.error.withValues(alpha: 0.1),
          child: Icon(
            company.isActive ? Icons.business : Icons.business_outlined,
            color: company.isActive ? AppTheme.success : AppTheme.error,
          ),
        ),
        title: Text(
          company.companyName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Company No: ${company.companyNumber}'),
            if (company.city != null) Text('City: ${company.city}'),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: company.isActive
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    company.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color:
                          company.isActive ? AppTheme.success : AppTheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getSyncStatusColor(company.syncStatus)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    company.syncStatus.toUpperCase(),
                    style: TextStyle(
                      color: _getSyncStatusColor(company.syncStatus),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'details':
                _showCompanyDetails(company);
                break;
              case 'toggle_status':
                _showToggleStatusDialog(company);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 8),
                  Text('View Details'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'toggle_status',
              child: Row(
                children: [
                  Icon(company.isActive
                      ? Icons.block
                      : Icons.check_circle_outline),
                  const SizedBox(width: 8),
                  Text(company.isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _showCompanyDetails(company),
      ),
    );
  }

  Color _getSyncStatusColor(String syncStatus) {
    switch (syncStatus.toLowerCase()) {
      case 'completed':
        return AppTheme.success;
      case 'pending':
        return AppTheme.warning;
      case 'failed':
        return AppTheme.error;
      case 'syncing':
        return AppTheme.primaryBlue;
      default:
        return AppTheme.grey;
    }
  }

  void _showToggleStatusDialog(TallyCompanyModel company) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${company.isActive ? 'Deactivate' : 'Activate'} Company'),
        content: Text(
            'Are you sure you want to ${company.isActive ? 'deactivate' : 'activate'} "${company.companyName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _toggleCompanyStatus(company);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  company.isActive ? AppTheme.error : AppTheme.success,
            ),
            child: Text(company.isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
  }
}

class CompanyDetailsDialog extends StatelessWidget {
  final TallyCompanyModel company;

  const CompanyDetailsDialog({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(company.companyName),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailRow('Company Number', company.companyNumber),
            _buildDetailRow('Company GUID', company.Guid),
            if (company.companyAlias != null)
              _buildDetailRow('Alias', company.companyAlias!),
            if (company.companyDescription != null)
              _buildDetailRow('Description', company.companyDescription!),
            const SizedBox(height: 16),
            const Text('Address',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (company.addressLine1 != null)
              _buildDetailRow('Address Line 1', company.addressLine1!),
            if (company.addressLine2 != null)
              _buildDetailRow('Address Line 2', company.addressLine2!),
            if (company.city != null) _buildDetailRow('City', company.city!),
            if (company.state != null) _buildDetailRow('State', company.state!),
            if (company.pinCode != null)
              _buildDetailRow('PIN Code', company.pinCode!),
            if (company.country != null)
              _buildDetailRow('Country', company.country!),
            const SizedBox(height: 16),
            const Text('Contact Information',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (company.phoneNumber != null)
              _buildDetailRow('Phone', company.phoneNumber!),
            if (company.email != null) _buildDetailRow('Email', company.email!),
            if (company.website != null)
              _buildDetailRow('Website', company.website!),
            const SizedBox(height: 16),
            const Text('Tax Information',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (company.gstNumber != null)
              _buildDetailRow('GST Number', company.gstNumber!),
            if (company.panNumber != null)
              _buildDetailRow('PAN Number', company.panNumber!),
            if (company.tanNumber != null)
              _buildDetailRow('TAN Number', company.tanNumber!),
            const SizedBox(height: 16),
            const Text('System Information',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildDetailRow('Status', company.isActive ? 'Active' : 'Inactive'),
            _buildDetailRow('Sync Status', company.syncStatus.toUpperCase()),
            if (company.lastSyncedAt != null)
              _buildDetailRow(
                  'Last Synced',
                  DateFormat('dd/MM/yyyy hh:mm a')
                      .format(company.lastSyncedAt!)),
            _buildDetailRow('Created',
                DateFormat('dd/MM/yyyy hh:mm a').format(company.createdAt)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
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
