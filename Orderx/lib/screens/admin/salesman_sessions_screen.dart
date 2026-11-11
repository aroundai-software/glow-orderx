import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalesmanSessionsTab extends StatefulWidget {
  const SalesmanSessionsTab({super.key});

  @override
  State<SalesmanSessionsTab> createState() => _SalesmanSessionsTabState();
}

class _SalesmanSessionsTabState extends State<SalesmanSessionsTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<_SalesmanSessionInfo> _sessions = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  String? _lastSelectedCompanyId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentId = context.watch<AuthProvider>().selectedCompanyId;
    if (_lastSelectedCompanyId != currentId) {
      _lastSelectedCompanyId = currentId;
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;

      print('📊 SalesmanSessionsTab - Loading sessions for company: $effectiveCompanyId');

      dynamic userQuery = _supabase
          .from('users')
          .select('id, name, mobile_number, company_id')
          .eq('user_type', 'salesman');

      if (effectiveCompanyId != null) {
        userQuery = userQuery.eq('company_id', effectiveCompanyId);
      }

      userQuery = userQuery.order('name');

      final userRows = await userQuery;

      final salesmen = (userRows as List)
          .cast<Map<String, dynamic>>()
          .map((row) => _SalesmanSessionInfo(
                userId: row['id']?.toString() ?? '',
                name: row['name']?.toString() ?? 'Unknown',
                mobile: row['mobile_number']?.toString(),
                companyId: row['company_id']?.toString(),
              ))
          .where((s) => s.userId.isNotEmpty)
          .toList();

      final ids = salesmen.map((s) => s.userId).toList();

      List<Map<String, dynamic>> sessionRows = [];
      if (ids.isNotEmpty) {
        sessionRows = await _supabase
            .from('user_sessions')
            .select('user_id, device_type, device_model, is_active, created_at, last_activity')
            .inFilter('user_id', ids)
            .order('created_at', ascending: false);
      }

      // Fetch company names if viewing ALL or even for single to ensure we have labels
      final companyIds = salesmen.map((s) => s.companyId).whereType<String>().toSet().toList();
      Map<String, String> companyNames = {};
      if (companyIds.isNotEmpty) {
        final companies = await _supabase
            .from('tally_companies')
            .select('id, company_name')
            .filter('id', 'in', companyIds);
        
        for (var c in (companies as List)) {
          companyNames[c['id']] = c['company_name'];
        }
      }

      final latestSessionByUser = <String, Map<String, dynamic>>{};
      for (final row in sessionRows) {
        final uid = row['user_id']?.toString();
        if (uid == null || uid.isEmpty) continue;
        latestSessionByUser.putIfAbsent(uid, () => row);
      }

      final enriched = salesmen.map((salesman) {
        final session = latestSessionByUser[salesman.userId];
        return salesman.copyWith(
          lastLogin: _parseDate(session?['created_at']),
          lastActivity: _parseDate(session?['last_activity']),
          isActive: session?['is_active'] == true,
          deviceInfo: _formatDevice(session),
          companyName: companyNames[salesman.companyId] ?? 'Unknown Company',
        );
      }).toList();

      if (mounted) {
        setState(() {
          _sessions = enriched;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load sessions: $e';
          _isLoading = false;
        });
      }
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value).toLocal();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String? _formatDevice(Map<String, dynamic>? session) {
    if (session == null) return null;
    final type = session['device_type']?.toString();
    final model = session['device_model']?.toString();
    if ((type == null || type.isEmpty) && (model == null || model.isEmpty)) {
      return null;
    }
    if (type != null && model != null && model.isNotEmpty) {
      return '$type · $model';
    }
    return type ?? model;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Never';
    final formatter = DateFormat('dd MMM yyyy, hh:mm a');
    return formatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadSessions,
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 40, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadSessions,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _sessions.isEmpty
                    ? const Center(child: Text('No salesmen found for the selected company'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              session.name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              session.companyName ?? 'Unknown Company',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.primaryBlue,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _StatusPill(isActive: session.isActive),
                                    ],
                                  ),
                                  if (session.mobile != null && session.mobile!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                                      child: Text(
                                        session.mobile!,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  _InfoRow(
                                    label: 'Last Login',
                                    value: _formatDate(session.lastLogin),
                                  ),
                                  _InfoRow(
                                    label: 'Last Activity',
                                    value: _formatDate(session.lastActivity),
                                  ),
                                  _InfoRow(
                                    label: 'Device',
                                    value: session.deviceInfo ?? 'Not recorded',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          );
  }
}

class _SalesmanSessionInfo {
  final String userId;
  final String name;
  final String? mobile;
  final String? companyId;
  final String? companyName;
  final DateTime? lastLogin;
  final DateTime? lastActivity;
  final bool isActive;
  final String? deviceInfo;

  _SalesmanSessionInfo({
    required this.userId,
    required this.name,
    this.mobile,
    this.companyId,
    this.companyName,
    this.lastLogin,
    this.lastActivity,
    this.isActive = false,
    this.deviceInfo,
  });

  _SalesmanSessionInfo copyWith({
    DateTime? lastLogin,
    DateTime? lastActivity,
    bool? isActive,
    String? deviceInfo,
    String? companyName,
  }) {
    return _SalesmanSessionInfo(
      userId: userId,
      name: name,
      mobile: mobile,
      companyId: companyId,
      companyName: companyName ?? this.companyName,
      lastLogin: lastLogin ?? this.lastLogin,
      lastActivity: lastActivity ?? this.lastActivity,
      isActive: isActive ?? this.isActive,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isActive;

  const _StatusPill({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.circle : Icons.remove_circle_outline,
            size: 10,
            color: isActive ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            isActive ? 'Active Session' : 'Inactive',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.green.shade900 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
