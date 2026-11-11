import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/connectivity_provider.dart';
import 'package:Orderx/providers/offline_data_provider.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MobileLoginScreen extends StatefulWidget {
  const MobileLoginScreen({super.key});

  @override
  State<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends State<MobileLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _companyService = TallyCompanyService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _loadingCompany = true;
  TallyCompanyModel? _company;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Safety check: if we are already authenticated, go to dashboard
      final authProvider = context.read<AuthProvider>();
      if (authProvider.isAuthenticated) {
        debugPrint(
            '🏠 MobileLoginScreen: Already authenticated, redirecting to dashboard...');
        Navigator.of(context).pushReplacementNamed('/');
        return;
      }

      _bootstrapCompany();
    });
  }

  @override
  void dispose() {
    _mobileController.dispose();
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

  Future<void> _bootstrapCompany() async {
    final authProvider = context.read<AuthProvider>();

    // Recovery: Try to get company from current user if selectedCompanyId is missing
    String? selectedCompanyId = authProvider.selectedCompanyId;
    if (selectedCompanyId == null &&
        authProvider.currentUser?.companyId != null) {
      selectedCompanyId = authProvider.currentUser!.companyId;
      debugPrint(
          '♻️ MobileLoginScreen: Recovered companyId from user profile: $selectedCompanyId');
    }

    if (selectedCompanyId == null) {
      debugPrint(
          '🚪 MobileLoginScreen: No company ID found, returning to key screen');
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/enter-company-key');
      }
      return;
    }

    final cachedCompany =
        await authProvider.getCachedCompany(selectedCompanyId);
    final isOnline = context.read<ConnectivityProvider>().isOnline;

    if (!isOnline && cachedCompany != null) {
      debugPrint('📡 MobileLoginScreen: Loading company from cache (offline)');
      if (!mounted) return;
      setState(() {
        _company = cachedCompany;
        _loadingCompany = false;
      });
      return;
    }

    try {
      debugPrint('🌐 MobileLoginScreen: Fetching company data online...');
      final fetchedCompany =
          await _companyService.getCompanyById(selectedCompanyId);

      if (!mounted) return;

      if (fetchedCompany != null) {
        debugPrint('✅ MobileLoginScreen: Company data fetched successfully');
        setState(() {
          _company = fetchedCompany;
          _loadingCompany = false;
        });
        await authProvider.cacheCompany(fetchedCompany);
      } else if (cachedCompany != null) {
        debugPrint(
            '⚠️ MobileLoginScreen: Online fetch returned null, using cache');
        setState(() {
          _company = cachedCompany;
          _loadingCompany = false;
        });
      } else {
        throw Exception('Company details not found');
      }
    } catch (e) {
      debugPrint('❌ MobileLoginScreen: Error loading company: $e');
      if (!mounted) return;

      if (cachedCompany != null) {
        debugPrint(
            '📦 MobileLoginScreen: Falling back to cached company after error');
        setState(() {
          _company = cachedCompany;
          _loadingCompany = false;
        });
      } else {
        setState(() {
          _loadingCompany = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load company details. Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;

    if (companyId == null || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No company selected. Please enter your access key.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isOnline = context.read<ConnectivityProvider>().isOnline;
      if (!isOnline) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'You are offline. Please connect to the internet to login.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      final mobile = _mobileController.text.trim();
      final userRecord = await Supabase.instance.client
          .from('users')
          .select('id, user_type, company_id')
          .eq('mobile_number', mobile)
          .maybeSingle();

      if (userRecord == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not found. Contact your administrator.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      final userCompanyId = userRecord['company_id'] as String?;
      if (userCompanyId == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'This account is not linked to a company. Contact your administrator.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      final userCompany = await _companyService.resolveCompany(userCompanyId);
      final keyCompany = await _companyService.resolveCompany(companyId);
      if (userCompany == null ||
          keyCompany == null ||
          userCompany.id != keyCompany.id) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'This account belongs to a different company. Enter the correct access key.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      final error = await authProvider.login(
        mobile,
        _passwordController.text.trim(),
        companyId: userCompany.id,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (error != null) {
        if (error.contains('SESSION_CONFLICT')) {
          final message = error.replaceAll('SESSION_CONFLICT:', '');
          _showForceLoginDialog(message);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppTheme.error),
        );
        return;
      }

      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);

      // Sync in background - don't await so dashboard shows immediately
      _syncOfflineData(companyId).catchError((e) {
        debugPrint('Post-login background sync error: $e');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _showForceLoginDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Conflict'),
        content: Text(
          '$message\n\nDo you want to logout the other device and login here?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleForceLogin();
            },
            child: const Text('Force Login'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleForceLogin() async {
    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;
    if (companyId == null || companyId.isEmpty) return;
    setState(() => _isLoading = true);
    final error = await authProvider.login(
      _mobileController.text.trim(),
      _passwordController.text.trim(),
      companyId: companyId,
      forceLogin: true,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.error),
      );
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCompany = _company;
    final authProvider = context.watch<AuthProvider>();
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company Login'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading
              ? null
              : () {
                  context.read<AuthProvider>().clearSelectedCompany();
                  Navigator.of(context)
                      .pushReplacementNamed('/enter-company-key');
                },
        ),
        actions: [
          TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    context.read<AuthProvider>().clearSelectedCompany();
                    Navigator.of(context)
                        .pushReplacementNamed('/enter-company-key');
                  },
            child: const Text('Change Company'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
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
                      'Mobile Login',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.grey,
                          ),
                    ),
                    if (!isOnline) ...[
                      const SizedBox(height: 16),
                      _buildOfflineBanner(authProvider.lastCacheSyncAt),
                    ],
                    const SizedBox(height: 24),
                    if (_loadingCompany)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (selectedCompany != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppTheme.grey.withOpacity(0.08),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.business,
                                color: AppTheme.primaryBlue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedCompany.companyName,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  if (selectedCompany.companyAlias != null)
                                    Text(
                                      selectedCompany.companyAlias!,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'City: ${selectedCompany.city ?? 'N/A'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppTheme.error),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'This company is unavailable. Please re-enter your access key.',
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
                                    context
                                        .read<AuthProvider>()
                                        .clearSelectedCompany();
                                    Navigator.of(context).pushReplacementNamed(
                                        '/enter-company-key');
                                  },
                            child: const Text('Enter a different key'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _mobileController,
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
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final cleaned = (value ?? '').trim();
                        if (cleaned.isEmpty) {
                          return 'Please enter mobile number';
                        }
                        if (cleaned.length != 10) {
                          return 'Mobile must be 10 digits';
                        }
                        if (!RegExp(r'^[6-9]').hasMatch(cleaned)) {
                          return 'Invalid mobile number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_isLoading && isOnline) {
                          _handleLogin();
                        }
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            (_isLoading || !isOnline) ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('LOGIN'),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 18,
                            color: AppTheme.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Salesman accounts are created by admin only. Contact your admin for access.',
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(color: AppTheme.grey.withOpacity(0.3)),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('OR'),
                        ),
                        Expanded(
                          child: Divider(color: AppTheme.grey.withOpacity(0.3)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pushNamed('/register'),
                      child: RichText(
                        text: TextSpan(
                          text: 'New admin? ',
                          style: Theme.of(context).textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: 'Create Admin Account',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.primaryBlue,
                                    fontWeight: FontWeight.w700,
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
    );
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
