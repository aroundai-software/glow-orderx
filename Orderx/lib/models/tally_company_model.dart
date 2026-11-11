class TallyCompanyModel {
  final String id;
  final String companyName;
  final String companyNumber;
  final String Guid;
  final String? companyAlias;
  final String? companyDescription;
  
  // Address Information
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? pinCode;
  final String? country;
  
  // Contact Information
  final String? phoneNumber;
  final String? email;
  final String? website;
  
  // Tax Information
  final String? gstNumber;
  final String? panNumber;
  final String? tanNumber;
  
  // Financial Information
  final DateTime? financialYearStartDate;
  final DateTime? financialYearEndDate;
  
  // Company Status
  final bool isActive;
  final bool isSynced;
  
  // Tally Connection Details
  final String? tallyServerUrl;
  final int? tallyPort;
  final String? tallyUsername;
  
  // Sync Metadata
  final DateTime? lastSyncedAt;
  final String syncStatus; // pending, syncing, completed, failed
  final String? syncErrorMessage;
  
  // Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;

  TallyCompanyModel({
    required this.id,
    required this.companyName,
    required this.companyNumber,
    required this.Guid,
    this.companyAlias,
    this.companyDescription,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.pinCode,
    this.country,
    this.phoneNumber,
    this.email,
    this.website,
    this.gstNumber,
    this.panNumber,
    this.tanNumber,
    this.financialYearStartDate,
    this.financialYearEndDate,
    required this.isActive,
    required this.isSynced,
    this.tallyServerUrl,
    this.tallyPort,
    this.tallyUsername,
    this.lastSyncedAt,
    required this.syncStatus,
    this.syncErrorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a TallyCompanyModel from JSON
  factory TallyCompanyModel.fromJson(Map<String, dynamic> json) {
    return TallyCompanyModel(
      id: json['id'] as String,
      companyName: json['company_name'] as String,
      companyNumber: json['company_number'] as String,
      Guid: json['Guid'] as String,
      companyAlias: json['company_alias'] as String?,
      companyDescription: json['company_description'] as String?,
      addressLine1: json['address_line1'] as String?,
      addressLine2: json['address_line2'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      pinCode: json['pin_code'] as String?,
      country: json['country'] as String? ?? 'India',
      phoneNumber: json['phone_number'] as String?,
      email: json['email'] as String?,
      website: json['website'] as String?,
      gstNumber: json['gst_number'] as String?,
      panNumber: json['pan_number'] as String?,
      tanNumber: json['tan_number'] as String?,
      financialYearStartDate: json['financial_year_start_date'] != null
          ? DateTime.parse(json['financial_year_start_date'] as String)
          : null,
      financialYearEndDate: json['financial_year_end_date'] != null
          ? DateTime.parse(json['financial_year_end_date'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      isSynced: json['is_synced'] as bool? ?? false,
      tallyServerUrl: json['tally_server_url'] as String?,
      tallyPort: json['tally_port'] as int? ?? 9000,
      tallyUsername: json['tally_username'] as String?,
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.parse(json['last_synced_at'] as String)
          : null,
      syncStatus: json['sync_status'] as String? ?? 'pending',
      syncErrorMessage: json['sync_error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert TallyCompanyModel to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_name': companyName,
      'company_number': companyNumber,
      'Guid': Guid,
      'company_alias': companyAlias,
      'company_description': companyDescription,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'city': city,
      'state': state,
      'pin_code': pinCode,
      'country': country,
      'phone_number': phoneNumber,
      'email': email,
      'website': website,
      'gst_number': gstNumber,
      'pan_number': panNumber,
      'tan_number': tanNumber,
      'financial_year_start_date': financialYearStartDate?.toIso8601String(),
      'financial_year_end_date': financialYearEndDate?.toIso8601String(),
      'is_active': isActive,
      'is_synced': isSynced,
      'tally_server_url': tallyServerUrl,
      'tally_port': tallyPort,
      'tally_username': tallyUsername,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
      'sync_status': syncStatus,
      'sync_error_message': syncErrorMessage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of this model with some fields replaced
  TallyCompanyModel copyWith({
    String? id,
    String? companyName,
    String? companyNumber,
    String? Guid,
    String? companyAlias,
    String? companyDescription,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? pinCode,
    String? country,
    String? phoneNumber,
    String? email,
    String? website,
    String? gstNumber,
    String? panNumber,
    String? tanNumber,
    DateTime? financialYearStartDate,
    DateTime? financialYearEndDate,
    bool? isActive,
    bool? isSynced,
    String? tallyServerUrl,
    int? tallyPort,
    String? tallyUsername,
    DateTime? lastSyncedAt,
    String? syncStatus,
    String? syncErrorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TallyCompanyModel(
      id: id ?? this.id,
      companyName: companyName ?? this.companyName,
      companyNumber: companyNumber ?? this.companyNumber,
      Guid: Guid ?? this.Guid,
      companyAlias: companyAlias ?? this.companyAlias,
      companyDescription: companyDescription ?? this.companyDescription,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      pinCode: pinCode ?? this.pinCode,
      country: country ?? this.country,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      website: website ?? this.website,
      gstNumber: gstNumber ?? this.gstNumber,
      panNumber: panNumber ?? this.panNumber,
      tanNumber: tanNumber ?? this.tanNumber,
      financialYearStartDate: financialYearStartDate ?? this.financialYearStartDate,
      financialYearEndDate: financialYearEndDate ?? this.financialYearEndDate,
      isActive: isActive ?? this.isActive,
      isSynced: isSynced ?? this.isSynced,
      tallyServerUrl: tallyServerUrl ?? this.tallyServerUrl,
      tallyPort: tallyPort ?? this.tallyPort,
      tallyUsername: tallyUsername ?? this.tallyUsername,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      syncErrorMessage: syncErrorMessage ?? this.syncErrorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get full address as a single string
  String get fullAddress {
    final parts = <String>[];
    if (addressLine1 != null) parts.add(addressLine1!);
    if (addressLine2 != null) parts.add(addressLine2!);
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    if (pinCode != null) parts.add(pinCode!);
    if (country != null) parts.add(country!);
    return parts.join(', ');
  }

  /// Check if company is ready for sync
  bool get isReadyForSync {
    return isActive && 
           tallyServerUrl != null && 
           tallyPort != null && 
           tallyUsername != null;
  }

  /// Get sync status display text
  String get syncStatusDisplay {
    switch (syncStatus) {
      case 'completed':
        return 'Synced';
      case 'syncing':
        return 'Syncing...';
      case 'failed':
        return 'Sync Failed';
      case 'pending':
      default:
        return 'Pending';
    }
  }

  @override
  String toString() {
    return 'TallyCompanyModel(id: $id, companyName: $companyName, companyNumber: $companyNumber, Guid: $Guid)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TallyCompanyModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          companyNumber == other.companyNumber &&
          Guid == other.Guid;

  @override
  int get hashCode =>
      id.hashCode ^ companyNumber.hashCode ^ Guid.hashCode;
}
