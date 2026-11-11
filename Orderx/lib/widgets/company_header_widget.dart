import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/models/tally_company_model.dart';

class CompanyHeaderWidget extends StatefulWidget {
  final bool showSwitcher;
  final VoidCallback? onCompanyChanged;

  const CompanyHeaderWidget({
    super.key,
    this.showSwitcher = false,
    this.onCompanyChanged,
  });

  @override
  State<CompanyHeaderWidget> createState() => _CompanyHeaderWidgetState();
}

class _CompanyHeaderWidgetState extends State<CompanyHeaderWidget> {
  final _tallyService = TallyCompanyService();
  String? _selectedCompanyName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCompanyName();
  }

  Future<void> _loadCompanyName() async {
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;

    if (companyId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Try loading from cache first for immediate display
    final cached = await authProvider.getCachedCompany(companyId);
    if (mounted && cached != null) { 
      setState(() {
        _selectedCompanyName = cached.companyName;
      });
    }

    try {
      final company = await _tallyService.getCompanyById(companyId);
      if (mounted && company != null) {
        setState(() {
          _selectedCompanyName = company.companyName;
          _isLoading = false;
        });
        // Cache it for future offline use
        await authProvider.cacheCompany(company);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading company name online: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showCompanySwitcher() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentCompanyId = authProvider.selectedCompanyId;

      if (currentCompanyId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No company selected. Enter company key again.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      final company = await _tallyService.getCompanyById(currentCompanyId);
      final List<TallyCompanyModel> companies =
          company != null ? [company] : [];

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Switch Company'),
          content: companies.isEmpty
              ? const Text('Company access is locked to your current key.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: companies.map((company) {
                    final companyId = company.id;
                    final companyName = company.companyName;
                    final isSelected = companyId == currentCompanyId;

                    return ListTile(
                      leading: isSelected
                          ? const Icon(Icons.check_circle,
                              color: AppTheme.success)
                          : const Icon(Icons.circle_outlined,
                              color: AppTheme.grey),
                      title: Text(companyName),
                      onTap: () {
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.1),
            border: Border(
              bottom: BorderSide(
                color: AppTheme.primaryBlue.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.business,
                color: AppTheme.primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _isLoading
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Selected Company',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.grey,
                                      fontSize: 11,
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedCompanyName ?? 'No company selected',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryBlue,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
              if (widget.showSwitcher)
                IconButton(
                  icon:
                      const Icon(Icons.swap_horiz, color: AppTheme.primaryBlue),
                  onPressed: _showCompanySwitcher,
                  tooltip: 'Switch Company',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        );
      },
    );
  }
}
