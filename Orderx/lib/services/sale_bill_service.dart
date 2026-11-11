import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Orderx/models/sale_bill_model.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/utils/company_query.dart';

class SaleBillService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all sale bills
  Future<List<SaleBillModel>> getAllSaleBills({String? companyId}) async {
    try {
      dynamic query = _supabase.from('sale_bill').select();

      // Filter by company_id if provided
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }

      query = query.order('date', ascending: false);
      final response = await query;

      return (response as List)
          .map((json) => SaleBillModel.fromJson(json))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        // company_id column missing in sale_bill table; fallback to unfiltered query
        final fallbackResponse = await _supabase
            .from('sale_bill')
            .select()
            .order('date', ascending: false);
        return (fallbackResponse as List)
            .map((json) => SaleBillModel.fromJson(json))
            .toList();
      }
      rethrow;
    } catch (e) {
      print('Error fetching sale bills: $e');
      rethrow;
    }
  }

  /// Get sale bills by date range
  Future<List<SaleBillModel>> getSaleBillsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _supabase
          .from('sale_bill')
          .select()
          .gte('date', startDate.toIso8601String().split('T')[0])
          .lte('date', endDate.toIso8601String().split('T')[0])
          .order('date', ascending: false);

      return (response as List)
          .map((json) => SaleBillModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching sale bills by date range: $e');
      rethrow;
    }
  }

  /// Get sale bills by status
  Future<List<SaleBillModel>> getSaleBillsByStatus(String status) async {
    try {
      final response = await _supabase
          .from('sale_bill')
          .select()
          .eq('status', status)
          .order('date', ascending: false);

      return (response as List)
          .map((json) => SaleBillModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching sale bills by status: $e');
      rethrow;
    }
  }

  /// Get sale bill by ID
  Future<SaleBillModel?> getSaleBillById(String id) async {
    try {
      final response =
          await _supabase.from('sale_bill').select().eq('id', id).maybeSingle();

      if (response == null) return null;
      return SaleBillModel.fromJson(response);
    } catch (e) {
      print('Error fetching sale bill by ID: $e');
      rethrow;
    }
  }

  Future<SaleBillModel?> getSaleBillByOrderNumber(
    String orderNumber, {
    String? companyId,
  }) async {
    try {
      dynamic query = _supabase
          .from('sale_bill')
          .select()
          .eq('order_number', orderNumber);

      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }

      final response = await query.order('date', ascending: false).maybeSingle();
      if (response == null) return null;
      return SaleBillModel.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        final response = await _supabase
            .from('sale_bill')
            .select()
            .eq('order_number', orderNumber)
            .order('date', ascending: false)
            .maybeSingle();
        if (response == null) return null;
        return SaleBillModel.fromJson(response);
      }
      rethrow;
    } catch (e) {
      print('Error fetching sale bill by order number $orderNumber: $e');
      rethrow;
    }
  }

  /// Search sale bills by order number or invoice number
  Future<List<SaleBillModel>> searchSaleBills(String query) async {
    try {
      final response = await _supabase
          .from('sale_bill')
          .select()
          .or('order_number.ilike.%$query%,invoice_number.ilike.%$query%')
          .order('date', ascending: false);

      return (response as List)
          .map((json) => SaleBillModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error searching sale bills: $e');
      rethrow;
    }
  }

  /// Get count of sale bills by status
  Future<Map<String, int>> getSaleBillStats({String? companyId}) async {
    try {
      dynamic pendingQuery = _supabase.from('sale_bill').select().eq('status', 'Pending');
      dynamic completedQuery = _supabase.from('sale_bill').select().eq('status', 'Completed');
      dynamic cancelledQuery = _supabase.from('sale_bill').select().eq('status', 'Cancelled');

      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        pendingQuery = applyCompanyIdFilter(pendingQuery, keys);
        completedQuery = applyCompanyIdFilter(completedQuery, keys);
        cancelledQuery = applyCompanyIdFilter(cancelledQuery, keys);
      }

      final pendingCount = await pendingQuery.count();
      final completedCount = await completedQuery.count();
      final cancelledCount = await cancelledQuery.count();

      return {
        'pending': pendingCount.count,
        'completed': completedCount.count,
        'cancelled': cancelledCount.count,
        'total':
            pendingCount.count + completedCount.count + cancelledCount.count,
      };
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        final pendingCount =
            await _supabase.from('sale_bill').select().eq('status', 'Pending').count();
        final completedCount =
            await _supabase.from('sale_bill').select().eq('status', 'Completed').count();
        final cancelledCount =
            await _supabase.from('sale_bill').select().eq('status', 'Cancelled').count();

        return {
          'pending': pendingCount.count,
          'completed': completedCount.count,
          'cancelled': cancelledCount.count,
          'total':
              pendingCount.count + completedCount.count + cancelledCount.count,
        };
      }
      rethrow;
    } catch (e) {
      print('Error fetching sale bill stats: $e');
      rethrow;
    }
  }

  /// Create a sale bill entry for a given order.
  /// This is used when converting a Sales Order to a SALE BILL.
  Future<SaleBillModel> createSaleBillForOrder(
    OrderModel order, {
    String? companyId,
  }) async {
    final existing =
        await getSaleBillByOrderNumber(order.orderNumber, companyId: companyId);
    if (existing != null) {
      return existing;
    }

    final now = DateTime.now().toUtc();
    final invoiceNumber = _generateInvoiceNumber();
    final Map<String, dynamic> baseData = {
      'order_number': order.orderNumber,
      'date': now.toIso8601String().split('T')[0],
      'invoice_number': invoiceNumber,
      'status': 'Completed',
      'created_at': now.toIso8601String(),
    };

    final Map<String, dynamic> withCompany = {
      ...baseData,
      if (companyId != null && companyId.isNotEmpty) 'company_id': companyId,
    };

    try {
      final response = await _supabase
          .from('sale_bill')
          .insert(withCompany)
          .select()
          .single();
      return SaleBillModel.fromJson(response);
    } on PostgrestException catch (e) {
      // If company_id column does not exist, retry without it.
      if (e.code == '42703') {
        final response = await _supabase
            .from('sale_bill')
            .insert(baseData)
            .select()
            .single();
        return SaleBillModel.fromJson(response);
      }
      rethrow;
    } catch (e) {
      print('Error creating sale bill for order ${order.orderNumber}: $e');
      rethrow;
    }
  }

  String _generateInvoiceNumber() {
    final now = DateTime.now().toUtc();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'SB$y$m$d$h$min$s';
  }
}
