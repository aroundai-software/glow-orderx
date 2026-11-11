import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/services/user_organization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class CompanyKeyScreen extends StatefulWidget {
  const CompanyKeyScreen({super.key});

  @override
  State<CompanyKeyScreen> createState() => _CompanyKeyScreenState();
}

class _CompanyKeyScreenState extends State<CompanyKeyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _keyController = TextEditingController();
  final _organizationService = UserOrganizationService();
  final _companyService = TallyCompanyService();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final enteredKey = _keyController.text.trim();
    try {
      final organization =
          await _organizationService.getOrganizationByKey(enteredKey);

      if (organization == null) {
        setState(() {
          _error = 'Invalid key. Please double-check with your admin.';
          _isLoading = false;
        });
        return;
      }

      final company = await _companyService.resolveCompany(organization.userId);
      if (company == null || !company.isActive) {
        setState(() {
          _error =
              'The company linked to this key is inactive. Contact support.';
          _isLoading = false;
        });
        return;
      }

      final authProvider = context.read<AuthProvider>();
      await authProvider.setSelectedCompany(company.id);
      await authProvider.cacheCompany(company);

      if (!mounted) return;

      Navigator.of(context).pushReplacementNamed('/mobile-login');
    } catch (e) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Orderx',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter Access Key',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.grey),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _keyController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(7),
                          ],
                          decoration: const InputDecoration(
                            labelText: '7-digit Company Key',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_isLoading) {
                              _handleSubmit();
                            }
                          },
                          validator: (value) {
                            final trimmed = (value ?? '').trim();
                            if (trimmed.isEmpty) {
                              return 'Please enter the key provided to you';
                            }
                            if (trimmed.length != 7) {
                              return 'Key must be 7 digits';
                            }
                            return null;
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.error),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleSubmit,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('CONTINUE'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your admin will provide a unique key that unlocks your company\'s login screen. Contact them if you need help.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.primaryBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
