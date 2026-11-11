class UserModel {
  final String id;
  final String mobileNumber;
  final String name;
  final String userType;
  final String? email; // Company email (optional for existing users)
  final String? password; // Password hash (optional for existing users)
  final bool isActive;
  final DateTime createdAt;
  final String? currentSessionId; // Current active session ID
  final DateTime? lastLoginAt; // Last login timestamp
  final String? companyId;

  UserModel({
    required this.id,
    required this.mobileNumber,
    required this.name,
    required this.userType,
    this.email,
    this.password,
    required this.isActive,
    required this.createdAt,
    this.currentSessionId,
    this.lastLoginAt,
    this.companyId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      try {
        return DateTime.parse(value.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    return UserModel(
      id: (json['id'] ?? '').toString(),
      mobileNumber: (json['mobile_number'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      userType: (json['user_type'] ?? '').toString(),
      email: json['email'] as String?,
      password: json['password'] as String?,
      isActive: json['is_active'] == true || json['is_active'] == 1,
      createdAt: parseDate(json['created_at']),
      currentSessionId: json['current_session_id'] as String?,
      lastLoginAt: json['last_login_at'] != null
          ? parseDate(json['last_login_at'])
          : null,
      companyId: json['company_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mobile_number': mobileNumber,
      'name': name,
      'user_type': userType,
      'email': email,
      'password': password,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'current_session_id': currentSessionId,
      'last_login_at': lastLoginAt?.toIso8601String(),
      'company_id': companyId,
    };
  }

  bool get isAdmin => userType == 'admin' || userType == 'super_admin';
  bool get isSalesman => userType == 'salesman';
}
