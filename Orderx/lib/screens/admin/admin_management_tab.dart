import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminManagementTab extends StatefulWidget {
  const AdminManagementTab({super.key});

  @override
  State<AdminManagementTab> createState() => _AdminManagementTabState();
}

class _AdminManagementTabState extends State<AdminManagementTab> {
  List<UserModel> _admins = [];
  bool _isLoading = true;
  bool _companyMissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _companyMissing = false;
    });
    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      if (companyId == null) {
        if (mounted) {
          setState(() {
            _admins = [];
            _isLoading = false;
            _companyMissing = true;
          });
        }
        return;
      }

      // Load admins for current company
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('user_type', 'admin')
          .eq('company_id', companyId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _admins = (response as List)
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

  @override
  Widget build(BuildContext context) {
    if (_companyMissing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 12),
            const Text('Select a company with your 7-digit key'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                context.read<AuthProvider>().clearSelectedCompany();
                Navigator.of(context).pushReplacementNamed('/enter-company-key');
              },
              child: const Text('Enter Company Key'),
            ),
          ],
        ),
      );
    }

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _admins.isEmpty
        ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 64,
                color: AppTheme.grey.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No admins found',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.grey,
                ),
              ),
            ],
          ),
        )
        : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _admins.length,
          itemBuilder: (context, index) {
            final admin = _admins[index];
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
                          backgroundColor: AppTheme.darkBlue,
                          child: Text(
                            admin.name[0].toUpperCase(),
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
                                admin.name,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                admin.mobileNumber,
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
                            color: admin.isActive
                                ? AppTheme.success.withOpacity(0.1)
                                : AppTheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: admin.isActive
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                          child: Text(
                            admin.isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: admin.isActive
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (admin.email != null)
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
                              admin.email!,
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
                          DateFormat('MMM dd, yyyy').format(admin.createdAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }
}
