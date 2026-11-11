import 'package:Orderx/models/user_organization_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserOrganizationService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<UserOrganization?> getOrganizationByKey(String key) async {
    try {
      final response = await _client
          .from('user_organization')
          .select('id, user_name, user_key, user_id, created_at')
          .eq('user_key', key)
          .maybeSingle();

      if (response == null) return null;
      return UserOrganization.fromJson(response);
    } catch (e) {
      print('Error fetching organization by key: $e');
      rethrow;
    }
  }
}
