import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/auth_service.dart';
import 'package:Orderx/services/salesman_company_access_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalesmanManagementTab extends StatefulWidget {
  const SalesmanManagementTab({super.key});

  @override
  State<SalesmanManagementTab> createState() => _SalesmanManagementTabState();
}

class _SalesmanManagementTabState extends State<SalesmanManagementTab> {
  final AuthService _authService = AuthService();
  final AdminSettingsService _settingsService = AdminSettingsService();
  final SalesmanCompanyAccessService _accessService = SalesmanCompanyAccessService();
  final _formKey = GlobalKey<FormState>();
  final _createFormKey = GlobalKey<FormState>();
  final _editNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();

  List<UserModel> _salesmen = [];
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isCreating = false;
  String? _companyEmail;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _editNameController.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      if (companyId == null) {
        if (mounted) {
          setState(() {
            _salesmen = [];
            _isLoading = false;
          });
        }
        return;
      }

      final settings = await _settingsService.getAdminSettings(companyId);
      _companyEmail = settings.contactEmail;

      // Load salesmen for selected company
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('user_type', 'salesman')
          .eq('company_id', companyId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _salesmen = (response as List)
              .map((json) => UserModel.fromJson(json))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _createSalesman() async {
    if (!_createFormKey.currentState!.validate()) return;
    setState(() => _isCreating = true);

    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      if (companyId == null) {
        if (mounted) {
          setState(() => _isCreating = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Company context missing. Re-enter access key.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      final newSalesman = await _authService.register(
        mobileNumber: _mobileController.text.trim(),
        name: _nameController.text.trim(),
        userType: 'salesman',
        password: _passwordController.text.trim(),
        companyId: companyId,
      );

      if (!mounted) return;

      if (newSalesman != null) {
        // Admin-created salesmen should be usable immediately.
        await Supabase.instance.client
            .from('users')
            .update({'is_active': true})
            .eq('id', newSalesman.id);

        setState(() {
          _salesmen.insert(
            0,
            UserModel(
              id: newSalesman.id,
              mobileNumber: newSalesman.mobileNumber,
              name: newSalesman.name,
              userType: newSalesman.userType,
              email: newSalesman.email,
              isActive: true,
              createdAt: newSalesman.createdAt,
            ),
          );
          _isCreating = false;
        });
        _nameController.clear();
        _mobileController.clear();
        _passwordController.clear();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Salesman account created successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        setState(() => _isCreating = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Salesman Account'),
        content: SingleChildScrollView(
          child: Form(
            key: _createFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Enter salesman name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter name';
                    }
                    if (value.trim().length < 3) {
                      return 'Name must be at least 3 characters';
                    }
                    return null;
                  },
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
                    hintText: 'Enter 10-digit mobile',
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
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter password (min 6 characters)',
                    prefixIcon: Icon(Icons.lock_outline),
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
                if (_companyEmail != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.success),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mail_outline,
                            color: AppTheme.success, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _companyEmail!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isCreating ? null : _createSalesman,
            child: _isCreating
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSalesmanName(UserModel salesman, String newName) async {
    setState(() => _isUpdating = true);

    try {
      await Supabase.instance.client
          .from('users')
          .update({'name': newName})
          .eq('id', salesman.id);

      if (mounted) {
        setState(() {
          final index = _salesmen.indexWhere((s) => s.id == salesman.id);
          if (index != -1) {
            _salesmen[index] = UserModel(
              id: salesman.id,
              mobileNumber: salesman.mobileNumber,
              name: newName,
              userType: salesman.userType,
              email: salesman.email,
              isActive: salesman.isActive,
              createdAt: salesman.createdAt,
            );
          }
          _isUpdating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Salesman name updated successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleSalesmanStatus(UserModel salesman) async {
    final newStatus = !salesman.isActive;
    final action = newStatus ? 'activate' : 'inactivate';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${action.replaceFirst(action[0], action[0].toUpperCase())} Salesman'),
        content: Text(
          'Are you sure you want to $action ${salesman.name}?\n\n'
          'They will ${newStatus ? 'be able to' : 'not be able to'} login after this action.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus ? AppTheme.success : AppTheme.error,
            ),
            child: Text(action.replaceFirst(action[0], action[0].toUpperCase())),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isUpdating = true);

    try {
      await Supabase.instance.client
          .from('users')
          .update({'is_active': newStatus})
          .eq('id', salesman.id);

      if (mounted) {
        setState(() {
          final index = _salesmen.indexWhere((s) => s.id == salesman.id);
          if (index != -1) {
            _salesmen[index] = UserModel(
              id: salesman.id,
              mobileNumber: salesman.mobileNumber,
              name: salesman.name,
              userType: salesman.userType,
              email: salesman.email,
              isActive: newStatus,
              createdAt: salesman.createdAt,
            );
          }
          _isUpdating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Salesman ${action}d successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showManageCompanyAccessDialog(UserModel salesman) async {
    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      if (companyId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Company context missing. Re-enter access key.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      final companiesWithStatus = await _accessService.getCompaniesWithAccessStatus(
        salesman.id,
        restrictedCompanyIds: [companyId],
      );
      
      if (!mounted) return;
      
      // Create a map to track selected companies
      final selectedCompanies = <String, bool>{};
      for (final company in companiesWithStatus) {
        selectedCompanies[company['id']] = company['has_access'] ?? false;
      }

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Manage Company Access - ${salesman.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select which companies this salesman can access:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ...companiesWithStatus.map((company) {
                    final companyId = company['id'] as String;
                    final companyName = company['company_name'] as String;
                    
                    return CheckboxListTile(
                      title: Text(companyName),
                      value: selectedCompanies[companyId] ?? false,
                      onChanged: (value) {
                        setState(() {
                          selectedCompanies[companyId] = value ?? false;
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    // Get current access
                    final currentAccess = await _accessService.getAccessibleCompanies(salesman.id);
                    final currentCompanyIds = (currentAccess as List)
                        .map((item) => item['company_id'] as String)
                        .toSet();

                    // Find companies to grant and revoke
                    final toGrant = selectedCompanies.entries
                        .where((e) => e.value && !currentCompanyIds.contains(e.key))
                        .map((e) => e.key)
                        .toList();

                    final toRevoke = selectedCompanies.entries
                        .where((e) => !e.value && currentCompanyIds.contains(e.key))
                        .map((e) => e.key)
                        .toList();

                    // Apply changes
                    if (toGrant.isNotEmpty) {
                      await _accessService.grantAccessToMultipleCompanies(salesman.id, toGrant);
                    }
                    if (toRevoke.isNotEmpty) {
                      await _accessService.revokeAccessFromMultipleCompanies(salesman.id, toRevoke);
                    }

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Company access updated successfully!'),
                          backgroundColor: AppTheme.success,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: ${e.toString()}'),
                          backgroundColor: AppTheme.error,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
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

  void _showEditDialog(UserModel salesman) {
    _editNameController.text = salesman.name;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Salesman'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _editNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Enter salesman name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter name';
                    }
                    if (value.trim().length < 3) {
                      return 'Name must be at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mobile Number',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        salesman.mobileNumber,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '(Cannot be changed)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
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
            onPressed: _isUpdating
                ? null
                : () {
              if (_formKey.currentState!.validate()) {
                _updateSalesmanName(salesman, _editNameController.text.trim());
                Navigator.pop(context);
              }
            },
            child: _isUpdating
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isUpdating || _isCreating ? null : _showCreateDialog,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add New Salesman'),
                  ),
                ),
              ),
              Expanded(
                child: _salesmen.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: AppTheme.grey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No salesmen found',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: AppTheme.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _salesmen.length,
                        itemBuilder: (context, index) {
                          final salesman = _salesmen[index];
                          return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.primaryBlue,
                          child: Text(
                            salesman.name[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                salesman.name,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                salesman.mobileNumber,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: salesman.isActive
                                ? AppTheme.success.withOpacity(0.1)
                                : AppTheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: salesman.isActive
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                          child: Text(
                            salesman.isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: salesman.isActive
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (salesman.email != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.mail_outline,
                            size: 16,
                            color: AppTheme.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              salesman.email!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: AppTheme.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMM dd, yyyy').format(salesman.createdAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Manage Company Access Button
                        SizedBox(
                          height: 32,
                          child: ElevatedButton.icon(
                            onPressed: _isUpdating ? null : () => _showManageCompanyAccessDialog(salesman),
                            icon: const Icon(Icons.business, size: 14),
                            label: const Text('Companies', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Edit Button
                        SizedBox(
                          height: 32,
                          child: OutlinedButton.icon(
                            onPressed: _isUpdating ? null : () => _showEditDialog(salesman),
                            icon: const Icon(Icons.edit, size: 14),
                            label: const Text('Edit', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Inactivate/Activate Button
                        SizedBox(
                          height: 32,
                          child: ElevatedButton.icon(
                            onPressed: _isUpdating ? null : () => _toggleSalesmanStatus(salesman),
                            icon: Icon(
                              salesman.isActive ? Icons.block : Icons.check_circle,
                              size: 14,
                            ),
                            label: Text(
                              salesman.isActive ? 'Inactivate' : 'Activate',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: salesman.isActive ? AppTheme.error : AppTheme.success,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
                          );
                        },
                      ),
              ),
            ],
          );
  }
}
