class User {
  final int id;
  final String name;
  final String? email;
  final String phone;
  final String role;
  final int? shiftId;
  final String? shiftName;
  final int? departmentId;
  final String? departmentName;
  final String status;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    this.email,
    required this.phone,
    required this.role,
    this.shiftId,
    this.shiftName,
    this.departmentId,
    this.departmentName,
    required this.status,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      role: json['role'],
      shiftId: json['shift_id'] != null
          ? (json['shift_id'] is int
              ? json['shift_id']
              : int.parse(json['shift_id'].toString()))
          : null,
      shiftName: json['shift_name'],
      departmentId: json['department_id'] != null
          ? (json['department_id'] is int
              ? json['department_id']
              : int.parse(json['department_id'].toString()))
          : null,
      departmentName: json['department_name'],
      status: json['status'] ?? 'active',
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'shift_id': shiftId,
      'shift_name': shiftName,
      'department_id': departmentId,
      'department_name': departmentName,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isSecurity => role == 'security';
  bool get isActive => status == 'active';
}
