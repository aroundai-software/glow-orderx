class UserOrganization {
  final String id;
  final String userName;
  final String userKey;
  final String userId;
  final DateTime? createdAt;

  UserOrganization({
    required this.id,
    required this.userName,
    required this.userKey,
    required this.userId,
    this.createdAt,
  });

  factory UserOrganization.fromJson(Map<String, dynamic> json) {
    return UserOrganization(
      id: json['id'] as String,
      userName: json['user_name'] as String,
      userKey: json['user_key'] as String,
      userId: json['user_id'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
