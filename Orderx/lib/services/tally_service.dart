// lib/services/tally_service.dart
import 'package:Orderx/models/tally_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TallyService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get current Tally settings
  Future<TallySettings> getTallySettings() async {
    final response = await _client
        .from('company_settings')
        .select()
        .limit(1)
        .single();

    return TallySettings.fromJson(response);
  }

  // Update Tally settings
  Future<void> updateTallySettings(TallySettings settings) async {
    await _client
        .from('company_settings')
        .upsert(settings.toJson())
        .select()
        .single();
  }

  // Test Tally connection
  Future<bool> testTallyConnection({
    required String serverUrl,
    required int port,
    required String companyName,
  }) async {
    try {
      // This will be implemented in your middleware/backend
      // For now, we'll simulate a connection test
      await Future.delayed(const Duration(seconds: 2));

      // In real implementation, this would call your middleware
      // that communicates with Tally XML API
      return serverUrl.isNotEmpty &&
          companyName.isNotEmpty &&
          port > 0;
    } catch (e) {
      return false;
    }
  }

  // Get sync logs (last 20 sync attempts)
  Future<List<Map<String, dynamic>>> getSyncLogs() async {
    final response = await _client
        .from('tally_sync_log')
        .select('''
          *,
          sales_orders(order_number),
          users(name)
        ''')
        .order('synced_at', ascending: false)
        .limit(20);

    return response;
  }
}