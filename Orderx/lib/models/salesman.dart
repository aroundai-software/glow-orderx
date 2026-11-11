// lib/models/salesman.dart
class Salesman {
  final String id;
  final String mobileNumber;
  final String name;
  final String userType;
  final bool isActive;
  final DateTime createdAt;

  Salesman({
    required this.id,
    required this.mobileNumber,
    required this.name,
    required this.userType,
    required this.isActive,
    required this.createdAt,
  });

  factory Salesman.fromJson(Map<String, dynamic> json) {
    return Salesman(
      id: json['id'],
      mobileNumber: json['mobile_number'],
      name: json['name'],
      userType: json['user_type'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mobile_number': mobileNumber,
      'name': name,
      'user_type': userType,
      'is_active': isActive,
    };
  }

  bool get isAdmin => userType == 'admin';
  bool get isSalesman => userType == 'salesman';
}