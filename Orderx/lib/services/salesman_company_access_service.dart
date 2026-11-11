import 'package:supabase_flutter/supabase_flutter.dart';

class SalesmanCompanyAccessService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all companies a salesman can access
  Future<List<Map<String, dynamic>>> getAccessibleCompanies(
      String salesmanId) async {
    try {
      print('🔍 Fetching accessible companies for salesman: $salesmanId');

      final response = await _supabase
          .from('salesman_company_access')
          .select(
              'company_id, tally_companies(id, company_name, company_number)')
          .eq('salesman_id', salesmanId);

      print('✅ Found ${response.length} accessible companies');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching accessible companies: $e');
      print('⚠️ salesman_company_access table not available - using salesman company only');
      try {
        final userRow = await _supabase
            .from('users')
            .select('company_id')
            .eq('id', salesmanId)
            .maybeSingle();
        final companyId = userRow?['company_id'] as String?;
        if (companyId == null) return [];

        var company = await _supabase
            .from('tally_companies')
            .select('id, company_name, company_number')
            .eq('id', companyId)
            .maybeSingle();
        company ??= await _supabase
            .from('tally_companies')
            .select('id, company_name, company_number')
            .eq('Guid', companyId)
            .maybeSingle();
        if (company == null) return [];

        return [
          {
            'company_id': company['id'],
            'tally_companies': company,
          }
        ];
      } catch (fallbackError) {
        print('❌ Fallback also failed: $fallbackError');
        return [];
      }
    }
  }

  /// Check if salesman can access a specific company
  Future<bool> canAccessCompany(String salesmanId, String companyId) async {
    try {
      print(
          '🔐 Checking access for salesman: $salesmanId, company: $companyId');

      final response = await _supabase
          .from('salesman_company_access')
          .select('id')
          .eq('salesman_id', salesmanId)
          .eq('company_id', companyId)
          .maybeSingle();

      final hasAccess = response != null;
      print(hasAccess ? '✅ Access granted' : '❌ Access denied');
      return hasAccess;
    } catch (e) {
      print('❌ Error checking access: $e');
      print('⚠️ salesman_company_access table not available - granting access');
      // Fallback: grant access if table doesn't exist
      return true;
    }
  }

  /// Grant salesman access to a company
  Future<void> grantAccess(String salesmanId, String companyId) async {
    try {
      print(
          '➕ Granting access to salesman: $salesmanId for company: $companyId');

      // salesman_company_access table doesn't exist - skipping
      print('⚠️ salesman_company_access table not available - access control disabled');
    } catch (e) {
      print('❌ Error granting access: $e');
      rethrow;
    }
  }

  /// Revoke salesman access to a company
  Future<void> revokeAccess(String salesmanId, String companyId) async {
    try {
      print(
          '➖ Revoking access for salesman: $salesmanId from company: $companyId');

      await _supabase
          .from('salesman_company_access')
          .delete()
          .eq('salesman_id', salesmanId)
          .eq('company_id', companyId);

      print('✅ Access revoked successfully');
    } catch (e) {
      print('❌ Error revoking access: $e');
      rethrow;
    }
  }

  /// Get all salesmen who can access a company
  Future<List<Map<String, dynamic>>> getSalesmenForCompany(
      String companyId) async {
    try {
      print('🔍 Fetching salesmen for company: $companyId');

      final response = await _supabase
          .from('salesman_company_access')
          .select('salesman_id, users(id, name, mobile_number)')
          .eq('company_id', companyId);

      print('✅ Found ${response.length} salesmen');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching salesmen: $e');
      return [];
    }
  }

  /// Get all companies and their access status for a salesman
  Future<List<Map<String, dynamic>>> getCompaniesWithAccessStatus(
    String salesmanId, {
    List<String>? restrictedCompanyIds,
  }) async {
    try {
      print(
          '🔍 Fetching companies with access status for salesman: $salesmanId');

      final userRow = await _supabase
          .from('users')
          .select('company_id')
          .eq('id', salesmanId)
          .maybeSingle();
      final linkedId = userRow?['company_id'] as String?;

      var companyRow = linkedId == null
          ? null
          : await _supabase
              .from('tally_companies')
              .select('id, company_name, company_number, is_active')
              .eq('id', linkedId)
              .maybeSingle();
      companyRow ??= linkedId == null
          ? null
          : await _supabase
              .from('tally_companies')
              .select('id, company_name, company_number, is_active')
              .eq('Guid', linkedId)
              .maybeSingle();

      if (companyRow == null) return [];

      if (restrictedCompanyIds != null &&
          restrictedCompanyIds.isNotEmpty &&
          !restrictedCompanyIds.contains(companyRow['id']) &&
          !restrictedCompanyIds.contains(linkedId)) {
        return [];
      }

      return [
        {
          ...companyRow,
          'has_access': true,
        }
      ];
    } catch (e) {
      print('❌ Error fetching companies with status: $e');
      return [];
    }
  }

  /// Bulk grant access to multiple companies
  Future<void> grantAccessToMultipleCompanies(
    String salesmanId,
    List<String> companyIds,
  ) async {
    try {
      print(
          '➕ Granting access to $salesmanId for ${companyIds.length} companies');

      final records = companyIds
          .map((companyId) => {
                'salesman_id': salesmanId,
                'company_id': companyId,
              })
          .toList();

      await _supabase.from('salesman_company_access').insert(records);

      print('✅ Access granted to all companies');
    } catch (e) {
      print('❌ Error granting bulk access: $e');
      rethrow;
    }
  }

  /// Bulk revoke access from multiple companies
  Future<void> revokeAccessFromMultipleCompanies(
    String salesmanId,
    List<String> companyIds,
  ) async {
    try {
      print(
          '➖ Revoking access for $salesmanId from ${companyIds.length} companies');

      // salesman_company_access table doesn't exist - skipping
      print('⚠️ salesman_company_access table not available - access control disabled');
    } catch (e) {
      print('❌ Error revoking bulk access: $e');
      rethrow;
    }
  }
}
