import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/company_model.dart';

class SupabaseService {
  final _client = Supabase.instance.client;

  /// Fetch companies by invoking the Edge Function on Supabase B.
  Future<List<Company>> fetchCompanies() async {
    try {
      final res = await _client.functions.invoke('fetch-companies-from-main');
      // res.data may be List or Map depending on function. Handle both.
      if (res.data == null) {
        return [];
      }

      final dynamic raw = res.data;
      final List<dynamic> list =
          (raw is List) ? raw : (raw is Map && raw['data'] is List) ? raw['data'] as List : [raw];

      return list.map((e) => Company.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e, st) {
      debugPrint('Error fetching companies via function: $e\n$st');
      rethrow;
    }
  }

  /// Update is_active by invoking the Edge Function that patches main DB.
  Future<void> updateIsActive(String companyId, bool newValue) async {
    try {
      final res = await _client.functions.invoke(
        'update-company-status',
        body: {'id': companyId, 'new_status': newValue},
      );
      // Optionally inspect res.data or res.status.
      debugPrint('update function response: ${res.data}');
    } catch (e, st) {
      debugPrint('Error invoking update-company-status: $e\n$st');
      rethrow;
    }
  }
}
