import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/outstanding_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/admin/completed_customers_screen.dart';
import 'package:Orderx/screens/admin/outstanding_details_screen.dart';
import 'package:Orderx/services/outstanding_followup_service.dart';
import 'package:Orderx/services/outstanding_service.dart';
import 'package:provider/provider.dart';

import 'package:Orderx/widgets/app_bar_actions.dart';

class OutstandingScreen extends StatefulWidget {
  const OutstandingScreen({super.key});

  @override
  State<OutstandingScreen> createState() => _OutstandingScreenState();
}

class _OutstandingScreenState extends State<OutstandingScreen>
    with SingleTickerProviderStateMixin {
  final OutstandingService _outstandingService = OutstandingService();
  final OutstandingFollowUpService _followUpService = OutstandingFollowUpService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  List<OutstandingModel> _filteredOutstanding = [];
  bool _isLoading = true;
  String _searchQuery = '';
  late TabController _tabController;
  Map<String, dynamic> _stats = {};
  Map<String, OutstandingFollowUpMeta> _followUps = {};
  Map<String, int> _tabCounts = {'all': 0, 'today': 0, 'overdue': 0};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _loadOutstanding();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _loadOutstanding();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadOutstanding() async {
    setState(() {
      _isLoading = true;
      _currentPage = 0;
      _hasMore = true;
      _filteredOutstanding = [];
    });
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;
      
      final filterMode = _tabController.index;
      
      List<OutstandingModel> outstanding;
      if (_searchQuery.isNotEmpty) {
        outstanding = await _outstandingService.searchOutstanding(
          _searchQuery,
          companyId: effectiveCompanyId,
          filterMode: filterMode,
          offset: 0,
          limit: _pageSize,
        );
      } else {
        outstanding = await _outstandingService.getAllOutstanding(
          companyId: effectiveCompanyId,
          filterMode: filterMode,
          offset: 0,
          limit: _pageSize,
        );
      }
      
      final stats = await _outstandingService.getOutstandingStats(companyId: effectiveCompanyId);
      final counts = await _outstandingService.getOutstandingCounts(companyId: effectiveCompanyId);
      final followUps = await _followUpService.getAll();

      if (mounted) {
        setState(() {
          _filteredOutstanding = outstanding;
          _stats = stats;
          _tabCounts = counts;
          _followUps = followUps;
          _hasMore = outstanding.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading outstanding: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;
      
      final filterMode = _tabController.index;
      _currentPage++;
      final offset = _currentPage * _pageSize;
      
      List<OutstandingModel> moreOutstanding;
      if (_searchQuery.isNotEmpty) {
        moreOutstanding = await _outstandingService.searchOutstanding(
          _searchQuery,
          companyId: effectiveCompanyId,
          filterMode: filterMode,
          offset: offset,
          limit: _pageSize,
        );
      } else {
        moreOutstanding = await _outstandingService.getAllOutstanding(
          companyId: effectiveCompanyId,
          filterMode: filterMode,
          offset: offset,
          limit: _pageSize,
        );
      }
      
      if (mounted) {
        setState(() {
          _filteredOutstanding.addAll(moreOutstanding);
          _hasMore = moreOutstanding.length == _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _currentPage--; // revert page increment on error
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading more outstanding: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yyyy');

    final userType = context.watch<AuthProvider>().currentUser?.userType;
    final isAdminUser = userType == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outstanding'),
        actions: [
          GlobalCompanySwitcher(onCompanyChanged: _loadOutstanding),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOutstanding,
          ),
          if (isAdminUser)
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CompletedCustomersScreen(),
                  ),
                );
              },
              child: const Text(
                'Completed',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'All (${_tabCounts["all"]})'),
            Tab(text: 'Today (${_tabCounts["today"]})'),
            Tab(text: 'Overdue (${_tabCounts["overdue"]})'),
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
                hintText: 'Search by customer name or invoice...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                          _loadOutstanding();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _loadOutstanding();
              },
            ),
          ),

          // Summary Card
          if (!_isLoading && _stats.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem(
                    'Total Closing',
                    currencyFormat.format(_stats['total_closing_balance'] ?? 0),
                    AppTheme.primaryBlue,
                  ),
                  _buildSummaryItem(
                    'Overdue',
                    '${_stats['overdue_count'] ?? 0}',
                    AppTheme.error,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Outstanding List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadOutstanding,
                    child: _filteredOutstanding.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.3,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_outlined,
                                        size: 64,
                                        color: AppTheme.grey
                                            .withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _searchQuery.isNotEmpty
                                            ? 'No records found matching "$_searchQuery"'
                                            : 'No outstanding records found',
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
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _filteredOutstanding.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filteredOutstanding.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final item = _filteredOutstanding[index];
                              return _buildOutstandingCard(
                                  item, currencyFormat, dateFormat,
                                  isAdminUser: isAdminUser);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildOutstandingCard(OutstandingModel item,
      NumberFormat currencyFormat, DateFormat dateFormat,
      {required bool isAdminUser}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final meta = _followUps[item.id];
    final effectiveDate = meta?.followUpDate ?? item.dueDate;
    final effectiveDateOnly = effectiveDate != null
        ? DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day)
        : null;

    final hasBalance = item.closingBalance > 0;
    final paymentReceived = meta?.paymentReceived == true;

    final isToday =
        hasBalance && !paymentReceived && effectiveDateOnly != null && effectiveDateOnly == today;
    final isOverdue = hasBalance && !paymentReceived &&
        ((effectiveDateOnly != null && effectiveDateOnly.isBefore(today)) ||
            (effectiveDateOnly == null && item.isOverdue));

    final statusColor = !hasBalance
        ? AppTheme.success
        : (paymentReceived
            ? AppTheme.success
            : (isOverdue
                ? AppTheme.error
                : (isToday ? AppTheme.warning : AppTheme.primaryBlue)));

    final showComplete =
        (isToday || isOverdue) && hasBalance && !paymentReceived && !isAdminUser;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _openOutstandingDetails(item);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.1),
                child: Icon(
                  isOverdue
                      ? Icons.warning
                      : (isToday ? Icons.today : Icons.account_balance_wallet),
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text('Invoice: ${item.invoiceNumber}'),
                    Text('Date: ${dateFormat.format(item.date)}'),
                    if (effectiveDate != null)
                      Text(
                        'Due: ${dateFormat.format(effectiveDate)}',
                        style: TextStyle(
                          color: isOverdue ? AppTheme.error : null,
                          fontWeight: isOverdue ? FontWeight.w500 : null,
                        ),
                      ),
                    if ((meta?.createdByName ?? '').trim().isNotEmpty)
                      Text(
                        'Created by: ${meta!.createdByName}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.grey,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            !hasBalance
                                ? 'Cleared'
                                : (paymentReceived
                                    ? 'Paid'
                                    : (isOverdue
                                        ? 'Overdue'
                                        : (isToday ? 'Today' : 'Upcoming'))),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isOverdue && effectiveDateOnly != null)
                          Text(
                            '${today.difference(effectiveDateOnly).inDays} days overdue',
                            style: const TextStyle(
                              color: AppTheme.error,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currencyFormat.format(item.closingBalance),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Balance',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.grey,
                    ),
                  ),
                  if (showComplete)
                    SizedBox(
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        iconSize: 22,
                        onPressed: () async {
                          await _followUpService.markFollowedUp(item.id);
                          if (!mounted) return;
                          final followUps = await _followUpService.getAll();
                          if (!mounted) return;
                          setState(() {
                            _followUps = followUps;
                          });
                          _loadOutstanding();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Marked as complete for today'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_circle,
                            color: AppTheme.success),
                        tooltip: 'Mark complete',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOutstandingDetails(OutstandingModel item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OutstandingDetailsScreen(outstanding: item),
      ),
    );

    final followUps = await _followUpService.getAll();
    if (!mounted) return;
    setState(() {
      _followUps = followUps;
    });
    _loadOutstanding();
  }
}
