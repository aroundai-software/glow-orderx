import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/connectivity_provider.dart';
import 'package:Orderx/providers/offline_data_provider.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/salesman_company_access_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/widgets/password_reset_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tallyCompanyService = TallyCompanyService();
  final _accessService = SalesmanCompanyAccessService();

  bool _isLoading = false;
  bool _loadingCompany = true;
  TallyCompanyModel? _selectedCompany;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSelectedCompany();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _syncOfflineData(String companyId) async {
    final offlineDataProvider = context.read<OfflineDataProvider>();
    final authProvider = context.read<AuthProvider>();
    try {
      await offlineDataProvider.syncAll(companyId);
      await authProvider.updateLastSyncTimestamp();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline data updated for offline use'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Offline data sync failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _loadSelectedCompany() async {
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;

    if (companyId == null) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/enter-company-key');
      }
      return;
    }

    try {
      setState(() => _loadingCompany = true);
      final company = await _tallyCompanyService.getCompanyById(companyId);
      if (!mounted) return;
      setState(() {
        _selectedCompany = company;
        _loadingCompany = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCompany = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load company. Please re-enter your key.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleRefresh() async {
    await _loadSelectedCompany();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;

    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No company selected. Please enter your access key.'),
          backgroundColor: AppTheme.error,
        ),
      );
      Navigator.of(context).pushReplacementNamed('/enter-company-key');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isOnline = context.read<ConnectivityProvider>().isOnline;
      if (!isOnline) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are offline. Please connect to the internet to login.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      final email = _emailController.text.trim();

      final userResponse = await Supabase.instance.client
          .from('users')
          .select('id, user_type, company_id')
          .eq('email', email)
          .maybeSingle();

      if (userResponse == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not found'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      final userId = userResponse['id'] as String;
      final userType = userResponse['user_type'] as String;
      final userCompanyId = userResponse['company_id'] as String?;

      if (userType == 'admin') {
        if (userCompanyId == null || userCompanyId != companyId) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'This admin belongs to a different company. Enter the correct key.'),
                backgroundColor: AppTheme.error,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      } else if (userType == 'salesman') {
        final hasAccess = await _accessService.canAccessCompany(userId, companyId);
        if (!hasAccess) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'You do not have access to this company. Please contact your admin.'),
                backgroundColor: AppTheme.error,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      } else {
        if (userCompanyId != null && userCompanyId != companyId) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account does not belong to this company.'),
                backgroundColor: AppTheme.error,
              ),
            );
          }
          return;
        }
      }

      final error = await authProvider.emailLogin(
        email,
        _passwordController.text.trim(),
        companyId: companyId,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (error != null) {
          if (error.contains('SESSION_CONFLICT')) {
            final message = error.replaceAll('SESSION_CONFLICT:', '');
            _showForceLoginDialog(email, message);
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: AppTheme.error,
            ),
          );
          return;
        }

        await authProvider.setSelectedCompany(companyId);
        print('✅ Login successful');
        await _syncOfflineData(companyId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showForceLoginDialog(String email, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
            SizedBox(width: 8),
            Text('Session Conflict'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            const Text(
              'Do you want to logout from the other device and login here?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleForceLogin(email);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Force Login'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleForceLogin(String email) async {
    setState(() => _isLoading = true);

    try {
      final isOnline = context.read<ConnectivityProvider>().isOnline;
      if (!isOnline) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connect to the internet to force login.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      if (companyId == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Company context missing. Please re-enter the access key.'),
            backgroundColor: AppTheme.error,
          ),
        );
        Navigator.of(context).pushReplacementNamed('/enter-company-key');
        return;
      }

      final error = await authProvider.emailLogin(
        email,
        _passwordController.text.trim(),
        companyId: companyId,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: AppTheme.error,
            ),
          );
          return;
        }

        print('✅ Force login successful');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Logged in successfully! Other sessions have been ended.'),
            backgroundColor: AppTheme.success,
          ),
        );
        await _syncOfflineData(companyId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showAdminRegistrationDialog() {
    showDialog(
      context: context,
      builder: (context) => AdminRegistrationDialog(company: _selectedCompany),
    );
  }

  void _showPasswordResetDialog() {
    showDialog(
      context: context,
      builder: (context) => const PasswordResetDialog(),
    );
  }

  Widget _buildCompanySection() {
    if (_loadingCompany) {
      return const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_selectedCompany != null) {
      final company = _selectedCompany!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.grey.withOpacity(0.08),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.business, color: AppTheme.primaryBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company.companyName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (company.companyAlias != null)
                        Text(
                          company.companyAlias!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (company.city != null)
                        Text(
                          'City: ${company.city}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      context.read<AuthProvider>().clearSelectedCompany();
                      Navigator.of(context)
                          .pushReplacementNamed('/enter-company-key');
                    },
              child: const Text('Change Company'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Company not available. Please re-enter your access key.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.error),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
                  context.read<AuthProvider>().clearSelectedCompany();
                  Navigator.of(context)
                      .pushReplacementNamed('/enter-company-key');
                },
          child: const Text('Enter a different key'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
        body: RefreshIndicator(
      onRefresh: _handleRefresh,
      child: Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isTablet ? 500 : double.infinity,
            ),
            child: Padding(
              padding: EdgeInsets.all(isTablet ? 48.0 : 32.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const CircleAvatar(
                        backgroundImage:
                            AssetImage('assets/icon/app_icon.png'),
                        backgroundColor: AppTheme.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Orderx',
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sales Order Management',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.grey),
                    ),
                    if (!isOnline) ...[
                      const SizedBox(height: 16),
                      _buildOfflineBanner(authProvider.lastCacheSyncAt),
                    ],
                    const SizedBox(height: 24),
                    _buildCompanySection(),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'Enter your email address',
                        prefixIcon:
                            Icon(Icons.email, color: AppTheme.primaryBlue),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter email';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline,
                            color: AppTheme.primaryBlue),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppTheme.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: (_isLoading || !isOnline) ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('LOGIN'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Reset Password Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _showPasswordResetDialog,
                        icon: const Icon(Icons.lock_reset, size: 18),
                        label: const Text('Reset Password'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryBlue,
                          side: const BorderSide(color: AppTheme.primaryBlue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.warning,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppTheme.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'New salesman accounts are created by admin only. Contact your admin for registration.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.warning,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                            child: Divider(
                                color: AppTheme.grey.withValues(alpha: 0.1))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.grey,
                                    ),
                          ),
                        ),
                        Expanded(
                            child: Divider(
                                color: AppTheme.grey.withValues(alpha: 0.1))),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: _showAdminRegistrationDialog,
                      child: RichText(
                        text: TextSpan(
                          text: 'New Admin? ',
                          style: Theme.of(context).textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: 'Register Here',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.primaryBlue,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildOfflineBanner(DateTime? lastSync) {
    final syncText = lastSync != null
        ? 'Last synced: ${lastSync.toLocal()}'
        : 'No offline data synced yet.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wifi_off, color: AppTheme.warning),
              SizedBox(width: 8),
              Text(
                'You are offline',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            syncText,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.darkGrey),
          ),
        ],
      ),
    );
  }
}

class AdminRegistrationDialog extends StatefulWidget {
  final TallyCompanyModel? company;

  const AdminRegistrationDialog({super.key, this.company});

  @override
  State<AdminRegistrationDialog> createState() =>
      _AdminRegistrationDialogState();
}

class _AdminRegistrationDialogState extends State<AdminRegistrationDialog> {
  final _adminFormKey = GlobalKey<FormState>();
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminMobileController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _adminSettingsService = AdminSettingsService();

  bool _isRegistering = false;
  bool _obscureAdminPassword = true;

  @override
  void dispose() {
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminMobileController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleAdminRegistration() async {
    if (!_adminFormKey.currentState!.validate()) return;

    setState(() => _isRegistering = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      if (companyId == null) {
        if (mounted) {
          setState(() => _isRegistering = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Company context missing. Please enter the access key again.'),
              backgroundColor: AppTheme.error,
            ),
          );
          Navigator.of(context).pushReplacementNamed('/enter-company-key');
        }
        return;
      }

      // Get company settings to validate email
      final settings = await _adminSettingsService.getAdminSettings();
      final companyEmail = settings.contactEmail;

      // Company email must be configured
      if (companyEmail == null || companyEmail.trim().isEmpty) {
        if (mounted) {
          setState(() => _isRegistering = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Company email not configured. Contact system administrator.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      // Verify email matches company email
      if (_adminEmailController.text.trim() != companyEmail.trim()) {
        if (mounted) {
          setState(() => _isRegistering = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Company email must match'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      final error = await authProvider.register(
        mobileNumber: _adminMobileController.text.trim(),
        name: _adminNameController.text.trim(),
        userType: 'admin',
        password: _adminPasswordController.text.trim(),
        companyId: companyId,
      );

      if (mounted) {
        setState(() => _isRegistering = false);

        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: AppTheme.error,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Admin account created successfully! You can now login.'),
              backgroundColor: AppTheme.success,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegistering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Admin Registration'),
      content: SingleChildScrollView(
        child: Form(
          key: _adminFormKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.company != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                  ),
                  child: Text(
                    widget.company!.companyName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'No company selected. Close this dialog and enter the access key again.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.error),
                  ),
                ),
              TextFormField(
                controller: _adminNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'Enter your full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your name';
                  }
                  if (value.trim().length < 3) {
                    return 'Name must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _adminMobileController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: 'Enter 10-digit mobile number',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter mobile number';
                  }
                  if (value.length != 10) {
                    return 'Mobile must be 10 digits';
                  }
                  if (!value.startsWith(RegExp(r'[6-9]'))) {
                    return 'Invalid mobile number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _adminEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Company Email *',
                  hintText: 'Enter company email',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Company email is required';
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Please enter valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _adminPasswordController,
                obscureText: _obscureAdminPassword,
                decoration: InputDecoration(
                  labelText: 'Password *',
                  hintText: 'Enter password (min 6 characters)',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureAdminPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppTheme.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureAdminPassword = !_obscureAdminPassword;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Password is required';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isRegistering ? null : _handleAdminRegistration,
          child: _isRegistering
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Register'),
        ),
      ],
    );
  }
}
