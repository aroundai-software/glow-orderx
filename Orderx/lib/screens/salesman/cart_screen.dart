import 'dart:async';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/cart_item_model.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/cart_provider.dart';
import 'package:Orderx/providers/connectivity_provider.dart';
import 'package:Orderx/providers/offline_data_provider.dart';
import 'package:Orderx/providers/offline_status_provider.dart';
import 'package:Orderx/screens/salesman/qr_scanner_screen.dart';
import 'package:Orderx/screens/salesman/product_selection_screen.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/category_discount_service.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/services/invoice_service.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:Orderx/services/promotional_discount_service.dart';
import 'package:Orderx/services/offline_order_queue_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/widgets/discount_dialog.dart';
import 'package:Orderx/widgets/item_discount_dialog.dart';
import 'package:Orderx/widgets/add_customer_dialog.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CartScreen extends StatefulWidget {
  final CustomerModel? preSelectedCustomer;
  const CartScreen({super.key, this.preSelectedCustomer});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isProcessingOrder = false;
  CustomerModel? _selectedCustomer;
  final CustomerService _customerService = CustomerService();
  final TextEditingController _itemCodeController = TextEditingController();
  final Map<String, TextEditingController> _quantityControllers = {};
  final AdminSettingsService _settingsService = AdminSettingsService();
  final TallyCompanyService _tallyCompanyService = TallyCompanyService();
  final CategoryDiscountService _categoryDiscountService =
      CategoryDiscountService();
  final PromotionalDiscountService _promoDiscountService =
      PromotionalDiscountService();
  final OfflineOrderQueueService _offlineOrderQueueService =
      OfflineOrderQueueService();
  String? _selectedCompanyName;
  String? _selectedCompanyIdForName;
  bool _isLoadingCompanyName = false;
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  bool _canScanQr = false;
  Timer? _debounceTimer;
  bool _allowOrderDiscounts = true;
  bool _allowItemDiscounts = true;
  bool _allowPaymentType = true;
  bool _hideStockQuantity = false;
  String _selectedLedger =
      'Credit'; // Default is Credit, can be 'Cash' or 'Credit'
  final FocusNode _searchFocusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  OverlayEntry? _overlayBarrierEntry;
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _gstController = TextEditingController();
  final TextEditingController _shippingAddressController =
      TextEditingController();
  final TextEditingController _shippingRemarksController =
      TextEditingController();
  final TextEditingController _dispatchedThroughController =
      TextEditingController();
  final TextEditingController _destinationController =
      TextEditingController();
  final List<CustomerModel> _customers = [];
  final List<CustomerModel> _filteredCustomers = [];
  List<Map<String, dynamic>> _availableCategories = [];
  bool _isLoadingCategories = false;

  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() => _isLoadingCategories = true);
    try {
      final categories = await _customerService.getAllCustomerCategories();
      if (mounted) {
        setState(() {
          _availableCategories = categories;
          _isLoadingCategories = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _ensureCompanyNameLoaded(String? companyId) async {
    if (companyId == null || companyId.isEmpty) {
      if (!mounted) return;
      if (_selectedCompanyName != null || _selectedCompanyIdForName != null) {
        setState(() {
          _selectedCompanyName = null;
          _selectedCompanyIdForName = null;
          _isLoadingCompanyName = false;
        });
      }
      return;
    }

    if (_isLoadingCompanyName || companyId == _selectedCompanyIdForName) return;

    if (mounted) {
      setState(() {
        _isLoadingCompanyName = true;
        _selectedCompanyIdForName = companyId;
      });
    }

    final company = await _tallyCompanyService.getCompanyById(companyId);
    if (!mounted) return;

    setState(() {
      _selectedCompanyName = company?.companyName;
      _isLoadingCompanyName = false;
    });
  }

  Future<void> _showAddCustomerDialog() async {
    final CustomerModel? newCustomer = await showDialog<CustomerModel>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddCustomerDialog(),
    );

    if (newCustomer != null && mounted) {
      setState(() {
        _selectedCustomer = newCustomer;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Customer "${newCustomer.customerName}" selected!'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Map<String, dynamic> _resetCartAfterOrder() {
    final cartProvider = context.read<CartProvider>();
    cartProvider.clear();
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();
    final clearedCustomer = _selectedCustomer;
    final shippingAddr = _shippingAddressController.text.trim();
    final disp = _dispatchedThroughController.text.trim();
    final dest = _destinationController.text.trim();
    final rem = _shippingRemarksController.text.trim();
    setState(() {
      _selectedCustomer = null;
      if (mounted) {
        _shippingAddressController.clear();
        _shippingRemarksController.clear();
        _dispatchedThroughController.clear();
        _destinationController.clear();
      }
    });
    return {
      'customer': clearedCustomer,
      'shippingAddress': shippingAddr,
      'dispatchedThrough': disp,
      'destination': dest,
      'remarks': rem,
    };
  }

  Future<void> _enqueueOfflineOrder({
    required AuthProvider authProvider,
    required List<CartItem> items,
    required double totalAmount,
    required double gstAmount,
    required double netAmount,
    required double orderDiscountAmount,
    required double orderDiscountPercentage,
    required double subtotalBeforeDiscount,
    required String? customerId,
    required String? customerName,
    required String? shippingAddress,
    required String? remarks,
    required String? dispatchedThrough,
    required String? destination,
    required String? companyId,
    required String? customerCategoryId,
    required String? customerCategoryName,
    required String? ledger,
  }) async {
    final payload = {
      'salesmanId': authProvider.currentUser!.id,
      'items': items.map((item) => item.toJson()).toList(),
      'totalAmount': totalAmount,
      'gstAmount': gstAmount,
      'netAmount': netAmount,
      'orderDiscountAmount': orderDiscountAmount,
      'orderDiscountPercentage': orderDiscountPercentage,
      'subtotalBeforeDiscount': subtotalBeforeDiscount,
      'customerId': customerId,
      'customerName': customerName,
      'shippingAddress': shippingAddress,
      'remarks': remarks,
      'dispatchedThrough': dispatchedThrough,
      'destination': destination,
      'companyId': companyId,
      'customerCategoryId': customerCategoryId,
      'customerCategoryName': customerCategoryName,
      'ledger': ledger,
      'orderNumber': 'OFF-${DateTime.now().millisecondsSinceEpoch}',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

    await _offlineOrderQueueService.enqueueOrder(payload);
    context.read<OfflineStatusProvider>().setHasOfflineData(true);
  }

  Future<void> _showItemDiscountDialog(
      BuildContext context, CartItem cartItem) async {
    if (!_allowItemDiscounts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item discounts are not allowed by admin settings.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => ItemDiscountDialog(
        productName: cartItem.product.productName,
        currentDiscountPercentage: cartItem.itemDiscountPercentage,
        basePrice: cartItem.effectivePrice,
        quantity: cartItem.quantity,
      ),
    );

    if (result == null) return;

    // Update the item discount
    final cartProvider = context.read<CartProvider>();
    cartProvider.updateItemDiscount(cartItem.product.id, result);
  }

  Future<void> _showOrderDiscountDialog(BuildContext context) async {
    final cartProvider = context.read<CartProvider>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => DiscountDialog(
        currentPercentage: cartProvider.orderDiscountPercentage,
        currentAmount: cartProvider.orderDiscountAmount,
        isPercentage: cartProvider.isPercentageDiscount,
        maxAmount: cartProvider.subtotal,
      ),
    );

    if (result == null) return;

    final isPercentage = result['isPercentage'] as bool? ?? true;
    final value = (result['value'] as double?) ?? 0.0;

    if (value <= 0) {
      cartProvider.setOrderDiscount(
        percentage: 0,
        amount: 0,
        isPercentage: isPercentage,
      );
      return;
    }

    if (isPercentage) {
      cartProvider.setOrderDiscount(
        percentage: value,
        amount: 0,
        isPercentage: true,
      );
    } else {
      cartProvider.setOrderDiscount(
        percentage: 0,
        amount: value,
        isPercentage: false,
      );
    }
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final customerData = {
        'customer_name': _nameController.text.trim(),
        'mobile_number': _mobileController.text.trim().isEmpty
            ? null
            : _mobileController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'state': _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        'pincode': _pincodeController.text.trim().isEmpty
            ? null
            : _pincodeController.text.trim(),
        'gst_number': _gstController.text.trim().isEmpty
            ? null
            : _gstController.text.trim(),
      };

      await _customerService.createCustomer(customerData);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add customer: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // NEW: Clear on first focus behavior
  bool _clearOnFirstFocus = true;

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.preSelectedCustomer;
    if (widget.preSelectedCustomer != null) {
      _shippingAddressController.text =
          widget.preSelectedCustomer!.fullAddress;
    }
    _itemCodeController.addListener(_onSearchChanged);

    // Ensure the field is empty when the screen is first shown.
    // This avoids leftover text and the need for the user to backspace.
    _itemCodeController.clear();

    // Add focus listener to clear only on the first focus (better UX).
    _searchFocusNode.addListener(_onSearchFocusChange);

    _loadSettings();
    _loadCategories();
  }

  void _onSearchFocusChange() {
    if (_searchFocusNode.hasFocus && _clearOnFirstFocus) {
      // Clear the field once when user first focuses the TextField
      _itemCodeController.clear();
      _clearOnFirstFocus = false;
    }
  }

  @override
  void dispose() {
    _itemCodeController.removeListener(_onSearchChanged);
    // remove focus listener explicitly
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _shippingAddressController.dispose();
    _shippingRemarksController.dispose();
    _dispatchedThroughController.dispose();
    _destinationController.dispose();
    // ✅ NEW
    _itemCodeController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _removeOverlay();
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();
    super.dispose();
  }

  Future<void> _selectCustomer() async {
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;
    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No company selected. Please enter the access key.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    List<CustomerModel> customers = [];
    try {
      final isOnline = context.read<ConnectivityProvider>().isOnline;
      customers = await context.read<OfflineDataProvider>().fetchCustomers(
            companyId: companyId,
            preferOnline: isOnline,
          );
    } catch (e) {
      print('Customer fetch error: $e');
    }
    if (!mounted) return;
    Navigator.pop(context);
    final selected = await showDialog<CustomerModel>(
      context: context,
      builder: (context) => _CustomerSelectionDialog(customers: customers),
    );
    if (selected != null) {
      setState(() {
        _selectedCustomer = selected;
        // ✅ Auto-fill shipping address with customer's address
        _shippingAddressController.text = selected.fullAddress ?? '';
        _shippingRemarksController.clear();
      });

      // ✅ Initialize selected category with customer's default category
      final cartProvider = context.read<CartProvider>();
      if (selected.customerCategoryId != null) {
        try {
          final categoryName = await _customerService
              .getCategoryNameById(selected.customerCategoryId!);
          if (mounted) {
            // Update CartProvider with customer's default category
            cartProvider.setSelectedCategory(
                selected.customerCategoryId, categoryName);
          }
        } catch (e) {
          print('⚠️ Error fetching category name: $e');
        }
      } else {
        // Clear category if customer has no default category
        cartProvider.setSelectedCategory(null, null);
      }

      // ✅ Recalculate discounts for all items in cart when customer is selected
      for (var productId in cartProvider.items.keys) {
        final cartItem = cartProvider.items[productId];
        if (cartItem != null) {
          _recalculateDiscountsForProduct(productId, cartItem.quantity);
        }
      }
    }
  }

  Future<void> _loadSettings() async {
    final companyId = context.read<AuthProvider>().selectedCompanyId!;
    final results = await Future.wait<bool>([
      _settingsService.canSalesmanScanQr(companyId),
      _settingsService.canUseOrderDiscounts(companyId),
      _settingsService.canUseItemDiscounts(companyId),
      _settingsService.canUsePaymentType(companyId),
      _settingsService.shouldHideStockQuantityFromSalesman(companyId),
    ]);

    if (!mounted) return;

    setState(() {
      _canScanQr = results[0];
      _allowOrderDiscounts = results[1];
      _allowItemDiscounts = results[2];
      _allowPaymentType = results[3];
      _hideStockQuantity = results[4];
      if (!_allowPaymentType) {
        _selectedLedger = 'Credit';
      }
    });

    if (!results[1]) {
      final cartProvider = context.read<CartProvider>();
      if (cartProvider.calculatedOrderDiscount > 0) {
        cartProvider.setOrderDiscount(
          percentage: 0,
          amount: 0,
          isPercentage: cartProvider.isPercentageDiscount,
        );
      }
    }
  }

  void _onSearchChanged() {
    // Cancel previous timer
    _debounceTimer?.cancel();

    final query = _itemCodeController.text.trim();
    if (query.isEmpty) {
      _removeOverlay();
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    // Show searching indicator immediately
    if (query.isNotEmpty) {
      setState(() => _isSearching = true);

      // Debounce: wait 400ms after user stops typing
      _debounceTimer = Timer(const Duration(milliseconds: 400), () {
        _searchProducts(query);
      });
    }
  }

  Future<void> _searchProducts(String query) async {
    if (!mounted) return;
    setState(() => _isSearching = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      if (companyId == null) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        return;
      }
      final isOnline = context.read<ConnectivityProvider>().isOnline;
      final results = await context.read<OfflineDataProvider>().searchProducts(
            query,
            companyId: companyId,
            preferOnline: isOnline,
          );
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
      if (results.isNotEmpty) {
        _showSearchOverlay();
      } else {
        _removeOverlay();
      }
    } catch (e) {
      print('Search error: $e');
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      _removeOverlay();
    }
  }

  void _showSearchOverlay() {
    _removeOverlay();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Full-screen barrier behind the results
    _overlayBarrierEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _removeOverlay,
          child: Container(
            color: Colors.black.withOpacity(0.3),
          ),
        ),
      ),
    );

    // Foreground results panel
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 16,
        right: 16,
        top: 150,
        child: Material(
          color: Colors.white,
          elevation: 8,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
            ),
            child: ListView.builder(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final product = _searchResults[index];
                final isOutOfStock = (product.stock ?? 0) <= 0;
                return ListTile(
                  enabled: true, // Always enable, allow out-of-stock items
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isOutOfStock
                          ? Colors.grey.withOpacity(0.3)
                          : AppTheme.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: product.imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ColorFiltered(
                              colorFilter: isOutOfStock
                                  ? const ColorFilter.mode(
                                      Colors.grey,
                                      BlendMode.saturation,
                                    )
                                  : const ColorFilter.mode(
                                      Colors.transparent,
                                      BlendMode.multiply,
                                    ),
                              child: Image.network(
                                product.imageUrl!,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.inventory_2,
                                    color: isOutOfStock
                                        ? Colors.grey
                                        : AppTheme.primaryBlue,
                                    size: 20,
                                  );
                                },
                              ),
                            ),
                          )
                        : Icon(
                            Icons.inventory_2,
                            color: isOutOfStock
                                ? Colors.grey
                                : AppTheme.primaryBlue,
                            size: 20,
                          ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.productName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isOutOfStock ? Colors.grey : Colors.black,
                          ),
                        ),
                      ),
                      if (isOutOfStock && !_hideStockQuantity)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppTheme.error,
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'Out of Stock',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    _hideStockQuantity
                        ? 'Code: ${product.productCode ?? "N/A"} • ₹${product.price.toStringAsFixed(2)}'
                        : 'Code: ${product.productCode ?? "N/A"} • ₹${product.price.toStringAsFixed(2)} • Stock: ${product.stock}${isOutOfStock ? " (Out of Stock)" : ""}',
                    style: TextStyle(
                      fontSize: 12,
                      color: (isOutOfStock && !_hideStockQuantity)
                          ? Colors.orange
                          : AppTheme.grey,
                    ),
                  ),
                  onTap: () {
                    _addProductToCart(product);
                    _itemCodeController.clear();
                    _removeOverlay();
                    _searchFocusNode.unfocus();
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    final overlayState = Overlay.of(context);
    overlayState.insert(_overlayBarrierEntry!);
    overlayState.insert(_overlayEntry!);
    }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _overlayBarrierEntry?.remove();
    _overlayBarrierEntry = null;
  }

  Future<void> _addProductToCart(dynamic product) async {
    final cartProvider = context.read<CartProvider>();
    // Remove stock validation - allow out-of-stock items

    // Fetch category discount based on selected Price Level or customer's category
    double categoryDiscount = 0.0;
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;

    // Check if a Price Level is selected
    final selectedCategoryId = cartProvider.selectedCategoryId;

    if (selectedCategoryId != null) {
      // Use selected Price Level for discount calculation
      print(
          '🔍 Fetching discount for Price Level: ${cartProvider.selectedCategoryName} ($selectedCategoryId)');
      print('🔍 Product: ${product.productName} (${product.id})');
      print('🔍 Company ID: $companyId');
      try {
        final discountInfo = await _categoryDiscountService
            .getCategoryDiscountForCategoryAndProduct(
          categoryId: selectedCategoryId,
          productId: product.id,
          companyId: companyId,
        );
        categoryDiscount = discountInfo['discount'] as double;
        print('✅ Category Discount Found: $categoryDiscount%');
      } catch (e) {
        print('❌ Error fetching category discount: $e');
      }
    } else if (_selectedCustomer != null) {
      // Fall back to customer's default category
      print(
          '🔍 Fetching discount for Customer: ${_selectedCustomer!.customerName} (${_selectedCustomer!.id})');
      print('🔍 Product: ${product.productName} (${product.id})');
      print('🔍 Company ID: $companyId');
      try {
        categoryDiscount = await _categoryDiscountService.getCategoryDiscount(
          customerId: _selectedCustomer!.id,
          productId: product.id,
          companyId: companyId,
        );
        print('✅ Category Discount Found: $categoryDiscount%');
      } catch (e) {
        print('❌ Error fetching category discount: $e');
      }
    } else {
      print('⚠️ No customer or price level selected - discount will be 0%');
    }

    // Fetch promotional discounts (ComboQtyOffTake and SpecialDiscount)
    final currentCartQuantity = cartProvider.getQuantity(product.id);
    final newQuantity = currentCartQuantity + 1;
    double comboDiscount = 0.0;
    double specialDiscount = 0.0;
    int comboEligibleQty = 0;
    try {
      final promoData = await _promoDiscountService.getPromotionalDiscount(
        productId: product.id,
        requestedQuantity: newQuantity.round(),
      );
      comboDiscount = promoData['combo_discount'] as double;
      specialDiscount = promoData['special_discount'] as double;
      comboEligibleQty = promoData['combo_eligible_qty'] as int;
      print(
          '🎁 Promotional Discounts - Combo: $comboDiscount%, Special: $specialDiscount%');
    } catch (e) {
      print('❌ Error fetching promotional discount: $e');
    }

    // Calculate effective discount based on priority
    // Priority: Combo > Special (only one promo discount applies)
    bool hasCombo = comboDiscount > 0 && comboEligibleQty > 0;
    bool hasSpecial = specialDiscount > 0;
    
    // Default to the product's own base discount if no special/combo promo exists
    double baseProductDiscount = product.discountPercentage;

    double totalDiscountAmount = 0.0;
    final basePrice = product.price;
    final totalBasePrice = basePrice * newQuantity;

    // 1. Category discount applies to ALL items (always stackable)
    if (categoryDiscount > 0) {
      totalDiscountAmount += (basePrice * newQuantity * categoryDiscount / 100);
    }

    // 2. Apply promotional discount (combo takes priority over special over base product discount)
    double totalDiscount = 0.0;
    if (hasCombo) {
      // Combo discount applies ONLY to eligible items
      totalDiscountAmount +=
          (basePrice * comboEligibleQty * comboDiscount / 100);
      // For combo: calculate average discount that produces correct total discount amount
      // This ensures cart calculations work correctly (discount is applied per unit * quantity)
      totalDiscount = totalBasePrice > 0
          ? (totalDiscountAmount / totalBasePrice * 100)
          : 0.0;
      print(
          '🧮 Combo: $comboDiscount% on $comboEligibleQty items (${newQuantity - comboEligibleQty} not eligible)');
      print(
          '🧮 Effective discount for cart: $totalDiscount% (ensures correct total discount amount)');
    } else if (hasSpecial) {
      // Special discount applies to ALL items
      totalDiscountAmount += (basePrice * newQuantity * specialDiscount / 100);
      // Calculate effective discount percentage for special discount
      totalDiscount = totalBasePrice > 0
          ? (totalDiscountAmount / totalBasePrice * 100)
          : 0.0;
      print('🧮 Special: $specialDiscount% on all $newQuantity items');
    } else if (baseProductDiscount > 0) {
      // Use the product's base discount
      totalDiscountAmount += (basePrice * newQuantity * baseProductDiscount / 100);
      totalDiscount = totalBasePrice > 0
          ? (totalDiscountAmount / totalBasePrice * 100)
          : 0.0;
      print('🧮 Base Product Discount: $baseProductDiscount% on all $newQuantity items');
    } else if (categoryDiscount > 0) {
      // Only category discount applies (no promotional discount)
      totalDiscount = categoryDiscount;
      print('🧮 Category: $categoryDiscount% on all $newQuantity items');
    }

    print(
        '💰 Total Discount Applied: $totalDiscount% (Discount Amount: ₹${totalDiscountAmount.toStringAsFixed(2)})');

    // Add to cart with discount
    cartProvider.addItemWithDiscount(
      product,
      itemDiscountPercentage: totalDiscount,
      categoryDiscountPercentage:
          categoryDiscount > 0 ? categoryDiscount : null,
    );
  }

  /// Recalculate discounts for a product based on new quantity
  Future<void> _recalculateDiscountsForProduct(
      String productId, double newQuantity) async {
    final cartProvider = context.read<CartProvider>();
    final cartItem = cartProvider.items[productId];
    if (cartItem == null) return;

    final product = cartItem.product;

    // Fetch category discount based on selected Price Level or customer's category
    double categoryDiscount = 0.0;
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;

    // Check if a Price Level is selected
    final selectedCategoryId = cartProvider.selectedCategoryId;

    if (selectedCategoryId != null) {
      // Use selected Price Level for discount calculation
      try {
        final discountInfo = await _categoryDiscountService
            .getCategoryDiscountForCategoryAndProduct(
          categoryId: selectedCategoryId,
          productId: product.id,
          companyId: companyId,
        );
        categoryDiscount = discountInfo['discount'] as double;
        print('✅ Category Discount (Price Level): $categoryDiscount%');
      } catch (e) {
        print('❌ Error fetching category discount: $e');
      }
    } else if (_selectedCustomer != null) {
      // Fall back to customer's default category
      try {
        categoryDiscount = await _categoryDiscountService.getCategoryDiscount(
          customerId: _selectedCustomer!.id,
          productId: product.id,
          companyId: companyId,
        );
        print('✅ Category Discount: $categoryDiscount%');
      } catch (e) {
        print('❌ Error fetching category discount: $e');
      }
    }

    // Fetch promotional discounts (ComboQtyOffTake and SpecialDiscount)
    double comboDiscount = 0.0;
    double specialDiscount = 0.0;
    int comboEligibleQty = 0;
    try {
      final promoData = await _promoDiscountService.getPromotionalDiscount(
        productId: product.id,
        requestedQuantity: newQuantity.round(),
      );
      comboDiscount = promoData['combo_discount'] as double;
      specialDiscount = promoData['special_discount'] as double;
      comboEligibleQty = promoData['combo_eligible_qty'] as int;
      print(
          '🎁 Promotional Discounts - Combo: $comboDiscount%, Special: $specialDiscount%');
    } catch (e) {
      print('❌ Error fetching promotional discount: $e');
    }

    // Calculate effective discount based on priority
    // Priority: Combo > Special (only one promo discount applies)
    bool hasCombo = comboDiscount > 0 && comboEligibleQty > 0;
    bool hasSpecial = specialDiscount > 0;
    
    // Default to the product's own base discount if no special/combo promo exists
    double baseProductDiscount = product.discountPercentage;

    double totalDiscountAmount = 0.0;
    final basePrice = product.price;
    final totalBasePrice = basePrice * newQuantity;

    // 1. Category discount applies to ALL items (always stackable)
    if (categoryDiscount > 0) {
      totalDiscountAmount += (basePrice * newQuantity * categoryDiscount / 100);
    }

    // 2. Apply promotional discount (combo takes priority over special over base product discount)
    double totalAutoDiscount = 0.0;
    if (hasCombo) {
      // Combo discount applies ONLY to eligible items
      totalDiscountAmount +=
          (basePrice * comboEligibleQty * comboDiscount / 100);
      // For combo: calculate average discount that produces correct total discount amount
      // This ensures cart calculations work correctly (discount is applied per unit * quantity)
      totalAutoDiscount = totalBasePrice > 0
          ? (totalDiscountAmount / totalBasePrice * 100)
          : 0.0;
      print(
          '🧮 Combo: $comboDiscount% on $comboEligibleQty items (${newQuantity - comboEligibleQty} not eligible)');
      print(
          '🧮 Effective auto-discount for cart: $totalAutoDiscount% (ensures correct total discount amount)');
    } else if (hasSpecial) {
      // Special discount applies to ALL items
      totalDiscountAmount += (basePrice * newQuantity * specialDiscount / 100);
      // Calculate effective discount percentage for special discount
      totalAutoDiscount = totalBasePrice > 0
          ? (totalDiscountAmount / totalBasePrice * 100)
          : 0.0;
      print('🧮 Special: $specialDiscount% on all $newQuantity items');
    } else if (baseProductDiscount > 0) {
      // Use the product's base discount
      totalDiscountAmount += (basePrice * newQuantity * baseProductDiscount / 100);
      totalAutoDiscount = totalBasePrice > 0
          ? (totalDiscountAmount / totalBasePrice * 100)
          : 0.0;
      print('🧮 Base Product Discount: $baseProductDiscount% on all $newQuantity items');
    } else if (categoryDiscount > 0) {
      // Only category discount applies
      totalAutoDiscount = categoryDiscount;
      print('🧮 Category: $categoryDiscount% on all $newQuantity items');
    }

    print(
        '💰 Total Auto-Discount Applied: $totalAutoDiscount% for quantity $newQuantity (Discount Amount: ₹${totalDiscountAmount.toStringAsFixed(2)})');

    // Update the auto-discount in cart (preserving manual discount)
    cartProvider.updateItemAutoDiscounts(
      productId, 
      autoDiscountPercentage: totalAutoDiscount,
      categoryDiscountPercentage: categoryDiscount > 0 ? categoryDiscount : null,
    );
  }

  TextEditingController _getOrCreateController(String productId, double quantity) {
    final display = quantity == quantity.truncateToDouble()
        ? quantity.toInt().toString()
        : quantity.toString();
    if (!_quantityControllers.containsKey(productId)) {
      _quantityControllers[productId] = TextEditingController(text: display);
    } else {
      if (_quantityControllers[productId]!.text != display) {
        _quantityControllers[productId]!.text = display;
      }
    }
    return _quantityControllers[productId]!;
  }

  Future<void> _scanQRCode() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const QRScannerScreen(),
      ),
    );
    if (scannedCode != null && mounted) {
      _fetchAndAddProduct(context, scannedCode);
    }
  }

  Future<void> _addItemByCode() async {
    final code = _itemCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an item code'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }
    _fetchAndAddProduct(context, code);
    _itemCodeController.clear();
  }

  Future<void> _fetchAndAddProduct(BuildContext context, String code) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final isOnline = context.read<ConnectivityProvider>().isOnline;
      final productService = ProductService();
      ProductModel? product;
      if (isOnline) {
        try {
          product = await productService.getProductByCode(code, companyId: companyId);
        } catch (e) {
          print('Online product fetch failed, trying cache: $e');
        }
      }
      if (product == null && companyId != null) {
        final cachedProducts =
            await context.read<OfflineDataProvider>().getCachedProducts(
                  companyId: companyId,
                );
        final normalized = code.trim().toLowerCase();
        product = cachedProducts.firstWhere(
          (cached) =>
              (cached.productCode?.toLowerCase() == normalized) ||
              (cached.vtNumber?.toLowerCase() == normalized),
          orElse: () {
            try {
              return cachedProducts.firstWhere(
                (cached) => cached.productName.toLowerCase().contains(normalized),
              );
            } catch (_) {
              return cachedProducts.first;
            }
          },
        );
      }
      if (!context.mounted) return;
      // Wait to prevent Navigator lock
      await Future.delayed(const Duration(milliseconds: 150));
      Navigator.pop(context);
      if (product != null) {
        // Allow out-of-stock items to be added via QR scan
        await _addProductToCart(product);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Product not found in selected company')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      // Wait to prevent Navigator lock
      await Future.delayed(const Duration(milliseconds: 150));
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  void _showDeleteConfirmation(
      BuildContext context, String productId, String productName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove $productName from cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<CartProvider>().removeItem(productId);
              _quantityControllers[productId]?.dispose();
              _quantityControllers.remove(productId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Item removed from cart')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _proceedToCheckout(BuildContext context) async {
    final cartProvider = context.read<CartProvider>();
    final authProvider = context.read<AuthProvider>();
    final isOnline = context.read<ConnectivityProvider>().isOnline;
    if (cartProvider.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cart is empty!'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a customer first'),
          backgroundColor: AppTheme.warning,
          action: SnackBarAction(
            label: 'SELECT',
            textColor: Colors.white,
            onPressed: _selectCustomer,
          ),
        ),
      );
      return;
    }

    if (_isProcessingOrder) return;
    
    setState(() {
      _isProcessingOrder = true;
    });
    try {
      final orderService = OrderService();
      final List<CartItem> orderItems =
          List<CartItem>.from(cartProvider.getCartItems());
      // Calculate totals with order discount
      final subtotalBeforeDiscount = cartProvider.subtotal;
      final orderDiscountAmount = cartProvider.calculatedOrderDiscount;
      final orderDiscountPercentage = cartProvider.orderDiscountPercentage;
      final subtotalAfterDiscount = cartProvider.subtotalAfterDiscount;
      final orderGstAmount = cartProvider.totalGst;
      final orderNetAmount = subtotalAfterDiscount + orderGstAmount;

      // ✅ Check if customer is temporary (not saved in database)
      final isTemporaryCustomer = _selectedCustomer!.id.startsWith('temp_');

      if (!isOnline) {
        await _enqueueOfflineOrder(
          authProvider: authProvider,
          items: orderItems,
          totalAmount: subtotalAfterDiscount,
          gstAmount: orderGstAmount,
          netAmount: orderNetAmount,
          orderDiscountAmount: orderDiscountAmount,
          orderDiscountPercentage: orderDiscountPercentage,
          subtotalBeforeDiscount: subtotalBeforeDiscount,
          customerId: isTemporaryCustomer ? null : _selectedCustomer!.id,
          customerName: _selectedCustomer!.customerName,
          shippingAddress: _shippingAddressController.text.trim(),
          remarks: _shippingRemarksController.text.trim(),
          dispatchedThrough: _dispatchedThroughController.text.trim(),
          destination: _destinationController.text.trim(),
          companyId: authProvider.selectedCompanyId,
          customerCategoryId: cartProvider.selectedCategoryId,
          customerCategoryName: cartProvider.selectedCategoryName,
          ledger: _selectedLedger,
        );
        _resetCartAfterOrder();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Order queued offline and will sync automatically when online.'),
            backgroundColor: AppTheme.warning,
          ),
        );
        Navigator.pop(context, true);
        return;
      }

      // ✅ Create Sales Order using OrderService
      final orderNumber = await orderService.createOrder(
        salesmanId: authProvider.currentUser!.id,
        items: cartProvider.getCartItems(),
        totalAmount: subtotalAfterDiscount,
        gstAmount: orderGstAmount,
        netAmount: orderNetAmount,
        orderDiscountAmount: orderDiscountAmount,
        orderDiscountPercentage: orderDiscountPercentage,
        subtotalBeforeDiscount: subtotalBeforeDiscount,
        customerId: isTemporaryCustomer ? null : _selectedCustomer!.id,
        customerName: _selectedCustomer!.customerName,
        shippingAddress: _shippingAddressController.text.trim(),
        remarks: _shippingRemarksController.text.trim(),
        dispatchedThrough: _dispatchedThroughController.text.trim(),
        destination: _destinationController.text.trim(),
        companyId: authProvider.selectedCompanyId,
        customerCategoryId: cartProvider.selectedCategoryId,
        customerCategoryName: cartProvider.selectedCategoryName,
        ledger: _selectedLedger,
      );

      if (!context.mounted) return;
      final resetData = _resetCartAfterOrder();
      final clearedCustomer = resetData['customer'] as CustomerModel?;
      final shippingAddr = resetData['shippingAddress'] as String? ?? '';
      final rem = resetData['remarks'] as String? ?? '';
      final disp = resetData['dispatchedThrough'] as String? ?? '';
      final dest = resetData['destination'] as String? ?? '';
      final String? dialogResult = await _showOrderSuccessDialog(
        context,
        orderNumber,
        clearedCustomer!,
        orderNetAmount,
      );
      if (dialogResult == 'share' && context.mounted) {
        // Fetch full company details for PDF header
        TallyCompanyModel? company;
        String? companyName;
        try {
          final selectedCompanyId = authProvider.selectedCompanyId;
          if (selectedCompanyId != null && selectedCompanyId.isNotEmpty) {
            final tallyCompanyService = TallyCompanyService();
            company =
                await tallyCompanyService.getCompanyById(selectedCompanyId);
            companyName = company?.companyName;
          }
        } catch (e) {
          print('⚠️ Error fetching company for PDF: $e');
        }

        await _generateAndSharePdf(
          orderNumber,
          orderItems,
          subtotalBeforeDiscount,
          orderGstAmount,
          orderNetAmount,
          clearedCustomer,
          authProvider,
          shippingAddr,
          rem,
          disp,
          dest,
          orderDiscountAmount,
          orderDiscountPercentage,
          company: company,
          companyName: companyName,
        );
      }
      if (context.mounted) {
        await Future.delayed(const Duration(milliseconds: 150));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!context.mounted) return;
      final isOnlineNow = context.read<ConnectivityProvider>().isOnline;
      if (!isOnlineNow) {
        await _enqueueOfflineOrder(
          authProvider: authProvider,
          items: cartProvider.getCartItems(),
          totalAmount: cartProvider.subtotalAfterDiscount,
          gstAmount: cartProvider.totalGst,
          netAmount: cartProvider.subtotalAfterDiscount + cartProvider.totalGst,
          orderDiscountAmount: cartProvider.calculatedOrderDiscount,
          orderDiscountPercentage: cartProvider.orderDiscountPercentage,
          subtotalBeforeDiscount: cartProvider.subtotal,
          customerId: _selectedCustomer == null
              ? null
              : (_selectedCustomer!.id.startsWith('temp_')
                  ? null
                  : _selectedCustomer!.id),
          customerName: _selectedCustomer?.customerName,
          shippingAddress: _shippingAddressController.text.trim(),
          remarks: _shippingRemarksController.text.trim(),
          dispatchedThrough: _dispatchedThroughController.text.trim(),
          destination: _destinationController.text.trim(),
          companyId: authProvider.selectedCompanyId,
          customerCategoryId: cartProvider.selectedCategoryId,
          customerCategoryName: cartProvider.selectedCategoryName,
          ledger: _selectedLedger,
        );
        _resetCartAfterOrder();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Invoice saved offline and will sync once internet is available.'),
            backgroundColor: AppTheme.warning,
          ),
        );
        Navigator.pop(context, true);
        return;
      }
      String errorMessage = 'Error creating invoice: ${e.toString()}';
      if (e.toString().contains('Insufficient stock') ||
          e.toString().contains('Not enough stock')) {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingOrder = false;
        });
      }
    }
  }

  Future<String?> _showOrderSuccessDialog(
    BuildContext context,
    String orderNumber,
    CustomerModel customer,
    double netAmount,
  ) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.1),
                    shape: BoxShape.circle),
                child:
                    const Icon(Icons.check_circle, color: AppTheme.success, size: 48),
              ),
              const SizedBox(height: 16),
              const Text('Order Created Successfully!',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Order #',
                        style: TextStyle(color: AppTheme.grey, fontSize: 14)),
                    const SizedBox(width: 8),
                    Text(orderNumber,
                        style: const TextStyle(
                            color: AppTheme.primaryBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Customer: ${customer.customerName}',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Text('Total Amount: ₹${calculateRoundOff(netAmount).roundedTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.success)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, 'close');
              },
              child: const Text('CLOSE'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, 'share');
              },
              icon: const Icon(Icons.share),
              label: const Text('SHARE PDF'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateAndSharePdf(
    String orderNumber,
    List<dynamic> orderItems,
    double subtotalBeforeDiscount,
    double gstAmount,
    double netAmount,
    CustomerModel customer,
    AuthProvider authProvider,
    String shippingAddress,
    String remarks,
    String dispatchedThrough,
    String destination,
    double orderDiscountAmount,
    double orderDiscountPercentage, {
    TallyCompanyModel? company,
    String? companyName,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Generating PDF...',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
    try {
      final order = OrderModel(
        id: '',
        orderNumber: orderNumber,
        customerName: customer.customerName,
        customerId: customer.id,
        salesmanId: authProvider.currentUser!.id,
        orderDate: DateTime.now().toUtc(),
        subtotalBeforeDiscount: subtotalBeforeDiscount,
        orderDiscountAmount: orderDiscountAmount,
        orderDiscountPercentage: orderDiscountPercentage,
        totalAmount: subtotalBeforeDiscount - orderDiscountAmount,
        gstAmount: gstAmount,
        netAmount: netAmount,
        status: 'pending',
        syncedToTally: false,
        createdAt: DateTime.now().toUtc(),
        customerMobile: customer.mobileNumber,
        customerAddress: customer.fullAddress,
        customerGst: customer.gstNumber,
        shippingAddress: shippingAddress,
        remarks: remarks,
        dispatchedThrough: dispatchedThrough,
        destination: destination,
        companyId: authProvider.selectedCompanyId,
        companyName: companyName,
      );

      final items = orderItems.map((cartItem) {
        // Use manual discount for PDF display (what user entered)
        final manualDiscountPercentage =
            cartItem.manualDiscountPercentage ?? 0.0;
        final categoryDiscountPercentage =
            cartItem.categoryDiscountPercentage ?? 0.0;
        final offerDiscountPercentage =
            cartItem.product.discountPercentage; // Special offer from product

        // Calculate discount amounts
        final basePrice = cartItem.effectivePrice;
        final qty = cartItem.quantity;

        // Cash Discount (Category) - calculated on base price
        final cashDiscountAmount = (categoryDiscountPercentage > 0)
            ? (basePrice * categoryDiscountPercentage / 100) * qty
            : 0.0;

        // Offer Discount (Special offer) - calculated on base price
        final offerDiscountAmount = (offerDiscountPercentage > 0)
            ? (basePrice * offerDiscountPercentage / 100) * qty
            : 0.0;

        // Item Discount (Manual) - calculated on already discounted price
        final priceAfterAutoDiscount =
            basePrice - (basePrice * categoryDiscountPercentage / 100);
        final itemDiscountAmount = (manualDiscountPercentage > 0)
            ? (priceAfterAutoDiscount * manualDiscountPercentage / 100) * qty
            : 0.0;

        return OrderItemModel(
          id: '',
          orderId: '',
          productId: cartItem.product.id,
          ItemName: cartItem.product.productName,
          PartNumber: cartItem.product.productCode,
          vtNumber: cartItem.product.vtNumber,
          hsn: cartItem.product.hsn,
          ItemQuantity: cartItem.quantity,
          ItemRate: cartItem.effectivePrice,
          GstRate: cartItem.product.gstRate,
          gstAmount: cartItem.subtotal * (cartItem.product.gstRate / 100),
          totalAmount: cartItem.subtotal + (cartItem.subtotal * (cartItem.product.gstRate / 100)),
          discountPercentage:
              manualDiscountPercentage, // Use manual discount percentage
          discountAmount:
              itemDiscountAmount, // Calculate manual discount amount
          mrp: cartItem.product.mrp,
          cashDiscountAmount: cashDiscountAmount,
          offerDiscountAmount: offerDiscountAmount,
          itemDiscountAmount: itemDiscountAmount,
        );
      }).toList();

      final pdfService = PdfService();
      final pdfBytes = await pdfService.generateOrderPdf(
        order,
        items,
        company: company,
        companyName: companyName,
        documentTitle: 'SALES ORDER',
      );
      if (!context.mounted) return;
      await Future.delayed(const Duration(milliseconds: 150));
      Navigator.pop(context);
      await pdfService.sharePdf(pdfBytes, orderNumber, filenamePrefix: 'Invoice_');
    } catch (e) {
      if (!context.mounted) return;
      await Future.delayed(const Duration(milliseconds: 150));
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing PDF: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final authProvider = context.watch<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;

    if (companyId != _selectedCompanyIdForName && !_isLoadingCompanyName) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureCompanyNameLoaded(companyId);
      });
    }

    final reversedCartItems = cartProvider.getCartItems().reversed.toList();
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping outside
        FocusScope.of(context).unfocus();
        _removeOverlay();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cart (${cartProvider.itemCount})'),
              if (_isLoadingCompanyName)
                const Text(
                  'Loading company...',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                )
              else if ((_selectedCompanyName ?? '').isNotEmpty)
                Text(
                  _selectedCompanyName!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _showAddCustomerDialog,
              icon: const Icon(Icons.person_add),
            ),
            if (cartProvider.itemCount > 0)
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Clear Cart'),
                      content: const Text('Remove all items from cart?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            context.read<CartProvider>().clear();
                            for (var controller
                                in _quantityControllers.values) {
                              controller.dispose();
                            }
                            _quantityControllers.clear();
                            if (mounted) {
                              setState(() {
                                _selectedCustomer = null;
                                _shippingAddressController.clear();
                                _shippingRemarksController.clear();
                                _dispatchedThroughController.clear();
                                _destinationController.clear();
                              });
                            }
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.error,
                          ),
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: true,
          child: Column(
            children: [
              _buildAddItemSection(),
              if (_selectedCustomer != null || cartProvider.itemCount > 0)
                _buildCustomerSelectionCard(),
              if (_selectedCustomer != null) _buildShippingDetailsField(),
              Expanded(
                child: cartProvider.isEmpty
                    ? _buildEmptyCartMessage()
                    : ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 40),
                        itemCount: reversedCartItems.length + 1,
                        itemBuilder: (context, index) {
                          if (index == reversedCartItems.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                              child: _buildCartSummary(context, cartProvider),
                            );
                          }
                          final cartItem = reversedCartItems[index];
                          return _buildCartItem(context, cartItem);
                        },
                      ),
              ),
              if (cartProvider.itemCount > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessingOrder ? null : () => _proceedToCheckout(context),
                      icon: _isProcessingOrder 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.receipt_long, size: 20, color: Colors.white),
                      label: Text(
                        _isProcessingOrder ? 'PROCESSING...' : 'CREATE SALES ORDER',
                        style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShippingDetailsField() {
    String _getShippingDetailsSummary() {
      List<String> parts = [];
      final dispatch = _dispatchedThroughController.text.trim();
      final dest = _destinationController.text.trim();
      if (dispatch.isNotEmpty) parts.add('Via: $dispatch');
      if (dest.isNotEmpty) parts.add('To: $dest');

      if (parts.isEmpty) return 'Additional Details (Dispatch, Destination)';
      return parts.join(' | ');
    }

    final summaryText = _getShippingDetailsSummary();
    final isEmpty = _dispatchedThroughController.text.trim().isEmpty &&
                    _destinationController.text.trim().isEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Column(
        children: [
          TextField(
            controller: _shippingAddressController,
            maxLines: 1,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Shipping Address',
              labelStyle: const TextStyle(fontSize: 11),
              hintText: 'Enter delivery address...',
              hintStyle: const TextStyle(fontSize: 11),
              prefixIcon: const Icon(Icons.local_shipping,
                  color: AppTheme.primaryBlue, size: 16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide:
                    const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _editShippingDetails,
            borderRadius: BorderRadius.circular(7),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      size: 16, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summaryText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isEmpty
                            ? AppTheme.grey
                            : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  Icon(
                    isEmpty
                        ? Icons.keyboard_arrow_down
                        : Icons.edit,
                    size: 16,
                    color: isEmpty
                        ? AppTheme.grey
                        : AppTheme.primaryBlue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editShippingDetails() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Additional Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                TextField(
                  controller: _dispatchedThroughController,
                  decoration: InputDecoration(
                    labelText: 'Dispatched Through',
                    hintText: 'e.g., VRL Logistics, Own Vehicle...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _destinationController,
                  decoration: InputDecoration(
                    labelText: 'Destination',
                    hintText: 'e.g., Ernakulam, Bangalore...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        _shippingRemarksController.clear();
                        _dispatchedThroughController.clear();
                        _destinationController.clear();
                        Navigator.pop(context, true);
                      },
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _openProductCatalog() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductSelectionScreen(
          preSelectedCustomer: _selectedCustomer,
          canScanQr: _canScanQr,
          isSelectionMode: true,
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildAddItemSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          label: const Text(
            'Add Product',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _openProductCatalog,
        ),
      ),
    );
  }

  Widget _buildEmptyCartMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 80,
              color: AppTheme.grey.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your cart is empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Click the Add Product button above to add items',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSelectionCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: _selectedCustomer != null
            ? AppTheme.success.withOpacity(0.1)
            : AppTheme.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color:
              _selectedCustomer != null ? AppTheme.success : AppTheme.warning,
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: _selectedCustomer == null ? _selectCustomer : null,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: _selectedCustomer == null
              ? const Row(
                  children: [
                    Icon(Icons.person_add, color: AppTheme.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select Customer',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        color: AppTheme.warning, size: 12),
                  ],
                )
              : Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppTheme.success,
                      radius: 11,
                      child: Icon(Icons.check,
                          color: Colors.white, size: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedCustomer!.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _selectedCustomer = null;
                          _shippingAddressController.clear();
                          _shippingRemarksController.clear();
                        });
                      },
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: AppTheme.error),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Remove customer',
                    ),
                  ],
                ),
        ),
      ),
    );
  }

// Replace your _buildCartItem method in cart_screen.dart with this:

// Replace your _buildCartItem method in cart_screen.dart with this:

  Widget _buildCartItem(BuildContext context, CartItem cartItem) {
    final product = cartItem.product;
    final controller = _getOrCreateController(product.id, cartItem.quantity);
    final availableStock = product.stock ?? 0;
    final currentQuantity = cartItem.quantity;
    final hasMrp = product.mrp != null && product.mrp! > 0; // ✅ ADD THIS

    // Debug: Print discount info
    print('🛒 Cart Item: ${product.productName}');
    print('   Item Discount %: ${cartItem.itemDiscountPercentage}');
    print('   Category Discount %: ${cartItem.categoryDiscountPercentage}');
    print('   Base Price: ${product.price}');
    print('   Price After Discount: ${cartItem.priceAfterDiscount}');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: product.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            product.imageUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.inventory_2,
                                color: AppTheme.primaryBlue,
                                size: 22,
                              );
                            },
                          ),
                        )
                      : const Icon(
                          Icons.inventory_2,
                          color: AppTheme.primaryBlue,
                          size: 22,
                        ),
                ),
                const SizedBox(width: 8),

                // Product Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Code: ${product.productCode ?? "N/A"}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.grey,
                        ),
                      ),
                      const SizedBox(height: 4),

                      if (hasMrp) ...[
                        Row(
                          children: [
                            Text(
                              'MRP: ',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                            Text(
                              '₹${product.mrp!.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
                      // Price display (with discount if applicable)
                      Row(
                        children: [
                          if (cartItem.itemDiscountPercentage > 0) ...[
                            Text(
                              '₹${cartItem.effectivePrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '₹${cartItem.priceAfterDiscount.toStringAsFixed(2)} / ${product.unit}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ] else ...[
                            Text(
                              '₹${cartItem.effectivePrice.toStringAsFixed(2)} / ${product.unit}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (!_hideStockQuantity) ...[
                            const SizedBox(width: 8),

                            // Stock indicator
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: availableStock <= 10
                                    ? AppTheme.warning.withOpacity(0.1)
                                    : AppTheme.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: availableStock <= 10
                                      ? AppTheme.warning
                                      : AppTheme.success,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'Stock: $availableStock',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: availableStock <= 10
                                      ? AppTheme.warning
                                      : AppTheme.success,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: AppTheme.error,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showDeleteConfirmation(
                    context,
                    product.id,
                    product.productName,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),

            // Quantity controls and price
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Quantity controls
                Row(
                  children: [
                    InkWell(
                      onTap: () async {
                        final cartProvider = context.read<CartProvider>();
                        final currentQty = cartProvider.getQuantity(product.id);
                        cartProvider.decrementQuantity(product.id);
                        // Recalculate discounts for new quantity
                        final newQty = currentQty - 1;
                        if (newQty > 0) {
                          await _recalculateDiscountsForProduct(
                              product.id, newQty);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.remove_circle_outline,
                          size: 18,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
                    Container(
                      width: 38,
                      height: 26,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppTheme.primaryBlue,
                          width: 1.2,
                        ),
                        borderRadius: BorderRadius.circular(5),
                        color: Colors.white,
                      ),
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlue,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 5,
                          ),
                          isDense: true,
                          counterText: '',
                        ),
                        maxLength: 4,
                        onChanged: (value) async {
                          final parsed = double.tryParse(value);
                          if (parsed != null && parsed > 0) {
                            if (availableStock > 0 && parsed > availableStock) {
                              final stockD = availableStock.toDouble();
                              controller.text = availableStock.toString();
                              context
                                  .read<CartProvider>()
                                  .updateQuantity(product.id, stockD);
                              await _recalculateDiscountsForProduct(
                                  product.id, stockD);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Only $availableStock items available in stock.',
                                  ),
                                  backgroundColor: AppTheme.warning,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            } else {
                              context
                                  .read<CartProvider>()
                                  .updateQuantity(product.id, parsed);
                              await _recalculateDiscountsForProduct(
                                  product.id, parsed);
                            }
                          }
                        },
                        onSubmitted: (value) async {
                          final parsed = double.tryParse(value);
                          if (parsed == null || parsed <= 0) {
                            context
                                .read<CartProvider>()
                                .updateQuantity(product.id, 1.0);
                            controller.text = '1';
                            await _recalculateDiscountsForProduct(
                                product.id, 1.0);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Quantity must be at least 1',
                                ),
                                backgroundColor: AppTheme.warning,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } else {
                            context
                                .read<CartProvider>()
                                .updateQuantity(product.id, parsed);
                            await _recalculateDiscountsForProduct(
                                product.id, parsed);
                          }
                        },
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        // Allow incrementing beyond stock
                        final cartProvider = context.read<CartProvider>();
                        cartProvider.incrementQuantity(product.id);
                        // Recalculate discounts for new quantity
                        final newQty = currentQuantity + 1;
                        await _recalculateDiscountsForProduct(
                            product.id, newQty);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: const Icon(
                          Icons.add_circle_outline,
                          size: 22,
                          color: AppTheme.primaryBlue, // Always enabled
                        ),
                      ),
                    ),
                  ],
                ),

                // Discount button
                if (_allowItemDiscounts) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _showItemDiscountDialog(context, cartItem),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cartItem.itemDiscountPercentage > 0
                            ? AppTheme.success.withOpacity(0.1)
                            : AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: cartItem.itemDiscountPercentage > 0
                              ? AppTheme.success
                              : AppTheme.primaryBlue,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_offer,
                            size: 14,
                            color: cartItem.itemDiscountPercentage > 0
                                ? AppTheme.success
                                : AppTheme.primaryBlue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cartItem.itemDiscountPercentage > 0
                                ? '${cartItem.itemDiscountPercentage.toStringAsFixed(1)}%'
                                : 'Discount',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: cartItem.itemDiscountPercentage > 0
                                  ? AppTheme.success
                                  : AppTheme.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Price breakdown
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Subtotal (before GST)
                    Text(
                      'Subtotal: ₹${cartItem.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.grey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Total with GST
                    Text(
                      '₹${(cartItem.subtotal + (cartItem.subtotal * cartItem.product.gstRate / 100)).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartSummary(BuildContext context, CartProvider cartProvider) {
    final hasOrderDiscount = cartProvider.calculatedOrderDiscount > 0;
    final hasCategoryDiscount = cartProvider.totalCategoryDiscounts > 0;
    final hasItemDiscount = cartProvider.totalManualItemDiscounts > 0;

    // Calculate subtotal before any discounts
    final subtotalBeforeDiscounts = cartProvider.items.values
        .fold(0.0, (sum, item) => sum + (item.effectivePrice * item.quantity));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_allowOrderDiscounts && cartProvider.subtotal > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _showOrderDiscountDialog(context),
                icon: const Icon(Icons.percent, size: 18),
                label: Text(
                  hasOrderDiscount
                      ? 'Edit Order Discount'
                      : 'Add Order Discount',
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.grey.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            _buildSummaryRow(
              context,
              'Subtotal (Before Discounts)',
              '₹${subtotalBeforeDiscounts.toStringAsFixed(2)}',
            ),
            // Category/Customer Discount
            if (hasCategoryDiscount) ...[
              const SizedBox(height: 6),
              _buildSummaryRow(
                context,
                'Customer Discount',
                '-₹${cartProvider.totalCategoryDiscounts.toStringAsFixed(2)}',
                color: AppTheme.success,
              ),
            ],
            // Manual Item Discount
            if (hasItemDiscount) ...[
              const SizedBox(height: 6),
              _buildSummaryRow(
                context,
                'Item Discount',
                '-₹${cartProvider.totalManualItemDiscounts.toStringAsFixed(2)}',
                color: AppTheme.success,
              ),
            ],
            // Order Discount
            if (_allowOrderDiscounts && hasOrderDiscount) ...[
              const SizedBox(height: 6),
              _buildSummaryRow(
                context,
                'Order Discount',
                '-₹${cartProvider.calculatedOrderDiscount.toStringAsFixed(2)}',
                color: AppTheme.success,
              ),
            ],
            const SizedBox(height: 6),
            _buildSummaryRow(
              context,
              'Subtotal (After Discounts)',
              '₹${cartProvider.subtotal.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 6),
            _buildSummaryRow(
              context,
              'Total GST',
              '₹${cartProvider.totalGst.toStringAsFixed(2)}',
            ),
            if (cartProvider.roundOffResult.numericRoundOff != 0) ...[
              const SizedBox(height: 6),
              _buildSummaryRow(
                context,
                'Round Off',
                cartProvider.roundOffResult.formattedRoundOff,
              ),
            ],
            const Divider(height: 16, thickness: 1),
            _buildSummaryRow(
              context,
              'Grand Total',
              '₹${cartProvider.roundedGrandTotal.toStringAsFixed(2)}',
              isBold: true,
              isLarge: true,
            ),
            if (_allowOrderDiscounts && hasOrderDiscount) ...[
              const SizedBox(height: 6),
              _buildSummaryRow(
                context,
                'Order Discount',
                '-₹${cartProvider.calculatedOrderDiscount.toStringAsFixed(2)}',
                color: AppTheme.success,
              ),
            ],
            const SizedBox(height: 12),
            if (_allowPaymentType) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: _selectedLedger == 'Cash'
                      ? Colors.green.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedLedger == 'Cash'
                        ? Colors.green
                        : AppTheme.primaryBlue,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedLedger == 'Cash'
                          ? Icons.money
                          : Icons.credit_card,
                      color: _selectedLedger == 'Cash'
                          ? Colors.green
                          : AppTheme.primaryBlue,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Payment Type:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    ToggleButtons(
                      isSelected: [
                        _selectedLedger == 'Cash',
                        _selectedLedger == 'Credit',
                      ],
                      onPressed: (index) {
                        setState(() {
                          _selectedLedger = index == 0 ? 'Cash' : 'Credit';
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      selectedColor: Colors.white,
                      fillColor: _selectedLedger == 'Cash'
                          ? Colors.green
                          : AppTheme.primaryBlue,
                      color: AppTheme.darkGrey,
                      constraints: const BoxConstraints(
                        minHeight: 36,
                        minWidth: 70,
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Cash'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Credit'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  ],
);
  }

  // Discount dialog removed

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value, {
    bool isBold = false,
    bool isLarge = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isLarge ? 16 : 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLarge ? 19 : 14,
            color: color ?? (isBold ? AppTheme.primaryBlue : AppTheme.darkGrey),
          ),
        ),
      ],
    );
  }
}

class _CustomerSelectionDialog extends StatefulWidget {
  final List<CustomerModel> customers;
  const _CustomerSelectionDialog({required this.customers});

  @override
  State<_CustomerSelectionDialog> createState() =>
      _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends State<_CustomerSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<CustomerModel> _filteredCustomers = [];

  @override
  void initState() {
    super.initState();
    _filteredCustomers = widget.customers;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCustomers(String query) {
    final trimmed = query.trim();
    setState(() {
      if (trimmed.isEmpty) {
        _filteredCustomers = widget.customers;
      } else {
        final scored = widget.customers
            .map((customer) => (
                  customer: customer,
                  score: _customerSearchScore(customer, trimmed),
                ))
            .where((entry) => entry.score >= 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
        _filteredCustomers = scored.map((entry) => entry.customer).toList();
      }
    });
  }

  int _customerSearchScore(CustomerModel customer, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return -1;

    final normalizedQuery = _normalizeSearch(query);
    final queryTokens = _tokenize(query);
    final name = customer.customerName.toLowerCase();
    final normalizedName = _normalizeSearch(name);
    final mobile = (customer.mobileNumber ?? '').toLowerCase();
    final city = (customer.city ?? '').toLowerCase();
    final address = (customer.address ?? '').toLowerCase();

    if (name.contains(query)) return 100;
    if (normalizedQuery.isNotEmpty &&
        normalizedName.contains(normalizedQuery)) {
      return 95;
    }
    if (mobile.contains(query)) return 90;
    if (city.contains(query) || address.contains(query)) return 75;

    if (queryTokens.isNotEmpty) {
      final nameTokens = _tokenize(name);
      final allTokensMatch = queryTokens.every(
        (queryToken) => nameTokens.any(
          (nameToken) => nameToken.startsWith(queryToken) || nameToken.contains(queryToken),
        ),
      );
      if (allTokensMatch) return 85;
    }

    return -1;
  }

  String _normalizeSearch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  List<String> _tokenize(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Select Customer',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _filterCustomers,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredCustomers.isEmpty
                  ? const Center(
                      child: Text(
                        'No customers found',
                        style: TextStyle(color: AppTheme.grey),
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final customer = _filteredCustomers[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppTheme.primaryBlue.withOpacity(0.1),
                              child: Text(
                                customer.customerName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(customer.customerName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (customer.mobileNumber != null)
                                  Text(customer.mobileNumber!),
                                if (customer.city != null) Text(customer.city!),
                              ],
                            ),
                            onTap: () => Navigator.pop(context, customer),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog();

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  final TextEditingController _gstController = TextEditingController();

  bool _isSaving = false;

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Create temporary CustomerModel without saving to database
      // This customer data will only be used for PDF generation
      final tempCustomer = CustomerModel(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}', // Temporary ID
        customerName: _nameController.text.trim(),
        mobileNumber: _mobileController.text.trim().isEmpty
            ? null
            : _mobileController.text.trim(),
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        state: _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        pincode: _pincodeController.text.trim().isEmpty
            ? null
            : _pincodeController.text.trim(),
        gstNumber: _gstController.text.trim().isEmpty
            ? null
            : _gstController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (mounted) {
        Navigator.pop(context, tempCustomer);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating customer: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add New Customer',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Enter name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileController,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'State',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pincodeController,
                      decoration: const InputDecoration(
                        labelText: 'Pincode',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _gstController,
                      decoration: const InputDecoration(
                        labelText: 'GST Number',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveCustomer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.darkBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
