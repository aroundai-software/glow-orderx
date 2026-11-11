import 'dart:convert';
import 'dart:io';

import 'package:Orderx/core/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
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
    final Database db = await DatabaseHelper().database;
    final List<Map<String, dynamic>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;",
    );
    final Map<String, dynamic> result = {};
    for (final t in tables) {
      final name = t['name'] as String;
      try {
        final rows = await db.rawQuery('SELECT * FROM $name');
        result[name] = rows;
      } catch (e) {
        result[name] = {'error': e.toString()};
      }
    }
    return result;
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

    // Try multiple approaches to save to Downloads
    String? savedPath = await _tryMultipleDownloadsPaths(content, filename);

    if (savedPath != null) {
      return savedPath;
    }

    // If all Downloads attempts fail, save to external storage root
    try {
      Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        // Navigate up to the root storage directory
        List<String> pathParts = externalDir.path.split('/');
        int androidIndex = pathParts.indexOf('Android');
        if (androidIndex > 0) {
          String rootPath = pathParts.sublist(0, androidIndex).join('/');
          final String fullPath = p.join(rootPath, filename);
          final file = File(fullPath);
          await file.writeAsString(content);

          if (await file.exists()) {
            return fullPath;
          }
        }
      }
    } catch (e) {
      // Continue to final fallback
    }

    // Final fallback to app documents directory
    final Directory dir = await getApplicationDocumentsDirectory();
    final String fullPath = p.join(dir.path, filename);
    final file = File(fullPath);
    await file.writeAsString(content);
    return fullPath;
  }

  Future<String?> _tryMultipleDownloadsPaths(
    String content,
    String filename,
  ) async {
    // Request storage permissions
    var storageStatus = await Permission.storage.request();

    // For Android 11+, also request manage external storage
    if (!storageStatus.isGranted) {
      try {
        var manageStorageStatus = await Permission.manageExternalStorage
            .request();
        if (manageStorageStatus.isGranted) {
          storageStatus = PermissionStatus.granted;
        }
      } catch (e) {
        // Permission not available on this device
      }
    }

    if (!storageStatus.isGranted) {
      return null;
    }

    // Try multiple Downloads paths
    final List<String> downloadsPaths = [
      '/storage/emulated/0/Download',
      '/sdcard/Download',
      '/storage/self/primary/Download',
      '/mnt/sdcard/Download',
    ];

    for (String downloadsPath in downloadsPaths) {
      try {
        final Directory downloadsDir = Directory(downloadsPath);

        // Try to create directory
        if (!downloadsDir.existsSync()) {
          await downloadsDir.create(recursive: true);
        }

        // Check if directory is accessible
        if (downloadsDir.existsSync()) {
          final String fullPath = p.join(downloadsPath, filename);
          final file = File(fullPath);
          await file.writeAsString(content);

          // Verify file was created and is accessible
          if (await file.exists()) {
            return fullPath;
          }
        }
      } catch (e) {
        // Try next path
        continue;
      }
    }

    return null;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
