import 'package:Orderx/models/cart_item_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:flutter/material.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/utils/rounding_utils.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  // Order-level discount
  double _orderDiscountPercentage = 0.0;
  double _orderDiscountAmount = 0.0;
  bool _isPercentageDiscount = true; // true = %, false = fixed amount

  // ✅ NEW: Track selected category for order
  String? _selectedCategoryId;
  String? _selectedCategoryName;

  // Global GST
  double _globalGstRate = 0.0;

  CartProvider();

  Future<void> loadGlobalGstRate(String companyId) async {
    final service = AdminSettingsService();
    _globalGstRate = await service.getGlobalGstRate(companyId);
    print('🛒 CartProvider loaded GST Rate for $companyId: $_globalGstRate');
    notifyListeners();
  }

  // Getters
  double get orderDiscountPercentage => _orderDiscountPercentage;
  double get orderDiscountAmount => _orderDiscountAmount;
  bool get isPercentageDiscount => _isPercentageDiscount;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedCategoryName => _selectedCategoryName;
  double get globalGstRate => _globalGstRate;

  // Subtotal BEFORE any order-level discount (sum of item subtotals after item discounts)
  double get subtotal {
    return _items.values.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  // Total of all item-level discounts
  double get totalItemDiscounts {
    return _items.values
        .fold(0.0, (sum, item) => sum + item.totalDiscountAmount);
  }

  // Total category/customer discounts
  double get totalCategoryDiscounts {
    return _items.values.fold(0.0, (sum, item) {
      if (item.categoryDiscountPercentage != null &&
          item.categoryDiscountPercentage! > 0) {
        return sum +
            (item.effectivePrice *
                item.categoryDiscountPercentage! /
                100 *
                item.quantity);
      }
      return sum;
    });
  }

  // Total manual item discounts (excluding category discounts)
  double get totalManualItemDiscounts {
    return _items.values.fold(0.0, (sum, item) {
      // If category discount exists, manual discount is 0, otherwise use item discount
      final categoryDiscount = item.categoryDiscountPercentage ?? 0.0;
      final manualDiscount =
          (categoryDiscount > 0) ? 0.0 : item.itemDiscountPercentage;
      return sum + (item.effectivePrice * manualDiscount / 100 * item.quantity);
    });
  }

  // Order-level discount amount (either % of subtotal or fixed)
  double get calculatedOrderDiscount {
    if (_isPercentageDiscount) {
      return subtotal * _orderDiscountPercentage / 100;
    }
    return _orderDiscountAmount;
  }

  // Subtotal AFTER applying order-level discount
  double get subtotalAfterDiscount {
    return subtotal - calculatedOrderDiscount;
  }

  // Total GST (calculated dynamically on discounted subtotal using effective GST rate)
  double get totalGst {
    final currentSubtotal = subtotal;
    // Calculate how much order discount is applied proportionally to each item's subtotal
    final discountFactor = currentSubtotal > 0 ? (subtotalAfterDiscount / currentSubtotal) : 1.0;
    
    return _items.values.fold(0.0, (sum, item) {
      final taxableSubtotal = item.subtotal * discountFactor;
      final itemGstAmount = taxableSubtotal * (item.product.gstRate / 100);
      return sum + itemGstAmount;
    });
  }

  // Final amount to pay (exact)
  double get grandTotal {
    return subtotalAfterDiscount + totalGst;
  }

  // Rounded amount properties
  RoundOffResult get roundOffResult => calculateRoundOff(grandTotal);
  double get roundedGrandTotal => roundOffResult.roundedTotal;

  // Standard cart info
  Map<String, CartItem> get items => {..._items};
  int get itemCount => _items.length;
  double get totalQuantity =>
      _items.values.fold(0.0, (sum, item) => sum + item.quantity);
  bool get isEmpty => _items.isEmpty;

  // Add item to cart (basic method without discount)
  void addItem(ProductModel product, {double quantity = 1.0}) {
    if (_items.containsKey(product.id)) {
      _items[product.id]!.quantity += quantity;
    } else {
      _items[product.id] = CartItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        product: product,
        quantity: quantity,
      );
    }
    notifyListeners();
  }

  // ✅ NEW: Add item with custom discount
  void addItemWithDiscount(
    ProductModel product, {
    double quantity = 1.0,
    double? itemDiscountPercentage,
    double? categoryDiscountPercentage,
    double? manualDiscountPercentage,
    double? customPrice,
  }) {
    if (_items.containsKey(product.id)) {
      // If item exists, update quantity and discount
      _items[product.id]!.quantity += quantity;
      // Update discount if a new one is provided
      if (itemDiscountPercentage != null) {
        _items[product.id]!.itemDiscountPercentage = itemDiscountPercentage;
      }
      if (categoryDiscountPercentage != null) {
        _items[product.id]!.categoryDiscountPercentage =
            categoryDiscountPercentage;
      }
      if (manualDiscountPercentage != null) {
        _items[product.id]!.manualDiscountPercentage = manualDiscountPercentage;
      }
      if (customPrice != null) {
        _items[product.id]!.customPrice = customPrice;
      }
    } else {
      _items[product.id] = CartItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        product: product,
        quantity: quantity,
        itemDiscountPercentage: itemDiscountPercentage,
        categoryDiscountPercentage: categoryDiscountPercentage,
        manualDiscountPercentage: manualDiscountPercentage,
        customPrice: customPrice,
      );
    }
    notifyListeners();
  }

  // Update quantity (removes if <= 0)
  void updateQuantity(String productId, double quantity) {
    if (_items.containsKey(productId)) {
      if (quantity > 0) {
        _items[productId]!.quantity = quantity;
      } else {
        _items.remove(productId);
      }
      notifyListeners();
    }
  }

  void incrementQuantity(String productId) {
    if (_items.containsKey(productId)) {
      _items[productId]!.quantity++;
      notifyListeners();
    }
  }

  void decrementQuantity(String productId) {
    if (_items.containsKey(productId)) {
      if (_items[productId]!.quantity > 1) {
        _items[productId]!.quantity--;
      } else {
        _items.remove(productId);
      }
      notifyListeners();
    }
  }

  void removeItem(String productId) {
    _items.remove(productId);
    notifyListeners();
  }

  bool isInCart(String productId) {
    return _items.containsKey(productId);
  }

  double getQuantity(String productId) {
    return _items[productId]?.quantity ?? 0.0;
  }

  List<CartItem> getCartItems() {
    return _items.values.toList();
  }

  // Clear cart AND reset discounts
  void clear() {
    _items.clear();
    _orderDiscountPercentage = 0.0;
    _orderDiscountAmount = 0.0;
    _isPercentageDiscount = true;
    _selectedCategoryId = null; // ✅ NEW: Clear category
    _selectedCategoryName = null; // ✅ NEW: Clear category name
    notifyListeners();
  }

  // ✅ NEW: Set selected category
  void setSelectedCategory(String? categoryId, String? categoryName) {
    _selectedCategoryId = categoryId;
    _selectedCategoryName = categoryName;
    notifyListeners();
  }

  // Set order-level discount
  void setOrderDiscount({
    double percentage = 0.0,
    double amount = 0.0,
    required bool isPercentage,
  }) {
    _isPercentageDiscount = isPercentage;
    _orderDiscountPercentage = percentage;
    _orderDiscountAmount = amount;
    notifyListeners();
  }

  // Update item-level discount (called manually by user via dialog)
  void updateItemDiscount(String productId, double discountPercentage) {
    if (_items.containsKey(productId)) {
      final item = _items[productId]!;
      // Calculate what portion is manual vs auto discount
      final categoryDiscount = item.categoryDiscountPercentage ?? 0.0;
      final productOfferDiscount = item.product.discountPercentage;
      
      // Total discount = category + offer + manual
      // So manual = total - category - offer (but not less than 0)
      final autoDiscount = categoryDiscount + productOfferDiscount;
      final manualPortion = (discountPercentage - autoDiscount).clamp(0.0, 100.0);
      
      item.itemDiscountPercentage = discountPercentage;
      item.manualDiscountPercentage = manualPortion;
      notifyListeners();
    }
  }

  // ✅ NEW: Update auto-discounts (called when customer changes, preserving manual discount)
  void updateItemAutoDiscounts(
    String productId, {
    double? categoryDiscountPercentage,
    required double autoDiscountPercentage,
  }) {
    if (_items.containsKey(productId)) {
      final item = _items[productId]!;
      
      item.categoryDiscountPercentage = categoryDiscountPercentage;
      
      // Preserve existing manual discount
      final manualPortion = item.manualDiscountPercentage ?? 0.0;
      
      // The new total discount is auto + manual
      item.itemDiscountPercentage = autoDiscountPercentage + manualPortion;
      notifyListeners();
    }
  }
}
