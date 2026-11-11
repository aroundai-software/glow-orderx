import 'package:Orderx/core/database/database_helper.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class OfflineCacheService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<void> refreshCacheCustomers(
    List<CustomerModel> customers, {
    required String companyId,
  }) async {
    if (kIsWeb) {
      debugPrint(
          '📦 [CACHE]: refreshCacheCustomers skipped on web (no local DB).');
      return;
    }
    final safeId = companyId.trim();
    if (customers.isEmpty) {
      debugPrint(
          '⚠️ [CACHE]: Skipping refreshCacheCustomers for empty list (Company: $safeId) to prevent accidental wipe.');
      return;
    }
    print(
        '📦 Cache: Refreshing ${customers.length} customers for company $safeId');
    final db = await _dbHelper.database;
    final batch = db.batch();

    batch.delete(
      'customers_cache',
      where: 'company_id = ?',
      whereArgs: [safeId],
    );

    for (final customer in customers) {
      batch.insert(
        'customers_cache',
        {
          'id': customer.id,
          'company_id': safeId,
          'customer_name': customer.customerName,
          'mobile_number': customer.mobileNumber,
          'address': customer.address,
          'city': customer.city,
          'state': customer.state,
          'pincode': customer.pincode,
          'gst_number': customer.gstNumber,
          'customer_category_id': customer.customerCategoryId,
          'created_at': customer.createdAt.toIso8601String(),
          'updated_at': customer.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    try {
      await batch.commit(noResult: true);
      print('✅ Cache: Successfully cached ${customers.length} customers');
    } catch (e) {
      print('❌ Cache: Customer batch commit FAILED: $e');
    }
  }

  Future<void> refreshCacheProducts(
    List<ProductModel> products, {
    required String companyId,
  }) async {
    if (kIsWeb) {
      debugPrint(
          '📦 [CACHE]: refreshCacheProducts skipped on web (no local DB).');
      return;
    }
    final safeId = companyId.trim();
    if (products.isEmpty) {
      debugPrint(
          '⚠️ [CACHE]: Skipping refreshCacheProducts for empty list (Company: $safeId) to prevent accidental wipe.');
      return;
    }
    print(
        '📦 Cache: Refreshing ${products.length} products for company $safeId');
    final db = await _dbHelper.database;
    final batch = db.batch();

    batch.delete(
      'products_cache',
      where: 'company_id = ?',
      whereArgs: [safeId],
    );

    for (final product in products) {
      batch.insert(
        'products_cache',
        {
          'id': product.id,
          'company_id': safeId,
          'ItemName': product.productName,
          'PartNumber': product.productCode,
          'ItemAlias1': product.vtNumber,
          'ItemUnit': product.unit,
          'ItemRate': product.price,
          'GstRate': product.gstRate,
          'ItemQuantity': product.stock,
          'is_active': product.isActive ? 1 : 0,
          'discount_percentage': product.discountPercentage,
          'mrp': product.mrp,
          'image_url': product.imageUrl,
          'image_path': product.imagePath,
          'updated_at': product.updatedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    try {
      await batch.commit(noResult: true);
      print('✅ Cache: Successfully cached ${products.length} products');
    } catch (e) {
      print('❌ Cache: Product batch commit FAILED: $e');
    }
  }

  Future<void> upsertCustomers(
    List<CustomerModel> customers, {
    required String companyId,
  }) async {
    if (kIsWeb) {
      debugPrint(
          '📦 [CACHE]: upsertCustomers skipped on web (no local DB).');
      return;
    }
    final safeId = companyId.trim();
    if (customers.isEmpty) return;
    print(
        '📦 Cache: Upserting ${customers.length} customers for company $safeId');
    final db = await _dbHelper.database;
    final batch = db.batch();

    for (final customer in customers) {
      batch.insert(
        'customers_cache',
        {
          'id': customer.id,
          'company_id': safeId,
          'customer_name': customer.customerName,
          'mobile_number': customer.mobileNumber,
          'address': customer.address,
          'city': customer.city,
          'state': customer.state,
          'pincode': customer.pincode,
          'gst_number': customer.gstNumber,
          'customer_category_id': customer.customerCategoryId,
          'created_at': customer.createdAt.toIso8601String(),
          'updated_at': customer.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    try {
      await batch.commit(noResult: true);
    } catch (e) {
      print('❌ Cache: Customer upsert FAILED: $e');
    }
  }

  Future<void> upsertProducts(
    List<ProductModel> products, {
    required String companyId,
  }) async {
    if (kIsWeb) {
      debugPrint(
          '📦 [CACHE]: upsertProducts skipped on web (no local DB).');
      return;
    }
    final safeId = companyId.trim();
    if (products.isEmpty) return;
    print(
        '📦 Cache: Upserting ${products.length} products for company $safeId');
    final db = await _dbHelper.database;
    final batch = db.batch();

    for (final product in products) {
      batch.insert(
        'products_cache',
        {
          'id': product.id,
          'company_id': safeId,
          'ItemName': product.productName,
          'PartNumber': product.productCode,
          'ItemAlias1': product.vtNumber,
          'ItemUnit': product.unit,
          'ItemRate': product.price,
          'GstRate': product.gstRate,
          'ItemQuantity': product.stock,
          'is_active': product.isActive ? 1 : 0,
          'discount_percentage': product.discountPercentage,
          'mrp': product.mrp,
          'image_url': product.imageUrl,
          'image_path': product.imagePath,
          'updated_at': product.updatedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    try {
      await batch.commit(noResult: true);
    } catch (e) {
      print('❌ Cache: Product upsert FAILED: $e');
    }
  }

  Future<List<CustomerModel>> getCachedCustomers(
      {required String companyId}) async {
    if (kIsWeb) {
      debugPrint(
          '📦 [CACHE]: getCachedCustomers called on web - returning empty list.');
      return [];
    }
    final safeId = companyId.trim();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'customers_cache',
      where: 'company_id = ?',
      whereArgs: [safeId],
      orderBy: 'customer_name COLLATE NOCASE ASC',
    );

    return rows
        .map(
          (row) => CustomerModel(
            id: row['id'] as String,
            customerName: row['customer_name'] as String,
            mobileNumber: row['mobile_number'] as String?,
            address: row['address'] as String?,
            city: row['city'] as String?,
            state: row['state'] as String?,
            pincode: row['pincode'] as String?,
            gstNumber: row['gst_number'] as String?,
            createdBy: null,
            customerCategoryId: row['customer_category_id'] as String?,
            createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
                DateTime.now(),
          ),
        )
        .toList();
  }

  Future<List<ProductModel>> getCachedProducts(
      {required String companyId}) async {
    if (kIsWeb) {
      debugPrint(
          '📦 [CACHE]: getCachedProducts called on web - returning empty list.');
      return [];
    }
    final db = await _dbHelper.database;
    final safeId = companyId.trim();
    final rows = await db.query(
      'products_cache',
      where: 'company_id = ?',
      whereArgs: [safeId],
      orderBy: 'ItemName COLLATE NOCASE ASC',
    );

    return rows
        .map((row) {
          try {
            return ProductModel.fromJson(row);
          } catch (e) {
            print('❌ Cache: Error mapping product row: $e');
            return null;
          }
        })
        .whereType<ProductModel>()
        .toList();
  }

  Future<List<CustomerModel>> searchCachedCustomers(
    String query, {
    required String companyId,
  }) async {
    if (kIsWeb) {
      debugPrint(
          '📦 [CACHE]: searchCachedCustomers called on web - returning empty list.');
      return [];
    }
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return getCachedCustomers(companyId: companyId);
    final customers = await getCachedCustomers(companyId: companyId);
    return customers
        .where(
          (customer) =>
              customer.customerName.toLowerCase().contains(normalized) ||
              (customer.mobileNumber?.toLowerCase().contains(normalized) ??
                  false) ||
              (customer.city?.toLowerCase().contains(normalized) ?? false) ||
              (customer.address?.toLowerCase().contains(normalized) ?? false),
        )
        .toList();
  }

  Future<List<ProductModel>> searchCachedProducts(
    String query, {
    required String companyId,
  }) async {
    if (kIsWeb) {
      debugPrint(
          '📦 [CACHE]: searchCachedProducts called on web - returning empty list.');
      return [];
    }
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return getCachedProducts(companyId: companyId);
    final products = await getCachedProducts(companyId: companyId);
    return products
        .where(
          (product) =>
              product.productName.toLowerCase().contains(normalized) ||
              (product.productCode?.toLowerCase().contains(normalized) ??
                  false) ||
              (product.vtNumber?.toLowerCase().contains(normalized) ?? false),
        )
        .toList();
  }

  Future<int> cachedCustomerCount(String companyId) async {
    if (kIsWeb) {
      return 0;
    }
    final db = await _dbHelper.database;
    final result = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM customers_cache WHERE company_id = ?',
          [companyId],
        )) ??
        0;
    return result;
  }

  Future<int> cachedProductCount(String companyId) async {
    if (kIsWeb) {
      return 0;
    }
    final db = await _dbHelper.database;
    final result = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM products_cache WHERE company_id = ?',
          [companyId.trim()],
        )) ??
        0;
    return result;
  }

  Future<void> logDatabaseHealth() async {
    if (kIsWeb) {
      debugPrint('🏥 [DB HEALTH]: Skipped on web (no local DB).');
      return;
    }
    try {
      final db = await _dbHelper.database;
      final cCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM customers_cache')) ??
          0;
      final pCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM products_cache')) ??
          0;
      final cCompanies =
          await db.rawQuery('SELECT DISTINCT company_id FROM customers_cache');
      final pCompanies =
          await db.rawQuery('SELECT DISTINCT company_id FROM products_cache');

      debugPrint('🏥 [DB HEALTH]: Total Cached Customers: $cCount');
      debugPrint('🏥 [DB HEALTH]: Total Cached Products: $pCount');
      debugPrint(
          '🏥 [DB HEALTH]: Customer Company IDs in DB: ${cCompanies.map((e) => e['company_id']).toList()}');
      debugPrint(
          '🏥 [DB HEALTH]: Product Company IDs in DB: ${pCompanies.map((e) => e['company_id']).toList()}');
      debugPrint('🏥 [DB HEALTH]: DB Path: ${db.path}');
    } catch (e) {
      debugPrint('❌ [DB HEALTH] Error: $e');
    }
  }
}
