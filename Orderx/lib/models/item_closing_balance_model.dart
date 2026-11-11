class ItemClosingBalanceModel {
  final String id;
  final String itemName;
  final String? partNumber;
  final String? godown;
  final String? batchNames;
  final double closingQuantity;
  final double closingAltQuantity;
  final double salableQty;
  final DateTime? createdAt;

  ItemClosingBalanceModel({
    required this.id,
    required this.itemName,
    this.partNumber,
    this.godown,
    this.batchNames,
    this.closingQuantity = 0,
    this.closingAltQuantity = 0,
    this.salableQty = 0,
    this.createdAt,
  });

  factory ItemClosingBalanceModel.fromJson(Map<String, dynamic> json) {
    return ItemClosingBalanceModel(
      id: json['id'] as String,
      itemName: json['itemname'] as String,
      partNumber: json['partnumber'] as String?,
      godown: json['godown'] as String?,
      batchNames: json['batch_names'] as String?,
      closingQuantity: (json['closing_quantity'] as num?)?.toDouble() ?? 0,
      closingAltQuantity:
          (json['closing_alt_quantity'] as num?)?.toDouble() ?? 0,
      salableQty: (json['salable_qty'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'itemname': itemName,
      'partnumber': partNumber,
      'godown': godown,
      'batch_names': batchNames,
      'closing_quantity': closingQuantity,
      'closing_alt_quantity': closingAltQuantity,
      'salable_qty': salableQty,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// Check if item is out of stock
  bool get isOutOfStock => closingQuantity <= 0;

  /// Check if item has low stock (less than 10)
  bool get isLowStock => closingQuantity > 0 && closingQuantity <= 10;

  /// Check if item is in stock
  bool get isInStock => closingQuantity > 10;

  ItemClosingBalanceModel copyWith({
    String? id,
    String? itemName,
    String? partNumber,
    String? godown,
    String? batchNames,
    double? closingQuantity,
    double? closingAltQuantity,
    double? salableQty,
    DateTime? createdAt,
  }) {
    return ItemClosingBalanceModel(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      partNumber: partNumber ?? this.partNumber,
      godown: godown ?? this.godown,
      batchNames: batchNames ?? this.batchNames,
      closingQuantity: closingQuantity ?? this.closingQuantity,
      closingAltQuantity: closingAltQuantity ?? this.closingAltQuantity,
      salableQty: salableQty ?? this.salableQty,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'ItemClosingBalanceModel(id: $id, itemName: $itemName, closingQuantity: $closingQuantity, salableQty: $salableQty)';
  }
}
