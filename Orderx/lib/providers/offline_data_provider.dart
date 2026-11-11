import 'package:flutter/material.dart';

import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/services/offline_cache_service.dart';
import 'package:Orderx/services/product_service.dart';

class OfflineDataProvider with ChangeNotifier {
  final CustomerService _customerService = CustomerService();
  final ProductService _productService = ProductService();
  final OfflineCacheService _cacheService = OfflineCacheService();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  Future<void> logHealth() async {
    await _cacheService.logDatabaseHealth();
  }

  Future<void> syncAll(String companyId) async {
    if (companyId.isEmpty) return;
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    debugPrint('🔄 [SYNC]: Starting Full Sync for Company: $companyId');

    try {
      // Sync Customers
      try {
        debugPrint('👥 [SYNC]: Fetching customers...');
        final customers =
            await _customerService.getAllCustomers(companyId: companyId);
        debugPrint(
            '👥 [SYNC]: Received ${customers.length} customers from server.');

        await _cacheService.refreshCacheCustomers(customers,
            companyId: companyId);
        debugPrint('✅ [SYNC]: Customers refreshed successfully.');
      } catch (e) {
        debugPrint('❌ [SYNC]: Customer sync failed: $e');
      }

      // Sync Products
      try {
        debugPrint('📦 [SYNC]: Fetching products...');
        final products =
            await _productService.getProducts(companyId: companyId);
        debugPrint(
            '📦 [SYNC]: Received ${products.length} products from server.');

        await _cacheService.refreshCacheProducts(products,
            companyId: companyId);
        debugPrint('✅ [SYNC]: Products refreshed successfully.');
      } catch (e) {
        debugPrint('❌ [SYNC]: Product sync failed: $e');
      }

      final cCount = await _cacheService.cachedCustomerCount(companyId);
      final pCount = await _cacheService.cachedProductCount(companyId);
      debugPrint(
          '🏁 [SYNC FINISHED]: Cache Status: Customers=$cCount, Products=$pCount');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<List<CustomerModel>> fetchCustomers({
    required String? companyId,
    bool preferOnline = true,
  }) async {
    if (companyId == null) return [];
    
    // First, load from cache for instant display
    final cachedResults =
        await _cacheService.getCachedCustomers(companyId: companyId);
    debugPrint(
        '📦 OfflineDataProvider: Loaded ${cachedResults.length} customers from local cache.');
    
    // Then refresh from online in background if online and cache is not empty
    // or if preferOnline is true but with a shorter timeout
    if (preferOnline && cachedResults.isNotEmpty) {
      // Refresh cache in background without blocking UI
      _customerService
          .getAllCustomers(companyId: companyId)
          .timeout(const Duration(seconds: 10))
          .then((customers) async {
        await _cacheService.refreshCacheCustomers(customers,
            companyId: companyId);
        debugPrint(
            '✅ OfflineDataProvider: Background refresh completed with ${customers.length} customers.');
      }).catchError((e) {
        debugPrint(
            '📡 OfflineDataProvider: Background refresh failed/timed out: $e');
      });
    } else if (preferOnline) {
      // If cache is empty, try online fetch with short timeout
      try {
        debugPrint(
            '🌐 OfflineDataProvider: Cache empty, fetching customers online for $companyId...');
        final customers = await _customerService
            .getAllCustomers(companyId: companyId)
            .timeout(const Duration(seconds: 10));

        await _cacheService.refreshCacheCustomers(customers,
            companyId: companyId);
        debugPrint(
            '✅ OfflineDataProvider: Received ${customers.length} customers online.');
        return customers;
      } catch (e) {
        debugPrint(
            '📡 OfflineDataProvider: Online customer fetch failed/timed out: $e');
        debugPrint('📦 OfflineDataProvider: Using cached results.');
      }
    }
    
    return cachedResults;
  }

  Future<List<CustomerModel>> searchCustomers(
    String query, {
    required String? companyId,
    bool preferOnline = true,
  }) async {
    if (companyId == null) return [];
    if (preferOnline) {
      try {
        if (query.trim().isEmpty) {
          return fetchCustomers(companyId: companyId, preferOnline: true);
        }
        debugPrint(
            '🌐 OfflineDataProvider: Searching customers online for "$query"...');
        final results = await _customerService
            .searchCustomers(query, companyId: companyId)
            .timeout(const Duration(seconds: 15));

        if (results.isNotEmpty) {
          // Use UPSERT for searches so we don't wipe the rest of the cache
          await _cacheService.upsertCustomers(results, companyId: companyId);
        }
        debugPrint(
            '✅ OfflineDataProvider: Found ${results.length} customers online.');
        return results;
      } catch (e) {
        debugPrint(
            '📡 OfflineDataProvider: Online customer search failed/timed out: $e');
        debugPrint('📦 OfflineDataProvider: Falling back to local cache.');
      }
    }

    final cachedResults =
        await _cacheService.searchCachedCustomers(query, companyId: companyId);
    debugPrint(
        '📦 OfflineDataProvider: Found ${cachedResults.length} customers in local cache.');
    return cachedResults;
  }

  Future<List<ProductModel>> searchProducts(
    String query, {
    required String? companyId,
    bool preferOnline = true,
  }) async {
    if (companyId == null) return [];
    final trimmed = query.trim();

    // For empty queries, load a page of products instead of using search
    if (preferOnline && trimmed.isEmpty) {
      try {
        debugPrint(
            '🌐 OfflineDataProvider: Loading products online for empty search...');
        final results = await _productService
            .getAllProducts(companyId: companyId)
            .timeout(const Duration(seconds: 15));

        if (results.isNotEmpty) {
          await _cacheService.refreshCacheProducts(results, companyId: companyId);
        }
        debugPrint(
            '✅ OfflineDataProvider: Loaded ${results.length} products online for empty search.');
        return results;
      } catch (e) {
        debugPrint(
            '📡 OfflineDataProvider: Online product load (empty search) failed/timed out: $e');
        debugPrint('📦 OfflineDataProvider: Falling back to local cache.');
      }
    }

    if (preferOnline && trimmed.isNotEmpty) {
      try {
        debugPrint(
            '🌐 OfflineDataProvider: Searching products online for "$trimmed"...');
        final results = await _productService
            .searchProducts(trimmed, companyId: companyId)
            .timeout(const Duration(seconds: 5));

        if (results.isNotEmpty) {
          // Use UPSERT for searches so we don't wipe the rest of the cache
          await _cacheService.upsertProducts(results, companyId: companyId);
        }
        debugPrint(
            '✅ OfflineDataProvider: Found ${results.length} products online.');
        return results;
      } catch (e) {
        debugPrint(
            '📡 OfflineDataProvider: Online product search failed/timed out: $e');
        debugPrint('📦 OfflineDataProvider: Falling back to local cache.');
      }
    }

    // Fallback to cache (no-op on web, real on mobile/desktop)
    final cachedResults = await _cacheService.searchCachedProducts(trimmed,
        companyId: companyId);
    debugPrint(
        '📦 OfflineDataProvider: Found ${cachedResults.length} products in local cache.');
    return cachedResults;
  }

  Future<List<ProductModel>> getCachedProducts({
    required String? companyId,
  }) async {
    if (companyId == null) return [];
    return _cacheService.getCachedProducts(companyId: companyId);
  }

  Future<void> refreshProductCache({
    required String? companyId,
  }) async {
    if (companyId == null) return;
    try {
      debugPrint('🔄 OfflineDataProvider: Force refreshing product cache...');
      final results = await _productService
          .getProductsPaginated(companyId: companyId, page: 0, limit: 1000)
          .timeout(const Duration(seconds: 10));
      
      if (results.isNotEmpty) {
        await _cacheService.refreshCacheProducts(results, companyId: companyId);
      }
      debugPrint('✅ OfflineDataProvider: Product cache refreshed with ${results.length} products.');
    } catch (e) {
      debugPrint('❌ OfflineDataProvider: Failed to refresh product cache: $e');
    }
  }

  Future<void> addCustomerToCache(CustomerModel customer, {required String? companyId}) async {
    if (companyId == null) return;
    try {
      await _cacheService.upsertCustomers([customer], companyId: companyId);
    } catch (e) {
      debugPrint('⚠️ Could not upsert customer to cache: $e');
    }
  }
}
