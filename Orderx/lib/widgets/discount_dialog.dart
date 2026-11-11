import 'package:Orderx/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


class DiscountDialog extends StatefulWidget {
  final double currentPercentage;
  final double currentAmount;
  final bool isPercentage;
  final double maxAmount; // subtotal for validation

  const DiscountDialog({
    super.key,
    required this.currentPercentage,
    required this.currentAmount,
    required this.isPercentage,
    required this.maxAmount,
  });

  @override
  State<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<DiscountDialog> {
  late bool _isPercentage;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _isPercentage = widget.isPercentage;
    _controller = TextEditingController(
      text: _isPercentage
          ? widget.currentPercentage.toStringAsFixed(2)
          : widget.currentAmount.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Order Discount'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle between % and fixed amount
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Percentage')),
              ButtonSegment(value: false, label: Text('Fixed Amount')),
            ],
            selected: {_isPercentage},
            onSelectionChanged: (Set<bool> selected) {
              setState(() {
                _isPercentage = selected.first;
                _controller.clear();
              });
            },
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: _isPercentage ? 'Discount %' : 'Discount Amount',
              prefixText: _isPercentage ? '' : '₹',
              suffixText: _isPercentage ? '%' : '',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Max subtotal: ₹${widget.maxAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final value = double.tryParse(_controller.text) ?? 0.0;

            // Validation
            if (_isPercentage && value > 100) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Percentage cannot exceed 100%')),
              );
              return;
            }

            if (!_isPercentage && value > widget.maxAmount) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Discount cannot exceed subtotal')),
              );
              return;
            }

            Navigator.pop(context, {
              'isPercentage': _isPercentage,
              'value': value,
            });
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}