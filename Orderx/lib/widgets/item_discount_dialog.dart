import 'package:Orderx/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ItemDiscountDialog extends StatefulWidget {
  final String productName;
  final double currentDiscountPercentage;
  final double basePrice;
  final double quantity;

  const ItemDiscountDialog({
    super.key,
    required this.productName,
    required this.currentDiscountPercentage,
    required this.basePrice,
    required this.quantity,
  });

  @override
  State<ItemDiscountDialog> createState() => _ItemDiscountDialogState();
}

class _ItemDiscountDialogState extends State<ItemDiscountDialog> {
  late TextEditingController _percentageController;
  late TextEditingController _amountController;
  double _discountPercentage = 0.0;
  double _discountAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _discountPercentage = widget.currentDiscountPercentage;
    _percentageController = TextEditingController(
      text: _discountPercentage > 0 ? _discountPercentage.toStringAsFixed(2) : '',
    );
    _amountController = TextEditingController();
    _updateAmountFromPercentage();
  }

  @override
  void dispose() {
    _percentageController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _updateAmountFromPercentage() {
    final baseTotal = widget.basePrice * widget.quantity;
    _discountAmount = (baseTotal * _discountPercentage / 100);
    _amountController.text = _discountAmount > 0 ? _discountAmount.toStringAsFixed(2) : '';
  }

  void _updatePercentageFromAmount() {
    final baseTotal = widget.basePrice * widget.quantity;
    _discountPercentage = baseTotal > 0 ? (_discountAmount / baseTotal * 100) : 0.0;
    _percentageController.text = _discountPercentage > 0 ? _discountPercentage.toStringAsFixed(2) : '';
  }

  void _onDiscountPercentageChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _discountPercentage = 0.0;
        _discountAmount = 0.0;
        _amountController.text = '';
        return;
      }
      
      final parsed = double.tryParse(value) ?? 0.0;
      _discountPercentage = parsed.clamp(0.0, 100.0);
      _updateAmountFromPercentage();
    });
  }

  void _onDiscountAmountChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _discountAmount = 0.0;
        _discountPercentage = 0.0;
        _percentageController.text = '';
        return;
      }
      
      final parsed = double.tryParse(value) ?? 0.0;
      final baseTotal = widget.basePrice * widget.quantity;
      final maxDiscount = baseTotal;
      
      _discountAmount = parsed.clamp(0.0, maxDiscount);
      _updatePercentageFromAmount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTotal = widget.basePrice * widget.quantity;
    final discountedTotal = baseTotal - _discountAmount;

    return AlertDialog(
      title: Text('Item Discount - ${widget.productName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Base Price: ₹${widget.basePrice.toStringAsFixed(2)} × ${widget.quantity}',
              style: const TextStyle(fontSize: 14, color: AppTheme.grey),
            ),
            Text(
              'Total: ₹${baseTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Discount Percentage
            TextField(
              controller: _percentageController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Discount Percentage',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
              onChanged: _onDiscountPercentageChanged,
            ),
            const SizedBox(height: 12),
            
            // Discount Amount
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Discount Amount',
                prefixText: '₹',
                border: OutlineInputBorder(),
              ),
              onChanged: _onDiscountAmountChanged,
            ),
            const SizedBox(height: 16),
            
            // Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Discount:'),
                      Text(
                        '₹${_discountAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Final Total:'),
                      Text(
                        '₹${discountedTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            // Validation
            if (_discountPercentage > 100) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Discount percentage cannot exceed 100%')),
              );
              return;
            }

            if (_discountAmount > baseTotal) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Discount amount cannot exceed total price')),
              );
              return;
            }

            Navigator.pop(context, _discountPercentage);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
