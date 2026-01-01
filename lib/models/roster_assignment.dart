class RosterAssignment {
  final int id;
  final String assignmentMonth; // Format: "YYYY-MM-DD"
  final int userId;
  final String userName;
  final String userPhone;
  final String userRole;
  final int patternId;
  final String patternName;
  final List<int>
      patternData; // 7-day pattern array [Mon, Tue, Wed, Thu, Fri, Sat, Sun]
  final String? notes;
  final DateTime assignedAt;

  RosterAssignment({
    required this.id,
    required this.assignmentMonth,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.userRole,
    required this.patternId,
    required this.patternName,
    required this.patternData,
    this.notes,
    required this.assignedAt,
  });

  factory RosterAssignment.fromJson(Map<String, dynamic> json) {
    return RosterAssignment(
      id: json['id'] as int,
      assignmentMonth: json['assignment_month'] as String,
      userId: json['user_id'] as int,
      userName: json['user_name'] as String,
      userPhone: json['user_phone'] as String,
      userRole: json['user_role'] as String,
      patternId: json['pattern_id'] as int,
      patternName: json['pattern_name'] as String,
      patternData:
          (json['pattern_data'] as List).map((shift) => shift as int).toList(),
      notes: json['notes'] as String?,
      assignedAt: DateTime.parse(json['assigned_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assignment_month': assignmentMonth,
      'user_id': userId,
      'user_name': userName,
      'user_phone': userPhone,
      'user_role': userRole,
      'pattern_id': patternId,
      'pattern_name': patternName,
      'pattern_data': patternData,
      'notes': notes,
      'assigned_at': assignedAt.toIso8601String(),
    };
  }
}
