// lib/services/admin_stats_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminStatsService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get total order count
  Future<int> getTotalOrdersCount() async {
    final response = await _client
        .from('sales_orders')
        .select()
        .count();
    return response.count;
  }

  // Get pending approvals count (status = 'pending' AND not synced)
  Future<int> getPendingApprovalsCount() async {
    final response = await _client
        .from('sales_orders')
        .select()
        .eq('status', 'pending')
        .eq('synced_to_tally', false)
        .count();
    return response.count;
  }

  // ✅ NEW: Get edit requests count
  Future<int> getEditRequestsCount() async {
    final response = await _client
        .from('sales_orders')
        .select()
        .eq('edit_request_status', 'pending')
        .count();
    return response.count;
  }

  // ✅ NEW: Get total pending items (orders + edit requests)
  Future<int> getTotalPendingCount() async {
    final orderCount = await getPendingApprovalsCount();
    final editCount = await getEditRequestsCount();
    return orderCount + editCount;
  }

  // Get synced orders count
  Future<int> getSyncedOrdersCount() async {
    final response = await _client
        .from('sales_orders')
        .select()
        .eq('synced_to_tally', true)
        .count();
    return response.count;
  }

  // Get active salesmen count
  Future<int> getSalesmenCount() async {
    final response = await _client
        .from('users')
        .select()
        .eq('user_type', 'salesman')
        .eq('is_active', true)
        .count();
    return response.count;
  }
}