import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/cart_provider.dart';
import 'package:Orderx/screens/salesman/cart_screen.dart';
import 'package:Orderx/screens/salesman/customer_selection_screen.dart';
import 'package:Orderx/screens/salesman/customers_screen.dart';
import 'package:Orderx/screens/salesman/product_selection_screen.dart';
import 'package:Orderx/screens/salesman/sales_orders_screen.dart';
import 'package:Orderx/screens/salesman/sales_bills_screen.dart';
import 'package:Orderx/screens/admin/outstanding_screen.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/services/invoice_service.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/outstanding_service.dart';
import 'package:Orderx/widgets/company_header_widget.dart';

import 'package:Orderx/providers/connectivity_provider.dart';
import 'package:Orderx/providers/offline_data_provider.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalesmanDashboard extends StatefulWidget {
  const SalesmanDashboard({super.key});

  @override
  State<SalesmanDashboard> createState() => _SalesmanDashboardState();
}

class _SalesmanDashboardState extends State<SalesmanDashboard> {
  // Services
  final OrderService _orderService = OrderService();
  final InvoiceService _invoiceService = InvoiceService();
  final CustomerService _customerService = CustomerService();
  final AdminSettingsService _settingsService = AdminSettingsService();
  final OutstandingService _outstandingService = OutstandingService();

  // Stats & Loading
  int _todayOrders = 0;
  double _todayAmount = 0.0;
  bool _isLoading = true; // Use this single loading variable

  // Settings
  bool _canScanQr = false;
  bool _canControlPriceLevelFromDashboard = true;

  // Customer Selection
  CustomerModel? _selectedCustomer;
  double _customerOutstandingBalance = 0.0;

  // Price Level (Customer Category) Selection
  List<Map<String, dynamic>> _availableCategories = [];
  final bool _isLoadingCategories = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _openProductSelectionScreen() async {
    final invoiceCreated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ProductSelectionScreen(
          preSelectedCustomer: _selectedCustomer,
          canScanQr: _canScanQr,
        ),
      ),
    );
    if (!mounted) return;
    if (invoiceCreated == true) {
      setState(() => _selectedCustomer = null);
    }
    _loadStats();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final offlineDataProvider = context.read<OfflineDataProvider>();
      final isOnline = context.read<ConnectivityProvider>().isOnline;

      // Log DB health on startup for diagnostics
      await offlineDataProvider.logHealth();

      if (authProvider.currentUser != null) {
        final companyId = authProvider.selectedCompanyId;
        debugPrint('📊 Dashboard - Loading data for company: $companyId');

        // 🔄 TRIGGER BACKGROUND SYNC IF ONLINE
        if (isOnline && companyId != null) {
          debugPrint('🔄 Dashboard: Starting background sync for $companyId');
          // Don't await this so the dashboard loads immediately
          offlineDataProvider.syncAll(companyId).then((_) {
            debugPrint('✅ Dashboard: Background sync completed.');
            authProvider.updateLastSyncTimestamp();
          }).catchError((e) {
            debugPrint('⚠️ Dashboard: Background sync failed: $e');
          });
        } else if (companyId == null) {
          debugPrint('⚠️ Dashboard: Cannot sync, companyId is NULL');
        }

        // Helper to wrap individual calls for offline resilience
        Future<T?> safeCall<T>(
            Future<T> Function() call, T? defaultValue) async {
          try {
            return await call();
          } catch (e, st) {
            print('⚠️ Service call failed: $e\n$st');
            return defaultValue;
          }
        }

        final results = await Future.wait([
          safeCall(
            () => _invoiceService.getTodayStats(authProvider.currentUser!.id,
                companyId: companyId),
            {'todayInvoices': 0, 'todayAmount': 0.0},
          ),
          safeCall(() => _settingsService.canSalesmanScanQr(companyId!), false),
          safeCall(
            () => _settingsService.canSalesmanControlPriceLevelFromDashboard(companyId!),
            true,
          ),
          safeCall(() => _customerService.getAllCustomerCategories(), []),
        ]);

        final stats = results[0] as Map<String, dynamic>;
        final canScan = results[1] as bool;
        final canControlPriceLevel = results[2] as bool;
        final categories = results[3] as List<Map<String, dynamic>>;

        if (!mounted) return;
        
        // Load the GST rate into the CartProvider
        await context.read<CartProvider>().loadGlobalGstRate(companyId!);
        setState(() {
          _todayOrders = (stats['todayInvoices'] as int?) ?? 0;
          _todayAmount = (stats['todayAmount'] as num).toDouble();
          _canScanQr = canScan;
          _canControlPriceLevelFromDashboard = canControlPriceLevel;
          _availableCategories = categories;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('❌ Dashboard loading error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.currentUser != null) {
        final companyId = authProvider.selectedCompanyId;
        print('📊 Dashboard - Refreshing stats for company: $companyId');

        final stats = await _invoiceService
            .getTodayStats(authProvider.currentUser!.id, companyId: companyId);
        if (!mounted) return;
        setState(() {
          _todayOrders = (stats['todayInvoices'] as int?) ?? 0;
          _todayAmount = (stats['todayAmount'] as num?)?.toDouble() ?? 0.0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectCustomer() async {
    if (!mounted) return;

    final selected = await Navigator.push<CustomerModel>(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomerSelectionScreen(),
      ),
    );
    if (selected != null) {
      setState(() {
        _selectedCustomer = selected;
        _customerOutstandingBalance = 0.0; // Reset while loading
      });

      // ✅ Fetch customer outstanding balance
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      _fetchCustomerOutstanding(selected.customerName, companyId);

      // ✅ Auto-set Price Level from customer's default category
      final cartProvider = context.read<CartProvider>();
      if (selected.customerCategoryId != null) {
        // Find the category name from available categories
        final category = _availableCategories.firstWhere(
          (c) => c['id'] == selected.customerCategoryId,
          orElse: () => {},
        );
        final categoryName = category['category_name'] as String?;
        cartProvider.setSelectedCategory(
            selected.customerCategoryId, categoryName);
        print(
            '✅ Price Level auto-set to: $categoryName (${selected.customerCategoryId})');
      } else {
        // Clear price level if customer has no default category
        cartProvider.setSelectedCategory(null, null);
        print('⚠️ Customer has no default category - Price Level cleared');
      }
    }
  }

  Future<void> _fetchCustomerOutstanding(
      String customerName, String? companyId) async {
    try {
      final selectedId = companyId?.trim();
      String normalize(String s) =>
          s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
      final normCustomer = normalize(customerName);
      print(
          '🔍 Fetching outstanding for customer: "$normCustomer", company: $selectedId');

      // Resolve company GUID (Guid column) for the selected company id (if any)
      String? companyGuid;
      if (selectedId != null && selectedId.isNotEmpty) {
        try {
          final row = await Supabase.instance.client
              .from('tally_companies')
              .select('Guid')
              .eq('id', selectedId)
              .maybeSingle();
          companyGuid = (row?['Guid'] as String?)?.trim();
          print('   Resolved company Guid: ${companyGuid ?? 'NULL'}');
        } catch (e) {
          print('   Failed to resolve company Guid: $e');
        }
      }

      // Try a direct DB query first for performance/accuracy
      try {
        final client = Supabase.instance.client;
        dynamic q = client.from('outstanding').select();
        if (selectedId != null && selectedId.isNotEmpty) {
          final orParts = <String>[
            'company_id.eq.$selectedId',
            'Guid.eq.$selectedId'
          ];
          if (companyGuid != null && companyGuid.isNotEmpty) {
            orParts
                .addAll(['company_id.eq.$companyGuid', 'Guid.eq.$companyGuid']);
          }
          q = q.or(orParts.join(','));
        }
        final like = '%${customerName.trim()}%';
        final directRows = await q
            .ilike('customer_name', like)
            .gt('closing_balance', 0)
            .order('date', ascending: false);

        double directTotal = 0.0;
        for (final row in (directRows as List)) {
          final amt = (row['closing_balance'] as num?)?.toDouble() ?? 0.0;
          if (amt > 0) directTotal += amt;
        }
        if (directTotal > 0) {
          print('✅ Direct outstanding total: ₹$directTotal');
          if (mounted) {
            setState(() {
              _customerOutstandingBalance = directTotal;
            });
          }
          return; // No need for fallback
        } else {
          print('ℹ️ Direct query returned 0; using fallback');
        }
      } catch (e) {
        print('⚠️ Direct outstanding query failed: $e');
      }

      // Fallback: fetch all and filter on client (handles legacy rows without company_id)
      final allOutstanding = await _outstandingService.getAllOutstanding(
        companyId: companyId,
        limit: 1000000,
      );
      print('📊 Total outstanding rows fetched: ${allOutstanding.length}');

      double totalBalance = 0.0;
      int matchedRows = 0;
      for (final item in allOutstanding) {
        final itemCompanyId = item.companyId?.trim();
        final itemGuid = item.guid?.trim();
        final companyMatches = selectedId == null ||
            selectedId.isEmpty ||
            itemCompanyId == selectedId ||
            itemGuid == selectedId ||
            (companyGuid != null &&
                (itemCompanyId == companyGuid || itemGuid == companyGuid));
        final customerMatches = normalize(item.customerName) == normCustomer;

        if (companyMatches && customerMatches) {
          matchedRows++;
          totalBalance += (item.closingBalance > 0) ? item.closingBalance : 0.0;
        }
      }
      // If no exact normalized match, try relaxed contains-based match
      if (matchedRows == 0) {
        print('⚠️ No exact match. Trying relaxed name match...');
        String? chosenKey; // normalized customer name chosen
        final Map<String, double> sumsByName = {};
        for (final item in allOutstanding) {
          final itemCompanyId = item.companyId?.trim();
          final itemGuid = item.guid?.trim();
          final companyMatches = selectedId == null ||
              selectedId.isEmpty ||
              itemCompanyId == selectedId ||
              itemGuid == selectedId ||
              (companyGuid != null &&
                  (itemCompanyId == companyGuid || itemGuid == companyGuid));
          if (!companyMatches) continue;

          final normItem = normalize(item.customerName);
          final containsMatch = normItem.contains(normCustomer) ||
              normCustomer.contains(normItem);
          if (containsMatch && item.closingBalance > 0) {
            sumsByName[normItem] =
                (sumsByName[normItem] ?? 0) + item.closingBalance;
          }
        }
        if (sumsByName.isNotEmpty) {
          // Pick the largest sum as best candidate
          sumsByName.forEach((k, v) {
            if (chosenKey == null || (v > (sumsByName[chosenKey] ?? 0))) {
              chosenKey = k;
            }
          });
          totalBalance = sumsByName[chosenKey] ?? 0.0;
          matchedRows = 1; // treat as matched
          print('✅ Relaxed match found for "$chosenKey" total: ₹$totalBalance');
        } else {
          print('❌ No relaxed match found either.');
        }
      }

      print('✅ Matches: $matchedRows, total balance: ₹$totalBalance');

      if (mounted) {
        setState(() {
          _customerOutstandingBalance = totalBalance;
        });
      }
    } catch (e) {
      print('❌ Error fetching customer outstanding: $e');
      // Silently fail - outstanding display is optional
    }
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final currencyFormatter = NumberFormat("#,##,##0", "en_IN");
    final isPhone = MediaQuery.sizeOf(context).width < 420;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Salesman Dashboard'),
        actions: [
          // Cart with badge
          AppBarCartButton(
            onPressed: () async {
              final orderCreated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => CartScreen(
                    preSelectedCustomer: _selectedCustomer,
                  ),
                ),
              );
              if (orderCreated == true && mounted) {
                setState(() => _selectedCustomer = null);
                _loadStats();
              }
            },
          ),
          // Overflow menu for secondary actions
          AppBarOverflowMenu(
            items: [
              AppBarMenuItem(
                value: 'refresh',
                label: 'Refresh',
                icon: Icons.refresh,
                onTap: _loadStats,
              ),
              AppBarMenuItem(
                value: 'logout',
                label: 'Logout',
                icon: Icons.logout,
                onTap: () => _showLogoutDialog(context),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _loadStats,
          child: Column(
            children: [
              // Company Header
                  const CompanyHeaderWidget(),

              // Offline Banner
              if (!context.watch<ConnectivityProvider>().isOnline)
                _buildOfflineBanner(),

              // 🔄 Syncing Indicator
              Consumer<OfflineDataProvider>(
                builder: (context, provider, _) {
                  if (provider.isSyncing) {
                    return Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.08),
                        border: Border(
                          bottom: BorderSide(
                            color: AppTheme.primaryBlue.withOpacity(0.2),
                            width: 0.5,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Updating products & customers...',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.primaryBlue,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(isPhone ? 12 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, ${user?.name ?? 'Salesman'}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppTheme.grey),
                      ),
                      SizedBox(height: isPhone ? 14 : 24),
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primaryBlue, Color(0xFF0056b3)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryBlue.withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.all(isPhone ? 16 : 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shopping_basket, color: Colors.white, size: 28),
                                const SizedBox(width: 12),
                                Text(
                                  'Create New Order',
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildCustomerSelectionCard(),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _openProductSelectionScreen,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.primaryBlue,
                                minimumSize: Size.fromHeight(isPhone ? 48 : 56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.symmetric(
                                  vertical: isPhone ? 10 : 14,
                                ),
                              ),
                              icon: Icon(
                                Icons.add_circle_outline,
                                size: isPhone ? 18 : 20,
                              ),
                              label: Text(
                                'Start Adding Products',
                                style: TextStyle(
                                    fontSize: isPhone ? 14 : 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isPhone ? 14 : 24),
                      Consumer<CartProvider>(
                        builder: (context, cartProvider, child) {
                          return cartProvider.itemCount > 0
                              ? Column(
                                  children: [
                                    Card(
                                      color: AppTheme.success.withOpacity(0.1),
                                      child: InkWell(
                                        onTap: () async {
                                          final orderCreated =
                                              await Navigator.push<bool>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => CartScreen(
                                                preSelectedCustomer:
                                                    _selectedCustomer,
                                              ),
                                            ),
                                          );
                                          if (orderCreated == true && mounted) {
                                            setState(
                                                () => _selectedCustomer = null);
                                            _loadStats();
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(16),
                                        child: Padding(
                                          padding:
                                              EdgeInsets.all(isPhone ? 12 : 16),
                                          child: Row(
                                            children: [
                                              Icon(Icons.shopping_cart,
                                                  color: AppTheme.success,
                                                  size: isPhone ? 30 : 40),
                                              SizedBox(
                                                  width: isPhone ? 10 : 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Current Cart',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyLarge
                                                          ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '${cartProvider.totalQuantity == cartProvider.totalQuantity.truncateToDouble() ? cartProvider.totalQuantity.toInt() : cartProvider.totalQuantity} items • ₹${cartProvider.grandTotal.toStringAsFixed(2)}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            color: AppTheme
                                                                .success,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(Icons.arrow_forward_ios,
                                                  color: AppTheme.success,
                                                  size: isPhone ? 16 : 20),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isPhone ? 14 : 24),
                                  ],
                                )
                              : const SizedBox.shrink();
                        },
                      ),
                      Text("Today's Summary",
                          style: Theme.of(context).textTheme.headlineMedium),
                      SizedBox(height: isPhone ? 10 : 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(context,
                                icon: Icons.add_shopping_cart,
                                title: 'Orders Created',
                                value: _isLoading ? '...' : '$_todayOrders',
                                color: AppTheme.primaryBlue,
                                compact: isPhone),
                          ),
                          SizedBox(width: isPhone ? 8 : 16),
                          Expanded(
                            child: _buildStatCard(
                              context,
                              icon: Icons.currency_rupee,
                              title: 'Total Amount',
                              value: _isLoading
                                  ? '...'
                                  : currencyFormatter.format(_todayAmount),
                              color: AppTheme.success,
                              compact: isPhone,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isPhone ? 10 : 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionCard(context,
                                icon: Icons.shopping_bag_outlined,
                                title: 'Sales Orders',
                                color: AppTheme.primaryBlue,
                                compact: isPhone, onTap: () async {
                              final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const SalesOrdersScreen()));
                              if (mounted) _loadStats();
                            }),
                          ),
                          SizedBox(width: isPhone ? 8 : 12),
                          Expanded(
                            child: _buildActionCard(context,
                                icon: Icons.people,
                                title: 'Customers',
                                color: AppTheme.success,
                                compact: isPhone, onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const CustomersScreen()));
                            }),
                          ),
                        ],
                      ),
                      SizedBox(height: isPhone ? 10 : 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionCard(
                              context,
                              icon: Icons.description_outlined,
                              title: 'Sales Bills',
                              color: Colors.deepOrange,
                              compact: isPhone,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const SalesBillsScreen(),
                                  ),
                                );
                                if (mounted) _loadStats();
                              },
                            ),
                          ),
                          SizedBox(width: isPhone ? 8 : 12),
                          Expanded(
                            child: _buildActionCard(
                              context,
                              icon: Icons.account_balance_wallet_outlined,
                              title: 'Outstanding',
                              color: AppTheme.primaryBlue,
                              compact: isPhone,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const OutstandingScreen(),
                                  ),
                                );
                                if (mounted) _loadStats();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    final authProvider = context.watch<AuthProvider>();
    final lastSync = authProvider.lastCacheSyncAt;
    final syncText = lastSync != null
        ? 'Last synced: ${DateFormat('dd MMM, hh:mm a').format(lastSync)}'
        : 'No offline data synced yet.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.warning.withOpacity(0.15),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, color: AppTheme.warning, size: 16),
              SizedBox(width: 8),
              Text(
                'You are currently offline',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.warning,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            syncText,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSelectionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(
          color:
              _selectedCustomer != null ? AppTheme.success : AppTheme.warning.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _selectCustomer,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _selectedCustomer == null
                ? const Row(
                    children: [
                      Icon(Icons.person_add, color: AppTheme.warning, size: 32),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Customer',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppTheme.warning,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tap to select a customer for this order',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, color: AppTheme.warning),
                    ],
                  )
                : Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: AppTheme.success,
                        child: Icon(Icons.check, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedCustomer!.customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (_selectedCustomer!.mobileNumber != null)
                              Text(
                                _selectedCustomer!.mobileNumber!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.grey,
                                ),
                              ),
                            if (_customerOutstandingBalance > 0)
                              Text(
                                'Outstanding Pending: ₹${NumberFormat('#,##,##0.00', 'en_IN').format(_customerOutstandingBalance)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedCustomer = null;
                          });
                        },
                        icon: const Icon(Icons.close, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Remove customer',
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceLevelDropdown() {
    final cartProvider = context.watch<CartProvider>();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.price_change, color: AppTheme.primaryBlue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Price Level',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                _isLoadingCategories
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: cartProvider.selectedCategoryId,
                          hint: const Text(
                            'Select Price Level',
                            style: TextStyle(fontSize: 14),
                          ),
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down,
                              color: AppTheme.primaryBlue),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('-- None --',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                            ..._availableCategories.map((category) {
                              return DropdownMenuItem<String>(
                                value: category['id'] as String,
                                child:
                                    Text(category['category_name'] as String),
                              );
                            }),
                          ],
                          onChanged: !_canControlPriceLevelFromDashboard
                              ? null
                              : (value) {
                                  if (value == null) {
                                    cartProvider.setSelectedCategory(
                                        null, null);
                                  } else {
                                    final category =
                                        _availableCategories.firstWhere(
                                      (c) => c['id'] == value,
                                      orElse: () => {},
                                    );
                                    cartProvider.setSelectedCategory(
                                      value,
                                      category['category_name'] as String?,
                                    );
                                  }
                                },
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String value,
      required Color color,
      bool compact = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: compact ? 24 : 28),
                  ),
                  SizedBox(height: compact ? 12 : 16),
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              color: color, 
                              fontWeight: FontWeight.bold,
                              fontSize: compact ? 22 : 28)),
                  const SizedBox(height: 4),
                  Text(title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.grey,
                            fontWeight: FontWeight.w500,
                            fontSize: compact ? 12 : 14,
                          )),
                ],
              ),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context,
      {required IconData icon,
      required String title,
      required Color color,
      required VoidCallback onTap,
      bool compact = false}) {
    return _HoverActionCard(
      icon: icon,
      title: title,
      color: color,
      onTap: onTap,
      compact: compact,
    );
  }
}

class _HoverActionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  const _HoverActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_HoverActionCard> createState() => _HoverActionCardState();
}

class _HoverActionCardState extends State<_HoverActionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_isHovered ? 1.03 : 1.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            if (_isHovered)
              BoxShadow(
                color: widget.color.withOpacity(0.2),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            if (!_isHovered)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.all(widget.compact ? 14 : 20),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(widget.compact ? 12 : 16),
                    decoration: BoxDecoration(
                        color: widget.color.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: Icon(widget.icon, color: widget.color, size: widget.compact ? 24 : 32),
                  ),
                  SizedBox(height: widget.compact ? 12 : 16),
                  Text(widget.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: widget.compact ? 14 : null,
                          ),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
