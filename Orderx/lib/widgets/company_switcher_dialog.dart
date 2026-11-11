import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/company_selection_service.dart';
import 'package:Orderx/core/theme/app_theme.dart';

class CompanySwitcherDialog extends StatefulWidget {
  const CompanySwitcherDialog({super.key});

  @override
  State<CompanySwitcherDialog> createState() => _CompanySwitcherDialogState();
}

class _CompanySwitcherDialogState extends State<CompanySwitcherDialog> {
  final CompanySelectionService _companyService = CompanySelectionService();
  List<Map<String, dynamic>> _companies = [];
  String? _selectedCompanyId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState(); 
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      _selectedCompanyId = companyId;

      if (companyId == null) {
        setState(() {
          _companies = [];
          _isLoading = false;
        });
        return;
      }

      final companies = await _companyService.getCompanyByIds([companyId]);
      setState(() {
        _companies = companies;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading companies: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _switchCompany() async {
    if (_selectedCompanyId == null) return;

    print('🔄 Switching to company: $_selectedCompanyId');
    final authProvider = context.read<AuthProvider>();
    await authProvider.setSelectedCompany(_selectedCompanyId!);
    print('✅ Company switch completed');

    if (mounted) {
      Navigator.of(context).pop(true); // Return true to indicate company was changed
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Switch Company'),
      content: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Company access is locked to your current key.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ..._companies.map((company) {
                  final companyId = company['id'] as String;
                  final companyName = company['company_name'] as String;
                  final isSelected = companyId == _selectedCompanyId;

                  return RadioListTile<String>(
                    title: Text(companyName),
                    value: companyId,
                    groupValue: _selectedCompanyId,
                    onChanged: (value) {
                      setState(() {
                        _selectedCompanyId = value;
                      });
                    },
                    activeColor: AppTheme.primaryBlue,
                    selected: isSelected,
                  );
                }),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _companies.isEmpty ? null : _switchCompany,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
          ),
          child: const Text('Switch'),
        ),
      ],
    );
  }
}
