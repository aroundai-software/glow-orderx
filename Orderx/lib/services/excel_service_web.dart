
import 'package:Orderx/core/web_download_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart';

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

  void _writeSheet(Excel excel, String sheetName, List<Map<String, dynamic>> rows) {
    final Sheet sheet = excel[sheetName];
    if (rows.isEmpty) {
      sheet.appendRow([TextCellValue('No data')]);
      return;
    }
    final headers = _allKeys(rows);
    sheet.appendRow(headers.map<CellValue?>((h) => TextCellValue(h)).toList());
    for (final r in rows) {
      final values = headers.map<CellValue?>((k) => TextCellValue((r[k])?.toString() ?? '')).toList();
      sheet.appendRow(values);
    }
  }

  Future<String> exportExcel() async {
    final excel = Excel.createExcel();

    for (final table in _supabaseTables) {
      try {
        final data = await _fetchTable(table);
        _writeSheet(excel, table, data);
      } catch (e) {
        final Sheet sheet = excel[table];
        sheet.appendRow([TextCellValue('Error'), TextCellValue(e.toString())]);
      }
    }

    final bytes = excel.encode()!;
    final filename = 'vk_backup_${_timestamp()}.xlsx';
    await saveBytesOnWeb(bytes, filename, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    return filename;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
