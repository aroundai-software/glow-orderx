import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/providers/auth_provider.dart';

class LocationTrackingSettingsScreen extends StatefulWidget {
  const LocationTrackingSettingsScreen({super.key});

  @override
  State<LocationTrackingSettingsScreen> createState() =>
      _LocationTrackingSettingsScreenState();
}

class _LocationTrackingSettingsScreenState
    extends State<LocationTrackingSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTrackingEnabled = true;
  int _intervalSeconds = 300; // default 5 minutes
  String? _settingsId;
  String? _companyId;
  String? _companyName;
  String? _error;
  bool _applyToAllCompanies = false;
  String _trailAccuracyMode = 'standard';
  double _mapMatchMaxMeters = 500.0;
  double _maxSegmentMeters = 50000.0;

  final TextEditingController _intervalMinutesController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _intervalMinutesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final companyId = auth.selectedCompanyId;
      if (companyId == null) {
        setState(() {
          _isLoading = false;
          _error = 'Please select a company in the Admin Dashboard first.';
        });
        return;
      }

      _companyId = companyId;

      final client = Supabase.instance.client;

      // Load company name for display
      try {
        final companyRow = await client
            .from('tally_companies')
            .select('company_name')
            .eq('id', companyId)
            .maybeSingle();
        _companyName =
            companyRow != null ? (companyRow['company_name'] as String?) : null;
      } catch (_) {
        _companyName = null;
      }

      // Load or infer location tracking settings
      final settingsRow = await client
          .from('location_tracking_settings')
          .select()
          .eq('company_id', companyId)
          .maybeSingle();

      if (settingsRow != null) {
        _settingsId = settingsRow['id'] as String?;
        _isTrackingEnabled =
            (settingsRow['is_tracking_enabled'] as bool?) ?? true;
        final rawInterval = settingsRow['tracking_interval_seconds'];
        int interval = 300;
        if (rawInterval is int) {
          interval = rawInterval;
        } else if (rawInterval is num) {
          interval = rawInterval.toInt();
        }
        _intervalSeconds = interval;
        final modeValue = settingsRow['trail_accuracy_mode'];
        const validModes = ['standard', 'high_accuracy', 'custom'];
        if (modeValue is String &&
            modeValue.isNotEmpty &&
            validModes.contains(modeValue)) {
          _trailAccuracyMode = modeValue;
        } else {
          _trailAccuracyMode = 'standard';
        }
        final rawMapMatch = settingsRow['trail_map_match_max_m'];
        if (rawMapMatch is num) {
          _mapMatchMaxMeters = rawMapMatch.toDouble();
        } else {
          _mapMatchMaxMeters =
              _trailAccuracyMode == 'high_accuracy' ? 1000.0 : 500.0;
        }
        final rawMaxSegment = settingsRow['trail_max_segment_m'];
        if (rawMaxSegment is num) {
          _maxSegmentMeters = rawMaxSegment.toDouble();
        } else {
          _maxSegmentMeters =
              _trailAccuracyMode == 'high_accuracy' ? 100000.0 : 50000.0;
        }
      } else {
        _settingsId = null;
        _isTrackingEnabled = true;
        _intervalSeconds = 300;
        _trailAccuracyMode = 'standard';
        _mapMatchMaxMeters = 500.0;
        _maxSegmentMeters = 50000.0;
      }

      final minutes = (_intervalSeconds / 60).clamp(1, 1440).round();
      _intervalMinutesController.text = minutes.toString();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_applyToAllCompanies && _companyId == null) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      int minutes = int.tryParse(_intervalMinutesController.text.trim()) ?? 0;
      if (minutes < 1) minutes = 1;
      if (minutes > 1440) minutes = 1440; // cap at 24 hours
      _intervalSeconds = minutes * 60;

      final client = Supabase.instance.client;

      if (_applyToAllCompanies) {
        // Apply settings to all active companies
        final companies = await client
            .from('tally_companies')
            .select('id, is_active')
            .eq('is_active', true);

        int updatedCount = 0;

        for (final row in companies as List) {
          final dynamic idValue = row['id'];
          if (idValue == null) continue;
          final companyId = idValue.toString();

          final existing = await client
              .from('location_tracking_settings')
              .select('id')
              .eq('company_id', companyId)
              .maybeSingle();

          if (existing != null && existing['id'] != null) {
            final existingId = existing['id'].toString();
            await client.from('location_tracking_settings').update({
              'is_tracking_enabled': _isTrackingEnabled,
              'tracking_interval_seconds': _intervalSeconds,
              'trail_accuracy_mode': _trailAccuracyMode,
              'trail_map_match_max_m': _mapMatchMaxMeters,
              'trail_max_segment_m': _maxSegmentMeters,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', existingId);
          } else {
            await client.from('location_tracking_settings').insert({
              'company_id': companyId,
              'is_tracking_enabled': _isTrackingEnabled,
              'tracking_interval_seconds': _intervalSeconds,
              'trail_accuracy_mode': _trailAccuracyMode,
              'trail_map_match_max_m': _mapMatchMaxMeters,
              'trail_max_segment_m': _maxSegmentMeters,
            });
          }

          updatedCount++;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Location tracking settings applied to $updatedCount companies',
              ),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } else {
        // Save settings only for the currently selected company
        if (_companyId == null) {
          throw Exception('No company selected');
        }

        if (_settingsId == null) {
          final insertResponse = await client
              .from('location_tracking_settings')
              .insert({
                'company_id': _companyId,
                'is_tracking_enabled': _isTrackingEnabled,
                'tracking_interval_seconds': _intervalSeconds,
                'trail_accuracy_mode': _trailAccuracyMode,
                'trail_map_match_max_m': _mapMatchMaxMeters,
                'trail_max_segment_m': _maxSegmentMeters,
              })
              .select('id')
              .single();

          _settingsId = insertResponse['id'] as String?;
        } else {
          final id = _settingsId;
          if (id != null) {
            await client.from('location_tracking_settings').update({
              'is_tracking_enabled': _isTrackingEnabled,
              'tracking_interval_seconds': _intervalSeconds,
              'trail_accuracy_mode': _trailAccuracyMode,
              'trail_map_match_max_m': _mapMatchMaxMeters,
              'trail_max_segment_m': _maxSegmentMeters,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', id);
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location tracking settings saved'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Tracking Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading || _isSaving ? null : _saveSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppTheme.error),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSettings,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSettings,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_companyName != null)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.business),
                            title: Text(_companyName!),
                            subtitle: const Text('Selected company'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tracking Behaviour',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Control whether salesman locations are tracked for this company and how frequently updates are sent.',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                              SwitchListTile(
                                title: const Text('Enable tracking'),
                                subtitle: const Text(
                                    'Turn off to completely disable background tracking for this company'),
                                value: _isTrackingEnabled,
                                activeThumbColor: AppTheme.primaryBlue,
                                onChanged: (value) {
                                  setState(() {
                                    _isTrackingEnabled = value;
                                  });
                                },
                              ),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Apply to all companies'),
                                subtitle: const Text(
                                  'When enabled, these settings will be saved for all active companies.',
                                  style: TextStyle(fontSize: 12),
                                ),
                                value: _applyToAllCompanies,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _applyToAllCompanies = value;
                                  });
                                },
                              ),
                              const Divider(height: 24),
                              TextField(
                                controller: _intervalMinutesController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Tracking interval (minutes)',
                                  helperText:
                                      'Minimum time between updates while stationary. Movement over ~10 meters can still trigger earlier updates.',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Current effective interval: ${(_intervalSeconds / 60).round()} minute(s)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue: _trailAccuracyMode,
                                decoration: const InputDecoration(
                                  labelText: 'Trail accuracy mode',
                                  helperText:
                                      'Standard is balanced. High accuracy is more lenient and keeps more points for testing.',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem<String>(
                                    value: 'standard',
                                    child: Text('Standard (recommended)'),
                                  ),
                                  DropdownMenuItem<String>(
                                    value: 'high_accuracy',
                                    child: Text('High accuracy / debug'),
                                  ),
                                  DropdownMenuItem<String>(
                                    value: 'custom',
                                    child: Text('Custom (use sliders)'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _trailAccuracyMode = value;
                                    if (value == 'standard') {
                                      _mapMatchMaxMeters = 500.0;
                                      _maxSegmentMeters = 50000.0;
                                    } else if (value == 'high_accuracy') {
                                      _mapMatchMaxMeters = 1000.0;
                                      _maxSegmentMeters = 100000.0;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Map-matching reassociation distance: '
                                '${_mapMatchMaxMeters.round()} m',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Slider(
                                min: 10,
                                max: 2000,
                                divisions: 199,
                                value: _mapMatchMaxMeters.clamp(10.0, 2000.0),
                                label: '${_mapMatchMaxMeters.round()} m',
                                onChanged: (value) {
                                  setState(() {
                                    _mapMatchMaxMeters = value;
                                    _trailAccuracyMode = 'custom';
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Max segment distance in path length: '
                                '${(_maxSegmentMeters / 1000).toStringAsFixed(1)} km',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Slider(
                                min: 1000,
                                max: 100000,
                                divisions: 99,
                                value:
                                    _maxSegmentMeters.clamp(1000.0, 100000.0),
                                label:
                                    '${(_maxSegmentMeters / 1000).toStringAsFixed(1)} km',
                                onChanged: (value) {
                                  setState(() {
                                    _maxSegmentMeters = value;
                                    _trailAccuracyMode = 'custom';
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
