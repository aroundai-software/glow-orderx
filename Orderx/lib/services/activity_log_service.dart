import 'package:Orderx/models/activity_log_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActivityLogService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<SalesmanOption>> getSalesmen({String? companyId}) async {
    try {
      dynamic query =
          _supabase.from('users').select('id, name').eq('user_type', 'salesman');

      if (companyId != null && companyId != 'ALL') {
        query = query.eq('company_id', companyId);
      }

      final rows = await query.order('name') as List;
      return rows
          .map((row) => SalesmanOption(
                id: row['id']?.toString() ?? '',
                name: (row['name'] as String?)?.trim().isNotEmpty == true
                    ? row['name'] as String
                    : 'Unknown',
              ))
          .where((s) => s.id.isNotEmpty)
          .toList();
    } catch (e) {
      print('Error loading salesmen for activity logs: $e');
      return [];
    }
  }

  Future<List<ActivityLog>> getActivityLogs({
    String? companyId,
    DateTime? startDate,
    DateTime? endDate,
    String? salesmanId,
    String? salesmanName,
    ActivityLogType? type,
  }) async {
    try {
      final users = await _loadSalesmenMap(
        companyId: companyId,
        salesmanId: salesmanId,
        salesmanName: salesmanName,
      );
      final userIds = users.keys.toList();

      final logs = <ActivityLog>[];
      if (type == null ||
          type == ActivityLogType.login ||
          type == ActivityLogType.logout) {
        if (userIds.isNotEmpty) {
          logs.addAll(await _loadSessionLogs(
            users: users,
            userIds: userIds,
            startDate: startDate,
            endDate: endDate,
            type: type,
          ));
        }
      }

      if (type == null || type == ActivityLogType.orderCreated) {
        logs.addAll(await _loadOrderLogs(
          users: users,
          userIds: userIds,
          companyId: companyId,
          salesmanId: salesmanId,
          startDate: startDate,
          endDate: endDate,
        ));
      }

      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return logs;
    } catch (e) {
      print('Error loading activity logs: $e');
      rethrow;
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadSalesmenMap({
    String? companyId,
    String? salesmanId,
    String? salesmanName,
  }) async {
    dynamic userQuery = _supabase
        .from('users')
        .select('id, name, mobile_number, company_id')
        .eq('user_type', 'salesman');

    if (companyId != null && companyId != 'ALL') {
      userQuery = userQuery.eq('company_id', companyId);
    }
    if (salesmanId != null && salesmanId.isNotEmpty) {
      userQuery = userQuery.eq('id', salesmanId);
    }
    if (salesmanName != null && salesmanName.trim().isNotEmpty) {
      userQuery = userQuery.ilike('name', '%${salesmanName.trim()}%');
    }

    final userRows = await userQuery as List;
    final users = <String, Map<String, dynamic>>{};
    for (final row in userRows) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) {
        users[id] = Map<String, dynamic>.from(row as Map);
      }
    }
    return users;
  }

  Future<List<ActivityLog>> _loadSessionLogs({
    required Map<String, Map<String, dynamic>> users,
    required List<String> userIds,
    DateTime? startDate,
    DateTime? endDate,
    ActivityLogType? type,
  }) async {
    dynamic query = _supabase
        .from('user_sessions')
        .select(
            'id, user_id, device_type, device_model, created_at, ended_at, is_active')
        .inFilter('user_id', userIds);

    final rows =
        await query.order('created_at', ascending: false).limit(1000) as List;
    final logs = <ActivityLog>[];

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final uid = row['user_id']?.toString();
      if (uid == null || !users.containsKey(uid)) continue;
      final user = users[uid]!;
      final device = _formatDevice(row);

      final loginAt = _parseDate(row['created_at']);
      if (loginAt != null &&
          (type == null || type == ActivityLogType.login) &&
          _inLocalRange(loginAt, startDate, endDate)) {
        logs.add(ActivityLog(
          id: 'login_${row['id']}',
          type: ActivityLogType.login,
          timestamp: loginAt,
          salesmanId: uid,
          salesmanName: user['name']?.toString() ?? 'Unknown',
          salesmanMobile: user['mobile_number']?.toString(),
          deviceInfo: device,
          companyId: user['company_id']?.toString(),
        ));
      }

      final logoutAt = _parseDate(row['ended_at']);
      if (logoutAt != null &&
          (type == null || type == ActivityLogType.logout) &&
          _inLocalRange(logoutAt, startDate, endDate)) {
        logs.add(ActivityLog(
          id: 'logout_${row['id']}',
          type: ActivityLogType.logout,
          timestamp: logoutAt,
          salesmanId: uid,
          salesmanName: user['name']?.toString() ?? 'Unknown',
          salesmanMobile: user['mobile_number']?.toString(),
          deviceInfo: device,
          companyId: user['company_id']?.toString(),
        ));
      }
    }

    return logs;
  }

  Future<List<ActivityLog>> _loadOrderLogs({
    required Map<String, Map<String, dynamic>> users,
    required List<String> userIds,
    String? companyId,
    String? salesmanId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    dynamic query = _supabase.from('sales_orders').select(
        'id, order_number, salesman_id, customer_name, net_amount, created_at, order_date, company_id, company_name');

    if (companyId != null && companyId != 'ALL') {
      query = query.eq('company_id', companyId);
    }
    if (salesmanId != null && salesmanId.isNotEmpty) {
      query = query.eq('salesman_id', salesmanId);
    } else if (userIds.isNotEmpty) {
      query = query.inFilter('salesman_id', userIds);
    }

    final rows =
        await query.order('created_at', ascending: false).limit(1000) as List;
    final logs = <ActivityLog>[];

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final uid = row['salesman_id']?.toString() ?? '';
      final createdAt =
          _parseDate(row['created_at']) ?? _parseDate(row['order_date']);
      final orderDate = _parseDate(row['order_date']);
      if (createdAt == null) continue;
      final matchesRange = _inLocalRange(createdAt, startDate, endDate) ||
          (orderDate != null && _inLocalRange(orderDate, startDate, endDate));
      if (!matchesRange) continue;
      final user = users[uid];

      logs.add(ActivityLog(
        id: 'order_${row['id']}',
        type: ActivityLogType.orderCreated,
        timestamp: createdAt,
        salesmanId: uid,
        salesmanName: user?['name']?.toString() ?? 'Unknown',
        salesmanMobile: user?['mobile_number']?.toString(),
        orderId: row['id']?.toString(),
        orderNumber: row['order_number']?.toString(),
        customerName: row['customer_name']?.toString(),
        orderAmount: (row['net_amount'] as num?)?.toDouble(),
        companyId: row['company_id']?.toString(),
        companyName: row['company_name']?.toString(),
      ));
    }

    return logs;
  }

  /// Compare using the local calendar, so "Today" matches the date on screen.
  bool _inLocalRange(DateTime value, DateTime? start, DateTime? end) {
    final local = value.toLocal();
    if (start != null && local.isBefore(start)) return false;
    if (end != null && local.isAfter(end)) return false;
    return true;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    final text = value.toString();
    if (text.isEmpty) return null;
    try {
      return DateTime.parse(text).toLocal();
    } catch (_) {
      return null;
    }
  }

  String? _formatDevice(Map<String, dynamic> session) {
    final type = session['device_type']?.toString();
    final model = session['device_model']?.toString();
    if ((type == null || type.isEmpty) && (model == null || model.isEmpty)) {
      return null;
    }
    if (type != null &&
        type.isNotEmpty &&
        model != null &&
        model.isNotEmpty &&
        type != model) {
      return '$type · $model';
    }
    return type ?? model;
  }
}
