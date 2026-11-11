import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/core/theme/app_theme.dart';

class SalesAnalysisScreen extends StatefulWidget {
  const SalesAnalysisScreen({super.key});

  @override
  State<SalesAnalysisScreen> createState() => _SalesAnalysisScreenState();
}

class _SalesAnalysisScreenState extends State<SalesAnalysisScreen> {
  // Date selection
  DateTime _selectedDate = DateTime.now();
  String _viewMode = 'month'; // 'month' or 'year'

  // Data
  List<DailySalesData> _salesData = [];
  List<SalesmanPerformance> _salesmenPerformance = [];
  bool _isLoading = true;

  // Summary metrics
  double _totalSales = 0.0;
  int _totalOrders = 0;
  double _avgOrderValue = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (_viewMode == 'month') {
        await _loadMonthlyData();
      } else {
        await _loadYearlyData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMonthlyData() async {
    final startDate = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final endDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);

    print('🔍 Loading data for: ${DateFormat('MMMM yyyy').format(_selectedDate)}');
    print('Start: ${startDate.toIso8601String()}');
    print('End: ${endDate.toIso8601String()}');

    // Get sales data
    final salesResponse = await Supabase.instance.client
        .from('sales_orders')
        .select('order_date, net_amount, salesman_id')
        .gte('order_date', startDate.toIso8601String())
        .lte('order_date', endDate.toIso8601String())
        .order('order_date', ascending: true);

    print('📊 Received ${salesResponse.length} orders');

    // Initialize all days of the month with 0
    final daysInMonth = endDate.day;
    final dailySalesMap = <int, double>{};
    for (int day = 1; day <= daysInMonth; day++) {
      dailySalesMap[day] = 0.0;
    }

    // Process daily sales
    for (var order in salesResponse) {
      final date = DateTime.parse(order['order_date'].toString());
      final day = date.day;
      final amount = (order['net_amount'] as num).toDouble();
      dailySalesMap[day] = (dailySalesMap[day] ?? 0) + amount;
    }

    _salesData = dailySalesMap.entries
        .map((e) => DailySalesData(e.key.toString(), e.value))
        .toList()
      ..sort((a, b) => int.parse(a.period).compareTo(int.parse(b.period)));

    // Calculate summary metrics
    _totalOrders = salesResponse.length;
    _totalSales = _salesData.fold(0.0, (sum, item) => sum + item.amount);
    _avgOrderValue = _totalOrders > 0 ? _totalSales / _totalOrders : 0.0;

    print('✅ Total Sales: ₹$_totalSales, Orders: $_totalOrders');

    // Get salesman performance
    await _loadSalesmenPerformance(startDate, endDate);
  }

  Future<void> _loadYearlyData() async {
    final startDate = DateTime(_selectedDate.year, 1, 1);
    final endDate = DateTime(_selectedDate.year, 12, 31);

    // Get sales data
    final salesResponse = await Supabase.instance.client
        .from('sales_orders')
        .select('order_date, net_amount, salesman_id')
        .gte('order_date', startDate.toIso8601String())
        .lte('order_date', endDate.toIso8601String())
        .order('order_date', ascending: true);

    // Process monthly sales
    final monthlySalesMap = <String, double>{};
    for (var order in salesResponse) {
      final date = DateTime.parse(order['order_date'].toString());
      final monthKey = DateFormat('MMM').format(date);
      final amount = (order['net_amount'] as num).toDouble();
      monthlySalesMap[monthKey] = (monthlySalesMap[monthKey] ?? 0) + amount;
    }

    final monthOrder = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    _salesData = monthOrder
        .map((month) => DailySalesData(month, monthlySalesMap[month] ?? 0.0))
        .toList();

    // Calculate summary metrics
    _totalOrders = salesResponse.length;
    _totalSales = _salesData.fold(0.0, (sum, item) => sum + item.amount);
    _avgOrderValue = _totalOrders > 0 ? _totalSales / _totalOrders : 0.0;

    // Get salesman performance
    await _loadSalesmenPerformance(startDate, endDate);
  }

  Future<void> _loadSalesmenPerformance(DateTime startDate, DateTime endDate) async {
    final response = await Supabase.instance.client
        .from('sales_orders')
        .select('''
          *,
          users!sales_orders_salesman_id_fkey(name)
        ''')
        .gte('order_date', startDate.toIso8601String())
        .lte('order_date', endDate.toIso8601String());

    final salesmenMap = <String, Map<String, dynamic>>{};

    for (var order in response) {
      final salesmanName = (order['users'] as Map?)?['name'] ?? 'Unknown';
      final amount = (order['net_amount'] as num).toDouble();

      if (!salesmenMap.containsKey(salesmanName)) {
        salesmenMap[salesmanName] = {
          'name': salesmanName,
          'orders': 1,
          'total_sales': amount,
        };
      } else {
        salesmenMap[salesmanName]!['orders'] =
            (salesmenMap[salesmanName]!['orders'] as int) + 1;
        salesmenMap[salesmanName]!['total_sales'] =
            (salesmenMap[salesmanName]!['total_sales'] as num) + amount;
      }
    }

    _salesmenPerformance = salesmenMap.values
        .map((data) => SalesmanPerformance(
      data['name'] as String,
      data['orders'] as int,
      (data['total_sales'] as num).toDouble(),
    ))
        .toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
  }

  void _showDatePicker() async {
    if (_viewMode == 'month') {
      // Month picker
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDatePickerMode: DatePickerMode.day,
      );

      if (picked != null) {
        setState(() => _selectedDate = picked);
        _loadData();
      }
    } else {
      // Year picker
      final picked = await showDialog<int>(
        context: context,
        builder: (context) => _YearPickerDialog(
          initialYear: _selectedDate.year,
        ),
      );

      if (picked != null) {
        setState(() => _selectedDate = DateTime(picked, 1, 1));
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##,##0", "en_IN");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date and View Mode Selection
              _buildDateSelector(),
              const SizedBox(height: 20),

              // Summary Cards
              _buildSummaryCards(currencyFormat),
              const SizedBox(height: 24),

              // Sales Chart
              _buildSalesChart(),
              const SizedBox(height: 32),

              // Top Performers
              _buildTopPerformers(currencyFormat),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // View Mode Toggle
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'month',
                        label: Text('Monthly'),
                        icon: Icon(Icons.calendar_view_month),
                      ),
                      ButtonSegment(
                        value: 'year',
                        label: Text('Yearly'),
                        icon: Icon(Icons.calendar_today),
                      ),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (Set<String> selected) {
                      setState(() {
                        _viewMode = selected.first;
                      });
                      _loadData();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date Display and Picker
            InkWell(
              onTap: _showDatePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryBlue),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            color: AppTheme.primaryBlue, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          _viewMode == 'month'
                              ? DateFormat('MMMM yyyy').format(_selectedDate)
                              : DateFormat('yyyy').format(_selectedDate),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_drop_down, color: AppTheme.primaryBlue),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(NumberFormat currencyFormat) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            'Total Sales',
            '₹${currencyFormat.format(_totalSales)}',
            Icons.currency_rupee,
            AppTheme.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Orders',
            _totalOrders.toString(),
            Icons.shopping_cart,
            AppTheme.primaryBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Avg Value',
            '₹${currencyFormat.format(_avgOrderValue)}',
            Icons.trending_up,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _viewMode == 'month' ? 'Daily Sales' : 'Monthly Sales',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: _salesData.isEmpty
                  ? const Center(child: Text('No sales data available'))
                  : SfCartesianChart(
                primaryXAxis: const CategoryAxis(
                  majorGridLines: MajorGridLines(width: 0),
                ),
                primaryYAxis: NumericAxis(
                  numberFormat: NumberFormat.compact(),
                  majorGridLines: MajorGridLines(
                    width: 0.5,
                    color: Colors.grey.withOpacity(0.2),
                  ),
                ),
                plotAreaBorderWidth: 0,
                series: <CartesianSeries>[
                  SplineAreaSeries<DailySalesData, String>(
                    dataSource: _salesData,
                    xValueMapper: (DailySalesData sales, _) => sales.period,
                    yValueMapper: (DailySalesData sales, _) => sales.amount,
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                    borderColor: AppTheme.primaryBlue,
                    borderWidth: 3,
                    markerSettings: const MarkerSettings(
                      isVisible: true,
                      shape: DataMarkerType.circle,
                      borderWidth: 2,
                      borderColor: AppTheme.primaryBlue,
                      color: Colors.white,
                    ),
                  ),
                ],
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.x: ₹point.y',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPerformers(NumberFormat currencyFormat) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Performers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_salesmenPerformance.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No performance data available'),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _salesmenPerformance.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final salesman = _salesmenPerformance[index];
                  final rank = index + 1;

                  Color rankColor;
                  if (rank == 1) {
                    rankColor = Colors.amber;
                  } else if (rank == 2) {
                    rankColor = Colors.grey[400]!;
                  } else if (rank == 3) {
                    rankColor = Colors.brown[300]!;
                  } else {
                    rankColor = AppTheme.primaryBlue.withOpacity(0.3);
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: rankColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              rank.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                salesman.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${salesman.orders} orders',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${currencyFormat.format(salesman.totalSales)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppTheme.success,
                              ),
                            ),
                            Text(
                              '₹${currencyFormat.format(salesman.totalSales / salesman.orders)}/order',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// Year Picker Dialog
class _YearPickerDialog extends StatelessWidget {
  final int initialYear;

  const _YearPickerDialog({required this.initialYear});

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List.generate(
      currentYear - 2020 + 1,
          (index) => 2020 + index,
    ).reversed.toList();

    return AlertDialog(
      title: const Text('Select Year'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: years.length,
          itemBuilder: (context, index) {
            final year = years[index];
            final isSelected = year == initialYear;

            return ListTile(
              title: Text(
                year.toString(),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppTheme.primaryBlue : null,
                ),
              ),
              selected: isSelected,
              onTap: () => Navigator.pop(context, year),
            );
          },
        ),
      ),
    );
  }
}

// Data Models
class DailySalesData {
  final String period;
  final double amount;

  DailySalesData(this.period, this.amount);
}

class SalesmanPerformance {
  final String name;
  final int orders;
  final double totalSales;

  SalesmanPerformance(this.name, this.orders, this.totalSales);
}