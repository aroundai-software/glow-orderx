// lib/screens/admin/admin_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/admin_settings.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/backup_service.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:provider/provider.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final AdminSettingsService _service = AdminSettingsService();
  final BackupService _backupService = BackupService();
  final _formKey = GlobalKey<FormState>();

  // State variables for form fields
  final _companyNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  // Invoice Configuration Controllers
  final _invoiceAddress1Controller = TextEditingController();
  final _invoiceAddress2Controller = TextEditingController();
  final _invoiceCityStatePinController = TextEditingController();
  final _invoiceGstController = TextEditingController();
  final _invoicePanController = TextEditingController();
  final _invoiceBankNameController = TextEditingController();
  final _invoiceBankAccountController = TextEditingController();
  final _invoiceBankIfscController = TextEditingController();
  final _invoiceMobileController = TextEditingController();
  final _invoiceEmailController = TextEditingController();

  bool _notificationsEnabled = true;
  final bool _autoSyncEnabled = true;
  bool _allowCustomerCreation = true;
  bool _allowQrScanning = true; // New state for QR scanning toggle
  // New discount toggles
  bool _allowItemDiscounts = true;
  bool _allowOrderDiscounts = true;
  // New category selection toggle
  bool _allowCategorySelection = true;
  bool _allowPaymentType = true;
  bool _allowPriceLevelSalesmanDashboardControl = true;
  int _orderEditWindowMinutes = 30;
  bool _allowOrderEditing = true;
  bool _syncSoToTally = true;
  bool _hideStockQuantitySalesman = false;

  bool _isLoading = true;
  bool _isBackingUp = false;
  String? _settingsId;
  AdminSettings? _initialSettings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _invoiceAddress1Controller.dispose();
    _invoiceAddress2Controller.dispose();
    _invoiceCityStatePinController.dispose();
    _invoiceGstController.dispose();
    _invoicePanController.dispose();
    _invoiceBankNameController.dispose();
    _invoiceBankAccountController.dispose();
    _invoiceBankIfscController.dispose();
    _invoiceMobileController.dispose();
    _invoiceEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      // Fetch selected company details
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      if (companyId == null) {
        setState(() => _isLoading = false);
        return;
      }

      TallyCompanyModel? currentCompany;
      if (companyId != 'ALL') {
        currentCompany = await TallyCompanyService().resolveCompany(
          authProvider.currentUser?.companyId ?? companyId,
        );
      }
      final settingsCompanyId = currentCompany?.id ?? companyId;
      final settings = await _service.getAdminSettings(settingsCompanyId);
      _settingsId = await _service.getSettingsId(settingsCompanyId);

      if (mounted) {
        setState(() {
          _initialSettings = settings;
          
          if (currentCompany != null) {
            _companyNameController.text = currentCompany.companyName;
            _emailController.text = currentCompany.email ?? '';
            _phoneController.text = currentCompany.phoneNumber ?? '';
          } else {
            _companyNameController.text = settings.companyName;
            _emailController.text = settings.contactEmail ?? '';
            _phoneController.text = settings.contactPhone ?? '';
          }
          
          _invoiceAddress1Controller.text = settings.invoiceAddressLine1 ?? '';
          _invoiceAddress2Controller.text = settings.invoiceAddressLine2 ?? '';
          _invoiceCityStatePinController.text = settings.invoiceCityStatePin ?? '';
          _invoiceGstController.text = settings.invoiceGst ?? '';
          _invoicePanController.text = settings.invoicePan ?? '';
          _invoiceBankNameController.text = settings.invoiceBankName ?? '';
          _invoiceBankAccountController.text = settings.invoiceBankAccount ?? '';
          _invoiceBankIfscController.text = settings.invoiceBankIfsc ?? '';
          _invoiceMobileController.text = settings.contactPhone ?? '';
          _invoiceEmailController.text = settings.contactEmail ?? '';

          _notificationsEnabled = settings.notificationsEnabled;

          _allowCustomerCreation = settings.allowCustomerCreation;
          _allowQrScanning = settings.allowQrScanning; // Load the new setting
          // Load discount flags
          _allowItemDiscounts = settings.allowItemDiscounts;
          _allowOrderDiscounts = settings.allowOrderDiscounts;
          // Load category selection flag
          _allowCategorySelection = settings.allowCategorySelection;
          _allowPaymentType = settings.allowPaymentType;
          _allowPriceLevelSalesmanDashboardControl =
              settings.allowPriceLevelSalesmanDashboardControl;
          _orderEditWindowMinutes = settings.orderEditWindowMinutes;
          _allowOrderEditing = settings.allowOrderEditing;
          _syncSoToTally = settings.syncSoToTally;
          _hideStockQuantitySalesman = settings.hideStockQuantitySalesman;
          _isLoading = false;
        });
      }
    } catch (e) {
      _handleError('Failed to load settings', e);
    }
  }

  Future<void> _handleToggleChange({
    required String key,
    required bool value,
    required Function(bool) onStateChange,
  }) async {
    if (!mounted) return;
    setState(() => onStateChange(value));
    final companyId = context.read<AuthProvider>().selectedCompanyId;
    if (companyId == null) return;
    try {
      if (key == 'hide_stock_quantity_salesman') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hide_stock_quantity_salesman_$companyId', value);
      }
      await _service.updateSettings(companyId, {key: value, 'updated_at': DateTime.now().toUtc().toIso8601String()});

      // Optional: Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setting updated successfully'),
            backgroundColor: AppTheme.success,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString();
        if (err.contains('PGRST204') && err.contains(key)) {
          if (key == 'hide_stock_quantity_salesman') {
            setState(() => onStateChange(value));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Saved locally! Note: Run migration 009 in Supabase SQL editor to sync across devices.',
                ),
                backgroundColor: AppTheme.success,
                duration: Duration(seconds: 3),
              ),
            );
            return;
          }
          setState(() => onStateChange(!value));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to save: missing "$key" column in company_settings. Add the column in Supabase and try again.',
              ),
              backgroundColor: AppTheme.error,
            ),
          );
        } else {
          setState(() => onStateChange(!value));
          _handleError('Failed to save setting', e);
        }
      }
    }
  }

  Future<void> _saveTextFields() async {
    if (!_formKey.currentState!.validate() || _settingsId == null) return;
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      if (companyId != null) {
        TallyCompanyModel? currentCompany =
            await TallyCompanyService().resolveCompany(
          authProvider.currentUser?.companyId ?? companyId,
        );
        final saveId = currentCompany?.id ?? companyId;

        // Save company details to tally_companies
        await TallyCompanyService().updateCompanyProfile(
          id: saveId,
          companyName: _companyNameController.text.trim(),
          email: _emailController.text.trim().isNotEmpty
              ? _emailController.text.trim()
              : null,
          phoneNumber: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
        );

        // Save settings to company_settings
        final dataToSave = {
          'invoice_address_line1': _invoiceAddress1Controller.text.trim().isNotEmpty ? _invoiceAddress1Controller.text.trim() : null,
          'invoice_address_line2': _invoiceAddress2Controller.text.trim().isNotEmpty ? _invoiceAddress2Controller.text.trim() : null,
          'invoice_city_state_pin': _invoiceCityStatePinController.text.trim().isNotEmpty ? _invoiceCityStatePinController.text.trim() : null,
          'invoice_gst': _invoiceGstController.text.trim().isNotEmpty ? _invoiceGstController.text.trim() : null,
          'invoice_pan': _invoicePanController.text.trim().isNotEmpty ? _invoicePanController.text.trim() : null,
          'invoice_bank_name': _invoiceBankNameController.text.trim().isNotEmpty ? _invoiceBankNameController.text.trim() : null,
          'invoice_bank_account': _invoiceBankAccountController.text.trim().isNotEmpty ? _invoiceBankAccountController.text.trim() : null,
          'invoice_bank_ifsc': _invoiceBankIfscController.text.trim().isNotEmpty ? _invoiceBankIfscController.text.trim() : null,
          'contact_phone': _invoiceMobileController.text.trim().isNotEmpty ? _invoiceMobileController.text.trim() : null,
          'contact_email': _invoiceEmailController.text.trim().isNotEmpty ? _invoiceEmailController.text.trim() : null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        await _service.updateSettings(saveId, dataToSave);
      } else {
        // Fallback if no company selected (Should not happen)
        final dataToSave = {
          'company_name': _companyNameController.text.trim(),
          'invoice_address_line1': _invoiceAddress1Controller.text.trim().isNotEmpty ? _invoiceAddress1Controller.text.trim() : null,
          'invoice_address_line2': _invoiceAddress2Controller.text.trim().isNotEmpty ? _invoiceAddress2Controller.text.trim() : null,
          'invoice_city_state_pin': _invoiceCityStatePinController.text.trim().isNotEmpty ? _invoiceCityStatePinController.text.trim() : null,
          'invoice_gst': _invoiceGstController.text.trim().isNotEmpty ? _invoiceGstController.text.trim() : null,
          'invoice_pan': _invoicePanController.text.trim().isNotEmpty ? _invoicePanController.text.trim() : null,
          'invoice_bank_name': _invoiceBankNameController.text.trim().isNotEmpty ? _invoiceBankNameController.text.trim() : null,
          'invoice_bank_account': _invoiceBankAccountController.text.trim().isNotEmpty ? _invoiceBankAccountController.text.trim() : null,
          'invoice_bank_ifsc': _invoiceBankIfscController.text.trim().isNotEmpty ? _invoiceBankIfscController.text.trim() : null,
          'contact_phone': _invoiceMobileController.text.trim().isNotEmpty ? _invoiceMobileController.text.trim() : null,
          'contact_email': _invoiceEmailController.text.trim().isNotEmpty ? _invoiceEmailController.text.trim() : null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        await _service.updateSettings('', dataToSave); // Might fail if empty id
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')),
        );
        await _loadSettings();
      }
    } catch (e) {
      _handleError('Error saving settings', e);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleError(String message, Object e) {
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$message: $e')),
      );
    }
  }

  Future<void> _requestStoragePermissions() async {
    try {
      // Request storage permission
      await Permission.storage.request();

      // For Android 11+, also request manage external storage
      try {
        await Permission.manageExternalStorage.request();
      } catch (e) {
        // Permission not available on this device
      }
    } catch (e) {
      // Permission request failed
    }
  }

  Future<void> _performBackup() async {
    if (_isBackingUp) return;

    // Request permissions first
    await _requestStoragePermissions();

    setState(() => _isBackingUp = true);
    try {
      final result = await _backupService.runBackup();
      if (!mounted) return;

      // Determine user-friendly message based on path
      String message;
      String fileName = result.split('/').last;

      if (result.contains('/Download') || result.contains('/download')) {
        message =
            '✅ Backup saved to Downloads folder!\nFile: $fileName\nOpen your file manager to access it.';
      } else if (result.contains('Android/data')) {
        message =
            '⚠️ Backup saved to app folder (not accessible via file manager).\n\nTo save to Downloads:\n1. Go to Settings > Apps > Orderx > Permissions\n2. Enable Storage permission\n3. Try backup again';
      } else if (result.contains('/storage/emulated/0/')) {
        message =
            '✅ Backup saved to device storage!\nFile: $fileName\nLocation: Internal Storage\nAccessible via file manager.';
      } else {
        message =
            '⚠️ Backup saved to app directory.\nFile: $fileName\nNot accessible via file manager.\nPlease enable storage permissions.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('App Settings'),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isLoading ? null : _saveTextFields,
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            labelStyle: TextStyle(fontSize: 11),
            unselectedLabelStyle: TextStyle(fontSize: 11),
            tabs: [
              Tab(icon: Icon(Icons.business), text: 'Company'),
              Tab(icon: Icon(Icons.receipt_long), text: 'Invoice'),
              Tab(icon: Icon(Icons.tune), text: 'Features'),
              Tab(icon: Icon(Icons.security), text: 'System'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: TabBarView(
                  children: [
                    // Company Tab
                    RefreshIndicator(
                      onRefresh: _loadSettings,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 16.0),
                        children: [
                          _buildCompanyInfoCard(),
                        ],
                      ),
                    ),
                    // Invoice Tab
                    RefreshIndicator(
                      onRefresh: _loadSettings,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 16.0),
                        children: [
                          _buildInvoiceSettingsCard(),
                        ],
                      ),
                    ),
                    // Features Tab
                    RefreshIndicator(
                      onRefresh: _loadSettings,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 16.0),
                        children: [
                          _buildAppPreferencesCard(),
                        ],
                      ),
                    ),
                    // System Tab
                    RefreshIndicator(
                      onRefresh: _loadSettings,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 16.0),
                        children: [
                          _buildTallySyncCard(),
                          const SizedBox(height: 16),
                          if (_initialSettings != null) _buildAppInfoCard(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildCompanyInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Company Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _companyNameController,
              decoration: const InputDecoration(
                  labelText: 'Company Name *', border: OutlineInputBorder()),
              validator: (value) => value == null || value.isEmpty
                  ? 'Company name is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                  labelText: 'Contact Email',
                  hintText: 'admin@company.com',
                  border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                  labelText: 'Contact Phone',
                  hintText: '+91 98765 43210',
                  border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildTallySyncCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('Tally Sync',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            SwitchListTile(
              title: const Text('Sync SO to Tally'),
              subtitle: const Text(
                  'When ON, the Tally sync exe pushes sales orders.\n'
                  'First run sends all orders; later runs send only new and edited orders.'),
              value: _syncSoToTally,
              onChanged: (value) => _handleToggleChange(
                key: 'sync_so_to_tally',
                value: value,
                onStateChange: (newValue) => _syncSoToTally = newValue,
              ),
              activeThumbColor: AppTheme.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invoice Configuration',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceAddress1Controller,
              decoration: const InputDecoration(
                  labelText: 'Address Line 1', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceAddress2Controller,
              decoration: const InputDecoration(
                  labelText: 'Address Line 2', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceCityStatePinController,
              decoration: const InputDecoration(
                  labelText: 'City, State, PIN', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceGstController,
              decoration: const InputDecoration(
                  labelText: 'GSTIN / UIN', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoicePanController,
              decoration: const InputDecoration(
                  labelText: 'Company PAN', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceMobileController,
              decoration: const InputDecoration(
                  labelText: 'Mobile Number', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceEmailController,
              decoration: const InputDecoration(
                  labelText: 'Email Address', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const Divider(height: 24),
            const Text('Bank Details',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceBankNameController,
              decoration: const InputDecoration(
                  labelText: 'Bank Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceBankAccountController,
              decoration: const InputDecoration(
                  labelText: 'Account Number', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceBankIfscController,
              decoration: const InputDecoration(
                  labelText: 'IFSC Code', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppPreferencesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: ListTileTheme(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('App Preferences',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Enable Notifications'),
              subtitle: const Text('Receive alerts for pending approvals'),
              value: _notificationsEnabled,
              onChanged: (value) => _handleToggleChange(
                key: 'notifications_enabled',
                value: value,
                onStateChange: (newValue) => _notificationsEnabled = newValue,
              ),
              activeThumbColor: AppTheme.primaryBlue,
            ),

            SwitchListTile(
              title: const Text('Allow Customer Creation'),
              subtitle: const Text("Allow salesmen to add new customers"),
              value: _allowCustomerCreation,
              onChanged: (value) => _handleToggleChange(
                key: 'allow_customer_creation',
                value: value,
                onStateChange: (newValue) => _allowCustomerCreation = newValue,
              ),
              activeThumbColor: AppTheme.primaryBlue,
            ),
            // New: Item-level discounts toggle
            SwitchListTile(
              title: const Text('Allow Item-level Discounts'),
              subtitle:
                  const Text('Enable per-item discount inputs for salesmen'),
              value: _allowItemDiscounts,
              onChanged: (value) => _handleToggleChange(
                key: 'allow_item_discounts',
                value: value,
                onStateChange: (newValue) => _allowItemDiscounts = newValue,
              ),
              activeThumbColor: AppTheme.primaryBlue,
            ),
            // New: Order-level discounts toggle
            SwitchListTile(
              title: const Text('Allow Order-level Discounts'),
              subtitle: const Text('Enable discount on the whole order'),
              value: _allowOrderDiscounts,
              onChanged: (value) => _handleToggleChange(
                key: 'allow_order_discounts',
                value: value,
                onStateChange: (newValue) => _allowOrderDiscounts = newValue,
              ),
              activeThumbColor: AppTheme.primaryBlue,
            ),
            // New: Category selection toggle
            SwitchListTile(
              title: const Text('Allow Category Selection'),
              subtitle: const Text(
                  'Enable customer category selection in product details'),
              value: _allowCategorySelection,
              onChanged: (value) => _handleToggleChange(
                key: 'allow_category_selection',
                value: value,
                onStateChange: (newValue) => _allowCategorySelection = newValue,
              ),
              activeThumbColor: AppTheme.primaryBlue,
            ),
            SwitchListTile(
              title: const Text('Enable Payment Type (Cash/Credit)'),
              subtitle: const Text(
                  'Allow salesmen to choose payment type in cart screen'),
              value: _allowPaymentType,
              onChanged: (value) => _handleToggleChange(
                key: 'allow_payment_type',
                value: value,
                onStateChange: (newValue) => _allowPaymentType = newValue,
              ),
              activeThumbColor: AppTheme.primaryBlue,
            ),
            SwitchListTile(
              title: const Text('Hide Stock Quantity from Salesman'),
              subtitle: const Text(
                  'Hide remaining stock quantities and stock status in salesman views'),
              value: _hideStockQuantitySalesman,
              onChanged: (value) => _handleToggleChange(
                key: 'hide_stock_quantity_salesman',
                value: value,
                onStateChange: (newValue) =>
                    _hideStockQuantitySalesman = newValue,
              ),
              activeThumbColor: AppTheme.primaryBlue,
            ),
            const Divider(height: 16),
            _buildEditWindowControl(),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('Backup Data'),
              subtitle:
                  const Text('Export all tables and data to a local JSON file'),
              trailing: _isBackingUp
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isBackingUp ? null : _performBackup,
            ),
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _saveEditWindowMinutes(int minutes) async {
    print('🔧 Debug: Attempting to save edit window minutes: $minutes');
    setState(() => _orderEditWindowMinutes = minutes);
    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      if (companyId != null) {
        await _service.saveOrderEditWindowMinutes(companyId, minutes);
      }
      print('🔧 Debug: Successfully saved edit window minutes to DB');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Edit window updated'),
            backgroundColor: AppTheme.success,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('🔧 Debug: Error saving edit window minutes: $e');
      if (mounted) {
        setState(() => _orderEditWindowMinutes =
            _initialSettings?.orderEditWindowMinutes ?? 30);
        _handleError('Failed to save edit window', e);
      }
    }
  }

  Widget _buildEditWindowControl() {
    // Preset values in minutes
    const presets = [
      {'label': '30 min', 'value': 30},
      {'label': '1 hr', 'value': 60},
      {'label': '2 hr', 'value': 120},
      {'label': '5 hr', 'value': 300},
      {'label': '12 hr', 'value': 720},
    ];

    final presetValues = presets.map((p) => p['value'] as int).toList();
    final isCustom = !presetValues.contains(_orderEditWindowMinutes);

    // Build dropdown items: presets + Custom
    final dropdownItems = [
      ...presets.map((p) => DropdownMenuItem<int>(
            value: p['value'] as int,
            child: Text(p['label'] as String),
          )),
      const DropdownMenuItem<int>(
        value: -1, // sentinel for custom
        child: Text('Custom'),
      ),
    ];

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Allow Orders Editing'),
          subtitle: const Text('Toggle ON: editable within time window\n'
              'Toggle OFF: editable until billed in Tally'),
          value: _allowOrderEditing,
          onChanged: (value) async {
            setState(() => _allowOrderEditing = value);
            try {
              final companyId = context.read<AuthProvider>().selectedCompanyId;
              if (companyId != null) {
                await _service.saveOrderEditingEnabled(companyId, value);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Setting updated'),
                    backgroundColor: AppTheme.success,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                setState(() => _allowOrderEditing = !value);
                _handleError('Failed to save setting', e);
              }
            }
          },
          activeThumbColor: AppTheme.primaryBlue,
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _allowOrderEditing
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit Time Window',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Orders can be edited only within this window after creation',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Dropdown
                    DropdownButton<int>(
                      value: isCustom ? -1 : _orderEditWindowMinutes,
                      items: dropdownItems,
                      onChanged: (selected) {
                        if (selected == null) return;
                        if (selected == -1) {
                          // Show custom input dialog
                          _showCustomWindowDialog();
                        } else {
                          _saveEditWindowMinutes(selected);
                        }
                      },
                      underline: Container(
                        height: 2,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    // Show current custom value if custom is active
                    if (isCustom) ...[
                      const SizedBox(width: 12),
                      Text(
                        '${_orderEditWindowMinutes} min',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Salesman can edit Orders freely until they are billed in Tally.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomWindowDialog() async {
    final controller = TextEditingController(
      text: _orderEditWindowMinutes.toString(),
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom Edit Window'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minutes',
              hintText: 'e.g. 45',
              suffixText: 'min',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a valid number of minutes';
              if (n > 10080) return 'Maximum is 10080 min (7 days)';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final minutes = int.parse(controller.text.trim());
      _saveEditWindowMinutes(minutes);
    }
  }

  Widget _buildAppInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('App Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _buildInfoRow('App Version', '1.0.0'),
            _buildInfoRow(
                'Last Saved',
                DateFormat('MMM dd, yyyy - hh:mm a')
                    .format(_initialSettings!.lastUpdated.toLocal())),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
