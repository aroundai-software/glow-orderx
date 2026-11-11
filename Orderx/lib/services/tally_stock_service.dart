// lib/services/tally_stock_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class TallyStockService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Check live stock from Tally for a specific product
  /// 
  /// This calls the Supabase Edge Function which communicates with Tally XML API
  /// to fetch real-time stock information
  Future<TallyStockResponse> checkLiveStock({
    required String productCode,
    required String tallyServerUrl,
    required int tallyPort,
    required String companyName,
  }) async {
    try {
      print('🔍 Checking live stock from Tally for: $productCode');

      // Call Supabase Edge Function
      final response = await _client.functions.invoke(
        'check-tally-stock',
        body: {
          'productCode': productCode,
          'tallyServerUrl': tallyServerUrl,
          'tallyPort': tallyPort,
          'companyName': companyName,
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to fetch stock from Tally: ${response.status}');
      }

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        print('✅ Stock fetched successfully: ${data['currentStock']}');
        return TallyStockResponse.fromJson(data);
      } else {
        throw Exception(data['error'] ?? 'Unknown error from Tally');
      }
    } catch (e) {
      print('❌ Error checking Tally stock: $e');
      rethrow;
    }
  }

  /// Check stock for multiple products (batch request)
  /// 
  /// Useful when validating entire cart/order at once
  Future<List<TallyStockResponse>> checkMultipleStocks({
    required List<String> productCodes,
    required String tallyServerUrl,
    required int tallyPort,
    required String companyName,
  }) async {
    final List<TallyStockResponse> results = [];

    for (final code in productCodes) {
      try {
        final stock = await checkLiveStock(
          productCode: code,
          tallyServerUrl: tallyServerUrl,
          tallyPort: tallyPort,
          companyName: companyName,
        );
        results.add(stock);
      } catch (e) {
        print('Error fetching stock for $code: $e');
        // Add error response for this product
        results.add(TallyStockResponse(
          success: false,
          productCode: code,
          productName: '',
          currentStock: 0,
          unit: '',
          lastUpdated: DateTime.now(),
          error: e.toString(),
        ));
      }
    }

    return results;
  }

  /// Get Tally settings from database
  Future<TallySettings> getTallySettings() async {
    try {
      final response = await _client
          .from('company_settings')
          .select()
          .limit(1)
          .single();

      return TallySettings.fromJson(response);
    } catch (e) {
      print('Error fetching Tally settings: $e');
      // Return default settings if not configured
      return TallySettings(
        tallyServerUrl: 'localhost',
        tallyPort: 9000,
        tallyCompanyName: '',
        enableLiveStock: false,
        stockCheckThreshold: 10,
      );
    }
  }

  /// Check stock with automatic settings retrieval
  /// 
  /// Convenience method that fetches Tally settings automatically
  Future<TallyStockResponse> checkStockAuto(String productCode) async {
    final settings = await getTallySettings();
    
    if (!settings.enableLiveStock) {
      throw Exception('Live stock check is disabled in settings');
    }
    
    return await checkLiveStock(
      productCode: productCode,
      tallyServerUrl: settings.tallyServerUrl,
      tallyPort: settings.tallyPort,
      companyName: settings.tallyCompanyName,
    );
  }

  /// Check if stock verification is needed based on threshold
  /// 
  /// Returns true if current stock is below threshold and needs Tally verification
  Future<bool> shouldCheckTallyStock(String productId, int requiredQty) async {
    try {
      final settings = await getTallySettings();
      
      if (!settings.enableLiveStock) {
        return false; // Live stock check disabled
      }

      // Get current stock from Supabase
      final response = await _client
          .from('products')
          .select('ItemQuantity')
          .eq('id', productId)
          .single();

      final currentStock = response['ItemQuantity'] as int? ?? 0;

      // Check if stock is below threshold or insufficient for order
      return currentStock < settings.stockCheckThreshold || 
             currentStock < requiredQty;
    } catch (e) {
      print('Error checking if Tally verification needed: $e');
      return false;
    }
  }

  /// Validate order items against Tally stock
  /// 
  /// Returns list of items with insufficient stock
  Future<List<StockValidationResult>> validateOrderStock(
    List<OrderItemForValidation> items,
  ) async {
    try {
      final settings = await getTallySettings();
      
      if (!settings.enableLiveStock) {
        // If live stock check is disabled, return all as valid
        return items.map((item) => StockValidationResult(
          productCode: item.productCode,
          productName: item.productName,
          requiredQty: item.quantity,
          availableStock: item.quantity.toDouble(), // Assume available
          isValid: true,
        )).toList();
      }

      final productCodes = items
          .map((item) => item.productCode)
          .where((code) => code.isNotEmpty)
          .toList();

      // Fetch stock from Tally
      final stockResults = await checkMultipleStocks(
        productCodes: productCodes,
        tallyServerUrl: settings.tallyServerUrl,
        tallyPort: settings.tallyPort,
        companyName: settings.tallyCompanyName,
      );

      // Validate each item
      final validationResults = <StockValidationResult>[];

      for (final item in items) {
        final stockData = stockResults.firstWhere(
          (s) => s.productCode == item.productCode,
          orElse: () => TallyStockResponse(
            success: false,
            productCode: item.productCode,
            productName: item.productName,
            currentStock: 0,
            unit: '',
            lastUpdated: DateTime.now(),
            error: 'Product not found',
          ),
        );

        validationResults.add(StockValidationResult(
          productCode: item.productCode,
          productName: item.productName,
          requiredQty: item.quantity,
          availableStock: stockData.currentStock,
          isValid: stockData.success && stockData.currentStock >= item.quantity.toDouble(),
          error: stockData.error,
        ));
      }

      return validationResults;
    } catch (e) {
      print('Error validating order stock: $e');
      rethrow;
    }
  }
}

// ============================================================================
// MODELS
// ============================================================================

/// Response from Tally stock check
class TallyStockResponse {
  final bool success;
  final String productCode;
  final String productName;
  final double currentStock;
  final String unit;
  final DateTime lastUpdated;
  final String? error;

  TallyStockResponse({
    required this.success,
    required this.productCode,
    required this.productName,
    required this.currentStock,
    required this.unit,
    required this.lastUpdated,
    this.error,
  });

  factory TallyStockResponse.fromJson(Map<String, dynamic> json) {
    return TallyStockResponse(
      success: json['success'] ?? false,
      productCode: json['productCode'] ?? '',
      productName: json['productName'] ?? '',
      currentStock: (json['currentStock'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] ?? '',
      lastUpdated: json['lastUpdated'] != null 
          ? DateTime.parse(json['lastUpdated'])
          : DateTime.now(),
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'productCode': productCode,
      'productName': productName,
      'currentStock': currentStock,
      'unit': unit,
      'lastUpdated': lastUpdated.toIso8601String(),
      'error': error,
    };
  }
}

/// Tally configuration settings
class TallySettings {
  final String tallyServerUrl;
  final int tallyPort;
  final String tallyCompanyName;
  final bool enableLiveStock;
  final int stockCheckThreshold;

  TallySettings({
    required this.tallyServerUrl,
    required this.tallyPort,
    required this.tallyCompanyName,
    this.enableLiveStock = false,
    this.stockCheckThreshold = 10,
  });

  factory TallySettings.fromJson(Map<String, dynamic> json) {
    return TallySettings(
      tallyServerUrl: json['tally_server_url'] ?? 'localhost',
      tallyPort: json['tally_port'] ?? 9000,
      tallyCompanyName: json['tally_company_name'] ?? '',
      enableLiveStock: json['tally_enable_live_stock'] ?? false,
      stockCheckThreshold: json['tally_stock_check_threshold'] ?? 10,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tally_server_url': tallyServerUrl,
      'tally_port': tallyPort,
      'tally_company_name': tallyCompanyName,
      'tally_enable_live_stock': enableLiveStock,
      'tally_stock_check_threshold': stockCheckThreshold,
    };
  }
}

/// Order item for stock validation
class OrderItemForValidation {
  final String productCode;
  final String productName;
  final int quantity;

  OrderItemForValidation({
    required this.productCode,
    required this.productName,
    required this.quantity,
  });
}

/// Result of stock validation for an item
class StockValidationResult {
  final String productCode;
  final String productName;
  final int requiredQty;
  final double availableStock;
  final bool isValid;
  final String? error;

  StockValidationResult({
    required this.productCode,
    required this.productName,
    required this.requiredQty,
    required this.availableStock,
    required this.isValid,
    this.error,
  });

  String get message {
    if (isValid) {
      return '$productName: ✅ In Stock ($availableStock available)';
    } else {
      return '$productName: ❌ Required $requiredQty, Available $availableStock';
    }
  }
}
