class OutstandingModel {
  final String id;
  final String customerName;
  final DateTime date;
  final String invoiceNumber;
  final double openingBalance;
  final double closingBalance;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final String? companyId;
  final String? guid; // Original company GUID column "Guid"
  final DateTime? effectiveDate; // Added from View
  final bool? paymentReceived; // Added from View

  OutstandingModel({
    required this.id,
    required this.customerName,
    required this.date,
    required this.invoiceNumber,
    this.openingBalance = 0,
    this.closingBalance = 0,
    this.dueDate,
    this.createdAt,
    this.companyId,
    this.guid,
    this.effectiveDate,
    this.paymentReceived,
  });

  factory OutstandingModel.fromJson(Map<String, dynamic> json) {
    return OutstandingModel(
      id: json['id'] as String,
      customerName: json['customer_name'] as String,
      date: DateTime.parse(json['date'] as String),
      invoiceNumber: json['invoicenumber'] as String,
      openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
      closingBalance: (json['closing_balance'] as num?)?.toDouble() ?? 0,
      dueDate: json['duedate'] != null
          ? DateTime.parse(json['duedate'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      companyId: json['company_id'] as String?,
      guid: json['Guid'] as String?,
      effectiveDate: json['effective_date'] != null
          ? DateTime.parse(json['effective_date'] as String)
          : null,
      paymentReceived: json['payment_received'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_name': customerName,
      'date': date.toIso8601String().split('T')[0],
      'invoicenumber': invoiceNumber,
      'opening_balance': openingBalance,
      'closing_balance': closingBalance,
      'duedate': dueDate?.toIso8601String().split('T')[0],
      'created_at': createdAt?.toIso8601String(),
      'company_id': companyId,
      'Guid': guid,
      'effective_date': effectiveDate?.toIso8601String().split('T')[0],
      'payment_received': paymentReceived,
    };
  }

  /// Get the outstanding amount (closing - opening)
  double get outstandingAmount => closingBalance - openingBalance;

  /// Check if payment is overdue
  bool get isOverdue {
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!) && closingBalance > 0;
  }

  /// Days until due or days overdue
  int get daysUntilDue {
    if (dueDate == null) return 0;
    return dueDate!.difference(DateTime.now()).inDays;
  }

  OutstandingModel copyWith({
    String? id,
    String? customerName,
    DateTime? date,
    String? invoiceNumber,
    double? openingBalance,
    double? closingBalance,
    DateTime? dueDate,
    DateTime? createdAt,
    String? companyId,
    String? guid,
    DateTime? effectiveDate,
    bool? paymentReceived,
  }) {
    return OutstandingModel(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      openingBalance: openingBalance ?? this.openingBalance,
      closingBalance: closingBalance ?? this.closingBalance,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      companyId: companyId ?? this.companyId,
      guid: guid ?? this.guid,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      paymentReceived: paymentReceived ?? this.paymentReceived,
    );
  }

  @override
  String toString() {
    return 'OutstandingModel(id: $id, customerName: $customerName, invoiceNumber: $invoiceNumber, closingBalance: $closingBalance)';
  }
}
