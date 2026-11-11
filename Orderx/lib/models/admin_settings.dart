// lib/models/admin_settings.dart

class AdminSettings {
  final String? companyId;
  final String companyName;
  final String? contactEmail;
  final String? contactPhone;
  final bool notificationsEnabled;

  final DateTime lastUpdated;
  final bool allowCustomerCreation;
  // ================== FIX START ==================
  final bool allowQrScanning;
  // ✅ New feature flags for discounts
  final bool allowItemDiscounts;
  final bool allowOrderDiscounts;
  // ✅ New feature flag for category selection
  final bool allowCategorySelection;
  final bool allowPaymentType;
  final bool allowPriceLevelSalesmanDashboardControl;
  // Master toggle: allow salesperson to edit orders at all
  final bool allowOrderEditing;
  // Order edit time window in minutes (30, 60, 120, 300, 720)
  final int orderEditWindowMinutes;
  // When true, the Tally sync exe pushes sales orders to Tally
  final bool syncSoToTally;
  // When true, remaining stock quantities are hidden from salesmen
  final bool hideStockQuantitySalesman;
  // Global GST rate
  final double globalGstRate;
  
  // Invoice Configuration
  final String? invoiceAddressLine1;
  final String? invoiceAddressLine2;
  final String? invoiceCityStatePin;
  final String? invoiceGst;
  final String? invoicePan;
  final String? invoiceBankName;
  final String? invoiceBankAccount;
  final String? invoiceBankIfsc;
  // =================== FIX END ===================

  AdminSettings({
    this.companyId,
    required this.companyName,
    this.contactEmail,
    this.contactPhone,
    this.notificationsEnabled = true,
    required this.lastUpdated,
    this.allowCustomerCreation = true,
    // ================== FIX START ==================
    this.allowQrScanning = true, // Default to true
    // ✅ Defaults for new flags
    this.allowItemDiscounts = true,
    this.allowOrderDiscounts = true,
    this.allowCategorySelection = true,
    this.allowPaymentType = true,
    this.allowPriceLevelSalesmanDashboardControl = true,
    this.allowOrderEditing = true,
    this.orderEditWindowMinutes = 30,
    this.syncSoToTally = true,
    this.hideStockQuantitySalesman = false,
    this.globalGstRate = 0.0,
    this.invoiceAddressLine1,
    this.invoiceAddressLine2,
    this.invoiceCityStatePin,
    this.invoiceGst,
    this.invoicePan,
    this.invoiceBankName,
    this.invoiceBankAccount,
    this.invoiceBankIfsc,
    // =================== FIX END ===================
  });

  factory AdminSettings.fromJson(Map<String, dynamic> json) {
    return AdminSettings(
      companyId: json['company_id'],
      companyName: json['company_name'] ?? 'V K Traders',
      contactEmail: json['contact_email'],
      contactPhone: json['contact_phone'],
      notificationsEnabled: json['notifications_enabled'] ?? true,

      lastUpdated: DateTime.parse(
          json['updated_at'] ?? DateTime.now().toIso8601String()),
      allowCustomerCreation: json['allow_customer_creation'] ?? true,
      // ================== FIX START ==================
      allowQrScanning: json['allow_qr_scanning'] ?? true,
      // ✅ Parse new flags with safe defaults
      allowItemDiscounts: json['allow_item_discounts'] ?? true,
      allowOrderDiscounts: json['allow_order_discounts'] ?? true,
      allowCategorySelection: json['allow_category_selection'] ?? true,
      allowPaymentType: json['allow_payment_type'] ?? true,
      allowPriceLevelSalesmanDashboardControl:
          json['allow_price_level_salesman_dashboard_control'] ?? true,
      allowOrderEditing: json['allow_order_editing'] ?? true,
      orderEditWindowMinutes:
          (json['order_edit_window_minutes'] as num?)?.toInt() ?? 30,
      syncSoToTally: json['sync_so_to_tally'] ?? true,
      hideStockQuantitySalesman: json['hide_stock_quantity_salesman'] ?? false,
      globalGstRate: (json['global_gst_rate'] as num?)?.toDouble() ?? 0.0,
      invoiceAddressLine1: json['invoice_address_line1'],
      invoiceAddressLine2: json['invoice_address_line2'],
      invoiceCityStatePin: json['invoice_city_state_pin'],
      invoiceGst: json['invoice_gst'],
      invoicePan: json['invoice_pan'],
      invoiceBankName: json['invoice_bank_name'],
      invoiceBankAccount: json['invoice_bank_account'],
      invoiceBankIfsc: json['invoice_bank_ifsc'],
      // =================== FIX END ===================
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (companyId != null) 'company_id': companyId,
      'company_name': companyName,
      'contact_email': contactEmail,
      'contact_phone': contactPhone,
      'notifications_enabled': notificationsEnabled,

      'allow_customer_creation': allowCustomerCreation,
      // ================== FIX START ==================
      'allow_qr_scanning': allowQrScanning,
      // ✅ Include new flags
      'allow_item_discounts': allowItemDiscounts,
      'allow_order_discounts': allowOrderDiscounts,
      'allow_category_selection': allowCategorySelection,
      'allow_payment_type': allowPaymentType,
      'allow_price_level_salesman_dashboard_control':
          allowPriceLevelSalesmanDashboardControl,
      'allow_order_editing': allowOrderEditing,
      'order_edit_window_minutes': orderEditWindowMinutes,
      'sync_so_to_tally': syncSoToTally,
      'hide_stock_quantity_salesman': hideStockQuantitySalesman,
      'global_gst_rate': globalGstRate,
      'invoice_address_line1': invoiceAddressLine1,
      'invoice_address_line2': invoiceAddressLine2,
      'invoice_city_state_pin': invoiceCityStatePin,
      'invoice_gst': invoiceGst,
      'invoice_pan': invoicePan,
      'invoice_bank_name': invoiceBankName,
      'invoice_bank_account': invoiceBankAccount,
      'invoice_bank_ifsc': invoiceBankIfsc,
      // =================== FIX END ===================
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
