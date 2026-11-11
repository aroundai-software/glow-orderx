class SaleBillModel {
  final String id;
  final String orderNumber;
  final DateTime date;
  final String? invoiceNumber;
  final String status;
  final DateTime? createdAt;

  SaleBillModel({
    required this.id,
    required this.orderNumber,
    required this.date,
    this.invoiceNumber,
    this.status = 'Pending',
    this.createdAt,
  });

  factory SaleBillModel.fromJson(Map<String, dynamic> json) {
    return SaleBillModel(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String,
      date: DateTime.parse(json['date'] as String),
      invoiceNumber: json['invoice_number'] as String?,
      status: json['status'] as String? ?? 'Pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'date': date.toIso8601String().split('T')[0],
      'invoice_number': invoiceNumber,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  SaleBillModel copyWith({
    String? id,
    String? orderNumber,
    DateTime? date,
    String? invoiceNumber,
    String? status,
    DateTime? createdAt,
  }) {
    return SaleBillModel(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      date: date ?? this.date,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'SaleBillModel(id: $id, orderNumber: $orderNumber, date: $date, invoiceNumber: $invoiceNumber, status: $status)';
  }
}
