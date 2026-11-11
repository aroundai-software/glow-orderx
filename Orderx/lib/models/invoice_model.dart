import 'package:intl/intl.dart';

class InvoiceModel {
  final String id;
  final String invoiceNumber;
  final String? customerId;
  final String? customerName;
  final String salesmanId;
  final String? salesmanName;
  final DateTime invoiceDate;
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

  // Shipping address
  String? shippingAddress;

  String? remarks;

  // Company info
  final String? companyId;
  final String? companyName;

  // Payment type
  final String ledger; // 'Cash' or 'Credit'

  // Discount fields
  final double subtotalBeforeDiscount;
  final double invoiceDiscountAmount;
  final double invoiceDiscountPercentage;

  // Whether this invoice has been edited after creation
  final bool isEdited;

  // Edit permission fields
  final DateTime? canEditUntil;
  final String editRequestStatus;
  final DateTime? editRequestedAt;
  final DateTime? editApprovedAt;
  final DateTime? editRejectedAt;

  // Invoice geotagging fields
  final double? invoiceLatitude;
  final double? invoiceLongitude;
  final String? invoiceAddress;
  final double? distanceFromCustomer;

  InvoiceModel({
    required this.id,
    required this.invoiceNumber,
    this.customerId,
    this.customerName,
    required this.salesmanId,
    this.salesmanName,
    required this.invoiceDate,
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
    this.isEdited = false,
    this.customerMobile,
    this.customerAddress,
    this.customerGst,
    this.shippingAddress,
    this.remarks,
    this.companyId,
    this.companyName,
    this.ledger = 'Credit',
    this.subtotalBeforeDiscount = 0.0,
    this.invoiceDiscountAmount = 0.0,
    this.invoiceDiscountPercentage = 0.0,
    this.canEditUntil,
    this.editRequestStatus = 'none',
    this.editRequestedAt,
    this.editApprovedAt,
    this.editRejectedAt,
    this.invoiceLatitude,
    this.invoiceLongitude,
    this.invoiceAddress,
    this.distanceFromCustomer,
  });

  /// Checks if invoice is within edit window from creation.
  /// Pass [editWindowMinutes] from admin settings; defaults to 30 min.
  bool canEditDirectly({int editWindowMinutes = 30}) {
    final now = DateTime.now();
    final windowEnd = createdAt.add(Duration(minutes: editWindowMinutes));
    return now.isBefore(windowEnd);
  }

  /// Checks if an edit request is pending approval
  bool get hasPendingEditRequest => editRequestStatus == 'pending';

  /// Checks if admin has granted temporary edit permission
  bool get hasAdminEditPermission {
    if (canEditUntil == null) return false;
    return DateTime.now().isBefore(canEditUntil!);
  }

  /// Overall check: can this invoice be edited right now?
  /// Pass [editWindowMinutes] from admin settings (ignored when [useTimeWindow] is false).
  /// An invoice synced to Tally can never be edited.
  /// When [useTimeWindow] is false the salesman can edit until it is billed.
  bool canEdit({int editWindowMinutes = 30, bool useTimeWindow = true}) {
    if (syncedToTally) return false;
    if (!useTimeWindow) return true; // editable until billed
    return canEditDirectly(editWindowMinutes: editWindowMinutes) ||
        hasAdminEditPermission;
  }

  String get formattedDate {
    return DateFormat('dd MMM yyyy, hh:mm a').format(invoiceDate);
  }

  String get formattedNetAmount {
    return '₹${netAmount.toStringAsFixed(2)}';
  }
}

class InvoiceItemModel {
  final String id;
  final String invoiceId;
  final String productId;
  final String productName;
  final String? productCode;
  final String? hsn;
  final double quantity;
  final double unitPrice;
  final double gstRate;
  final double gstAmount;
  final double totalAmount;
  final double discountPercentage;
  final double discountAmount;
  final double categoryDiscountPercentage;
  final String? vtNumber;
  final double? mrp;
  final double cashDiscountAmount;
  final double orderDiscountAmount;
  final double itemDiscountAmount;
  final double offerDiscountAmount;

  InvoiceItemModel({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.productName,
    this.productCode,
    this.hsn,
    required this.quantity,
    required this.unitPrice,
    required this.gstRate,
    required this.gstAmount,
    required this.totalAmount,
    this.discountPercentage = 0.0,
    this.discountAmount = 0.0,
    this.categoryDiscountPercentage = 0.0,
    this.vtNumber,
    this.mrp,
    this.cashDiscountAmount = 0.0,
    this.orderDiscountAmount = 0.0,
    this.itemDiscountAmount = 0.0,
    this.offerDiscountAmount = 0.0,
  });

  factory InvoiceItemModel.fromJson(Map<String, dynamic> json) {
    return InvoiceItemModel(
      id: json['id'] as String,
      invoiceId: json['invoice_id'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      productCode: json['product_code'] as String?,
      hsn: json['hsn'] as String?,
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unit_price'] as num).toDouble(),
      gstRate: (json['gst_rate'] as num).toDouble(),
      gstAmount: (json['gst_amount'] as num).toDouble(),
      totalAmount: (json['total_amount'] as num).toDouble(),
      discountPercentage:
          (json['discount_percentage'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      categoryDiscountPercentage:
          (json['category_discount_percentage'] as num?)?.toDouble() ?? 0.0,
      vtNumber: json['vt_number'] as String?,
      mrp: (json['mrp'] as num?)?.toDouble(),
      cashDiscountAmount:
          (json['cash_discount_amount'] as num?)?.toDouble() ?? 0.0,
      orderDiscountAmount:
          (json['order_discount_amount'] as num?)?.toDouble() ?? 0.0,
      itemDiscountAmount:
          (json['item_discount_amount'] as num?)?.toDouble() ?? 0.0,
      offerDiscountAmount:
          (json['offer_discount_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  double get subtotal => unitPrice * quantity;
  double get priceAfterDiscount =>
      unitPrice - (unitPrice * discountPercentage / 100);
}
