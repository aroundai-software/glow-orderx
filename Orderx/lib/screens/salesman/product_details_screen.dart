import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/price_level_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/cart_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/category_discount_service.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/services/price_level_service.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:Orderx/services/promotional_discount_service.dart';
import 'package:Orderx/utils/rounding_utils.dart';

class ProductDetailsDialog extends StatefulWidget {
  final ProductModel product;
  final CustomerModel? customer;

  const ProductDetailsDialog({
    super.key,
    required this.product,
    this.customer,
  });

  static Future<void> show(
    BuildContext context, {
    required ProductModel product,
    CustomerModel? customer,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ProductDetailsDialog(
        product: product,
        customer: customer,
      ),
    );
  }

  @override
  State<ProductDetailsDialog> createState() => _ProductDetailsDialogState();
}

class _ProductDetailsDialogState extends State<ProductDetailsDialog> {
  double _quantity = 0.0;
  double _customPrice = 0.0;
  late TextEditingController _quantityController;
  late TextEditingController _discountPercentageController;
  late TextEditingController _discountAmountController;
  late TextEditingController _priceController;
  final FocusNode _quantityFocusNode = FocusNode();

  double _discountPercentage = 0.0;
  double _discountAmount = 0.0;
  bool _isEditingPercentage = false;
  bool _isEditingAmount = false;
  // Separate auto and manual discounts
  double _autoDiscountPercentage = 0.0;
  double _categoryDiscountPercentage = 0.0;
  double _manualDiscountPercentage = 0.0;
  double _manualDiscountAmount = 0.0;
  // ✅ From admin settings
  final AdminSettingsService _settingsService = AdminSettingsService();
  final CategoryDiscountService _categoryDiscountService =
      CategoryDiscountService();
  final PromotionalDiscountService _promoDiscountService =
      PromotionalDiscountService();
  final CustomerService _customerService = CustomerService();
  final ProductService _productService = ProductService();
  final PriceLevelService _priceLevelService = PriceLevelService();
  bool _allowItemDiscounts = true;
  bool _allowCategorySelection = true;
  bool _isFetchingDiscount = false;
  bool _hasAutoDiscount = false;
  String _discountType = ''; // 'category', 'combo', 'special'

  // Price Level (from price_level table)
  List<PriceLevelModel> _productPriceLevels = [];
  PriceLevelModel? _selectedPriceLevel;
  bool _isLoadingPriceLevels = false;

  // Category selection (fallback)
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  List<Map<String, dynamic>> _availableCategories = [];
  
  // Current stock tracking
  double _currentStock = 0.0;
  bool _hideStockQuantity = false;

  // Unit from DB (fetched fresh on dialog open)
  String _unit = '';

  @override
  void initState() {
    super.initState();
    _quantity = 0.0; // Start empty for user input
    _customPrice = widget.product.price; // Initialize with product's default price
    _currentStock = widget.product.stock; // Initialize with current stock
    _unit = widget.product.unit; // Initialize unit from product (will be refreshed from DB)
    _quantityController = TextEditingController(text: ''); // Empty field
    _discountPercentageController = TextEditingController(text: '');
    _discountAmountController = TextEditingController(text: '');
    _priceController = TextEditingController(text: widget.product.price.toStringAsFixed(2));
    _loadDiscountSetting();
    _loadCategorySelectionSetting();
    _loadStockVisibilitySetting();
    _loadCategories();
    _loadProductPriceLevels();
    _refreshCurrentStock(); // Refresh stock on dialog open
    _fetchFreshUnit(); // Fetch exact unit from DB on dialog open
    // Don't initialize auto discount until quantity is entered
    // _initializeAutoDiscount();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _quantityFocusNode.requestFocus();
      // Select all text (empty in this case, but cursor will be ready)
      _quantityController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _quantityController.text.length,
      );
    });
  }

  Future<void> _refreshCurrentStock() async {
    try {
      final currentStock = await _productService.getCurrentStock(widget.product.id);
      if (mounted) {
        setState(() {
          _currentStock = currentStock;
        });
      }
    } catch (e) {
      print('Error refreshing stock: $e');
      // Keep the original stock value if refresh fails
    }
  }

  /// Fetches the exact unit (ItemUnit) for this product directly from Supabase.
  /// This ensures the UI always shows the DB value, not a stale/cached fallback.
  Future<void> _fetchFreshUnit() async {
    try {
      final response = await _productService.getProductUnit(widget.product.id);
      if (mounted && response != null) {
        setState(() {
          _unit = response;
        });
      }
    } catch (e) {
      print('Error fetching unit from DB: $e');
      // Keep widget.product.unit as fallback
    }
  }

  void _loadDiscountSetting() async {
    final companyId = context.read<AuthProvider>().selectedCompanyId!;
    final allowItemDiscounts = await _settingsService.canUseItemDiscounts(companyId);
    setState(() {
      _allowItemDiscounts = allowItemDiscounts;
    });
  }

  void _loadCategorySelectionSetting() async {
    final companyId = context.read<AuthProvider>().selectedCompanyId!;
    final allowCategorySelection =
        await _settingsService.canUseCategorySelection(companyId);
    setState(() {
      _allowCategorySelection = allowCategorySelection;
    });
  }

  void _loadStockVisibilitySetting() async {
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId ?? authProvider.currentUser?.companyId;
    if (companyId != null) {
      final hide = await _settingsService.shouldHideStockQuantityFromSalesman(companyId);
      if (mounted) {
        setState(() {
          _hideStockQuantity = hide;
        });
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _customerService.getAllCustomerCategories();
      if (mounted) {
        // Check if Price Level is already selected in CartProvider
        final cartProvider = context.read<CartProvider>();
        final cartCategoryId = cartProvider.selectedCategoryId;
        final cartCategoryName = cartProvider.selectedCategoryName;
        
        setState(() {
          _availableCategories = categories;
          // Priority: CartProvider's selected category > Customer's default category > First available category
          if (cartCategoryId != null) {
            // Use Price Level from dashboard
            _selectedCategoryId = cartCategoryId;
            _selectedCategoryName = cartCategoryName;
            print('📊 Using Price Level from CartProvider: $cartCategoryName');
          } else if (widget.customer?.customerCategoryId != null) {
            // Fall back to customer's default category
            _selectedCategoryId = widget.customer!.customerCategoryId;
            // Find category name
            final category = categories.firstWhere(
              (c) => c['id'] == _selectedCategoryId,
              orElse: () => {},
            );
            _selectedCategoryName = category['category_name'] as String?;
            print('📊 Using customer default category: $_selectedCategoryName');
          } else if (categories.isNotEmpty) {
            _selectedCategoryId = categories.first['id'] as String?;
            _selectedCategoryName = categories.first['category_name'] as String?;
          }
        });
        // ✅ Fetch discounts immediately so category discount is visible without user input
        if (widget.customer != null && _selectedCategoryId != null) {
          Future.microtask(() => _fetchAllDiscounts());
        }
      }
    } catch (e) {
      print('Error loading categories: $e');
    }
  }

  Future<void> _loadProductPriceLevels() async {
    if (!mounted) return;
    setState(() => _isLoadingPriceLevels = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final priceLevels = await _priceLevelService.getPriceLevelsForProduct(
        productId: widget.product.id,
        productName: widget.product.productName,
        companyId: companyId,
      );
      if (mounted) {
        setState(() {
          _productPriceLevels = priceLevels;
          _isLoadingPriceLevels = false;
          if (priceLevels.isNotEmpty) {
            _updatePriceLevelForQuantity(_quantity, autoSelectFirstIfZero: true);
          }
        });
      }
    } catch (e) {
      print('Error loading price levels: $e');
      if (mounted) {
        setState(() => _isLoadingPriceLevels = false);
      }
    }
  }

  void _updatePriceLevelForQuantity(double qty, {bool autoSelectFirstIfZero = false}) {
    if (_productPriceLevels.isEmpty) return;

    PriceLevelModel? matchedSlab;
    if (qty > 0) {
      for (final slab in _productPriceLevels) {
        if (slab.matchesQuantity(qty)) {
          matchedSlab = slab;
          break;
        }
      }
      matchedSlab ??= _productPriceLevels.last;
    } else if (autoSelectFirstIfZero) {
      matchedSlab = _productPriceLevels.first;
    }

    if (matchedSlab != null && matchedSlab.id != _selectedPriceLevel?.id) {
      setState(() {
        _selectedPriceLevel = matchedSlab;
        _customPrice = matchedSlab!.rate;
        _priceController.text = matchedSlab.rate.toStringAsFixed(2);
        if (matchedSlab.unit.isNotEmpty) {
          _unit = matchedSlab.unit;
        }
        _recalculateDiscount();
      });
    }
  }

  Future<void> _fetchAllDiscounts() async {
    setState(() {
      _isFetchingDiscount = true;
    });

    try {
      print('🔄 [ProductDetailsDialog] Fetching discounts...');
      print('   Selected Category ID: $_selectedCategoryId');
      print('   Selected Category Name: $_selectedCategoryName');
      print('   Customer: ${widget.customer?.customerName}');
      print('   Product: ${widget.product.productName}');
      
      // Fetch category discount with category name (only if customer is selected)
      double categoryDiscount = 0.0;
      String? categoryName;
      if (widget.customer != null && _selectedCategoryId != null) {
        // Check discount for the selected category + product's item parent
        final authProvider = context.read<AuthProvider>();
        final companyId = authProvider.selectedCompanyId;
        print('   Company ID: $companyId');
        final discountInfo = await _categoryDiscountService
            .getCategoryDiscountForCategoryAndProduct(
          categoryId: _selectedCategoryId!,
          productId: widget.product.id,
          companyId: companyId,
        );
        categoryDiscount = discountInfo['discount'] as double;
        categoryName = discountInfo['categoryName'] as String?;

        print('   ✅ Discount fetched for category "$_selectedCategoryName":');
        print('      Category Discount: $categoryDiscount%');
        print('      Category Name from DB: $categoryName');
        if (categoryDiscount == 0) {
          print('      ⚠️ WARNING: Category discount is 0% - check if discount rule exists in database');
          print('         for category "$_selectedCategoryName" + product "${widget.product.productName}"');
        }

        // Update selected category name if found
        if (categoryName != null) {
          setState(() {
            _selectedCategoryName = categoryName;
          });
        }
      } else {
        print('   ❌ No discount fetch - Customer: ${widget.customer?.customerName}, Category ID: $_selectedCategoryId');
      }

      // Fetch promotional discount (always check, regardless of customer)
      final promoData = await _promoDiscountService.getPromotionalDiscount(
        productId: widget.product.id,
        requestedQuantity: _quantity > 0 ? _quantity.round() : 1,
      );

      if (!mounted) return;

      final comboDiscount = promoData['combo_discount'] as double;
      final specialDiscount = promoData['special_discount'] as double;
      final comboEligibleQty = promoData['combo_eligible_qty'] as int;

      // Calculate effective discount percentage based on actual amounts
      // This properly handles multiple discount types
      double finalDiscount = 0.0;
      String discountType = '';

      // ✅ FIXED: Use actual quantity or fallback to 1 for discount calculation
      final calculationQuantity = _quantity > 0 ? _quantity : 1;
      final basePrice = _customPrice;
      final totalBasePrice = basePrice * calculationQuantity;

      // Calculate discount amounts for each item
      double totalDiscountAmount = 0.0;

      // Determine which discount to apply based on priority:
      // Priority: Combo > Special > Category (only one promo discount applies)

      bool hasCombo = comboDiscount > 0 && comboEligibleQty > 0;
      bool hasSpecial = specialDiscount > 0;

      // 1. Category discount applies to ALL items (always stackable)
      if (categoryDiscount > 0) {
        totalDiscountAmount +=
            (basePrice * calculationQuantity * categoryDiscount / 100);
      }

      // 2. Apply promotional discount (combo takes priority over special)
      if (hasCombo) {
        // Combo discount applies ONLY to eligible items
        totalDiscountAmount +=
            (basePrice * comboEligibleQty * comboDiscount / 100);

        // For combo: calculate average discount that produces correct total discount amount
        // This ensures cart calculations work correctly (discount is applied per unit * quantity)
        finalDiscount = totalBasePrice > 0
            ? (totalDiscountAmount / totalBasePrice * 100)
            : 0.0;

        // For non-eligible items, apply category discount only (already counted above)
        // No additional calculation needed
      } else if (hasSpecial) {
        // Special discount applies to ALL items
        totalDiscountAmount +=
            (basePrice * calculationQuantity * specialDiscount / 100);

        // Calculate effective discount percentage for special discount
        finalDiscount = totalBasePrice > 0
            ? (totalDiscountAmount / totalBasePrice * 100)
            : 0.0;
      } else if (categoryDiscount > 0) {
        // Only category discount applies (no promotional discount)
        finalDiscount = categoryDiscount;
      }

      // Build discount description - ALWAYS show category if customer selected
      List<String> discountTypes = [];
      
      // ALWAYS show category discount when customer is selected (even if 0%)
      if (widget.customer != null && _selectedCategoryName != null) {
        if (categoryDiscount > 0) {
          discountTypes.add('$_selectedCategoryName ${categoryDiscount.toStringAsFixed(1)}%');
        } else {
          discountTypes.add('$_selectedCategoryName 0%');
        }
      }
      
      // Add promotional discounts if they exist
      if (hasCombo) {
        discountTypes.add(
            'Combo ${comboDiscount.toStringAsFixed(1)}%');
      } else if (hasSpecial) {
        discountTypes.add('Special ${specialDiscount.toStringAsFixed(1)}%');
      }

      discountType = discountTypes.join(' + ');

      print('   💰 Discount breakdown:');
      print(
          '      Selected Category: $_selectedCategoryName (ID: $_selectedCategoryId)');
      print('      Product: ${widget.product.productName} (ID: ${widget.product.id})');
      if (categoryDiscount > 0) {
        print(
            '      ✅ Category: $categoryDiscount% on all $calculationQuantity items');
      } else {
        print(
            '      ❌ Category: No discount for this category-product combination');
        print('         💡 To fix: Add a row in category_itemgroup_discounts table with:');
        print('            - customer_category_name = "$_selectedCategoryName"');
        print('            - ItemGroupName = (this product\'s item group name)');
        print('            - category_discount_percentage = (desired %)');
      }
      if (hasCombo) {
        print('      Combo: $comboDiscount% on $comboEligibleQty items');
        if (comboEligibleQty < calculationQuantity) {
          print(
              '      Note: ${calculationQuantity - comboEligibleQty} items not eligible for combo');
        }
      } else if (hasSpecial) {
        print(
            '      Special: $specialDiscount% on all $calculationQuantity items');
      }
      print(
          '      Total discount amount: ₹${totalDiscountAmount.toStringAsFixed(2)}');
      print('      Effective discount: ${finalDiscount.toStringAsFixed(2)}%');

      // Show discount badge when customer is selected OR there's a promo discount
      bool shouldShowDiscount =
          (widget.customer != null && _selectedCategoryName != null) || finalDiscount > 0;

      if (shouldShowDiscount) {
        print('💰 APPLYING DISCOUNT:');
        print('   Final Discount: $finalDiscount%');
        print('   Discount Type: $discountType');
        print('   Setting _hasAutoDiscount = true');
        print('   Setting _autoDiscountPercentage = $finalDiscount');
        
        setState(() {
          _hasAutoDiscount = true;
          _autoDiscountPercentage = finalDiscount;
          _discountType = discountType;
          _categoryDiscountPercentage = categoryDiscount;
          // Preserve manual discount and recalculate total
          _updateTotalDiscount();
        });
        print('💰 ✅ Discount UI should now show: $finalDiscount% ($discountType)');
      } else {
        print('💰 NO DISCOUNT TO APPLY:');
        print('   Category Discount: $categoryDiscount%');
        print('   Final Discount: $finalDiscount%');
        print('   Should Show: $shouldShowDiscount');
        print('   Setting _hasAutoDiscount = false');
        
        setState(() {
          _hasAutoDiscount = false;
          _autoDiscountPercentage = 0.0;
          _discountType = '';
          _categoryDiscountPercentage = categoryDiscount; // may be 0
          // Preserve manual discount and recalculate total
          _updateTotalDiscount();
        });
        print('💰 ✅ Discount UI should now show: 0%');
      }
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingDiscount = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _discountPercentageController.dispose();
    _discountAmountController.dispose();
    _priceController.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _incrementQuantity() {
    final currentManualPercentage = _manualDiscountPercentage;
    final currentPercentageText = _discountPercentageController.text;
    final currentAmountText = _discountAmountController.text;
    final hasManualDiscount = currentManualPercentage > 0 ||
        currentPercentageText.isNotEmpty ||
        currentAmountText.isNotEmpty;

    setState(() {
      _quantity = (_quantity + 1.0);
      _quantityController.text = _quantity == _quantity.truncateToDouble()
          ? _quantity.toInt().toString()
          : _quantity.toString();
    });

    _updatePriceLevelForQuantity(_quantity);
    // Re-fetch auto discounts as quantity changed (affects combo discount)
    _fetchAllDiscounts();

    // Restore manual discount if it was set
    if (hasManualDiscount) {
      setState(() {
        _manualDiscountPercentage = currentManualPercentage;
        _discountPercentageController.text = currentPercentageText;
        _discountAmountController.text = currentAmountText;
        _recalculateDiscount();
      });
    }
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      final currentManualPercentage = _manualDiscountPercentage;
      final currentPercentageText = _discountPercentageController.text;
      final currentAmountText = _discountAmountController.text;
      final hasManualDiscount = currentManualPercentage > 0 ||
          currentPercentageText.isNotEmpty ||
          currentAmountText.isNotEmpty;

      setState(() {
        _quantity = (_quantity - 1.0);
        _quantityController.text = _quantity == _quantity.truncateToDouble()
            ? _quantity.toInt().toString()
            : _quantity.toString();
      });

      _updatePriceLevelForQuantity(_quantity);
      // Re-fetch auto discounts as quantity changed (affects combo discount)
      _fetchAllDiscounts();

      // Restore manual discount if it was set
      if (hasManualDiscount) {
        setState(() {
          _manualDiscountPercentage = currentManualPercentage;
          _discountPercentageController.text = currentPercentageText;
          _discountAmountController.text = currentAmountText;
          _recalculateDiscount();
        });
      }
    }
  }

  void _onDiscountPercentageChanged(String value) {
    if (!_allowItemDiscounts) return; // disable edits when not allowed
    setState(() {
      _isEditingPercentage = true;
      _isEditingAmount = false;

      if (value.isEmpty) {
        _manualDiscountPercentage = 0.0;
        _manualDiscountAmount = 0.0;
        _discountAmountController.text = '';
        _updateTotalDiscount();
        return;
      }

      final parsed = double.tryParse(value) ?? 0.0;
      _manualDiscountPercentage = parsed.clamp(0.0, 100.0);

      // Calculate manual discount amount based on percentage (applied to already discounted price)
      if (_quantity <= 0) return; // Avoid calculations with zero quantity
      final basePrice = _customPrice * _quantity;
      final priceAfterAutoDiscount =
          basePrice - (basePrice * _autoDiscountPercentage / 100);
      _manualDiscountAmount =
          (priceAfterAutoDiscount * _manualDiscountPercentage / 100);

      _discountAmountController.text = _manualDiscountAmount > 0
          ? _manualDiscountAmount.toStringAsFixed(2)
          : '';
      _updateTotalDiscount();
    });
  }

  void _onDiscountAmountChanged(String value) {
    if (!_allowItemDiscounts) return; // disable edits when not allowed
    setState(() {
      _isEditingAmount = true;
      _isEditingPercentage = false;

      if (value.isEmpty) {
        _manualDiscountAmount = 0.0;
        _manualDiscountPercentage = 0.0;
        _discountPercentageController.text = '';
        _updateTotalDiscount();
        return;
      }

      final parsed = double.tryParse(value) ?? 0.0;
      if (_quantity <= 0) return; // Avoid calculations with zero quantity
      final basePrice = _customPrice * _quantity;
      final maxDiscount = basePrice;

      _manualDiscountAmount = parsed.clamp(0.0, maxDiscount);

      // Calculate manual discount percentage based on amount (relative to already discounted price)
      final priceAfterAutoDiscount =
          basePrice - (basePrice * _autoDiscountPercentage / 100);
      _manualDiscountPercentage = priceAfterAutoDiscount > 0
          ? (_manualDiscountAmount / priceAfterAutoDiscount * 100)
          : 0.0;

      _discountPercentageController.text = _manualDiscountPercentage > 0
          ? _manualDiscountPercentage.toStringAsFixed(2)
          : '';
      _updateTotalDiscount();
    });
  }

  void _updateTotalDiscount() {
    // Calculate total discount correctly: manual discount applies to already discounted amount
    if (_quantity <= 0) return; // Avoid calculations with zero quantity
    final basePrice = _customPrice * _quantity;

    // Step 1: Apply auto discount to base price
    final priceAfterAutoDiscount =
        basePrice - (basePrice * _autoDiscountPercentage / 100);

    // Step 2: Apply manual discount to already discounted price
    final manualDiscountAmount =
        priceAfterAutoDiscount * _manualDiscountPercentage / 100;

    // Step 3: Calculate total discount amount and effective percentage
    final totalDiscountAmount =
        (basePrice * _autoDiscountPercentage / 100) + manualDiscountAmount;
    final effectiveDiscountPercentage =
        basePrice > 0 ? (totalDiscountAmount / basePrice * 100) : 0.0;

    // Debug output to verify calculations
    if (_autoDiscountPercentage > 0 || _manualDiscountPercentage > 0) {
      print('🧮 Discount Calculation:');
      print('   Base Price: ₹${basePrice.toStringAsFixed(2)}');
      print('   Auto Discount: ${_autoDiscountPercentage.toStringAsFixed(1)}%');
      print(
          '   Price after auto discount: ₹${priceAfterAutoDiscount.toStringAsFixed(2)}');
      print(
          '   Manual Discount: ${_manualDiscountPercentage.toStringAsFixed(1)}% on discounted price');
      print(
          '   Manual Discount Amount: ₹${manualDiscountAmount.toStringAsFixed(2)}');
      print(
          '   Total Discount Amount: ₹${totalDiscountAmount.toStringAsFixed(2)}');
      print(
          '   Effective Discount %: ${effectiveDiscountPercentage.toStringAsFixed(2)}%');
      print(
          '   Final Price: ₹${(basePrice - totalDiscountAmount).toStringAsFixed(2)}');
    }

    // Update the main discount variables for backward compatibility
    _discountPercentage = effectiveDiscountPercentage;
    _discountAmount = totalDiscountAmount;
  }

  void _clearManualDiscount() {
    setState(() {
      _manualDiscountPercentage = 0.0;
      _manualDiscountAmount = 0.0;
      _discountPercentageController.clear();
      _discountAmountController.clear();
      _updateTotalDiscount();
    });
  }

  void _recalculateDiscount() {
    // Recalculate discount amount when quantity changes
    if (_quantity <= 0) return; // Avoid calculations with zero quantity
    if (_manualDiscountPercentage > 0) {
      final basePrice = _customPrice * _quantity;
      final priceAfterAutoDiscount =
          basePrice - (basePrice * _autoDiscountPercentage / 100);
      _manualDiscountAmount =
          (priceAfterAutoDiscount * _manualDiscountPercentage / 100);
      _discountAmountController.text = _manualDiscountAmount > 0
          ? _manualDiscountAmount.toStringAsFixed(2)
          : '';
    } else {
      _manualDiscountAmount = 0.0;
      _discountAmountController.text = '';
    }
    _updateTotalDiscount();
  }

  double get basePrice => _customPrice * _quantity;
  double get priceAfterDiscount => basePrice - _discountAmount;
  double get gstAmount => priceAfterDiscount * widget.product.gstRate / 100;
  double get totalWithGst => priceAfterDiscount + gstAmount;
  double get _unitPriceAfterDiscount {
    if (_discountPercentage <= 0) return _customPrice;
    return _customPrice - (_customPrice * _discountPercentage / 100);
  }

  double get _unitPriceWithGst {
    final unitPrice = _unitPriceAfterDiscount;
    return unitPrice + (unitPrice * widget.product.gstRate / 100);
  }

  void _addToCart() {
    final text = _quantityController.text.trim();

    final enteredQty = double.tryParse(text);
    if (enteredQty == null || enteredQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid quantity before adding to cart.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // Allow any quantity, including out-of-stock items

    setState(() {
      _quantity = enteredQty;
    });

    // Ensure totals are up-to-date for current quantity
    _updateTotalDiscount();

    // Add to cart with item-level discount
    final cartProvider = context.read<CartProvider>();

    // Check if manual discount is applied
    final bool hasManualDiscount = _allowItemDiscounts &&
        _manualDiscountPercentage > 0 &&
        (_discountPercentageController.text.isNotEmpty ||
            _discountAmountController.text.isNotEmpty);

    // Use the correctly calculated effective discount percentage for display/calculation
    // But pass manual discount separately for database storage
    // If no manual discount, use auto discount directly to avoid edge cases
    // where _discountPercentage wasn't recomputed when qty was 0 earlier
    final double effectiveDiscount = hasManualDiscount
        ? _discountPercentage
        : (_hasAutoDiscount ? _autoDiscountPercentage : 0.0);
    final double manualDiscount =
        hasManualDiscount ? _manualDiscountPercentage : 0.0;

    cartProvider.addItemWithDiscount(
      widget.product,
      quantity: _quantity,
      itemDiscountPercentage:
          effectiveDiscount, // Total effective discount for calculations
      categoryDiscountPercentage:
          _categoryDiscountPercentage > 0 ? _categoryDiscountPercentage : null,
      manualDiscountPercentage:
          manualDiscount, // Manual discount for database storage
      customPrice: _customPrice > 0 ? _customPrice : null,
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final isInCart = cartProvider.isInCart(widget.product.id);
    final cartQuantity = cartProvider.getQuantity(widget.product.id);

    // Stock validation removed - always allow out-of-stock items

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Container(
        color: Colors.white,
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Product Details',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryBlue,
                                      ),
                                ),
                                if (widget.customer != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text.rich(
                                      TextSpan(
                                        text: '(Ordering for: ',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.success,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: widget.customer!.customerName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const TextSpan(text: ')'),
                                        ],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: true,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 22),
                            onPressed: () => Navigator.pop(context),
                            color: AppTheme.primaryBlue,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),

                      // Product image
                      Center(
                        child: Container(
                          width: double.infinity,
                          height: 110,
                          decoration: BoxDecoration(
                            color: AppTheme.lightGrey,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: widget.product.imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    widget.product.imageUrl!,
                                    width: double.infinity,
                                    height: 110,
                                    fit: BoxFit.fitHeight,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          value: loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                              : null,
                                          color: AppTheme.primaryBlue,
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.broken_image,
                                            size: 40,
                                            color: AppTheme.grey,
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            'Image not available',
                                            style: TextStyle(
                                              color: AppTheme.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inventory_2,
                                      size: 46,
                                      color:
                                          AppTheme.primaryBlue.withOpacity(0.3),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'No image available',
                                      style: TextStyle(
                                        color: AppTheme.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Product name
                      Text(
                        widget.product.productName,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),

                      // Product code + quantity row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed:
                                _quantity > 1 ? _decrementQuantity : null,
                            icon: const Icon(Icons.remove_circle_outline),
                            iconSize: 20,
                            color: AppTheme.primaryBlue,
                          ),
                          SizedBox(
                            width: 48,
                            height: 26,
                            child: Focus(
                              onFocusChange: (hasFocus) {
                                if (hasFocus) {
                                  _quantityController.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset:
                                        _quantityController.text.length,
                                  );
                                }
                              },
                              child: TextField(
                                controller: _quantityController,
                                focusNode: _quantityFocusNode,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                enabled: true, // Always enabled
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryBlue,
                                ),
                                decoration: InputDecoration(
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(5),
                                    borderSide: const BorderSide(
                                        color: AppTheme.primaryBlue,
                                        width: 1.6),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(5),
                                    borderSide: const BorderSide(
                                        color: AppTheme.primaryBlue,
                                        width: 1.8),
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                ),
                                onChanged: (value) {
                                  if (value.isEmpty) {
                                    setState(() {
                                      _quantity = 0.0;
                                      _hasAutoDiscount = false;
                                      _autoDiscountPercentage = 0.0;
                                      _discountType = '';
                                      _categoryDiscountPercentage = 0.0;
                                      _manualDiscountPercentage = 0.0;
                                      _manualDiscountAmount = 0.0;
                                      _discountPercentageController.clear();
                                      _discountAmountController.clear();
                                    });
                                    return;
                                  }

                                  final parsed = double.tryParse(value) ?? 0.0;
                                  if (parsed <= 0) return;

                                  setState(() {
                                    _quantity = parsed;
                                    _recalculateDiscount();
                                  });
                                  _updatePriceLevelForQuantity(parsed);
                                  // Re-fetch discount as quantity changed (affects combo discount)
                                  _fetchAllDiscounts();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _incrementQuantity, // Always enabled
                            icon: const Icon(Icons.add_circle_outline),
                            iconSize: 20,
                            color: AppTheme.primaryBlue,
                          ),
                          const SizedBox(width: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'HSN: ${widget.product.hsn ?? "N/A"}',
                              style: const TextStyle(
                                color: AppTheme.primaryBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (!_hideStockQuantity) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Available Stock: $_currentStock',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.darkGrey,
                          ),
                        ),
                      ],

                      if (isInCart) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppTheme.success, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle,
                                  color: AppTheme.success, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'In cart (Qty: $cartQuantity)',
                                style: const TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      if (_isFetchingDiscount)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: LinearProgressIndicator(),
                        ),

                      // Discount Section (always show when item discounts are allowed or price levels exist)
                      if (_productPriceLevels.isNotEmpty || _allowItemDiscounts)
                        _buildCompactCard([
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _productPriceLevels.isNotEmpty
                                    ? 'Price Level'
                                    : 'Discount',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                              // ✅ Show badge: Price level rate if selected, or category / auto discount
                              if (_selectedPriceLevel != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: AppTheme.primaryBlue, width: 1),
                                  ),
                                  child: Text(
                                    '₹${_selectedPriceLevel!.rate.toStringAsFixed(2)} / ${_selectedPriceLevel!.unit}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryBlue,
                                    ),
                                  ),
                                )
                              else if (_hasAutoDiscount && _autoDiscountPercentage > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: AppTheme.success, width: 1),
                                  ),
                                  child: Text(
                                    _discountType.isNotEmpty ? _discountType : "Auto: ${_autoDiscountPercentage.toStringAsFixed(1)}%",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.success,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // Price Level selector from price_level table (ONLY if product has tiered slabs)
                          if (_productPriceLevels.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Price Level',
                                  style: TextStyle(
                                      fontSize: 11, color: AppTheme.grey),
                                ),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  value: _selectedPriceLevel?.id,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  items: _productPriceLevels.map((slab) {
                                    return DropdownMenuItem<String>(
                                      value: slab.id,
                                      child: Text(
                                        slab.displayLabel,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      final slab = _productPriceLevels
                                          .firstWhere((p) => p.id == value);
                                      setState(() {
                                        _selectedPriceLevel = slab;
                                        _customPrice = slab.rate;
                                        _priceController.text =
                                            slab.rate.toStringAsFixed(2);
                                        if (slab.unit.isNotEmpty) {
                                          _unit = slab.unit;
                                        }
                                        _recalculateDiscount();
                                      });
                                      if (_quantity > 0) {
                                        _fetchAllDiscounts();
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                          if (_hasAutoDiscount) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Category discount applied. Enter values below to add extra discount.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Additional Percentage (%)',
                                      style: TextStyle(
                                          fontSize: 11, color: AppTheme.grey),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _discountPercentageController,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        suffixText: '%',
                                        suffixStyle: const TextStyle(
                                            color: AppTheme.primaryBlue),
                                      ),
                                      onChanged: _onDiscountPercentageChanged,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Additional Amount (₹)',
                                      style: TextStyle(
                                          fontSize: 11, color: AppTheme.grey),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _discountAmountController,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        prefixText: '₹',
                                        prefixStyle: const TextStyle(
                                            color: AppTheme.primaryBlue),
                                      ),
                                      onChanged: _onDiscountAmountChanged,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Clear manual discount button
                          if (_manualDiscountPercentage > 0 ||
                              _discountPercentageController.text.isNotEmpty ||
                              _discountAmountController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton.icon(
                                onPressed: _clearManualDiscount,
                                icon: const Icon(Icons.clear,
                                    size: 16, color: AppTheme.warning),
                                label: const Text(
                                  'Clear Additional Discount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.warning,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                ),
                              ),
                            ),
                          ],
                          // Total discount summary
                          if (_hasAutoDiscount ||
                              _manualDiscountPercentage > 0) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color:
                                        AppTheme.primaryBlue.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Total Discount:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryBlue,
                                        ),
                                      ),
                                      Text(
                                        '${_discountPercentage.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_hasAutoDiscount &&
                                      _manualDiscountPercentage > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Auto: ${_autoDiscountPercentage.toStringAsFixed(1)}% + Additional: ${_manualDiscountPercentage.toStringAsFixed(1)}% on discounted price',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ]),

                      const SizedBox(height: 10),

                      // Price info
                      _buildCompactCard([
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Base Rate',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.darkGrey,
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              height: 32,
                              child: TextField(
                                controller: _priceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryBlue,
                                ),
                                decoration: InputDecoration(
                                  prefixText: '₹',
                                  prefixStyle: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.primaryBlue,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: _customPrice != widget.product.price
                                          ? AppTheme.warning
                                          : AppTheme.primaryBlue.withOpacity(0.4),
                                      width: 1.2,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                      color: AppTheme.primaryBlue,
                                      width: 1.6,
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  _priceController.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: _priceController.text.length,
                                  );
                                },
                                onChanged: (value) {
                                  final parsed = double.tryParse(value);
                                  if (parsed != null && parsed > 0) {
                                    setState(() {
                                      _customPrice = parsed;
                                      _recalculateDiscount();
                                    });
                                    if (_quantity > 0) _fetchAllDiscounts();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        _buildPriceRow('Unit', _unit.isNotEmpty ? _unit : '-'),
                        _buildPriceRow(
                            'GST Rate', '${widget.product.gstRate}%'),
                        if (_discountPercentage > 0) ...[
                          _buildPriceRow(
                            'Total Discount',
                            '${_discountPercentage.toStringAsFixed(1)}%',
                            color: AppTheme.success,
                          ),
                          _buildPriceRow(
                            'Discounted Price',
                            '₹${_unitPriceAfterDiscount.toStringAsFixed(2)}',
                            isBold: true,
                            color: AppTheme.success,
                          ),
                        ],
                        const Divider(height: 10),
                        _buildPriceRow(
                          'Rate with GST',
                          '₹${_unitPriceWithGst.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                      ]),

                      const SizedBox(height: 10),

                      // Total summary
                      // Price info section - ADD MRP HERE
                      _buildCompactCard([
                        // ✅ NEW: Show MRP if available
                        if (widget.product.mrp != null &&
                            widget.product.mrp! > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'MRP',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                ],
                              ),
                              Text(
                                '₹${widget.product.mrp!.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Show savings if MRP > selling price
                          if (widget.product.mrp! > widget.product.price)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: AppTheme.success, width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.savings,
                                      size: 12, color: AppTheme.success),
                                  const SizedBox(width: 4),
                                  Text(
                                    'You save ₹${(widget.product.mrp! - widget.product.price).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.success,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(height: 12, thickness: 0.5),
                        ],

                        // Existing price rows
                        _buildPriceRow(
                          'Quantity',
                          _quantity.toString(),
                          isBold: true,
                        ),
                        _buildPriceRow(
                          'Subtotal',
                          '₹${basePrice.toStringAsFixed(2)}',
                        ),
                        if (_discountPercentage > 0) ...[
                          _buildPriceRow(
                            'Discount (${_discountPercentage.toStringAsFixed(1)}%)',
                            '- ₹${_discountAmount.toStringAsFixed(2)}',
                            color: AppTheme.success,
                          ),
                          _buildPriceRow(
                            'After Discount',
                            '₹${priceAfterDiscount.toStringAsFixed(2)}',
                          ),
                        ],
                        _buildPriceRow(
                          'GST (${widget.product.gstRate}%)',
                          '₹${gstAmount.toStringAsFixed(2)}',
                        ),
                        if (calculateRoundOff(totalWithGst).numericRoundOff != 0) ...[
                          _buildPriceRow(
                            'Round Off',
                            calculateRoundOff(totalWithGst).formattedRoundOff,
                          ),
                        ],
                        const Divider(height: 10),
                        _buildPriceRow(
                          'Total Amount',
                          '₹${calculateRoundOff(totalWithGst).roundedTotal.toStringAsFixed(2)}',
                          isBold: true,
                          color: AppTheme.primaryBlue,
                        ),
                      ]),

                      const SizedBox(height: 16),

                      // Add to cart button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: !_isFetchingDiscount ? _addToCart : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !_isFetchingDiscount
                                ? AppTheme.primaryBlue
                                : AppTheme.grey.withOpacity(0.5),
                          ),
                          icon: const Icon(Icons.add_shopping_cart, size: 18),
                          label: Text(
                            isInCart ? 'ADD MORE' : 'ADD TO CART',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard(List<Widget> children) {
    return Card(
      color: AppTheme.lightGrey.withOpacity(0.4),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppTheme.darkGrey,
            )),
        Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? AppTheme.darkGrey,
            )),
      ],
    );
  }
}
