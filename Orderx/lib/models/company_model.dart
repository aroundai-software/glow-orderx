class Company {
  final String id;
  final String companyName;
  final String companyNumber;
  final String? gstNumber;
  bool isActive;

  Company({
    required this.id,
    required this.companyName,
    required this.companyNumber,
    required this.isActive,
    this.gstNumber,
  });

  factory Company.fromMap(Map<String, dynamic> m) {
    return Company(
      id: m['id'].toString(), // ensure safe type conversion
      companyName: m['company_name']?.toString() ?? '',
      companyNumber: m['company_number']?.toString() ?? '',
      gstNumber: m['gst_number']?.toString(),
      isActive: m['is_active'] == true || m['is_active'] == 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'company_name': companyName,
        'company_number': companyNumber,
        'gst_number': gstNumber,
        'is_active': isActive,
      };
}
