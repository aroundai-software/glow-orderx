// lib/screens/admin/tally_config_screen.dart
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/tally_settings.dart';
import 'package:Orderx/services/tally_service.dart';
import 'package:flutter/material.dart';

class TallyConfigScreen extends StatefulWidget {
  const TallyConfigScreen({super.key});

  @override
  State<TallyConfigScreen> createState() => _TallyConfigScreenState();
}

class _TallyConfigScreenState extends State<TallyConfigScreen> {
  late Future<TallySettings> _settingsFuture;
  final TallyService _tallyService = TallyService();
  bool _isTestingConnection = false;
  bool? _connectionTestResult;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _companyNameController;
  late TextEditingController _serverUrlController;
  late TextEditingController _portController;
  late TextEditingController _tallyCompanyController;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _settingsFuture = _tallyService.getTallySettings();
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final currentSettings = await _settingsFuture;
      final updatedSettings = TallySettings(
        id: currentSettings.id,
        companyName: _companyNameController.text.trim(),
        tallyServerUrl: _serverUrlController.text.trim(),
        tallyPort: int.tryParse(_portController.text.trim()) ?? 9000,
        tallyCompanyName: _tallyCompanyController.text.trim(),
        isTallyConnected: currentSettings.isTallyConnected,
        createdAt: currentSettings.createdAt,
        updatedAt: DateTime.now(),
      );

      await _tallyService.updateTallySettings(updatedSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')),
        );
        _loadSettings(); // Refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: $e')),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isTestingConnection = true);
    _connectionTestResult = null;

    try {
      final port = int.tryParse(_portController.text.trim()) ?? 9000;
      final isConnected = await _tallyService.testTallyConnection(
        serverUrl: _serverUrlController.text.trim(),
        port: port,
        companyName: _tallyCompanyController.text.trim(),
      );

      if (mounted) {
        setState(() => _connectionTestResult = isConnected);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isConnected
                  ? '✅ Connection successful!'
                  : '❌ Connection failed. Please check settings.',
            ),
            backgroundColor: isConnected ? AppTheme.success : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connectionTestResult = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection test failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tally Integration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: FutureBuilder<TallySettings>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Failed to load settings'));
          }

          final settings = snapshot.data!;

          // Initialize controllers with current settings
          _companyNameController = TextEditingController(text: settings.companyName);
          _serverUrlController = TextEditingController(text: settings.tallyServerUrl);
          _portController = TextEditingController(text: settings.tallyPort.toString());
          _tallyCompanyController = TextEditingController(text: settings.tallyCompanyName ?? '');

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  // Company Info
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Company Information',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _companyNameController,
                            decoration: const InputDecoration(
                              labelText: 'Company Name *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Company name is required';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tally Connection Settings
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tally Connection Settings',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _serverUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Tally Server URL *',
                              hintText: 'http://localhost or IP address',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Server URL is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: 'Tally Port *',
                              hintText: 'Default: 9000',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Port is required';
                              }
                              final port = int.tryParse(value);
                              if (port == null || port <= 0 || port > 65535) {
                                return 'Enter a valid port number (1-65535)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _tallyCompanyController,
                            decoration: const InputDecoration(
                              labelText: 'Tally Company Name *',
                              hintText: 'Exact company name as in Tally',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Tally company name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isTestingConnection ? null : _testConnection,
                                  icon: _isTestingConnection
                                      ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : const Icon(Icons.sync),
                                  label: const Text('Test Connection'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_connectionTestResult != null)
                                Icon(
                                  _connectionTestResult!
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: _connectionTestResult!
                                      ? AppTheme.success
                                      : Colors.red,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Connection Status
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            settings.isTallyConnected
                                ? Icons.check_circle
                                : Icons.error,
                            color: settings.isTallyConnected
                                ? AppTheme.success
                                : Colors.red,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  settings.isTallyConnected
                                      ? 'Tally Connection: Active'
                                      : 'Tally Connection: Inactive',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: settings.isTallyConnected
                                        ? AppTheme.success
                                        : Colors.red,
                                  ),
                                ),
                                Text(
                                  settings.isTallyConnected
                                      ? 'Orders will be synced automatically'
                                      : 'Configure settings and test connection to enable sync',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}