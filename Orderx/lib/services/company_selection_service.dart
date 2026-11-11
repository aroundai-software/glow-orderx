import 'package:supabase_flutter/supabase_flutter.dart';

class CompanySelectionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all active Tally companies for selection
  Future<List<Map<String, dynamic>>> getCompanyByIds(
      List<String> companyIds) async {
    if (companyIds.isEmpty) return [];
    try {
      PostgrestFilterBuilder query = _supabase
          .from('tally_companies')
          .select('id, company_name, company_number, is_active');

      if (companyIds.length == 1) {
        final key = companyIds.first;
        query = query.or('id.eq.$key,Guid.eq.$key');
      } else {
        final filters = companyIds
            .expand((id) => ['id.eq.$id', 'Guid.eq.$id'])
            .join(',');
        query = query.or(filters);
      }

      final response = await query;
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error fetching companies by IDs: $e');
      return [];
    }
  }

  /// Get company by ID or Tally Guid
  Future<Map<String, dynamic>?> getCompanyById(String companyId) async {
    try {
      var response = await _supabase
          .from('tally_companies')
          .select()
          .eq('id', companyId)
          .maybeSingle();

      response ??= await _supabase
          .from('tally_companies')
          .select()
          .eq('Guid', companyId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error fetching company: $e');
      return null;
    }
  }
}
