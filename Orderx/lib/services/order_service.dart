// order_service.dart
// All order data is stored in sales_orders + order_items tables.
// OrderModel is a view over sales_orders — column mapping is handled here.

import 'package:Orderx/models/cart_item_model.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/admin_settings.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/utils/company_query.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class OrderService {
  final SupabaseClient _supabase = Supabase.instance.client;



  // ─── Column mapping ────────────────────────────────────────────────────────
  // sales_orders column  →  OrderModel field
  // order_number         →  orderNumber
  // order_date           →  orderDate
  // (no is_edited col)   →  isEdited (default false)
  // (no round_off col)   →  roundOff (default null)
  // ──────────────────────────────────────────────────────────────────────────

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value.replaceAll('+', ''));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Build an OrderModel from a sales_orders row.
  OrderModel _buildOrderModelFromJson(
    Map<String, dynamic> json, {
    String? customerMobile,
    String? customerGst,
    String? customerAddress,
    String? salesmanName,
  }) {
    DateTime? parseDateTime(dynamic value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value as String).toLocal();
      } catch (_) {
        return null;
      }
    }

    return OrderModel(
      id: json['id'] as String,
      orderNumber: (json['order_number'] ?? '') as String,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String?,
      salesmanId: json['salesman_id'] as String,
      salesmanName: salesmanName,
      orderDate: parseDateTime(json['order_date']) ?? DateTime.now(),
      subtotalBeforeDiscount:
          _parseDouble(json['subtotal_before_discount']) ?? 0.0,
      orderDiscountAmount: _parseDouble(json['discount_amount']) ?? 0.0,
      orderDiscountPercentage: _parseDouble(json['discount_percentage']) ?? 0.0,
      totalAmount: _parseDouble(json['total_amount']) ?? 0.0,
      gstAmount: _parseDouble(json['gst_amount']) ?? 0.0,
      netAmount: _parseDouble(json['net_amount']) ?? 0.0,
      roundOff: _parseDouble(json['round_off']),
      status: json['status'] as String? ?? 'approved',
      notes: json['notes'] as String?,
      syncedToTally: json['synced_to_tally'] as bool? ?? false,
      tallySyncDate: parseDateTime(json['tally_sync_date']),
      createdAt: parseDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: parseDateTime(json['updated_at']),
      customerMobile: customerMobile,
      customerAddress: customerAddress,
      customerGst: customerGst,
      shippingAddress: json['shipping_address'] as String?,
      remarks: json['remarks'] as String?,
      dispatchedThrough: json['dispatched_through'] as String?,
      destination: json['destination'] as String?,
      companyId: json['company_id'] as String?,
      companyName: json['company_name'] as String?,
      ledger: json['Type'] as String? ?? 'Credit',
      canEditUntil: parseDateTime(json['can_edit_until']),
      editRequestStatus: json['edit_request_status'] as String? ?? 'none',
      editRequestedAt: parseDateTime(json['edit_requested_at']),
      editApprovedAt: parseDateTime(json['edit_approved_at']),
      editRejectedAt: parseDateTime(json['edit_rejected_at']),
      orderLatitude: _parseDouble(json['order_latitude']),
      orderLongitude: _parseDouble(json['order_longitude']),
      orderAddress: json['order_address'] as String?,
      distanceFromCustomer: _parseDouble(json['distance_from_customer']),
    );
  }

  /// Batch fetch customer details map keyed by customer id.
  Future<Map<String, Map<String, String?>>> _fetchCustomerMap(
      Set<String> customerIds) async {
    final Map<String, Map<String, String?>> result = {};
    if (customerIds.isEmpty) return result;
    try {
      final orExpr = customerIds.map((id) => 'id.eq.$id').join(',');
      final rows = await _supabase
          .from('customers')
          .select(
              'id, mobile_number, address, city, state, pincode, gst_number')
          .or(orExpr);
      for (final c in rows as List) {
        final parts = <String>[];
        if (c['address'] != null) parts.add(c['address']);
        if (c['city'] != null) parts.add(c['city']);
        if (c['state'] != null) parts.add(c['state']);
        if (c['pincode'] != null) parts.add(c['pincode']);
        result[c['id'] as String] = {
          'mobile': c['mobile_number'] as String?,
          'gst': c['gst_number'] as String?,
          'address': parts.isNotEmpty ? parts.join(', ') : null,
        };
      }
    } catch (_) {}
    return result;
  }

  // ─── READ ─────────────────────────────────────────────────────────────────

  /// Get all orders created by a salesman (reads from sales_orders).
  Future<List<OrderModel>> getOrdersBySalesman(String salesmanId,
      {String? companyId}) async {
    try {
      print(
          '🔍 getOrdersBySalesman - salesmanId: $salesmanId, companyId: $companyId');
      dynamic query =
          _supabase.from('sales_orders').select().eq('salesman_id', salesmanId);

      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      query = query.order('created_at', ascending: false);

      final List data = await query as List;
      print('🔍 getOrdersBySalesman - fetched ${data.length} orders');
      final customerIds = {
        for (final row in data)
          if (row['customer_id'] != null &&
              row['customer_id'].toString().isNotEmpty)
            row['customer_id'] as String,
      };
      final customerMap = await _fetchCustomerMap(customerIds);

      return data.map((json) {
        final cid = json['customer_id'] as String?;
        final details = cid != null ? customerMap[cid] : null;
        return _buildOrderModelFromJson(
          json as Map<String, dynamic>,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
        );
      }).toList();
    } catch (e) {
      print('Error fetching orders: $e');
      return [];
    }
  }

  /// Get all orders (admin view, reads from sales_orders).
  Future<List<OrderModel>> getAllOrders({String? companyId}) async {
    try {
      dynamic query = _supabase.from('sales_orders').select();

      if (companyId != null && companyId != 'ALL') {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      query = query.order('order_date', ascending: false);

      final List data = await query as List;

      final customerIds = {
        for (final row in data)
          if (row['customer_id'] != null &&
              row['customer_id'].toString().isNotEmpty)
            row['customer_id'] as String,
      };
      final customerMap = await _fetchCustomerMap(customerIds);

      // Batch fetch salesman names
      final salesmanIds = {
        for (final row in data)
          if (row['salesman_id'] != null &&
              row['salesman_id'].toString().isNotEmpty)
            row['salesman_id'] as String,
      };
      final Map<String, String> salesmanNameMap = {};
      if (salesmanIds.isNotEmpty) {
        try {
          final orExpr = salesmanIds.map((id) => 'id.eq.$id').join(',');
          final rows =
              await _supabase.from('users').select('id, name').or(orExpr);
          for (final s in rows as List) {
            if (s['name'] != null) {
              salesmanNameMap[s['id'] as String] = s['name'] as String;
            }
          }
        } catch (_) {}
      }

      return data.map((json) {
        final cid = json['customer_id'] as String?;
        final sid = json['salesman_id'] as String?;
        final details = cid != null ? customerMap[cid] : null;
        return _buildOrderModelFromJson(
          json as Map<String, dynamic>,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
          salesmanName: sid != null ? salesmanNameMap[sid] : null,
        );
      }).toList();
    } catch (e) {
      print('Error fetching all orders: $e');
      return [];
    }
  }

  /// Get orders with filters for admin screen.
  Future<List<OrderModel>> getOrdersWithFilters({
    String? companyId,
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    String? itemName,
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
  }) async {
    try {
      print(
          '🔍 getOrdersWithFilters - companyId: $companyId, page: $page, searchQuery: $searchQuery');
      dynamic query = _supabase.from('sales_orders').select();

      if (companyId != null && companyId != 'ALL') {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      if (startDate != null) {
        query = query.gte('order_date', startDate.toIso8601String());
      }

      if (endDate != null) {
        query = query.lte('order_date', endDate.toIso8601String());
      }

      if (minAmount != null) {
        query = query.gte('net_amount', minAmount);
      }

      if (maxAmount != null) {
        query = query.lte('net_amount', maxAmount);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
            'order_number.ilike.%$searchQuery%,customer_name.ilike.%$searchQuery%');
      }

      query = query.order('created_at', ascending: false);

      final offset = (page - 1) * pageSize;
      query = query.range(offset, offset + pageSize - 1);

      final List data = await query as List;
      print('🔍 getOrdersWithFilters - fetched ${data.length} orders');

      final customerIds = {
        for (final row in data)
          if (row['customer_id'] != null &&
              row['customer_id'].toString().isNotEmpty)
            row['customer_id'] as String,
      };
      final customerMap = await _fetchCustomerMap(customerIds);

      // Batch fetch salesman names
      final salesmanIds = {
        for (final row in data)
          if (row['salesman_id'] != null &&
              row['salesman_id'].toString().isNotEmpty)
            row['salesman_id'] as String,
      };
      final Map<String, String> salesmanNameMap = {};
      if (salesmanIds.isNotEmpty) {
        try {
          final orExpr = salesmanIds.map((id) => 'id.eq.$id').join(',');
          final rows =
              await _supabase.from('users').select('id, name').or(orExpr);
          for (final s in rows as List) {
            if (s['name'] != null) {
              salesmanNameMap[s['id'] as String] = s['name'] as String;
            }
          }
        } catch (_) {}
      }

      return data.map((json) {
        final cid = json['customer_id'] as String?;
        final sid = json['salesman_id'] as String?;
        final details = cid != null ? customerMap[cid] : null;
        return _buildOrderModelFromJson(
          json as Map<String, dynamic>,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
          salesmanName: sid != null ? salesmanNameMap[sid] : null,
        );
      }).toList();
    } catch (e) {
      print('Error fetching orders with filters: $e');
      return [];
    }
  }

  /// Get order by ID.
  Future<OrderModel?> getOrderById(String orderId) async {
    try {
      final response = await _supabase
          .from('sales_orders')
          .select()
          .eq('id', orderId)
          .maybeSingle();

      if (response == null) return null;

      final json = response as Map<String, dynamic>;
      final customerId = json['customer_id'] as String?;

      Map<String, String?>? customerDetails;
      if (customerId != null) {
        final customerMap = await _fetchCustomerMap({customerId});
        customerDetails = customerMap[customerId];
      }

      return _buildOrderModelFromJson(
        json,
        customerMobile: customerDetails?['mobile'],
        customerGst: customerDetails?['gst'],
        customerAddress: customerDetails?['address'],
      );
    } catch (e) {
      print('Error fetching order by ID: $e');
      return null;
    }
  }

  /// Get items for an order (reads from order_items using order_id).
  Future<List<OrderItemModel>> getOrderItems(String orderId) async {
    try {
      final response =
          await _supabase.from('order_items').select().eq('order_id', orderId);

      final items = response as List;
      if (items.isEmpty) return [];

      // Fetch product data for vt_number, mrp, hsn
      final productIds = items
          .map((item) => item['product_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .cast<String>()
          .toList();

      final Map<String, Map<String, dynamic>> productMap = {};
      for (final pid in productIds) {
        try {
          final p = await _supabase
              .from('products')
              .select('id, ItemAlias1, MRP, hsn')
              .eq('id', pid)
              .maybeSingle();
          if (p != null) productMap[pid] = p;
        } catch (_) {}
      }

      return items.map((json) {
        final modifiedJson = Map<String, dynamic>.from(json as Map);

        final productId = json['product_id']?.toString();
        if (productId != null && productMap.containsKey(productId)) {
          final p = productMap[productId]!;
          modifiedJson['vtNumber'] = p['ItemAlias1'];
          modifiedJson['mrp'] = p['MRP'];
          modifiedJson['hsn'] = modifiedJson['hsn'] ?? p['hsn'];
        }

        // Compute discount sub-types
        final unitPrice = _parseDouble(json['unit_price']) ?? 0.0;
        final quantity = (json['quantity'] as num?)?.toDouble() ?? 0.0;
        final catDiscPct =
            _parseDouble(json['category_discount_percentage']) ?? 0.0;
        modifiedJson['cash_discount_amount'] =
            unitPrice * catDiscPct / 100 * quantity;
        modifiedJson['order_discount_amount'] =
            _parseDouble(json['discount_amount']) ?? 0.0;
        modifiedJson['item_discount_amount'] = 0.0;
        modifiedJson['offer_discount_amount'] = 0.0;

        return OrderItemModel.fromJson(modifiedJson);
      }).toList();
    } catch (e) {
      print('Error fetching order items: $e');
      return [];
    }
  }

  // ─── STATS ────────────────────────────────────────────────────────────────

  /// Today's order count and total amount for the dashboard.
  Future<Map<String, dynamic>> getTodayStats(String salesmanId,
      {String? companyId}) async {
    try {
      print(
          '📊 getTodayStats - salesmanId: $salesmanId, companyId: $companyId');
      final nowUtc = DateTime.now().toUtc();
      final startOfDayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
      final endOfDayUtc = startOfDayUtc.add(const Duration(days: 1));

      dynamic query = _supabase
          .from('sales_orders')
          .select('id, net_amount')
          .eq('salesman_id', salesmanId)
          .gte('created_at', startOfDayUtc.toIso8601String())
          .lt('created_at', endOfDayUtc.toIso8601String());

      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      final List data = await query as List;
      print('📊 getTodayStats - fetched ${data.length} orders');
      double todayAmount = 0.0;
      for (final row in data) {
        todayAmount += (row['net_amount'] as num?)?.toDouble() ?? 0.0;
      }

      return {
        'todayOrders': data.length,
        'todayAmount': todayAmount,
      };
    } catch (e) {
      print('❌ Error getting today stats: $e');
      return {'todayOrders': 0, 'todayAmount': 0.0};
    }
  }

  // ─── CREATE ───────────────────────────────────────────────────────────────

  /// Generate order number in format ORDYEARNUMBER (e.g., ORD2024001)
  Future<String> _generateOrderNumber({String? gstNumber}) async {
    final now = DateTime.now().toLocal();
    final year = now.year;
    final prefix = 'ORD$year';

    int nextSeq = 1;
    try {
      final response = await _supabase
          .from('sales_orders')
          .select('id')
          .like('order_number', '$prefix%')
          .count(CountOption.exact);
      nextSeq = response.count + 1;
    } catch (e) {
      nextSeq = now.millisecondsSinceEpoch % 10000;
    }

    return '$prefix${nextSeq.toString().padLeft(4, '0')}';
  }

  /// Create order — inserts into sales_orders + order_items.
  Future<String> createOrder({
    required String salesmanId,
    required List<CartItem> items,
    required double totalAmount,
    required double gstAmount,
    required double netAmount,
    required double orderDiscountAmount,
    required double orderDiscountPercentage,
    required double subtotalBeforeDiscount,
    String? customerId,
    String? customerName,
    String? customerGst,
    String? notes,
    String? shippingAddress,
    String? remarks,
    String? dispatchedThrough,
    String? destination,
    String? companyId,
    String? customerCategoryId,
    String? customerCategoryName,
    String? ledger,
    String? orderNumber,
  }) async {
    try {
      final adminService = AdminSettingsService();
      final globalGstRate = await adminService.getGlobalGstRate(companyId!);

      print('📝 createOrder - salesmanId: $salesmanId, companyId: $companyId');
      final RoundOffResult roundOffResult = calculateRoundOff(netAmount);
      final now = DateTime.now().toUtc().toIso8601String();

      String? finalCategoryId = customerCategoryId;
      String? finalCategoryName = customerCategoryName;
      String? customerGstNumber = customerGst;

      if (customerId != null) {
        try {
          final customerResponse = await _supabase
              .from('customers')
              .select(
                  'customer_category_id, gst_number, customer_categories(category_name)')
              .eq('id', customerId)
              .maybeSingle();

          if (customerResponse != null) {
            customerGstNumber = customerResponse['gst_number'] as String?;
            finalCategoryId ??=
                customerResponse['customer_category_id'] as String?;
            if (finalCategoryName == null) {
              final cat = customerResponse['customer_categories'];
              finalCategoryName = (cat?['category_name'] as String?)?.trim();
            }
          }
        } catch (_) {}
      }

      String? guid;
      String? companyName;
      if (companyId != null) {
        try {
          final companyResponse = await _supabase
              .from('tally_companies')
              .select('Guid, company_name')
              .eq('id', companyId)
              .single();
          guid = companyResponse['Guid'] as String?;
          companyName = companyResponse['company_name'] as String?;
        } catch (_) {
          guid = const Uuid().v4();
        }
      } else {
        guid = const Uuid().v4();
      }

      final finalOrderNumber = orderNumber ??
          await _generateOrderNumber(gstNumber: customerGstNumber);

      final orderData = {
        'Guid': guid,
        'order_number': finalOrderNumber,
        'salesman_id': salesmanId,
        'customer_id': customerId,
        'customer_name': customerName ?? 'Walk-in Customer',
        'customer_category_id': finalCategoryId,
        'customer_category_name': finalCategoryName,
        'order_date': now,
        'subtotal_before_discount': subtotalBeforeDiscount,
        'discount_amount': orderDiscountAmount,
        'discount_percentage': orderDiscountPercentage,
        'total_amount': totalAmount,
        'gst_amount': gstAmount,
        'net_amount': roundOffResult.roundedTotal,
        'status': 'approved',
        'notes': notes ?? '',
        'remarks': remarks ?? '',
        'dispatched_through': dispatchedThrough,
        'destination': destination,
        'synced_to_tally': false,
        'created_at': now,
        'edit_request_status': 'none',
        'shipping_address': shippingAddress,
        'company_id': companyId,
        'company_name': companyName,
        'Type': ledger ?? 'Credit',
      };

      print(
          '💾 Saving order with company_id: $companyId, salesman_id: $salesmanId');
      final orderResponse = await _supabase
          .from('sales_orders')
          .insert(orderData)
          .select()
          .single();
      print(
          '✅ Order saved with ID: ${orderResponse['id']}, company_id: ${orderResponse['company_id']}');

      final orderId = orderResponse['id'] as String;

      // Insert order items
      final orderItems = items.map((item) {
        final manualDiscPct = item.manualDiscountPercentage ?? 0.0;
        final catDiscPct = item.categoryDiscountPercentage ?? 0.0;
        final basePrice = item.effectivePrice;
        final afterAuto = basePrice - (basePrice * catDiscPct / 100);
        final manualDiscAmt = manualDiscPct > 0
            ? (afterAuto * manualDiscPct / 100) * item.quantity
            : 0.0;

        return {
          'Guid': const Uuid().v4(),
          'order_id': orderId,
          'product_id': item.product.id,
          'product_name': item.product.productName,
          'product_code': item.product.productCode ?? '',
          'quantity': item.quantity.round(),
          'unit_price': item.effectivePrice,
          'gst_rate': item.product.gstRate,
          'discount_percentage': manualDiscPct,
          'category_discount_percentage': catDiscPct,
          'discount_amount': manualDiscAmt,
          'cash_discount_amount': 0.0,
          'offer_discount_amount': 0.0,
          'item_discount_amount': 0.0,
          'order_discount_amount': 0.0,
          'mrp': item.product.mrp ?? item.product.price,
          'gst_amount': item.subtotal * (item.product.gstRate / 100),
          'total_amount': item.subtotal + (item.subtotal * (item.product.gstRate / 100)),
        };
      }).toList();

      await _supabase.from('order_items').insert(orderItems);

      // Reduce stock
      try {
        print('📦 Starting stock reduction for ${items.length} items');
        for (final item in items) {
          try {
            print(
                '📦 Reducing stock for product ${item.product.id} (${item.product.productName}) by ${item.quantity.round()}');
            await _reduceProductStock(item.product.id, item.quantity.round(), salesmanId: salesmanId);
            print('✅ Stock reduced for ${item.product.productName}');
          } catch (e) {
            print('❌ Error reducing stock for ${item.product.id}: $e');
          }
        }
      } catch (e) {
        print('❌ Error in stock reduction loop: $e');
      }

      return orderResponse['order_number'] as String;
    } catch (e) {
      print('Error creating order: $e');
      rethrow;
    }
  }

  // ─── UPDATE ───────────────────────────────────────────────────────────────

  /// Update order — updates sales_orders + replaces order_items.
  Future<void> updateOrder({
    required String orderId,
    required List<OrderItemModel> items,
    required double totalAmount,
    required double gstAmount,
    required double netAmount,
    double orderDiscountPercentage = 0.0,
    double orderDiscountAmount = 0.0,
    String? notes,
    String? shippingAddress,
    String? remarks,
    String? companyId,
  }) async {
    try {
      final adminService = AdminSettingsService();
      final globalGstRate = await adminService.getGlobalGstRate(companyId!);
      final RoundOffResult roundOffResult = calculateRoundOff(netAmount);

      // Fetch old items before deletion to adjust stock
      final oldItemsData = await _supabase
          .from('order_items')
          .select('product_id, quantity')
          .eq('order_id', orderId);

      // Build map of old quantities
      final oldQuantities = <String, int>{};
      for (final item in oldItemsData) {
        oldQuantities[item['product_id'] as String] =
            (item['quantity'] as num).toInt();
      }

      final updateData = <String, dynamic>{
        'subtotal_before_discount': totalAmount,
        // total_amount = subtotal after discount (before GST)
        'total_amount': totalAmount - orderDiscountAmount,
        'gst_amount': gstAmount,
        'net_amount': roundOffResult.roundedTotal,
        'discount_percentage': orderDiscountPercentage,
        'discount_amount': orderDiscountAmount,
        'notes': notes ?? '',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'edit_request_status': 'none',
        'can_edit_until': null,
        'edit_requested_at': null,
        'edit_approved_at': null,
      };

      if (shippingAddress != null) {
        updateData['shipping_address'] = shippingAddress;
      }
      if (remarks != null) {
        updateData['remarks'] = remarks;
      }

      // Mark as edited so the Tally exe will overwrite this SO on the next sync
      updateData['is_edited'] = true;
      updateData['alter_id'] = const Uuid().v4();

      await _updateSalesOrderHeader(orderId, updateData);

      await _supabase.from('order_items').delete().eq('order_id', orderId);

      if (items.isNotEmpty) {
        final itemsList = items.map((item) {
          return {
            'order_id': orderId,
            'product_id': item.productId,
            'product_name': item.ItemName,
            'product_code': item.PartNumber ?? '',
            'quantity': item.ItemQuantity.round(),
            'unit_price': item.ItemRate,
            'gst_rate': globalGstRate,
            'gst_amount': (item.totalAmount - item.gstAmount) * (globalGstRate / 100),
            'total_amount': (item.totalAmount - item.gstAmount) + ((item.totalAmount - item.gstAmount) * (globalGstRate / 100)),
            'discount_percentage': item.discountPercentage,
            'category_discount_percentage': 0.0,
            'discount_amount': item.discountAmount,
            'cash_discount_amount': item.cashDiscountAmount,
            'offer_discount_amount': item.offerDiscountAmount,
            'item_discount_amount': item.itemDiscountAmount,
            'order_discount_amount': item.orderDiscountAmount,
            'mrp': item.mrp ?? item.ItemRate,
            if (companyId != null) 'company_id': companyId,
          };
        }).toList();

        await _supabase.from('order_items').insert(itemsList);

        // Adjust stock based on quantity changes
        for (final item in items) {
          final oldQty = oldQuantities[item.productId] ?? 0;
          final newQty = item.ItemQuantity.round();
          final diff = newQty - oldQty;

          if (diff > 0) {
            // Quantity increased - reduce stock
            await _reduceProductStock(item.productId, diff);
          } else if (diff < 0) {
            // Quantity decreased - restore stock
            await _increaseProductStock(item.productId, diff.abs());
          }
        }

        // Handle removed items - restore their stock
        for (final entry in oldQuantities.entries) {
          final productId = entry.key;
          final oldQty = entry.value;
          final stillExists = items.any((item) => item.productId == productId);

          if (!stillExists && oldQty > 0) {
            await _increaseProductStock(productId, oldQty);
          }
        }
      }
    } catch (e) {
      print('❌ Error updating order: $e');
      rethrow;
    }
  }

  // ─── DELETE ───────────────────────────────────────────────────────────────

  /// Delete order — deletes from sales_orders (order_items cascade via FK).
  Future<void> deleteOrder(String orderId) async {
    try {
      await _supabase.from('order_items').delete().eq('order_id', orderId);
      await _supabase.from('sales_orders').delete().eq('id', orderId);
    } catch (e) {
      print('❌ Error deleting order: $e');
      rethrow;
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────

  /// Updates the sales_orders header. If alter_id / is_edited columns are not
  /// in the database yet, retries without them so editing still works.
  Future<void> _updateSalesOrderHeader(
      String orderId, Map<String, dynamic> updateData) async {
    try {
      await _supabase.from('sales_orders').update(updateData).eq('id', orderId);
    } catch (e) {
      final err = e.toString();
      if (err.contains('PGRST204') &&
          (updateData.containsKey('alter_id') ||
              updateData.containsKey('is_edited'))) {
        print(
            'Warning: alter_id/is_edited columns missing on sales_orders. Run migration 008.');
        updateData.remove('alter_id');
        updateData.remove('is_edited');
        await _supabase
            .from('sales_orders')
            .update(updateData)
            .eq('id', orderId);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _reduceProductStock(String productId, int quantity, {String? salesmanId}) async {
    try {
      print('📦 _reduceProductStock: productId=$productId, quantity=$quantity, salesmanId=$salesmanId');
      final response = await _supabase
          .from('products')
          .select('ItemQuantity, ItemName, company_id')
          .eq('id', productId)
          .single();
      final currentStock = (response['ItemQuantity'] as num?)?.toInt() ?? 0;
      final productName = response['ItemName'] as String?;
      final companyId = response['company_id'] as String?;
      print('📦 Current stock: $currentStock');
      final newStock = (currentStock - quantity).clamp(0, 999999);
      print('📦 New stock after reduction: $newStock');
      await _supabase
          .from('products')
          .update({'ItemQuantity': newStock}).eq('id', productId);
      print('✅ Stock updated in database');

      // Check if stock is now low or out of stock and send notification
      if (newStock == 0 && currentStock > 0) {
        // Stock became out of stock
        await _sendStockNotification(
          productId: productId,
          productName: productName ?? 'Unknown Product',
          stockLevel: newStock,
          notificationType: 'out_of_stock',
          companyId: companyId,
          salesmanId: salesmanId,
        );
      } else if (newStock <= 10 && currentStock > 10) {
        // Stock became low (threshold: 10)
        await _sendStockNotification(
          productId: productId,
          productName: productName ?? 'Unknown Product',
          stockLevel: newStock,
          notificationType: 'low_stock',
          companyId: companyId,
          salesmanId: salesmanId,
        );
      }
    } catch (e) {
      print('❌ Error in _reduceProductStock: $e');
    }
  }

  Future<void> _increaseProductStock(String productId, int quantity) async {
    try {
      final response = await _supabase
          .from('products')
          .select('ItemQuantity')
          .eq('id', productId)
          .single();
      final currentStock = (response['ItemQuantity'] as num?)?.toInt() ?? 0;
      final newStock = currentStock + quantity;
      await _supabase
          .from('products')
          .update({'ItemQuantity': newStock}).eq('id', productId);
    } catch (_) {}
  }

  Future<void> _sendStockNotification({
    required String productId,
    required String productName,
    required int stockLevel,
    required String notificationType,
    String? companyId,
    String? salesmanId,
  }) async {
    try {
      // Resolve the current user from Supabase auth if salesmanId is not provided
      String finalSalesmanId = salesmanId ?? '';
      if (finalSalesmanId.isEmpty) {
        final authUser = _supabase.auth.currentUser;
        if (authUser == null) {
          print('⚠️ _sendStockNotification: no auth user, skipping');
          return;
        }
        finalSalesmanId = authUser.id;
      }

      // Resolve salesman name from the custom users table
      String salesmanName = 'Salesman';
      try {
        final userRow = await _supabase
            .from('users')
            .select('name')
            .eq('id', finalSalesmanId)
            .maybeSingle();
        if (userRow != null && userRow['name'] != null) {
          salesmanName = userRow['name'] as String;
        }
      } catch (_) {}

      // Dedup: skip if an identical alert was already sent within the last 24 hours
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 24))
          .toIso8601String();

      final existing = await _supabase
          .from('notifications')
          .select('id')
          .eq('product_id', productId)
          .eq('type', notificationType)
          .gte('created_at', since)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        print(
            'ℹ️ Stock notification for $productName already sent within 24 h — skipping');
        return;
      }

      final title = notificationType == 'out_of_stock'
          ? 'Out of Stock Alert'
          : 'Low Stock Alert';
      final message = notificationType == 'out_of_stock'
          ? '$productName is out of stock'
          : '$productName is running low (Stock: $stockLevel)';

      await _supabase.from('notifications').insert({
        'type': notificationType,
        'title': title,
        'message': message,
        'product_id': productId,
        'product_name': productName,
        'current_stock': stockLevel,
        'salesman_id': finalSalesmanId,
        'salesman_name': salesmanName,
        'company_id': companyId,
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      print(
          '✅ Auto stock notification sent: $title — $productName (stock: $stockLevel)');
    } catch (e) {
      print('❌ Error sending stock notification: $e');
    }
  }
}
