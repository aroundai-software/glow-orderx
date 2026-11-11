import 'package:Orderx/models/price_level_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PriceLevelService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all price levels for a given product by product ID or product name
  Future<List<PriceLevelModel>> getPriceLevelsForProduct({
    required String productId,
    String? productName,
    String? companyId,
  }) async {
    try {
      var query = _supabase
          .from('price_level')
          .select()
          .eq('is_active', true);

      if (companyId != null && companyId.isNotEmpty) {
        query = query.eq('company_id', companyId);
      }

      // Try matching by product_id first
      final responseById = await query
          .eq('product_id', productId)
          .order('from_qty', ascending: true);

      final listById = (responseById as List)
          .map((item) => PriceLevelModel.fromJson(item as Map<String, dynamic>))
          .toList();

      if (listById.isNotEmpty) {
        return listById;
      }

      // Fallback: match by product name if product_id was not found
      if (productName != null && productName.isNotEmpty) {
        var queryByName = _supabase
            .from('price_level')
            .select()
            .eq('is_active', true)
            .eq('product_name', productName);

        if (companyId != null && companyId.isNotEmpty) {
          queryByName = queryByName.eq('company_id', companyId);
        }

        final responseByName = await queryByName.order('from_qty', ascending: true);
        final listByName = (responseByName as List)
            .map((item) => PriceLevelModel.fromJson(item as Map<String, dynamic>))
            .toList();

        return listByName;
      }

      return [];
    } catch (e) {
      print('❌ [PriceLevelService] Error fetching price levels for product: $e');
      return [];
    }
  }

  /// Get distinct price level names available in the database
  Future<List<String>> getDistinctPriceLevels({String? companyId}) async {
    try {
      var query = _supabase
          .from('price_level')
          .select('price_level')
          .eq('is_active', true);

      if (companyId != null && companyId.isNotEmpty) {
        query = query.eq('company_id', companyId);
      }

      final response = await query;
      final Set<String> levels = {};
      for (final row in response as List) {
        final level = row['price_level'] as String?;
        if (level != null && level.trim().isNotEmpty) {
          levels.add(level.trim());
        }
      }
      return levels.toList()..sort();
    } catch (e) {
      print('❌ [PriceLevelService] Error fetching distinct price levels: $e');
      return [];
    }
  }
}
