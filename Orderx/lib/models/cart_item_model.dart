import 'package:Orderx/models/product_model.dart';

class CartItem {
  final String id;
  final ProductModel product;
  double quantity;
  double itemDiscountPercentage; // Total effective discount (auto + manual)
  double? categoryDiscountPercentage; // Track category discount separately
  double? manualDiscountPercentage; // Track manual item-level discount separately
  double? customPrice; // Per-order price override (does not affect product DB price)

  CartItem({
    required this.id,
    required this.product,
    this.quantity = 1.0,
    double? itemDiscountPercentage, // Total effective discount
    this.categoryDiscountPercentage,
    this.manualDiscountPercentage,
    this.customPrice,
  }) : itemDiscountPercentage = itemDiscountPercentage ?? product.discountPercentage;

  // Effective unit price: uses customPrice if set, otherwise product's default price
  double get effectivePrice => customPrice ?? product.price;

  // Calculate price after item discount
  double get priceAfterDiscount {
    if (itemDiscountPercentage > 0) {
      return effectivePrice - (effectivePrice * itemDiscountPercentage / 100);
    }
    return effectivePrice;
  }

  // Calculate discount amount per unit
  double get discountAmountPerUnit {
    return effectivePrice * itemDiscountPercentage / 100;
  }

  // Calculate total discount for quantity
  double get totalDiscountAmount {
    return discountAmountPerUnit * quantity;
  }

  // Calculate subtotal (after discount, before GST)
  double get subtotal {
    return priceAfterDiscount * quantity;
  }

  CartItem copyWith({
    String? id,
    ProductModel? product,
    double? quantity,
    double? itemDiscountPercentage,
    double? categoryDiscountPercentage,
    double? manualDiscountPercentage,
    double? customPrice,
  }) {
    return CartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      itemDiscountPercentage: itemDiscountPercentage ?? this.itemDiscountPercentage,
      categoryDiscountPercentage: categoryDiscountPercentage ?? this.categoryDiscountPercentage,
      manualDiscountPercentage: manualDiscountPercentage ?? this.manualDiscountPercentage,
      customPrice: customPrice ?? this.customPrice,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product.toJson(),
      'quantity': quantity,
      'item_discount_percentage': itemDiscountPercentage,
      'category_discount_percentage': categoryDiscountPercentage,
      'manual_discount_percentage': manualDiscountPercentage,
      'custom_price': customPrice,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'],
      product: ProductModel.fromJson(json['product']),
      quantity: (json['quantity'] as num).toDouble(),
      itemDiscountPercentage: (json['item_discount_percentage'] as num?)?.toDouble(),
      categoryDiscountPercentage: (json['category_discount_percentage'] as num?)?.toDouble(),
      manualDiscountPercentage: (json['manual_discount_percentage'] as num?)?.toDouble(),
      customPrice: (json['custom_price'] as num?)?.toDouble(),
    );
  }
}