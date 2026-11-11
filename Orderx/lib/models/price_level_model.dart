class PriceLevelModel {
  final String id;
  final String priceLevel;
  final String? underGroup;
  final String? applicableFrom;
  final int? sNo;
  final String? productId;
  final String productName;
  final double fromQty;
  final double? lessThanQty;
  final double rate;
  final String unit;
  final double discountPercentage;
  final double? costPrice;
  final String? companyId;
  final String? companyName;
  final bool isActive;

  PriceLevelModel({
    required this.id,
    required this.priceLevel,
    this.underGroup,
    this.applicableFrom,
    this.sNo,
    this.productId,
    required this.productName,
    this.fromQty = 0.0,
    this.lessThanQty,
    required this.rate,
    this.unit = 'PCS',
    this.discountPercentage = 0.0,
    this.costPrice,
    this.companyId,
    this.companyName,
    this.isActive = true,
  });

  factory PriceLevelModel.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, [double defaultValue = 0.0]) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      if (value is String) {
        return double.tryParse(value) ?? defaultValue;
      }
      return defaultValue;
    }

    double? parseOptionalDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) {
        return double.tryParse(value);
      }
      return null;
    }

    return PriceLevelModel(
      id: json['id'] as String? ?? '',
      priceLevel: json['price_level'] as String? ?? 'Sales',
      underGroup: json['under_group'] as String?,
      applicableFrom: json['applicable_from'] as String?,
      sNo: json['s_no'] is int ? json['s_no'] as int : null,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String? ?? '',
      fromQty: parseDouble(json['from_qty'], 0.0),
      lessThanQty: parseOptionalDouble(json['less_than_qty']),
      rate: parseDouble(json['rate'], 0.0),
      unit: json['unit'] as String? ?? 'PCS',
      discountPercentage: parseDouble(json['discount_percentage'], 0.0),
      costPrice: parseOptionalDouble(json['cost_price']),
      companyId: json['company_id'] as String?,
      companyName: json['company_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'price_level': priceLevel,
      'under_group': underGroup,
      'applicable_from': applicableFrom,
      's_no': sNo,
      'product_id': productId,
      'product_name': productName,
      'from_qty': fromQty,
      'less_than_qty': lessThanQty,
      'rate': rate,
      'unit': unit,
      'discount_percentage': discountPercentage,
      'cost_price': costPrice,
      'company_id': companyId,
      'company_name': companyName,
      'is_active': isActive,
    };
  }

  /// User friendly display label for dropdown selection
  String get displayLabel {
    final fromStr = fromQty == fromQty.truncateToDouble() ? fromQty.toInt().toString() : fromQty.toString();
    final rateStr = rate.toStringAsFixed(2);
    
    if (lessThanQty != null) {
      final toStr = lessThanQty == lessThanQty!.truncateToDouble() ? lessThanQty!.toInt().toString() : lessThanQty.toString();
      if (priceLevel.isNotEmpty && priceLevel != 'Sales') {
        return '$priceLevel ($fromStr - $toStr $unit) : ₹$rateStr';
      }
      return '$fromStr - $toStr $unit : ₹$rateStr';
    } else {
      if (fromQty > 0) {
        if (priceLevel.isNotEmpty && priceLevel != 'Sales') {
          return '$priceLevel ($fromStr+ $unit) : ₹$rateStr';
        }
        return '$fromStr+ $unit : ₹$rateStr';
      } else {
        if (priceLevel.isNotEmpty) {
          return '$priceLevel : ₹$rateStr';
        }
        return 'Standard : ₹$rateStr';
      }
    }
  }

  /// Checks whether a given quantity falls into this slab
  bool matchesQuantity(double qty) {
    if (qty < fromQty) return false;
    if (lessThanQty != null && qty >= lessThanQty!) return false;
    return true;
  }
}
