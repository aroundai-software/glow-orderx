// lib/screens/admin/admin_dashboard.dart
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/admin/pending_approvals_screen.dart';
import 'package:Orderx/services/admin_stats_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
 // 👈 IMPORT STATS SERVICE

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // Stats variables
  int _totalOrders = 0;
  int _pendingCount = 0;
  int _syncedOrders = 0;
  int _salesmenCount = 0;

  // Service instance
  late final AdminStatsService _statsService;

  @override
  void initState() {
    super.initState();
    _statsService = AdminStatsService(); // Initialize service
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      // Show loading indicator (optional)
      if (mounted) {
        setState(() {
          _totalOrders = -1; // Special value to show loading
        });
      }

      final total = await _statsService.getTotalOrdersCount();
      final pending = await _statsService.getPendingApprovalsCount();
      final synced = await _statsService.getSyncedOrdersCount();
      final salesmen = await _statsService.getSalesmenCount();

      if (mounted) {
        setState(() {
          _totalOrders = total;
          _pendingCount = pending;
          _syncedOrders = synced;
          _salesmenCount = salesmen;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load stats: $e')),
        );
        // Reset to 0 on error
        setState(() {
          _totalOrders = 0;
          _pendingCount = 0;
          _syncedOrders = 0;
          _salesmenCount = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              _showLogoutDialog(context);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats, // Pull-to-refresh
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
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
                        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

              // Quick Stats
              Text(
                'Overview',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.5,
                children: [
                  _buildStatCard(
                    context,
                    icon: Icons.shopping_cart,
                    title: 'Total Orders',
                    value: _totalOrders == -1 ? '...' : _totalOrders.toString(),
                    color: AppTheme.primaryBlue,
                  ),
                  _buildStatCard(
                    context,
                    icon: Icons.pending_actions,
                    title: 'Pending',
                    value: _pendingCount == -1 ? '...' : _pendingCount.toString(),
                    color: AppTheme.warning,
                  ),
                  _buildStatCard(
                    context,
                    icon: Icons.sync,
                    title: 'Synced',
                    value: _syncedOrders == -1 ? '...' : _syncedOrders.toString(),
                    color: AppTheme.success,
                  ),
                  _buildStatCard(
                    context,
                    icon: Icons.people,
                    title: 'Salesmen',
                    value: _salesmenCount == -1 ? '...' : _salesmenCount.toString(),
                    color: AppTheme.accentBlue,
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Main Features
              Text(
                'Management',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                icon: Icons.receipt_long,
                title: 'Pending Approvals',
                subtitle: 'Review and approve order edits',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PendingApprovalsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                context,
                icon: Icons.people_outline,
                title: 'Manage Salesmen',
                subtitle: 'Add, edit, or remove sales team members',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Manage Salesmen - Coming Soon')),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                context,
                icon: Icons.inventory_2_outlined,
                title: 'Products',
                subtitle: 'Manage product catalog',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Products - Coming Soon')),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                context,
                icon: Icons.group_outlined,
                title: 'Customers',
                subtitle: 'Manage customer database',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Customers - Coming Soon')),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                context,
                icon: Icons.sync_alt,
                title: 'Tally Integration',
                subtitle: 'Configure and sync with Tally',
                color: AppTheme.success,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tally Integration - Coming Soon')),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                context,
                icon: Icons.settings,
                title: 'Settings',
                subtitle: 'App and account settings',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settings - Coming Soon')),
                  );
                },
              ),
            ],
          ),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.grey,
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
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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