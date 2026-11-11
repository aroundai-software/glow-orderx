// lib/widgets/stock_validation_dialog.dart
import 'package:flutter/material.dart';
import 'package:Orderx/services/tally_stock_service.dart';

/// Dialog to display stock validation results
class StockValidationDialog extends StatelessWidget {
  final List<StockValidationResult> validationResults;
  final VoidCallback? onProceedAnyway;
  final bool allowProceed;

  const StockValidationDialog({
    super.key,
    required this.validationResults,
    this.onProceedAnyway,
    this.allowProceed = false,
  });

  @override
  Widget build(BuildContext context) {
    final invalidItems = validationResults.where((r) => !r.isValid).toList();
    final validItems = validationResults.where((r) => r.isValid).toList();

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            invalidItems.isEmpty ? Icons.check_circle : Icons.warning,
            color: invalidItems.isEmpty ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              invalidItems.isEmpty 
                  ? 'Stock Verified' 
                  : 'Insufficient Stock',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (invalidItems.isNotEmpty) ...[
              Text(
                'The following items have insufficient stock in Tally:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                ),
              ),
              const SizedBox(height: 12),
              ...invalidItems.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Required: ${item.requiredQty} | Available: ${item.availableStock.toInt()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                          if (item.error != null)
                            Text(
                              'Error: ${item.error}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red[400],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
              if (validItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
              ],
            ],
            if (validItems.isNotEmpty) ...[
              Text(
                'Items in stock:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
              const SizedBox(height: 8),
              ...validItems.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.productName} (${item.availableStock.toInt()} available)',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
      actions: [
        if (invalidItems.isNotEmpty && allowProceed && onProceedAnyway != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onProceedAnyway!();
            },
            child: const Text(
              'Proceed Anyway',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(invalidItems.isEmpty ? 'OK' : 'Cancel'),
        ),
        if (invalidItems.isEmpty)
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
      ],
    );
  }
}

/// Loading dialog for stock validation
class StockValidationLoadingDialog extends StatelessWidget {
  final int itemCount;

  const StockValidationLoadingDialog({
    super.key,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            'Checking stock from Tally...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Validating $itemCount item${itemCount > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// Mixin to add stock validation functionality to any screen
mixin StockValidationMixin<T extends StatefulWidget> on State<T> {
  final TallyStockService _tallyStockService = TallyStockService();

  /// Validate stock for order items
  /// 
  /// Returns true if all items have sufficient stock or user chooses to proceed anyway
  Future<bool> validateStockForOrder(
    List<OrderItemForValidation> items, {
    bool allowProceedAnyway = false,
  }) async {
    if (items.isEmpty) return true;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StockValidationLoadingDialog(itemCount: items.length),
    );

    try {
      // Validate stock
      final results = await _tallyStockService.validateOrderStock(items);

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Check if all items are valid
      final allValid = results.every((r) => r.isValid);

      if (allValid) {
        // Show success briefly
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('✅ All items in stock'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return true;
      }

      // Show validation dialog with results
      if (mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => StockValidationDialog(
            validationResults: results,
            allowProceed: allowProceedAnyway,
            onProceedAnyway: allowProceedAnyway ? () {} : null,
          ),
        );

        return proceed ?? false;
      }

      return false;
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Show error dialog
      if (mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Stock Check Failed'),
              ],
            ),
            content: Text(
              'Unable to verify stock from Tally.\n\n'
              'Error: ${e.toString()}\n\n'
              'Do you want to proceed without stock verification?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              if (allowProceedAnyway)
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: const Text('Proceed Anyway'),
                ),
            ],
          ),
        );

        return proceed ?? false;
      }

      return false;
    }
  }

  /// Show a simple stock check for a single product
  Future<void> showProductStock(String productCode, String productName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Checking stock for $productName...'),
          ],
        ),
      ),
    );

    try {
      final stock = await _tallyStockService.checkStockAuto(productCode);

      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Stock Information'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stock.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('Product Code: ${stock.productCode}'),
                const SizedBox(height: 4),
                Text(
                  'Current Stock: ${stock.currentStock.toInt()} ${stock.unit}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: stock.currentStock > 0 ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last Updated: ${_formatDateTime(stock.lastUpdated)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking stock: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
