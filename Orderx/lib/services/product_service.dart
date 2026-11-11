import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/utils/company_query.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _productIdentifierFields = <String>[
  'PartNumber',
  'ItemAlias',
  'ItemAlias1',
  'ItemName',
];

String _escapeForSupabaseFilter(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll(',', r'\,')
      .replaceAll("'", "''");
}

String? _buildSubsequencePattern(String value) {
  final condensed = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (condensed.length < 2) {
    return null;
  }

  final buffer = StringBuffer('%');
  for (final char in condensed.split('')) {
    if (char.isEmpty) continue;
    buffer.write(_escapeForSupabaseFilter(char));
    buffer.write('%');
  }

  return buffer.toString();
}

List<String> _buildFieldFilters(String pattern) {
  return _productIdentifierFields
      .map((field) => '$field.ilike.$pattern')
      .toList();
}

List<String> _buildSearchPatterns(String rawQuery) {
  final trimmed = rawQuery.trim();
  if (trimmed.isEmpty) {
    return const [];
  }

  final patterns = <String>{};

  final escapedFull = _escapeForSupabaseFilter(trimmed);
  patterns.add('%$escapedFull%');

  final collapsed = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (collapsed.isNotEmpty) {
    final escapedCollapsed = _escapeForSupabaseFilter(collapsed);
    patterns.add('%$escapedCollapsed%');

    final subsequencePattern = _buildSubsequencePattern(collapsed);
    if (subsequencePattern != null) {
      patterns.add(subsequencePattern);
    }
  }

  final words = trimmed.split(RegExp(r'[\s\-_/]+'));
  for (final word in words) {
    if (word.isEmpty) continue;
    patterns.add('%${_escapeForSupabaseFilter(word)}%');
  }

  return patterns.toList();
}

String? _extractPrefixAnchor(String rawQuery) {
  final match = RegExp(r'[A-Za-z]+').firstMatch(rawQuery);
  if (match == null) {
    return null;
  }
  final anchor = match.group(0)?.toLowerCase();
  if (anchor == null || anchor.isEmpty) {
    return null;
  }
  return anchor;
}

bool _tokenListStartsWithAnchor(Iterable<String> tokens, String anchor) {
  for (final token in tokens) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.toLowerCase().startsWith(anchor)) {
      return true;
    }
  }
  return false;
}

bool _productMatchesPrefixAnchor(ProductModel product, String anchor) {
  bool matchesField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final tokens = value.split(RegExp(r'[^A-Za-z0-9]+'));
    return _tokenListStartsWithAnchor(tokens, anchor);
  }

  return matchesField(product.productName) ||
      matchesField(product.productCode) ||
      matchesField(product.vtNumber);
}

dynamic _createProductSearchQuery(SupabaseClient client, {String? companyId, List<String>? companyIdKeys}) {
  dynamic query = client.from('products').select('*').eq('is_active', true);
  final keys = companyIdKeys ??
      ((companyId != null && companyId.isNotEmpty) ? [companyId] : const <String>[]);
  if (keys.isNotEmpty) {
    query = applyCompanyIdFilter(query, keys);
  }
  return query;
}

List<String> _extractLookupTokens(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const [];
  }

  final tokens = <String>{trimmed};

  final lines = trimmed.split(RegExp(r'[\r\n]+'));
  for (final line in lines) {
    final lineTrimmed = line.trim();
    if (lineTrimmed.isEmpty) continue;
    tokens.add(lineTrimmed);

    final colonIndex = lineTrimmed.indexOf(':');
    if (colonIndex != -1 && colonIndex < lineTrimmed.length - 1) {
      final value = lineTrimmed.substring(colonIndex + 1).trim();
      if (value.isNotEmpty) {
        tokens.add(value);
      }
    }
  }

  return tokens.toList();
}

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;



  Future<List<ProductModel>> getProducts({String? companyId}) async {
    try {
      dynamic query = _supabase.from('products').select('*');
      
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }

      final response = await query.order('created_at', ascending: false);

      return await _mapProductsWithItemRates(response, companyId: companyId);
    } catch (e) {
      print('❌ Error fetching products: $e');
      rethrow;
    }
  }

  // Get total count of products
  Future<int> getTotalProductCount({String? companyId}) async {
    try {
      dynamic query = _supabase.from('products').select('id');
      
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }
      
      final response = await query.count(CountOption.exact);
      return response.count ?? 0;
    } catch (e) {
      print('❌ Error fetching product count: $e');
      return 0;
    }
  }

  // Get ALL products handling Supabase 1000 row limit
  Future<List<ProductModel>> getAllProducts({String? companyId}) async {
    try {
      final List<ProductModel> allProducts = [];
      int page = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final offset = page * pageSize;
        dynamic query = _supabase.from('products').select('*');

        if (companyId != null && companyId.isNotEmpty) {
          final keys = await companyKeys(companyId);
          query = applyCompanyIdFilter(query, keys);
        }

        final response = await query
            .order('ItemName', ascending: true)
            .range(offset, offset + pageSize - 1);

        final batch = await _mapProductsWithItemRates(response, companyId: companyId);
        allProducts.addAll(batch);

        if ((response as List).length < pageSize) {
          hasMore = false;
        } else {
          page++;
        }
      }

      return allProducts;
    } catch (e) {
      print('❌ Error fetching all products: $e');
      rethrow;
    }
  }

  // Get products with pagination (1000 per page)
  Future<List<ProductModel>> getProductsPaginated({
    String? companyId,
    int page = 0,
    int limit = 1000,
  }) async {
    try {
      final offset = page * limit;
      dynamic query = _supabase.from('products').select('*');
      
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }

      final response = await query
          .order('ItemName', ascending: true)
          .range(offset, offset + limit - 1);

      return await _mapProductsWithItemRates(response, companyId: companyId);
    } catch (e) {
      print('❌ Error fetching paginated products: $e');
      rethrow;
    }
  }

  Future<List<ProductModel>> _mapProductsWithItemRates(
    dynamic response, {
    String? companyId,
  }) async {
    if (response is! List) {
      return const [];
    }

    final productJsonList = response
        .whereType<Map<String, dynamic>>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final productIds = productJsonList
        .map((product) => product['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final ratesByProduct = await _fetchItemRatesForProducts(productIds, companyId: companyId);

    final enrichedProducts = productJsonList.map((product) {
      final productId = product['id']?.toString();
      final rates = productId != null ? ratesByProduct[productId] : null;
      if (rates != null && rates.isNotEmpty) {
        product['item_rates'] = rates;
        product['price_levels'] = rates;
      }
      return product;
    }).toList();

    return enrichedProducts.map(ProductModel.fromJson).toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchItemRatesForProducts(
    List<String> productIds, {
    String? companyId,
  }) async {
    final result = <String, List<Map<String, dynamic>>>{};
    if (productIds.isEmpty) {
      return result;
    }

    final keys = await companyKeys(companyId);

    try {
      const chunkSize = 100;
      for (var i = 0; i < productIds.length; i += chunkSize) {
        final end = (i + chunkSize) > productIds.length
            ? productIds.length
            : i + chunkSize;
        final chunk = productIds.sublist(i, end);

        dynamic query = _supabase
            .from('price_level')
            .select('id, product_id, product_name, rate, price_level, from_qty, less_than_qty, unit, discount_percentage')
            .eq('is_active', true)
            .inFilter('product_id', chunk);

        if (keys.isNotEmpty) {
          query = applyCompanyIdFilter(query, keys);
        }

        final ratesResponse = await query
            .order('from_qty', ascending: true) as List<dynamic>;

        for (final rate in ratesResponse) {
          if (rate is! Map<String, dynamic>) continue;
          final productId = rate['product_id']?.toString();
          if (productId == null) continue;
          result.putIfAbsent(productId, () => []).add(rate);
        }
      }
    } catch (e) {
      print('⚠️ Unable to fetch price_level rates: $e');
    }

    return result;
  }

  Future<List<ProductModel>> searchProducts(String query,
      {String? companyId}) async {
    try {
      final searchPatterns = _buildSearchPatterns(query);
      if (searchPatterns.isEmpty) {
        return [];
      }

      final keys = await companyKeys(companyId);
      final rawResults = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      final prefixAnchor = _extractPrefixAnchor(query);

      for (final pattern in searchPatterns) {
        if (rawResults.length >= 50) break;

        final remainingLimit = 50 - rawResults.length;
        final filter = _buildFieldFilters(pattern).join(',');

        final response =
            await _createProductSearchQuery(_supabase, companyIdKeys: keys)
                .or(filter)
                .order('ItemName', ascending: true)
                .limit(remainingLimit);

        if (response is! List || response.isEmpty) {
          continue;
        }

        for (final item in response) {
          if (item is! Map<String, dynamic>) continue;
          final id = item['id']?.toString();
          if (id != null && seenIds.add(id)) {
            rawResults.add(item);
            if (rawResults.length >= 50) break;
          }
        }
      }

      final results = await _mapProductsWithItemRates(rawResults, companyId: companyId);

      if (prefixAnchor == null) {
        return results;
      }

      final filtered = results
          .where(
              (product) => _productMatchesPrefixAnchor(product, prefixAnchor))
          .toList();

      return filtered;
    } catch (e) {
      print('❌ Error searching products: $e');
      rethrow;
    }
  }

  Future<ProductModel?> getProductByCode(String code,
      {String? companyId}) async {
    final lookupTokens = _extractLookupTokens(code);
    if (lookupTokens.isEmpty) {
      return null;
    }

    for (final token in lookupTokens) {
      final product =
          await _fetchProductBySingleToken(token, companyId: companyId);
      if (product != null) {
        return product;
      }
    }

    return null;
  }

  Future<ProductModel?> _fetchProductBySingleToken(String token,
      {String? companyId}) async {
    final sanitized = token.trim();
    if (sanitized.isEmpty) {
      return null;
    }

    try {
      final escapedValue = _escapeForSupabaseFilter(sanitized);
      final orFilter = _productIdentifierFields
          .map((field) => '$field.ilike.$escapedValue')
          .join(',');

      dynamic query = _supabase
          .from('products')
          .select('*')
          .eq('is_active', true)
          .or(orFilter);

      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }

      final response = await query.limit(5);

      if (response.isEmpty) {
        return null;
      }

      final normalized = sanitized.toLowerCase();

      Map<String, dynamic>? bestMatch;
      for (final Map<String, dynamic> item in response) {
        final matches = _productIdentifierFields.any((field) {
          final value = item[field];
          if (value is! String) return false;
          return value.trim().toLowerCase() == normalized;
        });
        if (matches) {
          bestMatch = item;
          break;
        }
        bestMatch ??= item;
      }

      if (bestMatch == null) {
        return null;
      }

      final enriched = await _mapProductsWithItemRates([bestMatch], companyId: companyId);
      return enriched.isNotEmpty
          ? enriched.first
          : ProductModel.fromJson(bestMatch);
    } catch (e) {
      print('Error fetching product by code [$sanitized]: $e');
      return null;
    }
  }

  Future<bool> productCodeExists(String code, {String? excludeId}) async {
    try {
      var query =
          _supabase.from('products').select('id').eq('PartNumber', code);

      if (excludeId != null) {
        query = query.neq('id', excludeId);
      }

      final response = await query.limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      print('Error checking product code: $e');
      return false;
    }
  }

  Future<String?> addProduct({
    required String productName,
    required String productCode,
    required String unit,
    required double price,
    required double gstRate,
    required bool isActive,
    int initialStock = 0, // Add optional initial stock parameter
    String? companyId, // Add optional company ID parameter
  }) async {
    try {
      final response = await _supabase
          .from('products')
          .insert({
            'ItemName': productName,
            'PartNumber': productCode,
            'ItemUnit': unit,
            'ItemRate': price,
            'GstRate': gstRate,
            'ItemQuantity': initialStock, // Set initial stock
            'is_active': isActive,
            'company_id': companyId, // Add company ID
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();

      return response['id'] as String;
    } catch (e) {
      print('Error adding product: $e');
      rethrow;
    }
  }

  Future<void> updateProduct({
    required String id,
    required String productName,
    required String productCode,
    required String unit,
    required double price,
    required double gstRate,
    required bool isActive,
    int? stock, // Add optional stock parameter for updates
  }) async {
    try {
      final Map<String, dynamic> updateData = {
        'ItemName': productName,
        'PartNumber': productCode,
        'ItemUnit': unit,
        'ItemRate': price,
        'GstRate': gstRate,
        'is_active': isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Only update stock if provided
      if (stock != null) {
        updateData['ItemQuantity'] = stock;
      }

      await _supabase.from('products').update(updateData).eq('id', id);
    } catch (e) {
      print('Error updating product: $e');
      rethrow;
    }
  }

  // NEW: Method to update stock separately (useful for inventory management)
  Future<void> updateProductStock(String productId, int newStock) async {
    try {
      await _supabase.from('products').update({
        'ItemQuantity': newStock,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', productId);
    } catch (e) {
      print('Error updating product stock: $e');
      rethrow;
    }
  }

  // NEW: Method to check if product has sufficient stock
  Future<bool> hasInStock(String productId, int requiredQuantity) async {
    try {
      final response = await _supabase
          .from('products')
          .select('ItemQuantity')
          .eq('id', productId)
          .single();

      final currentStock = response['ItemQuantity'] as int? ?? 0;
      return currentStock >= requiredQuantity;
    } catch (e) {
      print('❌ Error checking stock: $e');
      rethrow;
    }
  }

  // NEW: Method to get current stock level
  Future<double> getCurrentStock(String productId) async {
    try {
      final response = await _supabase
          .from('products')
          .select('ItemQuantity')
          .eq('id', productId)
          .single();

      final stock = response['ItemQuantity'];
      if (stock is num) {
        return stock.toDouble();
      } else {
        print('Warning: ItemQuantity is not a number: $stock');
        return 0.0;
      }
    } catch (e) {
      print('Error fetching current stock for product $productId: $e');
      return 0.0;
    }
  }

  /// Fetches the exact unit (ItemUnit) for a product from Supabase.
  /// Returns the raw DB value, or null if the product is not found.
  Future<String?> getProductUnit(String productId) async {
    try {
      final response = await _supabase
          .from('products')
          .select('ItemUnit')
          .eq('id', productId)
          .single();

      final unit = response['ItemUnit'];
      if (unit == null) return null;
      return unit.toString().trim();
    } catch (e) {
      print('Error fetching unit for product $productId: $e');
      return null;
    }
  }

  Future<bool> updateProductImage(
      String productId, String imageUrl, String imagePath) async {
    try {
      print('💾 Updating database...');
      print('🆔 Product ID: $productId');
      print('🔗 Image URL: $imageUrl');
      print('📂 Image Path: $imagePath');

      final response = await _supabase
          .from('products')
          .update({
            'image_url': imageUrl,
            'image_path': imagePath,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', productId)
          .select(); // Add select to see what was updated

      print('✅ Database update response: $response');
      return true;
    } catch (e) {
      print('❌ Database update error: $e');
      // Bubble up so UI can handle the failure explicitly
      rethrow;
    }
  }

  Future<bool> removeProductImage(String productId) async {
    try {
      await _supabase.from('products').update({
        'image_url': null,
        'image_path': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', productId);
      return true;
    } catch (e) {
      print('Error removing product image: $e');
      return false;
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _supabase.from('products').delete().eq('id', id);
    } catch (e) {
      print('Error deleting product: $e');
      rethrow;
    }
  }
}
