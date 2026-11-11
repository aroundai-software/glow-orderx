import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OutstandingFollowUpMeta {
  final DateTime? followUpDate;
  final bool paymentReceived;
  final DateTime? paymentReceivedAt;
  final DateTime? lastFollowedUpAt;
  final int followUpCount;
  final List<DateTime> followUpLog;
  final String remark;
  final String? createdByUserId;
  final String createdByName;
  final String createdByType;
  final String? lastUpdatedByUserId;
  final String lastUpdatedByName;
  final String lastUpdatedByType;
  final String? lastFollowedUpByUserId;
  final String lastFollowedUpByName;
  final String lastFollowedUpByType;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const OutstandingFollowUpMeta({
    required this.followUpDate,
    required this.paymentReceived,
    required this.paymentReceivedAt,
    required this.lastFollowedUpAt,
    required this.followUpCount,
    required this.followUpLog,
    required this.remark,
    required this.createdByUserId,
    required this.createdByName,
    required this.createdByType,
    required this.lastUpdatedByUserId,
    required this.lastUpdatedByName,
    required this.lastUpdatedByType,
    required this.lastFollowedUpByUserId,
    required this.lastFollowedUpByName,
    required this.lastFollowedUpByType,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OutstandingFollowUpMeta.empty() {
    return const OutstandingFollowUpMeta(
      followUpDate: null,
      paymentReceived: false,
      paymentReceivedAt: null,
      lastFollowedUpAt: null,
      followUpCount: 0,
      followUpLog: [],
      remark: '',
      createdByUserId: null,
      createdByName: '',
      createdByType: '',
      lastUpdatedByUserId: null,
      lastUpdatedByName: '',
      lastUpdatedByType: '',
      lastFollowedUpByUserId: null,
      lastFollowedUpByName: '',
      lastFollowedUpByType: '',
      createdAt: null,
      updatedAt: null,
    );
  }

  factory OutstandingFollowUpMeta.fromJson(Map<String, dynamic> json) {
    final followUpLogRaw = json['follow_up_log'] ?? json['followUpLog'];
    final List<DateTime> followUpLog = (followUpLogRaw is List)
        ? followUpLogRaw
            .whereType<String>()
            .map((s) => DateTime.parse(s))
            .toList()
        : const <DateTime>[];

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.parse(v);
      return null;
    }

    bool parseBool(dynamic v, {required bool fallback}) {
      if (v is bool) return v;
      return fallback;
    }

    int parseInt(dynamic v, {required int fallback}) {
      if (v is num) return v.toInt();
      return fallback;
    }

    final followUpDateRaw = json['follow_up_date'] ?? json['followUpDate'];
    final paymentReceivedRaw = json['payment_received'] ?? json['paymentReceived'];
    final paymentReceivedAtRaw = json['payment_received_at'] ?? json['paymentReceivedAt'];
    final lastFollowedUpAtRaw = json['last_followed_up_at'] ?? json['lastFollowedUpAt'];
    final followUpCountRaw = json['follow_up_count'] ?? json['followUpCount'];
    final remarkRaw = json['remark'];

    final createdByUserIdRaw = json['created_by_user_id'];
    final createdByNameRaw = json['created_by_name'];
    final createdByTypeRaw = json['created_by_type'];
    final lastUpdatedByUserIdRaw = json['last_updated_by_user_id'];
    final lastUpdatedByNameRaw = json['last_updated_by_name'];
    final lastUpdatedByTypeRaw = json['last_updated_by_type'];
    final lastFollowedUpByUserIdRaw = json['last_followed_up_by_user_id'];
    final lastFollowedUpByNameRaw = json['last_followed_up_by_name'];
    final lastFollowedUpByTypeRaw = json['last_followed_up_by_type'];
    final createdAtRaw = json['created_at'];
    final updatedAtRaw = json['updated_at'];

    return OutstandingFollowUpMeta(
      followUpDate: parseDate(followUpDateRaw),
      paymentReceived: parseBool(paymentReceivedRaw, fallback: false),
      paymentReceivedAt: parseDate(paymentReceivedAtRaw),
      lastFollowedUpAt: parseDate(lastFollowedUpAtRaw),
      followUpCount: parseInt(followUpCountRaw, fallback: 0),
      followUpLog: followUpLog,
      remark: remarkRaw is String ? remarkRaw : '',
      createdByUserId: createdByUserIdRaw is String ? createdByUserIdRaw : null,
      createdByName: createdByNameRaw is String ? createdByNameRaw : '',
      createdByType: createdByTypeRaw is String ? createdByTypeRaw : '',
      lastUpdatedByUserId:
          lastUpdatedByUserIdRaw is String ? lastUpdatedByUserIdRaw : null,
      lastUpdatedByName:
          lastUpdatedByNameRaw is String ? lastUpdatedByNameRaw : '',
      lastUpdatedByType:
          lastUpdatedByTypeRaw is String ? lastUpdatedByTypeRaw : '',
      lastFollowedUpByUserId:
          lastFollowedUpByUserIdRaw is String ? lastFollowedUpByUserIdRaw : null,
      lastFollowedUpByName:
          lastFollowedUpByNameRaw is String ? lastFollowedUpByNameRaw : '',
      lastFollowedUpByType:
          lastFollowedUpByTypeRaw is String ? lastFollowedUpByTypeRaw : '',
      createdAt: parseDate(createdAtRaw),
      updatedAt: parseDate(updatedAtRaw),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'follow_up_date': followUpDate?.toIso8601String().split('T')[0],
      'payment_received': paymentReceived,
      'payment_received_at': paymentReceivedAt?.toIso8601String(),
      'last_followed_up_at': lastFollowedUpAt?.toIso8601String(),
      'follow_up_count': followUpCount,
      'follow_up_log': followUpLog.map((d) => d.toIso8601String()).toList(),
      'remark': remark,
    };
  }

  OutstandingFollowUpMeta copyWith({
    DateTime? followUpDate,
    bool? paymentReceived,
    DateTime? paymentReceivedAt,
    DateTime? lastFollowedUpAt,
    int? followUpCount,
    List<DateTime>? followUpLog,
    String? remark,
    String? createdByUserId,
    String? createdByName,
    String? createdByType,
    String? lastUpdatedByUserId,
    String? lastUpdatedByName,
    String? lastUpdatedByType,
    String? lastFollowedUpByUserId,
    String? lastFollowedUpByName,
    String? lastFollowedUpByType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OutstandingFollowUpMeta(
      followUpDate: followUpDate ?? this.followUpDate,
      paymentReceived: paymentReceived ?? this.paymentReceived,
      paymentReceivedAt: paymentReceivedAt ?? this.paymentReceivedAt,
      lastFollowedUpAt: lastFollowedUpAt ?? this.lastFollowedUpAt,
      followUpCount: followUpCount ?? this.followUpCount,
      followUpLog: followUpLog ?? this.followUpLog,
      remark: remark ?? this.remark,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByName: createdByName ?? this.createdByName,
      createdByType: createdByType ?? this.createdByType,
      lastUpdatedByUserId: lastUpdatedByUserId ?? this.lastUpdatedByUserId,
      lastUpdatedByName: lastUpdatedByName ?? this.lastUpdatedByName,
      lastUpdatedByType: lastUpdatedByType ?? this.lastUpdatedByType,
      lastFollowedUpByUserId:
          lastFollowedUpByUserId ?? this.lastFollowedUpByUserId,
      lastFollowedUpByName: lastFollowedUpByName ?? this.lastFollowedUpByName,
      lastFollowedUpByType: lastFollowedUpByType ?? this.lastFollowedUpByType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class _ActorInfo {
  final String id;
  final String name;
  final String type;

  const _ActorInfo({
    required this.id,
    required this.name,
    required this.type,
  });
}

class OutstandingFollowUpService {
  static const String _prefsKeyV1 = 'outstanding_followups_v1';
  static const String _prefsMigrationFlag = 'outstanding_followups_v1_migrated';

  final SupabaseClient _supabase = Supabase.instance.client;
  _ActorInfo? _actorCache;

  Future<_ActorInfo?> _getActor() async {
    if (_actorCache != null) return _actorCache;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) return null;

    try {
      final row = await _supabase
          .from('users')
          .select('id, name, user_type')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        _actorCache = _ActorInfo(id: userId, name: '', type: '');
      } else {
        _actorCache = _ActorInfo(
          id: row['id'] as String? ?? userId,
          name: row['name'] as String? ?? '',
          type: row['user_type'] as String? ?? '',
        );
      }
    } catch (_) {
      _actorCache = _ActorInfo(id: userId, name: '', type: '');
    }

    return _actorCache;
  }

  Future<Map<String, dynamic>> _actorFieldsForUpsert(
    String outstandingId, {
    required bool includeFollowedUp,
  }) async {
    final actor = await _getActor();
    if (actor == null) return {};

    Map<String, dynamic>? existing;
    try {
      existing = await _supabase
          .from('outstanding_followups')
          .select('created_by_user_id, created_by_name, created_by_type')
          .eq('outstanding_id', outstandingId)
          .maybeSingle();
    } catch (_) {
      existing = null;
    }

    final createdByUserId = existing?['created_by_user_id'];
    final createdByName = existing?['created_by_name'];
    final createdByType = existing?['created_by_type'];

    final hasCreatedBy =
        (createdByUserId is String && createdByUserId.isNotEmpty) ||
            (createdByName is String && createdByName.isNotEmpty) ||
            (createdByType is String && createdByType.isNotEmpty);

    final Map<String, dynamic> fields = {
      'last_updated_by_user_id': actor.id,
      'last_updated_by_name': actor.name,
      'last_updated_by_type': actor.type,
    };

    if (!hasCreatedBy) {
      fields['created_by_user_id'] = actor.id;
      fields['created_by_name'] = actor.name;
      fields['created_by_type'] = actor.type;
    }

    if (includeFollowedUp) {
      fields['last_followed_up_by_user_id'] = actor.id;
      fields['last_followed_up_by_name'] = actor.name;
      fields['last_followed_up_by_type'] = actor.type;
    }

    return fields;
  }

  Future<void> _migrateLocalToSupabaseIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final already = prefs.getBool(_prefsMigrationFlag) ?? false;
    if (already) return;

    final raw = prefs.getString(_prefsKeyV1);
    if (raw == null || raw.isEmpty) {
      await prefs.setBool(_prefsMigrationFlag, true);
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.setBool(_prefsMigrationFlag, true);
        return;
      }

      final List<Map<String, dynamic>> rows = [];
      for (final entry in decoded.entries) {
        final outstandingId = entry.key;
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final meta = OutstandingFollowUpMeta.fromJson(value);
        rows.add({
          'outstanding_id': outstandingId,
          ...meta.toJson(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      if (rows.isNotEmpty) {
        await _supabase
            .from('outstanding_followups')
            .upsert(rows, onConflict: 'outstanding_id');
      }

      await prefs.remove(_prefsKeyV1);
      await prefs.setBool(_prefsMigrationFlag, true);
    } catch (_) {
      await prefs.setBool(_prefsMigrationFlag, true);
    }
  }

  Future<Map<String, OutstandingFollowUpMeta>> getAll() async {
    await _migrateLocalToSupabaseIfNeeded();
    final response = await _supabase.from('outstanding_followups').select();
    final list = response as List;

    final Map<String, OutstandingFollowUpMeta> result = {};
    for (final row in list) {
      if (row is Map<String, dynamic>) {
        final outstandingId = row['outstanding_id'] as String?;
        if (outstandingId == null) continue;
        result[outstandingId] = OutstandingFollowUpMeta.fromJson(row);
      }
    }
    return result;
  }

  Future<OutstandingFollowUpMeta> getForId(String outstandingId) async {
    await _migrateLocalToSupabaseIfNeeded();
    final row = await _supabase
        .from('outstanding_followups')
        .select()
        .eq('outstanding_id', outstandingId)
        .maybeSingle();
    if (row == null) return OutstandingFollowUpMeta.empty();
    return OutstandingFollowUpMeta.fromJson(row);
  }

  Future<void> setFollowUpDate(String outstandingId, DateTime? date) async {
    await _migrateLocalToSupabaseIfNeeded();
    final actorFields =
        await _actorFieldsForUpsert(outstandingId, includeFollowedUp: false);
    await _supabase.from('outstanding_followups').upsert(
      {
        'outstanding_id': outstandingId,
        'follow_up_date': date?.toIso8601String().split('T')[0],
        ...actorFields,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'outstanding_id',
    );
  }

  Future<void> setRemark(String outstandingId, String remark) async {
    await _migrateLocalToSupabaseIfNeeded();
    final actorFields =
        await _actorFieldsForUpsert(outstandingId, includeFollowedUp: false);
    await _supabase.from('outstanding_followups').upsert(
      {
        'outstanding_id': outstandingId,
        'remark': remark.trim(),
        ...actorFields,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'outstanding_id',
    );
  }

  Future<void> setPaymentReceived(String outstandingId, bool value) async {
    await _migrateLocalToSupabaseIfNeeded();
    final now = DateTime.now();

    final actorFields =
        await _actorFieldsForUpsert(outstandingId, includeFollowedUp: false);

    DateTime? paidAt;
    if (value) {
      final current = await getForId(outstandingId);
      paidAt = current.paymentReceivedAt ?? now;
    }

    await _supabase.from('outstanding_followups').upsert(
      {
        'outstanding_id': outstandingId,
        'payment_received': value,
        'payment_received_at': value ? paidAt?.toIso8601String() : null,
        ...actorFields,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'outstanding_id',
    );
  }

  Future<void> markFollowedUp(String outstandingId, {DateTime? nextFollowUp}) async {
    await _migrateLocalToSupabaseIfNeeded();
    final current = await getForId(outstandingId);

    final actorFields =
        await _actorFieldsForUpsert(outstandingId, includeFollowedUp: true);

    final now = DateTime.now();
    final next = nextFollowUp ??
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final updatedLog = List<DateTime>.from(current.followUpLog)..add(now);

    await _supabase.from('outstanding_followups').upsert(
      {
        'outstanding_id': outstandingId,
        'last_followed_up_at': now.toIso8601String(),
        'follow_up_date': next.toIso8601String().split('T')[0],
        'follow_up_count': current.followUpCount + 1,
        'follow_up_log': updatedLog.map((d) => d.toIso8601String()).toList(),
        ...actorFields,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'outstanding_id',
    );
  }
}
