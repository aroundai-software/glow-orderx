enum ActivityLogType { login, logout, orderCreated }

class ActivityLog {
  final String id;
  final ActivityLogType type;
  final DateTime timestamp;
  final String salesmanId;
  final String salesmanName;
  final String? salesmanMobile;
  final String? deviceInfo;
  final String? orderId;
  final String? orderNumber;
  final String? customerName;
  final double? orderAmount;
  final String? orderStatus;
  final String? ledger;
  final String? companyId;
  final String? companyName;

  const ActivityLog({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.salesmanId,
    required this.salesmanName,
    this.salesmanMobile,
    this.deviceInfo,
    this.orderId,
    this.orderNumber,
    this.customerName,
    this.orderAmount,
    this.orderStatus,
    this.ledger,
    this.companyId,
    this.companyName,
  });

  String get typeLabel {
    switch (type) {
      case ActivityLogType.login:
        return 'Login';
      case ActivityLogType.logout:
        return 'Logout';
      case ActivityLogType.orderCreated:
        return 'Order created';
    }
  }
}

class SalesmanOption {
  final String id;
  final String name;

  const SalesmanOption({required this.id, required this.name});
}

class ActivityDayGroup {
  final DateTime day;
  final List<ActivityLog> logins;
  final List<ActivityLog> logouts;
  final List<ActivityLog> orders;

  ActivityDayGroup({
    required this.day,
    required this.logins,
    required this.logouts,
    required this.orders,
  });

  DateTime? get firstLogin =>
      logins.isEmpty ? null : logins.first.timestamp;
  DateTime? get lastLogout =>
      logouts.isEmpty ? null : logouts.last.timestamp;
  bool get stillLoggedIn {
    if (logins.isEmpty) return false;
    if (logouts.isEmpty) return true;
    return logins.last.timestamp.isAfter(logouts.last.timestamp);
  }
}

class SalesmanActivityReport {
  final String salesmanId;
  final String salesmanName;
  final String? mobile;
  final List<ActivityDayGroup> days;

  const SalesmanActivityReport({
    required this.salesmanId,
    required this.salesmanName,
    this.mobile,
    required this.days,
  });

  int get orderCount =>
      days.fold(0, (sum, day) => sum + day.orders.length);
  int get loginCount =>
      days.fold(0, (sum, day) => sum + day.logins.length);
  int get logoutCount =>
      days.fold(0, (sum, day) => sum + day.logouts.length);
}

List<SalesmanActivityReport> groupActivityLogs(List<ActivityLog> logs) {
  final bySalesman = <String, List<ActivityLog>>{};
  for (final log in logs) {
    bySalesman.putIfAbsent(log.salesmanId, () => []).add(log);
  }

  final reports = <SalesmanActivityReport>[];
  for (final entry in bySalesman.entries) {
    final salesmanLogs = entry.value;
    salesmanLogs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final first = salesmanLogs.first;

    final byDay = <DateTime, List<ActivityLog>>{};
    for (final log in salesmanLogs) {
      final day = DateTime(
        log.timestamp.year,
        log.timestamp.month,
        log.timestamp.day,
      );
      byDay.putIfAbsent(day, () => []).add(log);
    }

    final days = byDay.entries.map((dayEntry) {
      final dayLogs = dayEntry.value
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return ActivityDayGroup(
        day: dayEntry.key,
        logins: dayLogs
            .where((l) => l.type == ActivityLogType.login)
            .toList(),
        logouts: dayLogs
            .where((l) => l.type == ActivityLogType.logout)
            .toList(),
        orders: dayLogs
            .where((l) => l.type == ActivityLogType.orderCreated)
            .toList(),
      );
    }).toList()
      ..sort((a, b) => b.day.compareTo(a.day));

    reports.add(SalesmanActivityReport(
      salesmanId: entry.key,
      salesmanName: first.salesmanName,
      mobile: first.salesmanMobile,
      days: days,
    ));
  }

  reports.sort((a, b) => a.salesmanName.compareTo(b.salesmanName));
  return reports;
}
