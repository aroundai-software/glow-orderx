import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to fetch category-based discounts
class CategoryDiscountService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get category discount info for a specific customer and product
  /// Returns a map with 'discount' (percentage) and 'categoryName' (string)
  Future<Map<String, dynamic>> getCategoryDiscountWithInfo({
    required String customerId,
    required String productId,
    String? companyId,
  }) async {
    try {
      print('📊 [CategoryDiscountService] Starting discount lookup...');
      print('   Customer ID: $customerId');
      print('   Product ID: $productId');
      
      // Step 1: Get customer's category ID and name via join
      final customerResponse = await _supabase
          .from('customers')
          .select('customer_category_id, customer_categories(category_name)')
          .eq('id', customerId)
          .maybeSingle();

      print('   Customer Response: $customerResponse');

      if (customerResponse == null || customerResponse['customer_category_id'] == null) {
        print('   ❌ Customer has no category assigned');
        return {'discount': 0.0, 'categoryName': null};
      }

      final String categoryId = (customerResponse['customer_category_id'] as String).trim();
      
      final categoryData = customerResponse['customer_categories'];
      final String? categoryName = (categoryData?['category_name'] as String?)?.trim();

      print('   ✓ Customer Category ID: "$categoryId"');
      if (categoryName != null) {
        print('   ✓ Customer Category Name: "$categoryName"');
      }

      // Step 2: Get product information including ALL possible parent fields
      Map<String, dynamic>? productResponse;
      try {
        // Try to get all possible fields that might contain parent/category info
        productResponse = await _supabase
            .from('products')
            .select('*')  // Get all fields to see what's available
            .eq('id', productId)
            .single();
        
        print('   Full Product Response: $productResponse');
      } catch (e) {
        print('   ❌ Error fetching product: $e');
        return {'discount': 0.0, 'categoryName': categoryName};
      }

      // Try to extract parent information from various possible fields
      final String? parentId = (productResponse['parent_id'] as String?)?.trim();
      final String? productItemParent = (productResponse['ItemParent'] as String?)?.trim();
      
      // Also check for other possible fields that might contain parent info
      // Based on your product table, you might have these fields
      final String? itemName = (productResponse['ItemName'] as String?)?.trim();
      
      // For debugging - let's see what fields we have
      print('   Product fields:');
      print('      parent_id: $parentId');
      print('      ItemParent: $productItemParent');
      print('      ItemName: $itemName');
      
      String? itemGroupName;

      if (parentId == null && productItemParent == null) {
        print('   ⚠️ Product has no item group (parent_id and ItemParent are null)');
        print('   💡 Still showing category "$categoryName" with 0% discount');
        // Don't return early - still show the category even if no discount applies
      }

      // Fetch item group name from item_parents table if we have parent_id
      if (parentId != null) {
        try {
          final parentLookup = await _supabase
              .from('item_parents')
              .select('ParentName, ItemGroupName')
              .eq('id', parentId)
              .maybeSingle();
          itemGroupName = (parentLookup?['ItemGroupName'] as String?)?.trim() ??
              (parentLookup?['ParentName'] as String?)?.trim();
        } catch (e) {
          print('     ⚠️ Could not fetch item group name: $e');
        }
      }

      // Use ItemParent from product if we don't have itemGroupName
      if (itemGroupName == null && productItemParent != null) {
        itemGroupName = productItemParent;
      }

      print('   ✓ Product Item Group ID: "$parentId"');
      if (itemGroupName != null) {
        print('   ✓ Product Item Group Name: "$itemGroupName"');
      }

      // Step 3: Query category_itemgroup_discounts table - MUST match BOTH category AND parent
      print('   🔎 Looking for discount where category_name="$categoryName" AND parent_name="$itemGroupName"');
      Map<String, dynamic>? discountResponse;
      
      // Primary attempt: Match by category_name and parent_name (the main columns in your schema)
      if (categoryName != null && itemGroupName != null) {
        print('   🔎 Checking discount for: $categoryName + $itemGroupName (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage')
              .eq('category_name', categoryName)
              .eq('parent_name', itemGroupName);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          discountResponse = await query.maybeSingle();
              
          if (discountResponse != null) {
            print('   ✅ Found discount match by category_name + parent_name');
          } else {
            print('   ❌ No discount found for this exact combination');
          }
        } catch (e) {
          print('     ⚠️ Query failed: $e');
        }
      }
      
      // TEMPORARY: If product has no parent, try to get ANY discount for this category
      if (discountResponse == null && categoryName != null && itemGroupName == null) {
        print('   🔧 WORKAROUND: Product has no parent, checking for ANY discount for "$categoryName" (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage, parent_name')
              .eq('category_name', categoryName);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          final anyDiscountList = await query;
              
          if (anyDiscountList.isNotEmpty) {
            discountResponse = anyDiscountList[0];
            print('   🔧 Found discount: ${discountResponse['category_discount_percentage']}% for parent: ${anyDiscountList[0]['parent_name']}');
            print('   ⚠️ FIX NEEDED: Set product ItemParent = "${anyDiscountList[0]['parent_name']}"');
          }
        } catch (e) {
          print('     ⚠️ Workaround failed: $e');
        }
      }

      
      // Fallback: Try with IDs if names didn't work and we have valid IDs
      if (discountResponse == null && categoryId.isNotEmpty && parentId != null) {
        print('   🔎 Trying fallback with IDs... (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage')
              .eq('customer_category_id', categoryId)
              .eq('item_group_id', parentId);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          discountResponse = await query.maybeSingle();
              
          if (discountResponse != null) {
            print('   ✅ Found discount match by customer_category_id + item_group_id');
          }
        } catch (e) {
          print('     ⚠️ ID-based query failed: $e');
        }
      }

      print('   Discount Response (final): $discountResponse');

      if (discountResponse == null) {
        print('   ❌ No discount rule found for this category + item group combination');
        print('   💡 Ensure the discount table has a row with either:');
        print('      - customer_category_name = "$categoryName" AND item_group_name = "$itemGroupName"');
        print('      - OR customer_category_id = "$categoryId" AND item_group_id = "$parentId"');
        return {'discount': 0.0, 'categoryName': categoryName};
      }

      final discount = (discountResponse['category_discount_percentage'] as num?)?.toDouble() ?? 0.0;
      print('   ✅ Discount Found: $discount%');
      
      return {'discount': discount, 'categoryName': categoryName};
    } catch (e, stackTrace) {
      print('❌ Error fetching category discount: $e');
      print('   Stack trace: $stackTrace');
      return {'discount': 0.0, 'categoryName': null};
    }
  }

  /// Get category discount for a specific customer and product
  /// Returns the discount percentage (0.0 if no discount found)
  Future<double> getCategoryDiscount({
    required String customerId,
    required String productId,
    String? companyId,
  }) async {
    try {
      print('📊 [CategoryDiscountService] Starting discount lookup...');
      print('   Customer ID: $customerId');
      print('   Product ID: $productId');
      
      // Step 1: Get customer's category ID and name via join
      final customerResponse = await _supabase
          .from('customers')
          .select('customer_category_id, customer_categories(category_name)')
          .eq('id', customerId)
          .maybeSingle();

      print('   Customer Response: $customerResponse');

      if (customerResponse == null || customerResponse['customer_category_id'] == null) {
        print('   ❌ Customer has no category assigned');
        return 0.0; // No category assigned to customer
      }

      final String categoryId = (customerResponse['customer_category_id'] as String).trim();
      
      final categoryData = customerResponse['customer_categories'];
      final String? categoryName = (categoryData?['category_name'] as String?)?.trim();

      print('   ✓ Customer Category ID: "$categoryId"');
      if (categoryName != null) {
        print('   ✓ Customer Category Name: "$categoryName"');
      }

      // Step 2: Get product's parent id (names optional)
      final productResponse = await _supabase
          .from('products')
          .select('parent_id')
          .eq('id', productId)
          .single();

      print('   Product Response: $productResponse');

      final String? parentId = (productResponse['parent_id'] as String?)?.trim();
      String? itemGroupName;

      if (parentId == null) {
        print('   ❌ Product has no item group (parent_id is null)');
        return 0.0; // Product has no item group
      }

      // Fetch item group name from item_parents table
      try {
        final parentLookup = await _supabase
            .from('item_parents')
            .select('ParentName, ItemGroupName')
            .eq('id', parentId)
            .maybeSingle();
        itemGroupName = (parentLookup?['ItemGroupName'] as String?)?.trim() ??
            (parentLookup?['ParentName'] as String?)?.trim();
      } catch (e) {
        print('     ⚠️ Could not fetch item group name: $e');
      }

      print('   ✓ Product Item Group ID: "$parentId"');
      if (itemGroupName != null) {
        print('   ✓ Product Item Group Name: "$itemGroupName"');
      }

      // Step 3: Query category_itemgroup_discounts table - MUST match BOTH category AND parent
      print('   🔎 Looking for discount where category_name="$categoryName" AND parent_name="$itemGroupName" (company: $companyId)');
      Map<String, dynamic>? discountResponse;
      
      // Primary attempt: Match by category_name and parent_name (the main columns in your schema)
      if (categoryName != null && itemGroupName != null) {
        print('   🔎 Checking discount for: $categoryName + $itemGroupName (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage')
              .eq('category_name', categoryName)
              .eq('parent_name', itemGroupName);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          discountResponse = await query.maybeSingle();
              
          if (discountResponse != null) {
            print('   ✅ Found discount match by category_name + parent_name');
          } else {
            print('   ❌ No discount found for this exact combination');
          }
        } catch (e) {
          print('     ⚠️ Query failed: $e');
        }
      }
      
      // TEMPORARY: If product has no parent, try to get ANY discount for this category
      if (discountResponse == null && categoryName != null && itemGroupName == null) {
        print('   🔧 WORKAROUND: Product has no parent, checking for ANY discount for "$categoryName" (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage, parent_name')
              .eq('category_name', categoryName);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          final anyDiscountList = await query;
              
          if (anyDiscountList.isNotEmpty) {
            discountResponse = anyDiscountList[0];
            print('   🔧 Found discount: ${discountResponse['category_discount_percentage']}% for parent: ${anyDiscountList[0]['parent_name']}');
            print('   ⚠️ FIX NEEDED: Set product ItemParent = "${anyDiscountList[0]['parent_name']}"');
          }
        } catch (e) {
          print('     ⚠️ Workaround failed: $e');
        }
      }

      
      // Fallback: Try with IDs if names didn't work and we have valid IDs
      // Note: parentId cannot be null here due to early return above
      if (discountResponse == null && categoryId.isNotEmpty) {
        print('   🔎 Trying fallback with IDs... (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage')
              .eq('customer_category_id', categoryId)
              .eq('item_group_id', parentId);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          discountResponse = await query.maybeSingle();
              
          if (discountResponse != null) {
            print('   ✅ Found discount match by customer_category_id + item_group_id');
          }
        } catch (e) {
          print('     ⚠️ ID-based query failed: $e');
        }
      }

      print('   Discount Response (final): $discountResponse');

      if (discountResponse == null) {
        print('   ❌ No discount rule found for this category + item group combination');
        print('   💡 Ensure the discount table has a row with either:');
        print('      - customer_category_name = "$categoryName" AND item_group_name = "$itemGroupName"');
        print('      - OR customer_category_id = "$categoryId" AND item_group_id = "$parentId"');
        return 0.0; // No discount configured for this combination
      }

      final discount = (discountResponse['category_discount_percentage'] as num?)?.toDouble() ?? 0.0;
      print('   ✅ Discount Found: $discount%');
      
      return discount;
    } catch (e, stackTrace) {
      print('❌ Error fetching category discount: $e');
      print('   Stack trace: $stackTrace');
      return 0.0;
    }
  }

  /// Get category discount for multiple products (batch)
  Future<Map<String, double>> getBatchCategoryDiscounts({
    required String customerId,
    required List<String> productIds,
    String? companyId,
  }) async {
    final Map<String, double> discounts = {};

    for (final productId in productIds) {
      discounts[productId] = await getCategoryDiscount(
        customerId: customerId,
        productId: productId,
        companyId: companyId,
      );
    }

    return discounts;
  }

  /// Get category discount for a specific category ID and product
  /// Returns a map with 'discount' (percentage) and 'categoryName' (string)
  /// This is used when salesman changes the category in product details
  Future<Map<String, dynamic>> getCategoryDiscountForCategoryAndProduct({
    required String categoryId,
    required String productId,
    String? companyId,
  }) async {
    try {
      print('📊 [CategoryDiscountService] Checking discount for category + product...');
      print('   Category ID: $categoryId');
      print('   Product ID: $productId');
      
      // Step 1: Get category name
      final categoryResponse = await _supabase
          .from('customer_categories')
          .select('category_name')
          .eq('id', categoryId)
          .maybeSingle();

      if (categoryResponse == null) {
        print('   ❌ Category not found');
        return {'discount': 0.0, 'categoryName': null};
      }

      final String? categoryName = (categoryResponse['category_name'] as String?)?.trim();
      print('   ✓ Category Name: "$categoryName"');

      // Step 2: Get product's parent id and ItemParent
      Map<String, dynamic>? productResponse;
      String? parentId;
      String? productItemParent;
      
      try {
        productResponse = await _supabase
            .from('products')
            .select('parent_id, ItemParent')
            .eq('id', productId)
            .single();
            
        parentId = (productResponse['parent_id'] as String?)?.trim();
        productItemParent = (productResponse['ItemParent'] as String?)?.trim();
      } catch (e) {
        print('   ⚠️ Error fetching product with parent fields: $e');
        // Try just getting the product ID to confirm it exists
        try {
          productResponse = await _supabase
              .from('products')
              .select('id')
              .eq('id', productId)
              .single();
          print('   ⚠️ Product exists but has no parent fields accessible');
        } catch (e2) {
          print('   ❌ Product not found: $e2');
          return {'discount': 0.0, 'categoryName': categoryName};
        }
      }

      if (parentId == null && productItemParent == null) {
        print('   ⚠️ Product has no item group (parent_id and ItemParent are null)');
        print('   💡 Returning 0% discount for category "$categoryName"');
        return {'discount': 0.0, 'categoryName': categoryName};
      }

      print('   ✓ Product Item Group ID: "$parentId"');

      // Step 3: Get item group name
      String? itemGroupName;
      if (parentId != null) {
        try {
          final parentLookup = await _supabase
              .from('item_parents')
              .select('ParentName, ItemGroupName')
              .eq('id', parentId)
              .maybeSingle();
          itemGroupName = (parentLookup?['ItemGroupName'] as String?)?.trim() ??
              (parentLookup?['ParentName'] as String?)?.trim();
        } catch (e) {
          print('     ⚠️ Could not fetch item group name: $e');
        }
      }
      
      // Use ItemParent from product if we don't have itemGroupName
      if (itemGroupName == null && productItemParent != null) {
        itemGroupName = productItemParent;
      }

      if (itemGroupName != null) {
        print('   ✓ Product Item Group Name: "$itemGroupName"');
      }

      // Step 4: Query category_itemgroup_discounts table - MUST match BOTH category AND parent
      print('   🔎 Looking for discount where category_name="$categoryName" AND parent_name="$itemGroupName" (company: $companyId)');
      Map<String, dynamic>? discountResponse;

      // Primary attempt: Match by category_name and parent_name (the main columns in your schema)
      if (categoryName != null && itemGroupName != null) {
        print('   🔎 Checking discount for: $categoryName + $itemGroupName (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage')
              .eq('category_name', categoryName)
              .eq('parent_name', itemGroupName);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          discountResponse = await query.maybeSingle();
              
          if (discountResponse != null) {
            print('   ✅ Found discount match by category_name + parent_name');
          } else {
            print('   ❌ No discount found for this exact combination');
          }
        } catch (e) {
          print('     ⚠️ Query failed: $e');
        }
      }
      
      // TEMPORARY: If product has no parent, try to get ANY discount for this category
      if (discountResponse == null && categoryName != null && itemGroupName == null) {
        print('   🔧 WORKAROUND: Product has no parent, checking for ANY discount for "$categoryName" (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage, parent_name')
              .eq('category_name', categoryName);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          final anyDiscountList = await query;
              
          if (anyDiscountList.isNotEmpty) {
            discountResponse = anyDiscountList[0];
            print('   🔧 Found discount: ${discountResponse['category_discount_percentage']}% for parent: ${anyDiscountList[0]['parent_name']}');
            print('   ⚠️ FIX NEEDED: Set product ItemParent = "${anyDiscountList[0]['parent_name']}"');
          }
        } catch (e) {
          print('     ⚠️ Workaround failed: $e');
        }
      }
      
      // Fallback: Try with IDs if names didn't work and we have valid IDs
      if (discountResponse == null && parentId != null) {
        print('   🔎 Trying fallback with IDs... (company: $companyId)');
        try {
          var query = _supabase
              .from('category_itemgroup_discounts')
              .select('category_discount_percentage')
              .eq('customer_category_id', categoryId)
              .eq('item_group_id', parentId);
          
          // Filter by company_id if provided
          if (companyId != null) {
            query = query.eq('company_id', companyId);
          }
          
          discountResponse = await query.maybeSingle();
              
          if (discountResponse != null) {
            print('   ✅ Found discount match by customer_category_id + item_group_id');
          }
        } catch (e) {
          print('     ⚠️ ID-based query failed: $e');
        }
      }

      if (discountResponse == null) {
        print('   ❌ No discount found for this category + item group combination');
        print('   💡 Showing 0% - Salesman can add manual discount if needed');
        return {'discount': 0.0, 'categoryName': categoryName};
      }

      final discount = (discountResponse['category_discount_percentage'] as num?)?.toDouble() ?? 0.0;
      print('   ✅ Discount Found: $discount% for category "$categoryName"');
      
      return {'discount': discount, 'categoryName': categoryName};
    } catch (e, stackTrace) {
      print('❌ Error fetching category discount: $e');
      print('   Stack trace: $stackTrace');
      return {'discount': 0.0, 'categoryName': null};
    }
  }
}
