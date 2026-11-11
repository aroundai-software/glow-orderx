// lib/screens/admin/admin_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/admin/pending_approvals_screen.dart';
import 'package:Orderx/screens/admin/sales_reports_screen.dart';
import 'package:Orderx/screens/admin/customer_management_screen.dart';
import 'package:Orderx/screens/admin/product_management_screen.dart';
import 'package:Orderx/screens/admin/admin_settings_screen.dart';
import 'package:Orderx/screens/admin/account_management_screen.dart';
import 'package:Orderx/screens/admin/outstanding_screen.dart';
import 'package:Orderx/screens/admin/item_closing_balance_screen.dart';
import 'package:Orderx/screens/admin/stock_notifications_screen.dart';
// sales_invoices_screen removed - using AllOrdersScreen for sales orders
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/stock_notification_service.dart';
import 'package:Orderx/services/company_selection_service.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Orderx/screens/admin/all_orders_screen.dart';
import 'package:Orderx/screens/admin/activity_logs_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _approvalRequestCount = 0;
  int _totalOrders = 0;
  int _todayOrdersCount = 0;
  double _todayTotalAmount = 0.0;
  int _unreadNotifications = 0;
  String _totalOrdersFilter = 'All-time';
  String? _selectedCompanyName;
  final OrderService _orderService = OrderService();
  final StockNotificationService _notificationService =
      StockNotificationService();
  final CompanySelectionService _companyService = CompanySelectionService();

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadSelectedCompanyName();
  }

  Future<void> _loadSelectedCompanyName() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      if (companyId == 'ALL') {
        setState(() {
          _selectedCompanyName = 'All Companies';
        });
      } else if (companyId != null) {
        final company = await _companyService.getCompanyById(companyId);
        if (mounted && company != null) {
          setState(() {
            _selectedCompanyName = company['company_name'] as String?;
          });
        }
      }
    } catch (e) {
      print('Error loading company name: $e');
    }
  }

  Future<void> _loadStats() async {
    try {
      print('=== LOADING ADMIN STATS ===');

      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      print('📊 Admin Dashboard - Loading stats for company: $companyId');

      // 1. Total Orders Count
      dynamic totalQuery = Supabase.instance.client.from('sales_orders').select();
      if (companyId != null && companyId != 'ALL') {
        totalQuery = totalQuery.eq('company_id', companyId);
      }
      
      final nowTime = DateTime.now();
      if (_totalOrdersFilter == 'This Week') {
        final startOfWeek = DateTime(nowTime.year, nowTime.month, nowTime.day - nowTime.weekday + 1).toIso8601String();
        totalQuery = totalQuery.gte('order_date', startOfWeek);
      } else if (_totalOrdersFilter == 'This Month') {
        final startOfMonth = DateTime(nowTime.year, nowTime.month, 1).toIso8601String();
        totalQuery = totalQuery.gte('order_date', startOfMonth);
      }
      
      final totalCountResponse = await totalQuery.count(CountOption.exact);
      final totalOrders = totalCountResponse.count;
      print('✓ Total orders ($_totalOrdersFilter): $totalOrders');

      // 2. Pending Approvals Count
      dynamic editQuery = Supabase.instance.client
          .from('sales_orders')
          .select()
          .eq('edit_request_status', 'pending');
      
      if (companyId != null && companyId != 'ALL') {
        editQuery = editQuery.eq('company_id', companyId);
      }
      final editCountResponse = await editQuery.count(CountOption.exact);
      final approvalCount = editCountResponse.count;
      print('✓ Pending approval requests: $approvalCount');

      // 3. Today's Orders and Amount
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
      
      dynamic todayQuery = Supabase.instance.client
          .from('sales_orders')
          .select('net_amount')
          .gte('order_date', startOfDay);
      
      if (companyId != null && companyId != 'ALL') {
        todayQuery = todayQuery.eq('company_id', companyId);
      }
      
      final todayOrdersData = await todayQuery as List<dynamic>;
      final todayCount = todayOrdersData.length;
      
      double todayAmount = 0.0;
      for (var row in todayOrdersData) {
        if (row['net_amount'] != null) {
          todayAmount += (row['net_amount'] as num).toDouble();
        }
      }
      print('✓ Today orders: $todayCount, amount: $todayAmount');

      // Get unread stock notifications count
      final unreadCount = await _notificationService.getUnreadCount(
        companyId: (companyId == 'ALL') ? null : companyId,
      );
      print('✓ Unread stock notifications: $unreadCount');

      if (mounted) {
        setState(() {
          _totalOrders = totalOrders;
          _todayOrdersCount = todayCount;
          _todayTotalAmount = todayAmount;
          _approvalRequestCount = approvalCount;
          _unreadNotifications = unreadCount;
        });
      }

      print('=== STATS LOADED ===\n');
    } catch (e) {
      print('❌ Error loading stats: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load stats: $e')),
        );
      }
    }
  }

  Future<void> _viewAllOrders() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AllOrdersScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          // Global Company Switcher
          GlobalCompanySwitcher(onCompanyChanged: _loadStats),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => authProvider.logout(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor:
                          AppTheme.primaryBlue.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.admin_panel_settings,
                        size: 35,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome Back!',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppTheme.grey,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.name ?? 'Admin',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.mobileNumber ?? '',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.grey,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Overview Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overview',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.grey.withOpacity(0.3)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _totalOrdersFilter,
                      icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryBlue),
                      style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13),
                      items: <String>['All-time', 'This Week', 'This Month'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null && newValue != _totalOrdersFilter) {
                          setState(() {
                            _totalOrdersFilter = newValue;
                          });
                          _loadStats();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                // Total Orders Card - CLICKABLE
                Expanded(
                  child: GestureDetector(
                    onTap: _viewAllOrders,
                    child: _buildStatCard(
                      context,
                      icon: Icons.shopping_cart,
                      title: 'Total Orders',
                      value: '$_totalOrders',
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Today's Orders
                Expanded(
                  child: GestureDetector(
                    onTap: _viewAllOrders,
                    child: _buildStatCard(
                      context,
                      icon: Icons.today,
                      title: 'Today\'s Orders',
                      value: '$_todayOrdersCount',
                      color: AppTheme.success,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Today's Amount
                Expanded(
                  child: _buildStatCard(
                    context,
                    icon: Icons.currency_rupee,
                    title: 'Today\'s Amount',
                    value: '₹${_todayTotalAmount.toStringAsFixed(2)}',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Management Section
            Text(
              'Management',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),

            // Pending Approvals Card (HIDDEN)
            // _buildMenuCard(
            //   context,
            //   icon: Icons.receipt_long,
            //   title: 'Pending Approvals',
            //   subtitle: 'Review order & edit approvals',
            //   badgeCount: _approvalRequestCount,
            //   onTap: () {
            //     Navigator.push(
            //       context,
            //       MaterialPageRoute(
            //         builder: (context) => const PendingApprovalsScreen(),
            //       ),
            //     );
            //   },
            // ),
            // const SizedBox(height: 12),

            // Account Management Card
            _buildMenuCard(
              context,
              icon: Icons.manage_accounts,
              title: 'Account Management',
              subtitle: 'Manage Salesman and Admin accounts',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AccountManagementScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),



            // Products Card
            _buildMenuCard(
              context,
              icon: Icons.inventory_2_outlined,
              title: 'Products',
              subtitle: 'Manage product catalog',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProductManagementScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Stock Notifications Card
            _buildMenuCard(
              context,
              icon: Icons.notifications_active,
              title: 'Stock Notifications',
              subtitle: 'View stock alerts from salesmen',
              badgeCount: _unreadNotifications,
              color: Colors.orange,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StockNotificationsScreen(),
                  ),
                );
                // Reload stats when returning from notifications screen
                _loadStats();
              },
            ),
            const SizedBox(height: 12),

            // Customers Card
            _buildMenuCard(
              context,
              icon: Icons.group_outlined,
              title: 'Customers',
              subtitle: 'Manage customer database',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CustomerManagementScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Sales Reports Card
            _buildMenuCard(
              context,
              icon: Icons.bar_chart,
              title: 'Sales Reports',
              subtitle: 'View sales analytics and trends',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SalesAnalysisScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Sales Orders Card
            _buildMenuCard(
              context,
              icon: Icons.shopping_bag_outlined,
              title: 'Sales Orders',
              subtitle: 'View and manage all sales orders',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AllOrdersScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Activity Logs Card
            _buildMenuCard(
              context,
              icon: Icons.history,
              title: 'Activity Logs',
              subtitle: 'Login, logout and order creation times',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ActivityLogsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Item Closing Balance Card
            _buildMenuCard(
              context,
              icon: Icons.inventory,
              title: 'Item Closing Balance',
              subtitle: 'View closing stock by item',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ItemClosingBalanceScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Outstanding Card
            _buildMenuCard(
              context,
              icon: Icons.account_balance_wallet_outlined,
              title: 'Outstanding',
              subtitle: 'View customer outstanding balances',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OutstandingScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Settings Card
            _buildMenuCard(
              context,
              icon: Icons.settings,
              title: 'Settings',
              subtitle: 'App and account settings',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminSettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.grey,
                      fontSize: 11,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    int badgeCount = 0,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (color ?? AppTheme.primaryBlue).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: color ?? AppTheme.primaryBlue,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(subtitle),
        trailing: badgeCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.warning,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              )
            : const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

