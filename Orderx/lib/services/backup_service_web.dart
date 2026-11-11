import 'dart:convert';

import 'package:Orderx/core/web_download_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BackupService {
  final SupabaseClient _client = Supabase.instance.client;

  static const List<String> _supabaseTables = [
    'users',
    'products',
    'customers',
    'sales_orders',
    'order_items',
    'notifications',
    'company_settings',
    'customer_categories',
    'item_parents',
    'category_itemgroup_discounts',
  ];

  Future<Map<String, dynamic>> _exportSupabase() async {
    final Map<String, dynamic> result = {};
    for (final table in _supabaseTables) {
      try {
        final data = await _client.from(table).select();
        result[table] = data;
      } catch (e) {
        result[table] = {'error': e.toString()};
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _exportSqlite() async {
    return {'info': 'SQLite export is not supported on Web builds.'};
  }

  Future<String> runBackup() async {
    final supabaseData = await _exportSupabase();
    final sqliteData = await _exportSqlite();

    final payload = {
      'metadata': {
        'created_at': DateTime.now().toIso8601String(),
        'format': 'orderx_backup_v1',
      },
      'supabase': supabaseData,
      'sqlite': sqliteData,
    };

    final String filename = 'vk_backup_${_timestamp()}.json';
    final String content = const JsonEncoder.withIndent('  ').convert(payload);

    await saveBackupOnWeb(content, filename);
    return filename;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
