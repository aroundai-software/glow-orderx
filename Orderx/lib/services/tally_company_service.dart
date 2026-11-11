import 'package:Orderx/models/tally_company_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TallyCompanyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all active Tally companies
  Future<List<TallyCompanyModel>> getAllCompanies() async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select()
          .eq('is_active', true)
          .order('company_name', ascending: true);

      return (response as List)
          .map((json) => TallyCompanyModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching companies: $e');
      rethrow;
    }
  }

  /// Get all companies (both active and inactive)
  Future<List<TallyCompanyModel>> getAllCompaniesWithStatus() async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select()
          .order('company_name', ascending: true);

      return (response as List)
          .map((json) => TallyCompanyModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching all companies: $e');
      rethrow;
    }
  }

  /// Get company by company number
  Future<TallyCompanyModel?> getCompanyByNumber(String companyNumber) async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select()
          .eq('company_number', companyNumber)
          .maybeSingle();

      if (response == null) return null;
      return TallyCompanyModel.fromJson(response);
    } catch (e) {
      print('Error fetching company by number: $e');
      return null;
    }
  }

  /// Get company by GUID
  Future<TallyCompanyModel?> getCompanyByGuid(String Guid) async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select()
          .eq('Guid', Guid)
          .maybeSingle();

      if (response == null) return null;
      return TallyCompanyModel.fromJson(response);
    } catch (e) {
      print('Error fetching company by GUID: $e');
      return null;
    }
  }

  /// Resolve a company from either tally_companies.id or Tally Guid.
  /// App users may store either value in company_id.
  Future<TallyCompanyModel?> resolveCompany(String? idOrGuid) async {
    final key = idOrGuid?.trim() ?? '';
    if (key.isEmpty || key == 'ALL') return null;

    try {
      var row = await _supabase
          .from('tally_companies')
          .select()
          .eq('id', key)
          .maybeSingle();

      row ??= await _supabase
          .from('tally_companies')
          .select()
          .eq('Guid', key)
          .maybeSingle();

      if (row == null) return null;
      return TallyCompanyModel.fromJson(row);
    } catch (e) {
      print('Error resolving company: $e');
      return null;
    }
  }

  /// Get company by ID (also accepts Tally Guid)
  Future<TallyCompanyModel?> getCompanyById(String id) async {
    return resolveCompany(id);
  }

  /// Create a new Tally company
  Future<TallyCompanyModel> createCompany({
    required String companyName,
    required String companyNumber,
    required String Guid,
    String? companyAlias,
    String? companyDescription,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? pinCode,
    String? country,
    String? phoneNumber,
    String? email,
    String? website,
    String? gstNumber,
    String? panNumber,
    String? tanNumber,
    DateTime? financialYearStartDate,
    DateTime? financialYearEndDate,
    bool isActive = true,
    String? tallyServerUrl,
    int tallyPort = 9000,
    String? tallyUsername,
  }) async {
    try {
      // Check if company already exists
      final existing = await _supabase
          .from('tally_companies')
          .select()
          .or('company_number.eq.$companyNumber,Guid.eq.$Guid')
          .maybeSingle();

      if (existing != null) {
        throw Exception('Company with this number or GUID already exists');
      }

      final response = await _supabase
          .from('tally_companies')
          .insert({
            'company_name': companyName,
            'company_number': companyNumber,
            'Guid': Guid,
            'company_alias': companyAlias,
            'company_description': companyDescription,
            'address_line1': addressLine1,
            'address_line2': addressLine2,
            'city': city,
            'state': state,
            'pin_code': pinCode,
            'country': country ?? 'India',
            'phone_number': phoneNumber,
            'email': email,
            'website': website,
            'gst_number': gstNumber,
            'pan_number': panNumber,
            'tan_number': tanNumber,
            'financial_year_start_date': financialYearStartDate?.toIso8601String(),
            'financial_year_end_date': financialYearEndDate?.toIso8601String(),
            'is_active': isActive,
            'tally_server_url': tallyServerUrl,
            'tally_port': tallyPort,
            'tally_username': tallyUsername,
            'sync_status': 'pending',
          })
          .select()
          .single();

      return TallyCompanyModel.fromJson(response);
    } catch (e) {
      print('Error creating company: $e');
      rethrow;
    }
  }

  /// Update company profile details (Name, Email, Phone)
  Future<void> updateCompanyProfile({
    required String id,
    required String companyName,
    String? email,
    String? phoneNumber,
  }) async {
    try {
      await _supabase.from('tally_companies').update({
        'company_name': companyName,
        'email': email,
        'phone_number': phoneNumber,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      print('Error updating company profile: $e');
      rethrow;
    }
  }

  /// Update company details
  Future<TallyCompanyModel> updateCompany({
    required String id,
    String? companyName,
    String? companyAlias,
    String? companyDescription,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? pinCode,
    String? phoneNumber,
    String? email,
    String? website,
    String? gstNumber,
    String? panNumber,
    String? tanNumber,
    DateTime? financialYearStartDate,
    DateTime? financialYearEndDate,
    bool? isActive,
    String? tallyServerUrl,
    int? tallyPort,
    String? tallyUsername,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (companyName != null) updateData['company_name'] = companyName;
      if (companyAlias != null) updateData['company_alias'] = companyAlias;
      if (companyDescription != null) updateData['company_description'] = companyDescription;
      if (addressLine1 != null) updateData['address_line1'] = addressLine1;
      if (addressLine2 != null) updateData['address_line2'] = addressLine2;
      if (city != null) updateData['city'] = city;
      if (state != null) updateData['state'] = state;
      if (pinCode != null) updateData['pin_code'] = pinCode;
      if (phoneNumber != null) updateData['phone_number'] = phoneNumber;
      if (email != null) updateData['email'] = email;
      if (website != null) updateData['website'] = website;
      if (gstNumber != null) updateData['gst_number'] = gstNumber;
      if (panNumber != null) updateData['pan_number'] = panNumber;
      if (tanNumber != null) updateData['tan_number'] = tanNumber;
      if (financialYearStartDate != null) {
        updateData['financial_year_start_date'] = financialYearStartDate.toIso8601String();
      }
      if (financialYearEndDate != null) {
        updateData['financial_year_end_date'] = financialYearEndDate.toIso8601String();
      }
      if (isActive != null) updateData['is_active'] = isActive;
      if (tallyServerUrl != null) updateData['tally_server_url'] = tallyServerUrl;
      if (tallyPort != null) updateData['tally_port'] = tallyPort;
      if (tallyUsername != null) updateData['tally_username'] = tallyUsername;

      final response = await _supabase
          .from('tally_companies')
          .update(updateData)
          .eq('id', id)
          .select()
          .single();

      return TallyCompanyModel.fromJson(response);
    } catch (e) {
      print('Error updating company: $e');
      rethrow;
    }
  }

  /// Update sync status
  Future<void> updateSyncStatus({
    required String id,
    required String syncStatus,
    String? syncErrorMessage,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'sync_status': syncStatus,
      };

      if (syncStatus == 'completed') {
        updateData['is_synced'] = true;
        updateData['last_synced_at'] = DateTime.now().toUtc().toIso8601String();
        updateData['sync_error_message'] = null;
      } else if (syncStatus == 'failed') {
        updateData['sync_error_message'] = syncErrorMessage;
      }

      await _supabase
          .from('tally_companies')
          .update(updateData)
          .eq('id', id);
    } catch (e) {
      print('Error updating sync status: $e');
      rethrow;
    }
  }

  /// Delete company (soft delete - set is_active to false)
  Future<void> deleteCompany(String id) async {
    try {
      await _supabase
          .from('tally_companies')
          .update({'is_active': false})
          .eq('id', id);
    } catch (e) {
      print('Error deleting company: $e');
      rethrow;
    }
  }

  /// Get companies by sync status
  Future<List<TallyCompanyModel>> getCompaniesBySyncStatus(String syncStatus) async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select()
          .eq('sync_status', syncStatus)
          .eq('is_active', true);

      return (response as List)
          .map((json) => TallyCompanyModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching companies by sync status: $e');
      rethrow;
    }
  }

  /// Get companies pending sync
  Future<List<TallyCompanyModel>> getPendingSyncCompanies() async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select()
          .eq('sync_status', 'pending')
          .eq('is_active', true);

      return (response as List)
          .map((json) => TallyCompanyModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching pending sync companies: $e');
      rethrow;
    }
  }

  /// Check if company number exists
  Future<bool> companyNumberExists(String companyNumber) async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select('id')
          .eq('company_number', companyNumber)
          .maybeSingle();

      return response != null;
    } catch (e) {
      print('Error checking company number: $e');
      return false;
    }
  }

  /// Check if company GUID exists
  Future<bool> GuidExists(String Guid) async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select('id')
          .eq('Guid', Guid)
          .maybeSingle();

      return response != null;
    } catch (e) {
      print('Error checking company GUID: $e');
      return false;
    }
  }

  /// Get sync statistics
  Future<Map<String, int>> getSyncStatistics() async {
    try {
      final response = await _supabase
          .from('tally_companies')
          .select('sync_status')
          .eq('is_active', true);

      final stats = {
        'total': 0,
        'pending': 0,
        'syncing': 0,
        'completed': 0,
        'failed': 0,
      };

      for (final item in response as List) {
        stats['total'] = stats['total']! + 1;
        final status = item['sync_status'] as String;
        stats[status] = (stats[status] ?? 0) + 1;
      }

      return stats;
    } catch (e) {
      print('Error getting sync statistics: $e');
      rethrow;
    }
  }
}
