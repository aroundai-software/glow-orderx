import 'package:supabase_flutter/supabase_flutter.dart';

class PromotionalDiscountService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Check and calculate promotional discounts for a product
  /// Returns a map with discount details
  Future<Map<String, dynamic>> getPromotionalDiscount({
    required String productId,
    required int requestedQuantity,
  }) async {
    try {
      print('🎁 [PromotionalDiscountService] Checking promotional discounts...');
      print('   Product ID: $productId');
      print('   Requested Quantity: $requestedQuantity');

      // Fetch product promotional details
      final productResponse = await _supabase
          .from('products')
          .select('''
            ComboStartDate,
            ComboEndDate,
            ComboQtyOffTake,
            SpecialStartDate,
            SpecialEndDate,
            SpecialDiscount
          ''')
          .eq('id', productId)
          .single();

      print('   Product Promo Data: $productResponse');

      final now = DateTime.now().toUtc();
      final today = DateTime(now.year, now.month, now.day); // Date only, no time
      double comboDiscount = 0.0;
      double specialDiscount = 0.0;
      int comboEligibleQty = 0;

      // Get the discount value from SpecialDiscount column
      final discountValue = (productResponse['SpecialDiscount'] as num?)?.toDouble() ?? 0.0;
      
      // Check Combo Discount (quantity-based with dates)
      final comboStartDate = productResponse['ComboStartDate'] != null
          ? DateTime.parse(productResponse['ComboStartDate'] as String)
          : null;
      final comboEndDate = productResponse['ComboEndDate'] != null
          ? DateTime.parse(productResponse['ComboEndDate'] as String)
          : null;
      final comboQtyOffTake = (productResponse['ComboQtyOffTake'] as num?)?.toDouble() ?? 0;

      // Normalize dates to date-only for comparison
      final comboStart = comboStartDate != null 
          ? DateTime(comboStartDate.year, comboStartDate.month, comboStartDate.day)
          : null;
      final comboEnd = comboEndDate != null
          ? DateTime(comboEndDate.year, comboEndDate.month, comboEndDate.day)
          : null;

      bool isInComboPeriod = false;
      if (comboStart != null &&
          comboEnd != null &&
          comboQtyOffTake > 0 &&
          !today.isBefore(comboStart) &&
          !today.isAfter(comboEnd)) {
        isInComboPeriod = true;
        print('   ✓ Combo period is active ($comboStart to $comboEnd)');
        print('   Today: $today');
        print('   Combo quantity per set: $comboQtyOffTake');
        print('   Customer requested quantity: $requestedQuantity');

        // Combo applies for every complete set of ComboQtyOffTake items
        final comboQty = comboQtyOffTake.toInt();
        final completeSets = requestedQuantity ~/ comboQty;
        comboEligibleQty = completeSets * comboQty;
        
        if (comboEligibleQty > 0) {
          comboDiscount = discountValue;
          print('   ✅ Complete sets: $completeSets');
          print('   ✅ Items eligible for combo discount: $comboEligibleQty');
          print('   ✅ Combo discount applied: $comboDiscount%');
        } else {
          print('   ❌ Not enough items for combo. Need at least $comboQty items, got $requestedQuantity');
        }
      } else {
        if (comboStart != null && comboEnd != null) {
          print('   ❌ Combo period not active ($comboStart to $comboEnd, today: $today)');
        }
      }

      // Check Special Discount (only if we're NOT in combo period)
      // Special discount uses the same SpecialDiscount value but applies to all items
      // If combo period is active, special discount should NOT apply even if quantity doesn't meet combo threshold
      if (!isInComboPeriod && discountValue > 0) {
        final specialStartDate = productResponse['SpecialStartDate'] != null
            ? DateTime.parse(productResponse['SpecialStartDate'] as String)
            : null;
        final specialEndDate = productResponse['SpecialEndDate'] != null
            ? DateTime.parse(productResponse['SpecialEndDate'] as String)
            : null;

        // If no special dates set, treat as always active
        if (specialStartDate == null || specialEndDate == null) {
          specialDiscount = discountValue;
          print('   ✓ Special discount (always active): $specialDiscount%');
        } else {
          // Dates are set - check if within period
          final specialStart = DateTime(specialStartDate.year, specialStartDate.month, specialStartDate.day);
          final specialEnd = DateTime(specialEndDate.year, specialEndDate.month, specialEndDate.day);
          
          if (!today.isBefore(specialStart) && !today.isAfter(specialEnd)) {
            specialDiscount = discountValue;
            print('   ✓ Special discount active ($specialStart to $specialEnd): $specialDiscount%');
            print('   Today: $today');
          } else {
            print('   ❌ Special period not active ($specialStart to $specialEnd, today: $today)');
          }
        }
      }

      // Return the highest applicable discount
      // If combo is active for some items, those get combo discount
      // Remaining items get special discount if active
      final result = {
        'has_combo': comboEligibleQty > 0,
        'combo_eligible_qty': comboEligibleQty,
        'combo_discount': comboDiscount,
        'has_special': specialDiscount > 0,
        'special_discount': specialDiscount,
        'max_discount': comboDiscount > specialDiscount ? comboDiscount : specialDiscount,
      };

      print('   📊 Result: $result');
      return result;
    } catch (e, stackTrace) {
      print('❌ Error fetching promotional discount: $e');
      print('   Stack trace: $stackTrace');
      return {
        'has_combo': false,
        'combo_eligible_qty': 0,
        'combo_discount': 0.0,
        'has_special': false,
        'special_discount': 0.0,
        'max_discount': 0.0,
      };
    }
  }
}
