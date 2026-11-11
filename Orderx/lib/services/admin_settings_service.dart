// lib/services/admin_settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Orderx/models/admin_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSettingsService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Checks if company_settings table has any records
  Future<bool> _settingsExist(String companyId) async {
    try {
      final response =
          await _client.from('company_settings').select('id').eq('company_id', companyId).maybeSingle();
      return response != null;
    } catch (e) {
      print('Error checking settings existence: $e');
      return false;
    }
  }

  /// Creates default company settings if none exist
  Future<void> _createDefaultSettings(String companyId) async {
    try {
      final companyRes = await _client
          .from('tally_companies')
          .select('company_name')
          .eq('id', companyId)
          .maybeSingle();
      final actualCompanyName = companyRes != null ? (companyRes['company_name'] as String?) ?? 'Unknown Company' : 'Unknown Company';

      final defaultSettings = AdminSettings(
        companyId: companyId,
        companyName: actualCompanyName,
        contactEmail: null,
        contactPhone: null,
        notificationsEnabled: true,
        lastUpdated: DateTime.now(),
        allowCustomerCreation: true,
        allowQrScanning: true,
        allowItemDiscounts: true,
        allowOrderDiscounts: true,
        allowCategorySelection: true,
        allowPriceLevelSalesmanDashboardControl: true,
        orderEditWindowMinutes: 30,
        allowOrderEditing: true,
        globalGstRate: 0.0,
      );

      await _client.from('company_settings').insert(defaultSettings.toJson());

      print('Default company settings created successfully');
    } catch (e) {
      print('Error creating default settings: $e');
      rethrow;
    }
  }

  /// Fetches all company settings from the database.
  Future<AdminSettings> getAdminSettings(String companyId) async {
    try {
      // Check if settings exist, create if not
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response =
          await _client.from('company_settings').select().eq('company_id', companyId).single();

      return AdminSettings.fromJson(response);
    } catch (e) {
      print('Error fetching admin settings: $e');
      rethrow;
    }
  }

  /// Retrieves the unique ID of the settings record.
  /// Creates default settings if none exist.
  Future<String> getSettingsId(String companyId) async {
    try {
      // Check if settings exist, create if not
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response =
          await _client.from('company_settings').select('id').eq('company_id', companyId).single();
      return response['id'];
    } catch (e) {
      print('Error fetching settings ID: $e');
      rethrow;
    }
  }

  /// A flexible method to update one or more settings using a map.
  /// This is ideal for saving individual toggle changes immediately.
  Future<void> updateSettings(String companyId, Map<String, dynamic> data) async {
    try {
      final id = await getSettingsId(companyId);
      await _client.from('company_settings').update(data).eq('id', id);
    } catch (e) {
      print('Error updating settings: $e');
      rethrow;
    }
  }

  /// Checks if the "Allow Customer Creation" setting is enabled.
  /// This is called by the salesman's app.
  Future<bool> canSalesmanAddCustomer(String companyId) async {
    try {
      // Ensure settings exist
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('allow_customer_creation')
          .eq('company_id', companyId)
          .single();

      // Return the value, defaulting to `true` if it's null or an error occurs.
      return response['allow_customer_creation'] ?? true;
    } catch (e) {
      print('Error fetching customer creation setting: $e');
      // Default to true to prevent blocking the feature if the check fails.
      return true;
    }
  }

  /// Checks if the "Allow QR Scanning" setting is enabled.
  Future<bool> canSalesmanScanQr(String companyId) async {
    try {
      // Ensure settings exist
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('allow_qr_scanning')
          .eq('company_id', companyId)
          .single();
      return response['allow_qr_scanning'] ?? true;
    } catch (e) {
      print('Error fetching QR scanning setting: $e');
      return true; // Default to true if check fails
    }
  }

  /// Checks if item-level discounts are allowed
  Future<bool> canUseItemDiscounts(String companyId) async {
    try {
      // Ensure settings exist
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('allow_item_discounts')
          .eq('company_id', companyId)
          .single();
      return response['allow_item_discounts'] ?? true;
    } catch (e) {
      print('Error fetching item discount setting: $e');
      return true; // default safe behavior
    }
  }

  /// Checks if order-level discounts are allowed
  Future<bool> canUseOrderDiscounts(String companyId) async {
    try {
      // Ensure settings exist
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('allow_order_discounts')
          .eq('company_id', companyId)
          .single();
      return response['allow_order_discounts'] ?? true;
    } catch (e) {
      print('Error fetching order discount setting: $e');
      return true; // default safe behavior
    }
  }

  /// Checks if category selection is allowed in product details
  Future<bool> canUseCategorySelection(String companyId) async {
    try {
      // Ensure settings exist
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('allow_category_selection')
          .eq('company_id', companyId)
          .single();
      return response['allow_category_selection'] ?? true;
    } catch (e) {
      print('Error fetching category selection setting: $e');
      return true; // default safe behavior
    }
  }

  /// Checks if salesman can choose Payment Type (Cash/Credit) in cart
  Future<bool> canUsePaymentType(String companyId) async {
    try {
      // Ensure settings exist
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('allow_payment_type')
          .eq('company_id', companyId)
          .single();
      return response['allow_payment_type'] ?? true;
    } catch (e) {
      print('Error fetching payment type setting: $e');
      return true; // default safe behavior
    }
  }

  /// Checks if salesman can control Price Level from Salesman Dashboard
  Future<bool> canSalesmanControlPriceLevelFromDashboard(String companyId) async {
    try {
      // Ensure settings exist
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('allow_price_level_salesman_dashboard_control')
          .eq('company_id', companyId)
          .single();
      return response['allow_price_level_salesman_dashboard_control'] ?? true;
    } catch (e) {
      print('Error fetching price level dashboard control setting: $e');
      return true; // default safe behavior
    }
  }

  /// Returns the order edit window in minutes — stored in database.
  Future<int> getOrderEditWindowMinutes(String companyId) async {
    try {
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('order_edit_window_minutes')
          .eq('company_id', companyId)
          .single();
      return response['order_edit_window_minutes'] ?? 30;
    } catch (e) {
      print('Error fetching order edit window minutes: $e');
      return 30; // Default fallback
    }
  }

  /// Saves the order edit window minutes to database.
  Future<void> saveOrderEditWindowMinutes(String companyId, int minutes) async {
    try {
      final id = await getSettingsId(companyId);
      print('🔧 Debug: Settings ID: $id');
      print('🔧 Debug: Updating order_edit_window_minutes to: $minutes');
      final result = await _client
          .from('company_settings')
          .update({'order_edit_window_minutes': minutes})
          .eq('id', id);
      print('🔧 Debug: Update result: $result');
    } catch (e) {
      print('Error saving order edit window minutes: $e');
      rethrow;
    }
  }

  /// Returns whether order editing is allowed — stored in database.
  Future<bool> getOrderEditingEnabled(String companyId) async {
    try {
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('allow_order_editing')
          .eq('company_id', companyId)
          .single();
      return response['allow_order_editing'] ?? true;
    } catch (e) {
      print('Error fetching order editing enabled: $e');
      return true; // Default fallback
    }
  }

  /// Saves the order editing toggle to database.
  Future<void> saveOrderEditingEnabled(String companyId, bool value) async {
    try {
      final id = await getSettingsId(companyId);
      await _client
          .from('company_settings')
          .update({'allow_order_editing': value})
          .eq('id', id);
    } catch (e) {
      print('Error saving order editing enabled: $e');
      rethrow;
    }
  }

  /// Updates the entire settings object.
  /// Used by the main "Save" button for text fields.
  Future<void> updateAdminSettingsWithId(
      AdminSettings settings, String id) async {
    await _client
        .from('company_settings')
        .update(settings.toJson())
        .eq('id', id);
  }

  /// Returns the global GST rate — stored in database.
  Future<double> getGlobalGstRate(String companyId) async {
    try {
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('global_gst_rate')
          .eq('company_id', companyId)
          .single();
      return (response['global_gst_rate'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      print('Error fetching global GST rate: $e');
      return 0.0; // Default fallback
    }
  }

  /// Checks if remaining stock quantities should be hidden from salesman views.
  /// Seamlessly caches the value in SharedPreferences for instant offline support.
  Future<bool> shouldHideStockQuantityFromSalesman(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'hide_stock_quantity_salesman_$companyId';
    final cachedVal = prefs.getBool(cacheKey);

    try {
      final exists = await _settingsExist(companyId);
      if (!exists) {
        await _createDefaultSettings(companyId);
      }

      final response = await _client
          .from('company_settings')
          .select('hide_stock_quantity_salesman')
          .eq('company_id', companyId)
          .single();

      final remoteVal = response['hide_stock_quantity_salesman'] as bool?;
      if (remoteVal != null) {
        await prefs.setBool(cacheKey, remoteVal);
        return remoteVal;
      }
      return cachedVal ?? false;
    } catch (e) {
      return cachedVal ?? false;
    }
  }

  /// Saves the hide stock quantity toggle both locally in SharedPreferences and to Supabase.
  Future<void> saveHideStockQuantitySalesman(String companyId, bool hide) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hide_stock_quantity_salesman_$companyId', hide);
    } catch (_) {}

    try {
      final id = await getSettingsId(companyId);
      await _client
          .from('company_settings')
          .update({'hide_stock_quantity_salesman': hide, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id);
    } catch (e) {
      print('Warning: could not update hide_stock_quantity_salesman on server: $e');
      rethrow;
    }
  }
}

