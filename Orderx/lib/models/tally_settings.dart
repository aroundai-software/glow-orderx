// lib/models/tally_settings.dart
class TallySettings {
  final String id;
  final String companyName;
  final String tallyServerUrl;
  final int tallyPort;
  final String? tallyCompanyName;
  final bool isTallyConnected;
  final DateTime createdAt;
  final DateTime updatedAt;

  TallySettings({
    required this.id,
    required this.companyName,
    required this.tallyServerUrl,
    required this.tallyPort,
    required this.tallyCompanyName,
    required this.isTallyConnected,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TallySettings.fromJson(Map<String, dynamic> json) {
    return TallySettings(
      id: json['id'],
      companyName: json['company_name'] ?? 'V K Traders',
      tallyServerUrl: json['tally_server_url'] ?? 'http://localhost',
      tallyPort: json['tally_port'] ?? 9000,
      tallyCompanyName: json['tally_company_name'],
      isTallyConnected: json['is_tally_connected'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_name': companyName,
      'tally_server_url': tallyServerUrl,
      'tally_port': tallyPort,
      'tally_company_name': tallyCompanyName,
      'is_tally_connected': isTallyConnected,
    };
  }
}