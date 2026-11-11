import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Orderx/models/item_closing_balance_model.dart';
import 'package:Orderx/utils/company_query.dart';

class ItemClosingBalanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all item closing balances
  Future<List<ItemClosingBalanceModel>> getAllItemClosingBalances({String? companyId}) async {
    try {
      dynamic query = _supabase.from('item_closing_balance').select();

      // Filter by company_id if provided
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }

      query = query.order('itemname', ascending: true);
      final response = await query;

      return (response as List)
          .map((json) => ItemClosingBalanceModel.fromJson(json))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        // company_id column missing; fallback to unfiltered query
        final fallbackResponse = await _supabase
            .from('item_closing_balance')
            .select()
            .order('itemname', ascending: true);
        return (fallbackResponse as List)
            .map((json) => ItemClosingBalanceModel.fromJson(json))
            .toList();
      }
      rethrow;
    } catch (e) {
      print('Error fetching item closing balances: $e');
      rethrow;
    }
  }

  /// Get item closing balances by godown
  Future<List<ItemClosingBalanceModel>> getItemsByGodown(String godown) async {
    try {
      final response = await _supabase
          .from('item_closing_balance')
          .select()
          .eq('godown', godown)
          .order('itemname', ascending: true);

      return (response as List)
          .map((json) => ItemClosingBalanceModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching items by godown: $e');
      rethrow;
    }
  }

  /// Get out of stock items
  Future<List<ItemClosingBalanceModel>> getOutOfStockItems() async {
    try {
      final response = await _supabase
          .from('item_closing_balance')
          .select()
          .lte('closing_quantity', 0)
          .order('itemname', ascending: true);

      return (response as List)
          .map((json) => ItemClosingBalanceModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching out of stock items: $e');
      rethrow;
    }
  }

  /// Get low stock items (quantity <= 10)
  Future<List<ItemClosingBalanceModel>> getLowStockItems() async {
    try {
      final response = await _supabase
          .from('item_closing_balance')
          .select()
          .gt('closing_quantity', 0)
          .lte('closing_quantity', 10)
          .order('closing_quantity', ascending: true);

      return (response as List)
          .map((json) => ItemClosingBalanceModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching low stock items: $e');
      rethrow;
    }
  }

  /// Search items by name or part number
  Future<List<ItemClosingBalanceModel>> searchItems(String query) async {
    try {
      final response = await _supabase
          .from('item_closing_balance')
          .select()
          .or('itemname.ilike.%$query%,partnumber.ilike.%$query%')
          .order('itemname', ascending: true);

      return (response as List)
          .map((json) => ItemClosingBalanceModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error searching items: $e');
      rethrow;
    }
  }

  /// Get item closing balance statistics
  Future<Map<String, dynamic>> getItemStats({String? companyId}) async {
    try {
      final allItems = await getAllItemClosingBalances(companyId: companyId);

      int inStockCount = 0;
      int lowStockCount = 0;
      int outOfStockCount = 0;
      double totalClosingQty = 0;
      double totalSalableQty = 0;

      for (var item in allItems) {
        totalClosingQty += item.closingQuantity;
        totalSalableQty += item.salableQty;

        if (item.isOutOfStock) {
          outOfStockCount++;
        } else if (item.isLowStock) {
          lowStockCount++;
        } else {
          inStockCount++;
        }
      }

      return {
        'total_items': allItems.length,
        'in_stock_count': inStockCount,
        'low_stock_count': lowStockCount,
        'out_of_stock_count': outOfStockCount,
        'total_closing_quantity': totalClosingQty,
        'total_salable_quantity': totalSalableQty,
      };
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        // Fallback to unfiltered stats if company column missing
        return await getItemStats();
      }
      rethrow;
    } catch (e) {
      print('Error fetching item stats: $e');
      rethrow;
    }
  }

  /// Get unique godowns
  Future<List<String>> getGodowns() async {
    try {
      final response = await _supabase
          .from('item_closing_balance')
          .select('godown')
          .not('godown', 'is', null);

      final godowns = (response as List)
          .map((json) => json['godown'] as String)
          .toSet()
          .toList();

      godowns.sort();
      return godowns;
    } catch (e) {
      print('Error fetching godowns: $e');
      rethrow;
    }
  }
}
