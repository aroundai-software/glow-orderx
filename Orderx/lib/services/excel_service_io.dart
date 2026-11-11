import 'dart:io';

import 'package:excel/excel.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExcelExportService {
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

  Future<List<Map<String, dynamic>>> _fetchTable(String table) async {
    final resp = await _client.from(table).select();
    return (resp as List).cast<Map<String, dynamic>>();
  }

  List<String> _allKeys(List<Map<String, dynamic>> rows) {
    final keys = <String>{};
    for (final r in rows) {
      keys.addAll(r.keys);
    }
    return keys.toList();
  }

  String _safeSheetName(String raw, Set<String> used) {
    // Replace invalid characters: : \/ ? * [ ]
    var name = raw.replaceAll(RegExp(r'[:\\/\?\*\[\]]'), '_');
    if (name.isEmpty) name = 'Sheet';
    // Trim to 31 characters (Excel limit)
    if (name.length > 31) {
      name = name.substring(0, 31);
    }
    // Ensure uniqueness
    var base = name;
    var i = 2;
    while (used.contains(name)) {
      final suffix = '_$i';
      final maxBaseLen = 31 - suffix.length;
      final trimmedBase = base.length > maxBaseLen ? base.substring(0, maxBaseLen) : base;
      name = trimmedBase + suffix;
      i++;
    }
    used.add(name);
    return name;
  }

  void _writeSheet(Excel excel, String sheetName, List<Map<String, dynamic>> rows) {
    final Sheet sheet = excel[sheetName];
    
    if (rows.isEmpty) {
      // Write "No data" in cell A1
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('No data');
      return;
    }
    
    final headers = _allKeys(rows);
    
    // Write headers in first row
    for (var col = 0; col < headers.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).value = 
          TextCellValue(headers[col]);
    }
    
    // Write data rows
    for (var rowIdx = 0; rowIdx < rows.length; rowIdx++) {
      final row = rows[rowIdx];
      for (var col = 0; col < headers.length; col++) {
        final key = headers[col];
        final value = row[key];
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx + 1)).value = 
            TextCellValue(value?.toString() ?? '');
      }
    }
  }

  Future<String> exportExcel() async {
    final excel = Excel.createExcel();
    // Remove default sheet if present to avoid empty/invalid default sheet issues
    try {
      excel.delete('Sheet1');
    } catch (_) {
      // ignore if it doesn't exist
    }

    String? defaultSheet;
    final usedNames = <String>{};
    int totalRows = 0;
    
    for (final table in _supabaseTables) {
      try {
        final data = await _fetchTable(table);
        totalRows += data.length;
        print('Fetched ${data.length} rows from $table'); // Debug
        final sheetName = _safeSheetName(table, usedNames);
        _writeSheet(excel, sheetName, data);
        defaultSheet ??= sheetName;
      } catch (e) {
        print('Error fetching $table: $e'); // Debug
        final sheetName = _safeSheetName('${table}_error', usedNames);
        final Sheet sheet = excel[sheetName];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Error');
        sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(e.toString());
        defaultSheet ??= sheetName;
      }
    }

    print('Total rows exported: $totalRows'); // Debug
    
    if (defaultSheet != null) {
      excel.setDefaultSheet(defaultSheet);
    }

    // Save to Downloads directory for file manager access
    // Check storage permissions first
    var storageStatus = await Permission.storage.status;
    if (!storageStatus.isGranted) {
      storageStatus = await Permission.storage.request();
    }
    
    String fullPath;
    
    if (storageStatus.isGranted) {
      Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        // Navigate to Downloads folder
        final String downloadsPath = p.join(externalDir.path.split('Android')[0], 'Download');
        final Directory downloadsDir = Directory(downloadsPath);
        
        // Create Downloads directory if it doesn't exist
        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }
        
        final filename = 'vk_backup_${_timestamp()}.xlsx';
        fullPath = p.join(downloadsDir.path, filename);
      } else {
        // Fallback to app documents if external storage not available
        final Directory dir = await getApplicationDocumentsDirectory();
        final filename = 'vk_backup_${_timestamp()}.xlsx';
        fullPath = p.join(dir.path, filename);
      }
    } else {
      // Fallback to app documents if permission denied
      final Directory dir = await getApplicationDocumentsDirectory();
      final filename = 'vk_backup_${_timestamp()}.xlsx';
      fullPath = p.join(dir.path, filename);
    }

    final bytes = excel.encode()!;
    final file = File(fullPath);
    
    // Ensure parent directory exists
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    
    file.writeAsBytesSync(bytes);

    return file.path;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }
}
