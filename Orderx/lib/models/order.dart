// lib/models/order.dart

class SalesOrder {
  final String id; // UUID
  final String orderNumber;
  final String customerId;
  final String customerName; // Denormalized for UI
  final String salesmanId;
  final String salesmanName; // Denormalized
  final List<SalesOrderItem> items;
  final double totalAmount;
  final double gstAmount;
  final double netAmount;
  final String status; // 'pending', 'approved', 'rejected', 'synced_to_tally'
  final bool syncedToTally;
  final DateTime orderDate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;

  SalesOrder({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.salesmanId,
    required this.salesmanName,
    required this.items,
    required this.totalAmount,
    required this.gstAmount,
    required this.netAmount,
    required this.status,
    required this.syncedToTally,
    required this.orderDate,
    required this.createdAt,
    this.updatedAt,
    this.notes,
  });

  // PRD Logic: Can this order be edited?
  bool get canEditBySalesman {
    // Only 'pending' orders can be edited
    if (status != 'pending') return false;

    // Check if created today (same day rule)
    final now = DateTime.now();
    return orderDate.year == now.year &&
        orderDate.month == now.month &&
        orderDate.day == now.day;
  }

  // Does this edit require approval? (Not used directly — status handles it)
  bool get requiresApproval => !canEditBySalesman && status == 'pending';

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    // Note: customerName & salesmanName must be joined or denormalized
    // For now, assume they're included in the query
    return SalesOrder(
      id: json['id'],
      orderNumber: json['order_number'],
      customerId: json['customer_id'],
      customerName: json['customer_name'] ?? 'Unknown Customer',
      salesmanId: json['salesman_id'],
      salesmanName: json['salesman_name'] ?? 'Unknown Salesman',
      items: (json['items'] as List?)
          ?.map((item) => SalesOrderItem.fromJson(item))
          .toList() ??
          [],
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      gstAmount: (json['gst_amount'] as num?)?.toDouble() ?? 0.0,
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'pending',
      syncedToTally: json['synced_to_tally'] ?? false,
      orderDate: DateTime.parse(json['order_date']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'customer_id': customerId,
      'salesman_id': salesmanId,
      'total_amount': totalAmount,
      'gst_amount': gstAmount,
      'net_amount': netAmount,
      'status': status,
      'synced_to_tally': syncedToTally,
      'order_date': orderDate.toIso8601String().split('T')[0], // Date only
      'notes': notes,
    };
  }
}

class SalesOrderItem {
  final String id;
  final String orderId;
  final String productId;
  final String productName; // Denormalized
  final String productCode;
  final double quantity;
  final double unitPrice;
  final double gstRate;
  final double gstAmount;
  final double totalAmount;

  SalesOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    required this.unitPrice,
    required this.gstRate,
    required this.gstAmount,
    required this.totalAmount,
  });

  factory SalesOrderItem.fromJson(Map<String, dynamic> json) {
    return SalesOrderItem(
      id: json['id'],
      orderId: json['order_id'],
      productId: json['product_id'],
      productName: json['product_name'] ?? 'Unknown Product',
      productCode: json['product_code'] ?? '',
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unit_price'] as num).toDouble(),
      gstRate: (json['gst_rate'] as num).toDouble(),
      gstAmount: (json['gst_amount'] as num).toDouble(),
      totalAmount: (json['total_amount'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'gst_rate': gstRate,
      'gst_amount': gstAmount,
      'total_amount': totalAmount,
    };
  }
}