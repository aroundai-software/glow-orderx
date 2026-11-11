import 'package:Orderx/models/price_level_model.dart';

class ProductModel {
  final String id;
  final String productName;
  final String? productCode;
  final String? vtNumber; // VT Number (Alias)
  final String? hsn; // HSN Code
  final String unit;
  final double price;
  final double gstRate;
  final double stock; // ✅ Stock field (decimal for units like MTR)
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? imageUrl;
  final String? imagePath;
  final double discountPercentage;
  final double? mrp; // ✅ NEW
  final List<PriceLevelModel> priceLevels; // All tiered pricing slabs

  ProductModel({
    required this.id,
    required this.productName,
    this.productCode,
    this.vtNumber,
    this.hsn,
    required this.unit,
    required this.price,
    required this.gstRate,
    this.stock = 0.0, // ✅ Default to 0 if not provided
    required this.isActive,
    this.createdAt,
    this.updatedAt,
    this.imageUrl,
    this.imagePath,
    this.discountPercentage = 0.0,
    this.mrp, // ✅ NEW
    this.priceLevels = const [],
  });

  // Calculate price after discount
  double get priceAfterDiscount {
    if (discountPercentage > 0) {
      return price - (price * discountPercentage / 100);
    }
    return price;
  }

  // Calculate discount amount
  double get discountAmount {
    return price * discountPercentage / 100;
  }

  // ✅ Helper getter to check if product is in stock
  bool get isInStock => stock > 0;

  // ✅ Helper getter to check if stock is low (optional - useful for warnings)
  bool get isLowStock => stock > 0 && stock <= 10;

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0.0;
    }

    // Intelligent price detection: prioritize non-zero values from all common fields
    double findPrice() {
      // 1. Check for joined price_levels or item_rates from Supabase (Priority)
      final rateList = (json['price_levels'] ?? json['item_rates']) as List?;
      if (rateList != null && rateList.isNotEmpty) {
        // Try to find a non-zero rate in the list
        for (final rateData in rateList) {
          if (rateData is Map<String, dynamic>) {
            final rateVal = parseDouble(rateData['rate'] ?? rateData['ItemRate']);
            if (rateVal > 0) return rateVal;
          }
        }
      }

      // 2. Fallback to standard fields
      final fields = [
        'ItemRate',
        'item_rate',
        'SellingRate',
        'selling_rate',
        'StandardPrice',
        'standard_price',
        'Rate',
        'rate',
        'StandardRate',
        'standard_rate',
        'UnitPrice',
        'unit_price',
        'MRP',
        'mrp',
        'price'
      ];

      for (final field in fields) {
        final val = parseDouble(json[field]);
        if (val > 0) return val;
      }
      return 0.0;
    }

    double basePrice = findPrice();

    return ProductModel(
      id: (json['id'] ?? '').toString(),
      productName:
          (json['ItemName'] ?? json['product_name'] ?? 'Unknown Product')
              .toString(),
      productCode:
          json['PartNumber']?.toString() ?? json['product_code']?.toString(),
      vtNumber: json['ItemAlias1']?.toString() ?? json['vt_number']?.toString(),
      hsn: json['hsn']?.toString(),
      unit: (json['ItemUnit'] ?? json['unit'] ?? 'PCS').toString(),
      price: basePrice,
      gstRate: parseDouble(
          json['GstRate'] ?? json['gst_rate'] ?? json['gst'] ?? 0.0),
      stock: parseDouble(json['ItemQuantity'] ??
          json['item_quantity'] ??
          json['stock'] ??
          json['quantity'] ??
          0),
      isActive: json['is_active'] == true ||
          json['is_active'] == 1 ||
          json['is_active'] == null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      imageUrl: json['image_url'] as String?,
      imagePath: json['image_path'] as String?,
      discountPercentage:
          parseDouble(json['discount_percentage'] ?? json['discount'] ?? 0.0),
      mrp: json['MRP'] != null ? parseDouble(json['MRP']) : null,
      priceLevels: () {
        final raw = (json['price_levels'] ?? json['item_rates']) as List?;
        if (raw == null || raw.isEmpty) return const <PriceLevelModel>[];
        final list = <PriceLevelModel>[];
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            list.add(PriceLevelModel.fromJson(item));
          }
        }
        return list;
      }(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ItemName': productName,
      'PartNumber': productCode,
      'ItemAlias1': vtNumber,
      'hsn': hsn,
      'ItemUnit': unit,
      'ItemRate': price,
      'GstRate': gstRate,
      'ItemQuantity': stock,
      'is_active': isActive ? 1 : 0,
      'discount_percentage': discountPercentage,
      'image_url': imageUrl,
      'image_path': imagePath,
      'MRP': mrp,
      'price_levels': priceLevels.map((p) => p.toJson()).toList(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is ProductModel &&
        other.id == id &&
        other.productName == productName &&
        other.productCode == productCode &&
        other.vtNumber == vtNumber &&
        other.hsn == hsn &&
        other.unit == unit &&
        other.price == price &&
        other.gstRate == gstRate &&
        other.stock == stock &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.imageUrl == imageUrl &&
        other.imagePath == imagePath &&
        other.discountPercentage == discountPercentage &&
        other.mrp == mrp;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      productName,
      productCode,
      vtNumber,
      hsn,
      unit,
      price,
      gstRate,
      stock,
      isActive,
      createdAt,
      updatedAt,
      imageUrl,
      imagePath,
      discountPercentage,
      mrp,
    );
  }

  @override
  String toString() {
    return 'ProductModel(id: $id, productName: $productName, price: $price, stock: $stock, discountPercentage: $discountPercentage, mrp: $mrp)';
  }
}
