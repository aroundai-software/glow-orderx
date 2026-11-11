import 'package:intl/intl.dart';

class OrderModel {
  final String id;
  final String orderNumber;
  final String? customerId;
  final String? customerName;
  final String salesmanId;
  final String? salesmanName; // ✅ NEW
  final DateTime orderDate;
  final double totalAmount;
  final double gstAmount;
  final double netAmount;
  final double? roundOff;
  final String status;
  final String? notes;
  final bool syncedToTally;
  final DateTime? tallySyncDate;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Customer details
  String? customerMobile;
  String? customerAddress;
  String? customerGst;

  // ✅ NEW: Shipping address
  String? shippingAddress;

  String? dispatchedThrough;
  String? destination;

  String? remarks;

  // Company info
  final String? companyId;
  final String? companyName;

  // Payment type
  final String ledger; // 'Cash' or 'Credit'

  // Discount fields
  final double subtotalBeforeDiscount;
  final double orderDiscountAmount;
  final double orderDiscountPercentage;

  // Edit permission fields
  final DateTime? canEditUntil;
  final String editRequestStatus;
  final DateTime? editRequestedAt;
  final DateTime? editApprovedAt;
  final DateTime? editRejectedAt;

  // Order geotagging fields
  final double? orderLatitude;
  final double? orderLongitude;
  final String? orderAddress;
  final double? distanceFromCustomer;

  OrderModel({
    required this.id,
    required this.orderNumber,
    this.customerId,
    this.customerName,
    required this.salesmanId,
    this.salesmanName, // ✅ NEW
    required this.orderDate,
    required this.totalAmount,
    required this.gstAmount,
    required this.netAmount,
    this.roundOff,
    required this.status,
    this.notes,
    required this.syncedToTally,
    this.tallySyncDate,
    required this.createdAt,
    this.updatedAt,
    this.customerMobile,
    this.customerAddress,
    this.customerGst,
    this.shippingAddress,
    this.dispatchedThrough,
    this.destination,
    this.remarks,
    this.companyId,
    this.companyName,
    this.ledger = 'Credit', // Default to Credit
    this.subtotalBeforeDiscount = 0.0,
    this.orderDiscountAmount = 0.0,
    this.orderDiscountPercentage = 0.0,
    this.canEditUntil,
    this.editRequestStatus = 'none',
    this.editRequestedAt,
    this.editApprovedAt,
    this.editRejectedAt,
    this.orderLatitude,
    this.orderLongitude,
    this.orderAddress,
    this.distanceFromCustomer,
  });
  // ✅ Helper getters for edit permissions

  /// Checks if order is within edit window from creation
  /// Note: This getter is deprecated. Use the editWindowMinutes parameter from admin settings instead.
  bool get canEditDirectly {
    final now = DateTime.now();
    const editWindowMinutes = 3; // Default to 3 minutes
    final windowEnd = createdAt.add(const Duration(minutes: editWindowMinutes));
    return now.isBefore(windowEnd);
  }

  bool get hasApprovedEditWindow {
    if (editRequestStatus != 'approved') return false;
    if (canEditUntil == null) return false;
    // Only consider approved window if there was actually an edit request made
    if (editRequestedAt == null) return false;
    final now = DateTime.now();
    return now.isBefore(canEditUntil!);
  }

  /// Can request edit from admin if direct window expired and no active request
  bool get hasEditPermission {
    return canEditDirectly || hasApprovedEditWindow;
  }

  bool get canRequestEdit {
    return !canEditDirectly &&
        editRequestStatus == 'none' &&
        !hasApprovedEditWindow;
  }

  Duration? get editTimeRemaining {
    if (hasApprovedEditWindow && canEditUntil != null) {
      final now = DateTime.now();
      return canEditUntil!.difference(now);
    }
    return null;
  }

  /// Status label for edit request
  String get editStatusLabel {
    switch (editRequestStatus) {
      case 'pending':
        return 'Edit Request Pending';
      case 'approved':
        return 'Edit Approved';
      case 'rejected':
        return 'Edit Request Rejected';
      default:
        return '';
    }
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // Parse datetime - ISO8601 UTC strings already return UTC DateTime
    DateTime parseDate(String dateStr) {
      return DateTime.parse(dateStr);
    }

    return OrderModel(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String?,
      salesmanId: json['salesman_id'] as String,
      salesmanName: json['salesman_name'] as String?, // ✅ NEW
      orderDate: parseDate(json['order_date'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
      gstAmount: (json['gst_amount'] as num).toDouble(),
      netAmount: (json['net_amount'] as num).toDouble(),
      roundOff: (json['round_off'] as num?)?.toDouble(),
      status: json['status'] as String,
      notes: json['notes'] as String?,
      syncedToTally: json['synced_to_tally'] as bool? ?? false,
      tallySyncDate: json['tally_sync_date'] != null
          ? parseDate(json['tally_sync_date'] as String)
          : null,
      createdAt: parseDate(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? parseDate(json['updated_at'] as String)
          : null,
      customerMobile: json['customer_mobile'] as String?,
      customerAddress: json['customer_address'] as String?,
      customerGst: json['customer_gst'] as String?,
      shippingAddress: json['shipping_address'] as String?,
      dispatchedThrough: json['dispatched_through'] as String?,
      destination: json['destination'] as String?,
      remarks: json['remarks'] as String?,
      companyId: json['company_id'] as String?,
      companyName: json['company_name'] as String? ??
          (json['tally_companies'] as Map<String, dynamic>?)?['name']
              as String?,
      ledger: json['Type'] as String? ?? 'Credit',
      subtotalBeforeDiscount:
          (json['subtotal_before_discount'] as num?)?.toDouble() ?? 0.0,
      orderDiscountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      orderDiscountPercentage:
          (json['discount_percentage'] as num?)?.toDouble() ?? 0.0,
      canEditUntil: json['can_edit_until'] != null
          ? parseDate(json['can_edit_until'] as String)
          : null,
      editRequestStatus: json['edit_request_status'] as String? ?? 'none',
      editRequestedAt: json['edit_requested_at'] != null
          ? parseDate(json['edit_requested_at'] as String)
          : null,
      editApprovedAt: json['edit_approved_at'] != null
          ? parseDate(json['edit_approved_at'] as String)
          : null,
      editRejectedAt: json['edit_rejected_at'] != null
          ? parseDate(json['edit_rejected_at'] as String)
          : null,
      orderLatitude: (json['order_latitude'] as num?)?.toDouble(),
      orderLongitude: (json['order_longitude'] as num?)?.toDouble(),
      orderAddress: json['order_address'] as String?,
      distanceFromCustomer:
          (json['distance_from_customer'] as num?)?.toDouble(),
    );
  }

  // Helper method to parse datetime and keep as UTC
  static DateTime _parseLocalDateTime(String dateString) {
    return DateTime.parse(dateString).toUtc();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'salesman_id': salesmanId,
      'salesman_name': salesmanName, // ✅ NEW
      'order_date': orderDate.toIso8601String(),
      'subtotal_before_discount': subtotalBeforeDiscount,
      'discount_amount': orderDiscountAmount,
      'discount_percentage': orderDiscountPercentage,
      'total_amount': totalAmount,
      'gst_amount': gstAmount,
      'net_amount': netAmount,
      'round_off': roundOff,
      'status': status,
      'notes': notes,
      'remarks': remarks,
      'synced_to_tally': syncedToTally,
      'tally_sync_date': tallySyncDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'shipping_address': shippingAddress,
      'dispatched_through': dispatchedThrough,
      'destination': destination,
      'can_edit_until': canEditUntil?.toIso8601String(),
      'edit_request_status': editRequestStatus,
      'edit_requested_at': editRequestedAt?.toIso8601String(),
      'edit_approved_at': editApprovedAt?.toIso8601String(),
      'edit_rejected_at': editRejectedAt?.toIso8601String(),
      'order_latitude': orderLatitude,
      'order_longitude': orderLongitude,
      'order_address': orderAddress,
      'distance_from_customer': distanceFromCustomer,
    };
  }
}

class OrderItemModel {
  final String id;
  final String orderId;
  final String productId;
  final String ItemName;
  final String? PartNumber;
  final String? vtNumber; // VT Number (Alias)
  final String? hsn; // HSN Code
  final double ItemQuantity;
  final double ItemRate;
  final double GstRate;
  final double gstAmount;
  final double totalAmount;
  final double discountPercentage;
  final double discountAmount;
  final double? mrp;
  // Discount fields for PDF table
  final double cashDiscountAmount; // Category discount (customer category)
  final double offerDiscountAmount; // Special offer discount
  final double itemDiscountAmount; // Product screen discount
  final double orderDiscountAmount; // Cart screen manual discount

  OrderItemModel({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.ItemName,
    this.PartNumber,
    this.vtNumber,
    this.hsn,
    required this.ItemQuantity,
    required this.ItemRate,
    required this.GstRate,
    required this.gstAmount,
    required this.totalAmount,
    this.discountPercentage = 0.0,
    this.discountAmount = 0.0,
    this.mrp,
    this.cashDiscountAmount = 0.0,
    this.offerDiscountAmount = 0.0,
    this.itemDiscountAmount = 0.0,
    this.orderDiscountAmount = 0.0,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      productId: json['product_id'] as String,
      ItemName: json['ItemName'] as String? ??
          json['product_name'] as String? ??
          'N/A',
      PartNumber:
          json['PartNumber'] as String? ?? json['product_code'] as String?,
      vtNumber: json['vtNumber'] as String? ?? json['vt_number'] as String?,
      hsn: json['hsn'] as String?,
      ItemQuantity: (json['ItemQuantity'] as num?)?.toDouble() ??
          (json['quantity'] as num).toDouble(),
      ItemRate: (json['ItemRate'] as num?)?.toDouble() ??
          (json['unit_price'] as num).toDouble(),
      GstRate: (json['GstRate'] as num?)?.toDouble() ??
          (json['gst_rate'] as num).toDouble(),
      gstAmount: (json['gst_amount'] as num).toDouble(),
      totalAmount: (json['total_amount'] as num).toDouble(),
      discountPercentage:
          (json['discount_percentage'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      mrp: (json['mrp'] as num?)?.toDouble(),
      cashDiscountAmount:
          (json['cash_discount_amount'] as num?)?.toDouble() ?? 0.0,
      offerDiscountAmount:
          (json['offer_discount_amount'] as num?)?.toDouble() ?? 0.0,
      itemDiscountAmount:
          (json['item_discount_amount'] as num?)?.toDouble() ?? 0.0,
      orderDiscountAmount:
          (json['order_discount_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'ItemName': ItemName,
      'PartNumber': PartNumber,
      'vtNumber': vtNumber,
      'hsn': hsn,
      'ItemQuantity': ItemQuantity,
      'ItemRate': ItemRate,
      'GstRate': GstRate,
      'gst_amount': gstAmount,
      'total_amount': totalAmount,
      'discount_percentage': discountPercentage,
      'discount_amount': discountAmount,
      'mrp': mrp,
      'cash_discount_amount': cashDiscountAmount,
      'offer_discount_amount': offerDiscountAmount,
      'item_discount_amount': itemDiscountAmount,
      'order_discount_amount': orderDiscountAmount,
    };
  }
}
