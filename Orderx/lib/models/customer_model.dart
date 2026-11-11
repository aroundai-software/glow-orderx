class CustomerModel {
  final String id;
  final String customerName;
  final String? mobileNumber;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? gstNumber;
  final String? createdBy;
  final String? customerCategoryId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? guid;
  final int? masterId;

  CustomerModel({
    required this.id,
    required this.customerName,
    this.mobileNumber,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.gstNumber,
    this.createdBy,
    this.customerCategoryId,
    required this.createdAt,
    required this.updatedAt,
    this.guid,
    this.masterId,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    int? parseMasterId(dynamic val) {
      if (val == null) return null;
      if (val is int) return val;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString());
    }

    return CustomerModel(
      id: (json['id'] ?? '').toString(),
      customerName: (json['customer_name'] ?? '').toString(),
      mobileNumber: json['mobile_number'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      pincode: json['pincode'] as String?,
      gstNumber: json['gst_number'] as String?,
      createdBy: json['created_by'] as String?,
      customerCategoryId: json['customer_category_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      guid: json['Guid'] as String?,
      masterId: parseMasterId(json['MasterID']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_name': customerName,
      'mobile_number': mobileNumber,
      'address': address,
      'city': city,
      'state': state,
      'pincode': pincode,
      'gst_number': gstNumber,
      'created_by': createdBy,
      'customer_category_id': customerCategoryId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'Guid': guid,
      'MasterID': masterId,
    };
  }

  String get fullAddress {
    List<String> parts = [];
    if (address != null && address!.isNotEmpty) parts.add(address!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (state != null && state!.isNotEmpty) parts.add(state!);
    if (pincode != null && pincode!.isNotEmpty) parts.add(pincode!);
    return parts.join(', ');
  }
}