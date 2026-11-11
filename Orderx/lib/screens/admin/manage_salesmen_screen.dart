// lib/screens/admin/manage_salesmen_screen.dart
import 'package:flutter/material.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/salesman.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/salesman_service.dart';
import 'package:provider/provider.dart';

class ManageSalesmenScreen extends StatefulWidget {
  const ManageSalesmenScreen({super.key});

  @override
  State<ManageSalesmenScreen> createState() => _ManageSalesmenScreenState();
}

class _ManageSalesmenScreenState extends State<ManageSalesmenScreen> {
  late Future<List<Salesman>> _salesmenFuture;
  final SalesmanService _service = SalesmanService();
  bool _companyMissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshSalesmen());
  }

  Future<void> _refreshSalesmen() async {
    if (!mounted) return;
    final companyId = context.read<AuthProvider>().selectedCompanyId;
    if (companyId == null) {
      setState(() {
        _companyMissing = true;
        _salesmenFuture = Future.value([]);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No company selected. Please enter the access key.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() {
      _companyMissing = false;
      _salesmenFuture = _service.getSalesmen(companyId: companyId);
    });
  }

  Future<void> _showAddSalesmanDialog() async {
    await _showSalesmanFormDialog(
      title: 'Add New Salesman',
      onSave: (name, mobile) async {
        final companyId = context.read<AuthProvider>().selectedCompanyId;
        if (companyId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Company context missing. Re-enter access key.'),
              backgroundColor: AppTheme.error,
            ),
          );
          return;
        }

        try {
          await _service.addSalesman(
            name: name,
            mobileNumber: mobile,
            companyId: companyId,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Salesman added successfully!')),
            );
            _refreshSalesmen();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}')),
            );
          }
        }
      },
    );
  }

  Future<void> _showEditSalesmanDialog(Salesman salesman) async {
    await _showSalesmanFormDialog(
      title: 'Edit Salesman',
      initialName: salesman.name,
      initialMobile: salesman.mobileNumber,
      isEdit: true,
      onSave: (name, mobile) async {
        final companyId = context.read<AuthProvider>().selectedCompanyId;
        if (companyId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Company context missing. Re-enter access key.'),
              backgroundColor: AppTheme.error,
            ),
          );
          return;
        }

        try {
          await _service.updateSalesman(
            id: salesman.id,
            name: name,
            isActive: salesman.isActive,
            companyId: companyId,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Salesman updated successfully!')),
            );
            _refreshSalesmen();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}')),
            );
          }
        }
      },
    );
  }

  Future<void> _toggleSalesmanStatus(Salesman salesman) async {
    final companyId = context.read<AuthProvider>().selectedCompanyId;
    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Company context missing. Re-enter access key.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    try {
      await _service.updateSalesman(
        id: salesman.id,
        name: salesman.name,
        isActive: !salesman.isActive,
        companyId: companyId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              salesman.isActive
                  ? 'Salesman deactivated!'
                  : 'Salesman activated!',
            ),
          ),
        );
        _refreshSalesmen();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _showSalesmanFormDialog({
    required String title,
    String? initialName,
    String? initialMobile,
    bool isEdit = false,
    required Future<void> Function(String name, String mobile) onSave,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final mobileController = TextEditingController(text: initialMobile);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: !isEdit,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: mobileController,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number *',
                        hintText: '10-digit mobile number',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      enabled: !isEdit, // Can't edit mobile for existing users
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
                  onPressed: isSaving
                      ? null
                      : () async {
                    final name = nameController.text.trim();
                    final mobile = mobileController.text.trim();

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter name')),
                      );
                      return;
                    }

                    if (!isEdit) {
                      if (mobile.length != 10 ||
                          !RegExp(r'^[6-9]').hasMatch(mobile)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Enter valid 10-digit mobile')),
                        );
                        return;
                      }

                      // Check if mobile exists (only for new users)
                      final exists =
                      await _service.mobileNumberExists(mobile);
                      if (exists) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Mobile number already exists')),
                        );
                        return;
                      }
                    }

                    setState(() => isSaving = true);
                    try {
                      await onSave(name, mobile);
                      Navigator.pop(context);
                    } finally {
                      if (mounted) setState(() => isSaving = false);
                    }
                  },
                  child: isSaving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Salesmen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshSalesmen,
          ),
        ],
      ),
      body: _companyMissing
          ? Center(
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
                      Navigator.of(context)
                          .pushReplacementNamed('/enter-company-key');
                    },
                    child: const Text('Enter Company Key'),
                  ),
                ],
              ),
            )
          : FutureBuilder<List<Salesman>>(
        future: _salesmenFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No salesmen found'));
          }

          final salesmen = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: salesmen.length,
            itemBuilder: (context, index) {
              final salesman = salesmen[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    child: Icon(
                      salesman.isActive
                          ? Icons.person
                          : Icons.person_off,
                      color: salesman.isActive
                          ? AppTheme.primaryBlue
                          : Colors.grey,
                    ),
                  ),
                  title: Text(salesman.name),
                  subtitle: Text(
                    '${salesman.mobileNumber} • '
                        '${salesman.isActive ? "Active" : "Inactive"}',
                    style: TextStyle(
                      color: salesman.isActive
                          ? Colors.green
                          : Colors.redAccent,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditSalesmanDialog(salesman),
                      ),
                      Switch(
                        value: salesman.isActive,
                        onChanged: (_) =>
                            _toggleSalesmanStatus(salesman),
                        activeThumbColor: AppTheme.success,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSalesmanDialog,
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}