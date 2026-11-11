// invoice_service.dart
// All invoice data is stored in sales_orders + order_items tables.
// InvoiceModel is a view over sales_orders — column mapping is handled here.

import 'package:Orderx/models/cart_item_model.dart';
import 'package:Orderx/models/invoice_model.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/utils/company_query.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// Low-stock threshold (matches the value in product_model.dart & stock_level_screen.dart)
const int _kLowStockThreshold = 10;

class InvoiceService {
  final SupabaseClient _supabase = Supabase.instance.client;



  // ─── Column mapping ────────────────────────────────────────────────────────
  // sales_orders column  →  InvoiceModel field
  // order_number         →  invoiceNumber
  // order_date           →  invoiceDate
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

  /// Build an InvoiceModel from a sales_orders row.
  InvoiceModel _buildInvoiceModelFromJson(
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

    return InvoiceModel(
      id: json['id'] as String,
      // sales_orders uses order_number
      invoiceNumber:
          (json['order_number'] ?? json['invoice_number'] ?? '') as String,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String?,
      salesmanId: json['salesman_id'] as String,
      salesmanName: salesmanName,
      // sales_orders uses order_date
      invoiceDate: parseDateTime(json['order_date'] ?? json['invoice_date']) ??
          DateTime.now(),
      subtotalBeforeDiscount:
          _parseDouble(json['subtotal_before_discount']) ?? 0.0,
      invoiceDiscountAmount: _parseDouble(json['discount_amount']) ?? 0.0,
      invoiceDiscountPercentage:
          _parseDouble(json['discount_percentage']) ?? 0.0,
      totalAmount: _parseDouble(json['total_amount']) ?? 0.0,
      gstAmount: _parseDouble(json['gst_amount']) ?? 0.0,
      netAmount: _parseDouble(json['net_amount']) ?? 0.0,
      roundOff: null, // not in sales_orders
      status: json['status'] as String? ?? 'approved',
      notes: json['notes'] as String?,
      syncedToTally: json['synced_to_tally'] as bool? ?? false,
      tallySyncDate: parseDateTime(json['tally_sync_date']),
      createdAt: parseDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: parseDateTime(json['updated_at']),
      isEdited: json['is_edited'] as bool? ?? false,
      customerMobile: customerMobile,
      customerAddress: customerAddress,
      customerGst: customerGst,
      shippingAddress: json['shipping_address'] as String?,
      remarks: json['remarks'] as String?,
      companyId: json['company_id'] as String?,
      companyName: json['company_name'] as String?,
      ledger: json['Type'] as String? ?? 'Credit',
      canEditUntil: parseDateTime(json['can_edit_until']),
      editRequestStatus: json['edit_request_status'] as String? ?? 'none',
      editRequestedAt: parseDateTime(json['edit_requested_at']),
      editApprovedAt: parseDateTime(json['edit_approved_at']),
      editRejectedAt: parseDateTime(json['edit_rejected_at']),
      invoiceLatitude: _parseDouble(json['order_latitude']),
      invoiceLongitude: _parseDouble(json['order_longitude']),
      invoiceAddress: json['order_address'] as String?,
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

  /// Get all invoices created by a salesman (reads from sales_orders).
  Future<List<InvoiceModel>> getInvoicesBySalesman(String salesmanId,
      {String? companyId}) async {
    try {
      dynamic query =
          _supabase.from('sales_orders').select().eq('salesman_id', salesmanId);

      if (companyId != null && companyId.isNotEmpty) {
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

      return data.map((json) {
        final cid = json['customer_id'] as String?;
        final details = cid != null ? customerMap[cid] : null;
        return _buildInvoiceModelFromJson(
          json as Map<String, dynamic>,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
        );
      }).toList();
    } catch (e) {
      print('Error fetching invoices: $e');
      return [];
    }
  }

  /// Get all invoices (admin view, reads from sales_orders).
  Future<List<InvoiceModel>> getAllInvoices({String? companyId}) async {
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
        return _buildInvoiceModelFromJson(
          json as Map<String, dynamic>,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
          salesmanName: sid != null ? salesmanNameMap[sid] : null,
        );
      }).toList();
    } catch (e) {
      print('Error fetching all invoices: $e');
      return [];
    }
  }

  /// Get invoices synced from Tally for a salesman by checking the sale_bill table.
  Future<List<InvoiceModel>> getTallySyncedInvoicesBySalesman(
    String salesmanId, {
    String? companyId,
  }) async {
    try {
      // 1. Fetch all orders for this salesman
      dynamic query = _supabase
          .from('sales_orders')
          .select()
          .eq('salesman_id', salesmanId);

      if (companyId != null && companyId != 'ALL') {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      query = query.order('order_date', ascending: false);
      final List data = await query as List;

      if (data.isEmpty) return [];

      // 2. Extract order numbers to find corresponding bills
      final orderNumbers = data
          .map((row) => row['order_number']?.toString())
          .where((num) => num != null && num.isNotEmpty)
          .toList();

      // 3. Query sale_bill table in chunks to avoid URL length limits
      final List<dynamic> saleBillsList = [];
      const chunkSize = 200;
      for (var i = 0; i < orderNumbers.length; i += chunkSize) {
        final end = (i + chunkSize < orderNumbers.length)
            ? i + chunkSize
            : orderNumbers.length;
        final chunk = orderNumbers.sublist(i, end);

        final response = await _supabase
            .from('sale_bill')
            .select()
            .inFilter('order_number', chunk);
        
        saleBillsList.addAll(response as List);
      }

      // Map bills by order number for quick lookup
      final Map<String, dynamic> saleBillMap = {};
      for (final bill in saleBillsList) {
        saleBillMap[bill['order_number']] = bill;
      }

      // 4. Filter original data to ONLY those that have a generated sale_bill
      final filteredData = data
          .where((row) => saleBillMap.containsKey(row['order_number']))
          .toList();

      // 5. Fetch customer details
      final customerIds = {
        for (final row in filteredData)
          if (row['customer_id'] != null &&
              row['customer_id'].toString().isNotEmpty)
            row['customer_id'] as String,
      };
      final customerMap = await _fetchCustomerMap(customerIds);

      // 6. Combine and map to InvoiceModel
      return filteredData.map((json) {
        final mutableJson = Map<String, dynamic>.from(json as Map);
        final cid = mutableJson['customer_id'] as String?;
        final details = cid != null ? customerMap[cid] : null;

        final orderNumber = mutableJson['order_number'] as String;
        final bill = saleBillMap[orderNumber];

        if (bill != null) {
          // Override order details with the actual bill details
          mutableJson['invoice_number'] = bill['invoice_number'] ?? orderNumber;
          mutableJson['invoice_date'] = bill['date'] ?? mutableJson['order_date'];
          mutableJson['status'] = bill['status'] ?? mutableJson['status'];
          mutableJson['synced_to_tally'] = true;
          mutableJson['tally_sync_date'] = bill['created_at'] ?? bill['updated_at'];
        }

        return _buildInvoiceModelFromJson(
          mutableJson,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
        );
      }).toList();
    } catch (e) {
      print('Error fetching Tally-synced invoices: $e');
      return [];
    }
  }

  /// Returns true if a sale_bill record exists for the given order_number.
  /// Used to authoritatively block editing even when synced_to_tally flag is stale.
  Future<bool> checkOrderBilledInTally(String orderNumber) async {
    try {
      final result = await _supabase
          .from('sale_bill')
          .select('id')
          .eq('order_number', orderNumber)
          .limit(1);
      return (result as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Get items for an invoice (reads from order_items using order_id).
  Future<List<InvoiceItemModel>> getInvoiceItems(String invoiceId) async {
    try {
      final response = await _supabase
          .from('order_items')
          .select()
          .eq('order_id', invoiceId);

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
        // Map order_items columns → InvoiceItemModel fields
        modifiedJson['invoice_id'] = modifiedJson['order_id'];

        final productId = json['product_id']?.toString();
        if (productId != null && productMap.containsKey(productId)) {
          final p = productMap[productId]!;
          modifiedJson['vt_number'] = p['ItemAlias1'];
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

        return InvoiceItemModel.fromJson(modifiedJson);
      }).toList();
    } catch (e) {
      print('Error fetching invoice items: $e');
      return [];
    }
  }

  // ─── STATS ────────────────────────────────────────────────────────────────

  /// Today's invoice count and total amount for the dashboard.
  Future<Map<String, dynamic>> getTodayStats(String salesmanId,
      {String? companyId}) async {
    try {
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
      double todayAmount = 0.0;
      for (final row in data) {
        todayAmount += (row['net_amount'] as num?)?.toDouble() ?? 0.0;
      }

      return {
        'todayInvoices': data.length,
        'todayAmount': todayAmount,
      };
    } catch (e) {
      print('❌ Error getting today stats: $e');
      return {'todayInvoices': 0, 'todayAmount': 0.0};
    }
  }

  // ─── CREATE ───────────────────────────────────────────────────────────────

  /// Generate order number (reuses the same format as OrderService).
  Future<String> _generateOrderNumber({String? gstNumber}) async {
    final now = DateTime.now().toLocal();
    final year = now.year;
    final month = now.month;
    String fy;
    if (month >= 4) {
      fy =
          "${year.toString().substring(2)}-${(year + 1).toString().substring(2)}";
    } else {
      fy =
          "${(year - 1).toString().substring(2)}-${year.toString().substring(2)}";
    }

    final hasGst = gstNumber != null && gstNumber.trim().isNotEmpty;
    final prefix = hasGst ? 'B' : 'UX';

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

    return '$prefix${nextSeq.toString().padLeft(4, '0')}/$fy';
  }

  /// Create invoice — inserts into sales_orders + order_items.
  Future<String> createInvoice({
    required String salesmanId,
    required List<CartItem> items,
    required double totalAmount,
    required double gstAmount,
    required double netAmount,
    required double invoiceDiscountAmount,
    required double invoiceDiscountPercentage,
    required double subtotalBeforeDiscount,
    String? customerId,
    String? customerName,
    String? customerGst,
    String? notes,
    String? shippingAddress,
    String? remarks,
    String? companyId,
    String? customerCategoryId,
    String? customerCategoryName,
    String? ledger,
    String? invoiceNumber,
  }) async {
    try {
      final adminService = AdminSettingsService();
      final globalGstRate = await adminService.getGlobalGstRate(companyId!);
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

      final orderNumber = invoiceNumber ??
          await _generateOrderNumber(gstNumber: customerGstNumber);

      final orderData = {
        'Guid': guid,
        'order_number': orderNumber,
        'salesman_id': salesmanId,
        'customer_id': customerId,
        'customer_name': customerName ?? 'Walk-in Customer',
        'customer_category_id': finalCategoryId,
        'customer_category_name': finalCategoryName,
        'order_date': now,
        'subtotal_before_discount': subtotalBeforeDiscount,
        'discount_amount': invoiceDiscountAmount,
        'discount_percentage': invoiceDiscountPercentage,
        'total_amount': totalAmount,
        'gst_amount': gstAmount,
        'net_amount': roundOffResult.roundedTotal,
        'status': 'approved',
        'notes': notes ?? '',
        'remarks': remarks ?? '',
        'synced_to_tally': false,
        'created_at': now,
        'edit_request_status': 'none',
        'shipping_address': shippingAddress,
        'company_id': companyId,
        'company_name': companyName,
        'Type': ledger ?? 'Credit',
      };

      final orderResponse = await _supabase
          .from('sales_orders')
          .insert(orderData)
          .select()
          .single();

      final orderId = orderResponse['id'] as String;

      // Insert order items
      final orderItems = items.map((item) {
        final manualDiscPct = item.manualDiscountPercentage ?? 0.0;
        final catDiscPct = item.categoryDiscountPercentage ?? 0.0;
        final basePrice = item.product.price;
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
          'unit_price': item.product.price,
          'gst_rate': globalGstRate,
          'discount_percentage': manualDiscPct,
          'category_discount_percentage': catDiscPct,
          'discount_amount': manualDiscAmt,
          'gst_amount': item.subtotal * (globalGstRate / 100),
          'total_amount': item.subtotal + (item.subtotal * (globalGstRate / 100)),
        };
      }).toList();

      await _supabase.from('order_items').insert(orderItems);

      // Reduce stock and auto-notify admin if stock hits low / zero
      try {
        for (final item in items) {
          try {
            await _reduceProductStock(
              productId: item.product.id,
              productName: item.product.productName,
              quantity: item.quantity.round(),
              salesmanId: salesmanId,
              companyId: companyId,
            );
          } catch (_) {}
        }
      } catch (_) {}

      return orderResponse['order_number'] as String;
    } catch (e) {
      print('Error creating invoice: $e');
      rethrow;
    }
  }

  // ─── UPDATE ───────────────────────────────────────────────────────────────

  /// Update invoice — updates sales_orders + replaces order_items.
  Future<void> updateInvoice({
    required String invoiceId,
    required List<InvoiceItemModel> items,
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

      await _updateSalesOrderHeader(invoiceId, updateData);

      await _supabase.from('order_items').delete().eq('order_id', invoiceId);

      if (items.isNotEmpty) {
        final itemsList = items.map((item) {
          return {
            'order_id': invoiceId,
            'product_id': item.productId,
            'product_name': item.productName,
            'product_code': item.productCode ?? '',
            // quantity is integer in DB
            'quantity': item.quantity.round(),
            'unit_price': item.unitPrice,
            'gst_rate': globalGstRate,
            'gst_amount': (item.totalAmount - item.gstAmount) * (globalGstRate / 100),
            'total_amount': (item.totalAmount - item.gstAmount) + ((item.totalAmount - item.gstAmount) * (globalGstRate / 100)),
            'discount_percentage': item.discountPercentage,
            'category_discount_percentage': item.categoryDiscountPercentage,
            'discount_amount': item.discountAmount,
            if (companyId != null) 'company_id': companyId,
          };
        }).toList();

        await _supabase.from('order_items').insert(itemsList);
      }
    } catch (e) {
      print('❌ Error updating invoice: $e');
      rethrow;
    }
  }

  // ─── DELETE ───────────────────────────────────────────────────────────────

  /// Delete invoice — deletes from sales_orders (order_items cascade via FK).
  Future<void> deleteInvoice(String invoiceId) async {
    try {
      await _supabase.from('order_items').delete().eq('order_id', invoiceId);
      await _supabase.from('sales_orders').delete().eq('id', invoiceId);
    } catch (e) {
      print('❌ Error deleting invoice: $e');
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

  /// Decrements stock for [productId] by [quantity].
  /// After updating, automatically writes an admin notification when the new
  /// stock level crosses the out-of-stock or low-stock threshold.
  Future<void> _reduceProductStock({
    required String productId,
    required String productName,
    required int quantity,
    required String salesmanId,
    String? companyId,
  }) async {
    try {
      // 1. Read current stock
      final response = await _supabase
          .from('products')
          .select('ItemQuantity')
          .eq('id', productId)
          .single();
      final currentStock = (response['ItemQuantity'] as num?)?.toInt() ?? 0;
      final newStock = (currentStock - quantity).clamp(0, 999999);

      // 2. Write updated stock
      await _supabase
          .from('products')
          .update({'ItemQuantity': newStock}).eq('id', productId);

      // 3. Auto-notify admin if the product just became out-of-stock or low-stock
      final bool wasAboveThreshold = currentStock > _kLowStockThreshold;
      final bool isNowOutOfStock = newStock == 0;
      final bool isNowLowStock =
          newStock > 0 && newStock <= _kLowStockThreshold;

      // Only fire when the stock level actually crosses a threshold this sale
      if (isNowOutOfStock || (isNowLowStock && wasAboveThreshold)) {
        await _sendAutoStockNotification(
          productId: productId,
          productName: productName,
          newStock: newStock,
          salesmanId: salesmanId,
          companyId: companyId,
        );
      }
    } catch (_) {}
  }

  /// Inserts a stock-alert notification into the `notifications` table.
  /// De-duplicates: skips if an identical alert was already sent in the last 24 hours.
  Future<void> _sendAutoStockNotification({
    required String productId,
    required String productName,
    required int newStock,
    required String salesmanId,
    String? companyId,
  }) async {
    try {
      final notificationType = newStock == 0 ? 'out_of_stock' : 'low_stock';

      // Dedup: avoid spamming the same alert within 24 hours
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

      // Resolve salesman name for the notification record
      String salesmanName = 'Salesman';
      try {
        final userRow = await _supabase
            .from('users')
            .select('name')
            .eq('id', salesmanId)
            .maybeSingle();
        if (userRow != null && userRow['name'] != null) {
          salesmanName = userRow['name'] as String;
        }
      } catch (_) {}

      final title = notificationType == 'out_of_stock'
          ? 'Out of Stock Alert'
          : 'Low Stock Alert';
      final message = notificationType == 'out_of_stock'
          ? '$productName is out of stock'
          : '$productName is running low (Stock: $newStock)';

      await _supabase.from('notifications').insert({
        'type': notificationType,
        'title': title,
        'message': message,
        'product_id': productId,
        'product_name': productName,
        'current_stock': newStock,
        'salesman_id': salesmanId,
        'salesman_name': salesmanName,
        'company_id': companyId,
        'is_read': false,
      });

      print(
          '✅ Auto stock notification sent: $title — $productName (stock: $newStock)');
    } catch (e) {
      // Non-critical — log but don't surface to the caller
      print('⚠️ Failed to send auto stock notification: $e');
    }
  }
}
