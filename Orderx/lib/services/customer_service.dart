import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/utils/company_query.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // FOR BOTH: Get all customers (paginated to bypass Supabase 1000-row limit)
  Future<List<CustomerModel>> getAllCustomers({String? companyId}) async {
    try {
      print('🔍 CustomerService: Fetching ALL customers for companyId=$companyId');
      
      final List<CustomerModel> allCustomers = [];
      int page = 0;
      const int pageSize = 1000;
      bool hasMore = true;
      
      while (hasMore) {
        final offset = page * pageSize;
        dynamic query = _supabase
            .from('customers')
            .select();
        
        if (companyId != null && companyId.isNotEmpty) {
          final keys = await companyKeys(companyId);
          query = applyCompanyIdFilter(query, keys);
        }
        
        final response = await query
            .order('customer_name', ascending: true)
            .range(offset, offset + pageSize - 1);

        final batch = (response as List)
            .map((json) => CustomerModel.fromJson(json))
            .toList();
        
        allCustomers.addAll(batch);
        print('🔍 CustomerService: Page $page fetched ${batch.length} customers (total so far: ${allCustomers.length})');
        
        if (batch.length < pageSize) {
          hasMore = false;
        } else {
          page++;
        }
      }
      
      print('🔍 CustomerService: Fetched ${allCustomers.length} TOTAL customers from database');
      return allCustomers;
    } catch (e) {
      print('❌ Error fetching customers: $e');
      rethrow;
    }
  }

  // FOR BOTH: Get customers with pagination (1000 per page)
  Future<List<CustomerModel>> getAllCustomersPaginated({
    String? companyId,
    int page = 0,
    int limit = 1000,
  }) async {
    try {
      final offset = page * limit;
      dynamic query = _supabase
          .from('customers')
          .select();
      
      // Filter by company_id if provided
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }
      
      final response = await query
          .order('customer_name', ascending: true)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => CustomerModel.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error fetching paginated customers: $e');
      rethrow;
    }
  }

  // Get total count of customers
  Future<int> getTotalCustomerCount({String? companyId}) async {
    try {
      dynamic query = _supabase.from('customers').select('id');
      
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }
      
      final response = await query.count(CountOption.exact);
      return response.count ?? 0;
    } catch (e) {
      print('❌ Error fetching customer count: $e');
      return 0;
    }
  }

  // Alias for consistency with admin screens
  Future<List<CustomerModel>> getCustomers({String? companyId}) async {
    return getAllCustomers(companyId: companyId);
  }

  // FOR BOTH: Get customer by ID
  Future<CustomerModel?> getCustomerById(String id) async {
    try {
      final response =
          await _supabase.from('customers').select().eq('id', id).single();

      return CustomerModel.fromJson(response);
    } catch (e) {
      print('Error fetching customer: $e');
      return null;
    }
  }

  // FOR BOTH: Search customers
  Future<List<CustomerModel>> searchCustomers(String query,
      {String? companyId}) async {
    try {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return [];

      print('🔍 Searching customers: query="$trimmed", companyId=$companyId');

      // Use database-level filtering for better performance with large datasets
      dynamic dbQuery = _supabase
          .from('customers')
          .select();
      
      // Filter by company_id if provided
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        dbQuery = applyCompanyIdFilter(dbQuery, keys);
        print('🔍 Filtering by company_id: $companyId');
      }
      
      // Use database OR query for name, mobile, city, address
      final searchPattern = 'customer_name.ilike.%$trimmed%,mobile_number.ilike.%$trimmed%,city.ilike.%$trimmed%,address.ilike.%$trimmed%';
      print('🔍 Search pattern: $searchPattern');
      
      dbQuery = dbQuery.or(searchPattern);
      
      final response = await dbQuery
          .order('customer_name', ascending: true)
          .limit(1000);

      final results = (response as List)
          .map((json) => CustomerModel.fromJson(json))
          .toList();
      
      print('🔍 Search results: ${results.length} customers found');
      return results;
    } catch (e) {
      print('❌ Error searching customers: $e');
      rethrow;
    }
  }

  // Creates a full CustomerModel and returns the complete customer object
  Future<CustomerModel> createCustomerModel({
    required String customerName,
    required String mobileNumber,
    String? gstNumber,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? createdBy,
    String? companyId,
    String? companyName,
  }) async {
    try {
      final insertData = <String, dynamic>{
        'customer_name': customerName.trim(),
        'mobile_number': mobileNumber.trim(),
        'created_by': createdBy,
        'company_id': companyId,
        'company_name': companyName,
        'ledger_group': 'Sundry Debtors',
        'customer_category_name': 'Sundry Debtors',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (gstNumber != null && gstNumber.trim().isNotEmpty) {
        insertData['gst_number'] = gstNumber.trim().toUpperCase();
      }
      if (address != null && address.trim().isNotEmpty) {
        insertData['address'] = address.trim();
      }
      if (city != null && city.trim().isNotEmpty) {
        insertData['city'] = city.trim();
      }
      if (state != null && state.trim().isNotEmpty) {
        insertData['state'] = state.trim();
      }
      if (pincode != null && pincode.trim().isNotEmpty) {
        insertData['pincode'] = pincode.trim();
      }

      final response = await _supabase
          .from('customers')
          .insert(insertData)
          .select()
          .single();

      return CustomerModel.fromJson(response);
    } catch (e) {
      print('❌ Error creating customer model: $e');
      rethrow;
    }
  }

  // ================== FIX START ==================
  // This new method matches what your UI is calling.
  Future<String> createCustomer(Map<String, dynamic> customerData) async {
    // It takes the map from the dialog and calls the existing 'addCustomer' method.
    return addCustomer(
      customerName: customerData['customer_name'],
      mobileNumber: customerData['mobile_number'],
      address: customerData['address'],
      city: customerData['city'],
      state: customerData['state'],
      pincode: customerData['pincode'],
      gstNumber: customerData['gst_number'],
      companyId: customerData['company_id'],
      // You can add 'createdBy' here if you pass it from the UI
    );
  }
  // =================== FIX END ===================

  // FOR ADMIN: Add customer (This is the original method, now used by `createCustomer`)
  Future<String> addCustomer({
    required String customerName,
    String? mobileNumber,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? gstNumber,
    String? createdBy,
    String? companyId,
  }) async {
    try {
      final response = await _supabase
          .from('customers')
          .insert({
            'customer_name': customerName,
            'mobile_number': mobileNumber,
            'address': address,
            'city': city,
            'state': state,
            'pincode': pincode,
            'gst_number': gstNumber,
            'created_by': createdBy,
            'company_id': companyId,
            'ledger_group': 'Sundry Debtors',
            'customer_category_name': 'Sundry Debtors',
          })
          .select()
          .single();

      return response['id'];
    } catch (e) {
      print('Error creating customer: $e');
      rethrow;
    }
  }

  // FOR ADMIN: Update customer
  Future<void> updateCustomer({
    required String id,
    required String customerName,
    String? mobileNumber,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? gstNumber,
  }) async {
    try {
      await _supabase.from('customers').update({
        'customer_name': customerName,
        'mobile_number': mobileNumber,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'gst_number': gstNumber,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      print('Error updating customer: $e');
      rethrow;
    }
  }

  // FOR ADMIN: Delete customer
  Future<void> deleteCustomer(String id) async {
    try {
      await _supabase.from('customers').delete().eq('id', id);
    } catch (e) {
      print('Error deleting customer: $e');
      rethrow;
    }
  }

  // Get all customer categories
  Future<List<Map<String, dynamic>>> getAllCustomerCategories() async {
    try {
      final response = await _supabase
          .from('customer_categories')
          .select('id, category_name')
          .order('category_name', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching customer categories: $e');
      rethrow;
    }
  }

  // Get customer category name by ID
  Future<String?> getCategoryNameById(String categoryId) async {
    try {
      final response = await _supabase
          .from('customer_categories')
          .select('category_name')
          .eq('id', categoryId)
          .maybeSingle();

      return response?['category_name'] as String?;
    } catch (e) {
      print('Error fetching category name: $e');
      return null;
    }
  }
}
