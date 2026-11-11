import 'dart:convert';

import 'package:Orderx/core/database/database_helper.dart';
import 'package:Orderx/models/cart_item_model.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:sqflite/sqflite.dart';

class OfflineOrderQueueService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final OrderService _orderService = OrderService();
  bool _isSyncing = false;

  Future<void> enqueueOrder(Map<String, dynamic> payload) async {
    final db = await _dbHelper.database;
    await db.insert(
      'pending_orders',
      {
        'payload': jsonEncode(payload),
        'status': 'queued',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingOrdersRaw() async {
    final db = await _dbHelper.database;
    return db.query('pending_orders', orderBy: 'id ASC');
  }

  Future<int> pendingCount() async {
    final db = await _dbHelper.database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM pending_orders'),
        ) ??
        0;
    return count;
  }

  Future<void> clearOrder(int id) async {
    final db = await _dbHelper.database;
    await db.delete('pending_orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> syncPendingOrders() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final db = await _dbHelper.database;
      final rows = await db.query('pending_orders', orderBy: 'id ASC');
      for (final row in rows) {
        final id = row['id'] as int;
        final payloadJson = row['payload'] as String;
        final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
        try {
          final items = (payload['items'] as List<dynamic>)
              .map((item) => CartItem.fromJson(
                  Map<String, dynamic>.from(item as Map<String, dynamic>)))
              .toList();

          await _orderService.createOrder(
            salesmanId: payload['salesmanId'] as String,
            items: items,
            totalAmount: (payload['totalAmount'] as num).toDouble(),
            gstAmount: (payload['gstAmount'] as num).toDouble(),
            netAmount: (payload['netAmount'] as num).toDouble(),
            orderDiscountAmount:
                (payload['orderDiscountAmount'] as num).toDouble(),
            orderDiscountPercentage:
                (payload['orderDiscountPercentage'] as num).toDouble(),
            subtotalBeforeDiscount:
                (payload['subtotalBeforeDiscount'] as num).toDouble(),
            customerId: payload['customerId'] as String?,
            customerName: payload['customerName'] as String?,
            notes: payload['notes'] as String?,
            shippingAddress: payload['shippingAddress'] as String?,
            remarks: payload['remarks'] as String?,
            dispatchedThrough: payload['dispatchedThrough'] as String?,
            destination: payload['destination'] as String?,
            companyId: payload['companyId'] as String?,
            customerCategoryId: payload['customerCategoryId'] as String?,
            customerCategoryName: payload['customerCategoryName'] as String?,
            ledger: payload['ledger'] as String?,
            orderNumber: payload['orderNumber'] as String?,
          );

          await db.delete('pending_orders', where: 'id = ?', whereArgs: [id]);
        } catch (e) {
          await db.update(
            'pending_orders',
            {
              'status': 'error',
              'last_error': e.toString(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
