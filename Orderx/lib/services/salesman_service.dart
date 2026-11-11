// lib/services/salesman_service.dart
import 'package:Orderx/models/salesman.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class SalesmanService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get all salesmen (user_type = 'salesman') scoped to company
  Future<List<Salesman>> getSalesmen({required String companyId}) async {
    final response = await _client
        .from('users')
        .select()
        .eq('user_type', 'salesman')
        .eq('company_id', companyId)
        .order('created_at', ascending: false);

    return (response as List).map((user) => Salesman.fromJson(user)).toList();
  }

  // Add new salesman scoped to company
  Future<String> addSalesman({
    required String name,
    required String mobileNumber,
    required String companyId,
  }) async {
    final response = await _client
        .from('users')
        .insert({
      'name': name,
      'mobile_number': mobileNumber,
      'user_type': 'salesman',
      'company_id': companyId,
      'is_active': false,
    })
        .select()
        .single();

    return response['id'];
  }

  // Update salesman (name, active status)
  Future<void> updateSalesman({
    required String id,
    required String name,
    required bool isActive,
    required String companyId,
  }) async {
    await _client
        .from('users')
        .update({
      'name': name,
      'is_active': isActive,
    })
        .eq('id', id);
  }

  // Check if mobile number exists (for validation)
  Future<bool> mobileNumberExists(String mobileNumber) async {
    final response = await _client
        .from('users')
        .select()
        .eq('mobile_number', mobileNumber)
        .count();
    return response.count > 0;
  }
}