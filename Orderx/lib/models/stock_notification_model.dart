class StockNotificationModel {
  final String id;
  final String type; // 'low_stock' or 'out_of_stock'
  final String title;
  final String message;
  final String? productId;
  final String? productName;
  final int? currentStock;
  final String salesmanId;
  final String salesmanName;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;

  StockNotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.productId,
    this.productName,
    this.currentStock,
    required this.salesmanId,
    required this.salesmanName,
    required this.createdAt,
    this.isRead = false,
    this.readAt,
  });

  factory StockNotificationModel.fromJson(Map<String, dynamic> json) {
    return StockNotificationModel(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String?,
      currentStock: json['current_stock'] as int?,
      salesmanId: json['salesman_id'] as String,
      salesmanName: json['salesman_name'] as String,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'product_id': productId,
      'product_name': productName,
      'current_stock': currentStock,
      'salesman_id': salesmanId,
      'salesman_name': salesmanName,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
    };
  }

  StockNotificationModel copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    String? productId,
    String? productName,
    int? currentStock,
    String? salesmanId,
    String? salesmanName,
    DateTime? createdAt,
    bool? isRead,
    DateTime? readAt,
  }) {
    return StockNotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      currentStock: currentStock ?? this.currentStock,
      salesmanId: salesmanId ?? this.salesmanId,
      salesmanName: salesmanName ?? this.salesmanName,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
    );
  }
}
