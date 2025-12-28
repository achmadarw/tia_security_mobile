class ShiftAssignment {
  final int id;
  final int userId;
  final int shiftId;
  final DateTime assignmentDate;
  final bool isReplacement;
  final int? replacedUserId;
  final String? notes;
  final int? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Populated from JOIN queries
  final String? userName;
  final String? userPhone;
  final String? shiftName;
  final String? startTime;
  final String? endTime;
  final String? replacedUserName;

  ShiftAssignment({
    required this.id,
    required this.userId,
    required this.shiftId,
    required this.assignmentDate,
    required this.isReplacement,
    this.replacedUserId,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.userName,
    this.userPhone,
    this.shiftName,
    this.startTime,
    this.endTime,
    this.replacedUserName,
  });

  factory ShiftAssignment.fromJson(Map<String, dynamic> json) {
    return ShiftAssignment(
      id: json['id'],
      userId: json['user_id'],
      shiftId: json['shift_id'],
      assignmentDate: _parseDate(json['assignment_date']),
      isReplacement: json['is_replacement'] ?? false,
      replacedUserId: json['replaced_user_id'],
      notes: json['notes'],
      createdBy: json['created_by'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      userName: json['user_name'],
      userPhone: json['user_phone'],
      shiftName: json['shift_name'],
      startTime: json['start_time'],
      endTime: json['end_time'],
      replacedUserName: json['replaced_user_name'],
    );
  }

  // Parse date string as local date to avoid timezone issues
  static DateTime _parseDate(String dateString) {
    print('DEBUG ShiftAssignment: Parsing date string: "$dateString"');

    // If it's a UTC timestamp (contains 'T'), parse and convert to local date
    if (dateString.contains('T')) {
      final utcDateTime = DateTime.parse(dateString); // Parse as UTC
      final localDateTime = utcDateTime.toLocal(); // Convert to local timezone

      // Return date only (no time component)
      final result =
          DateTime(localDateTime.year, localDateTime.month, localDateTime.day);
      print(
          'DEBUG ShiftAssignment: Parsed UTC timestamp to local date: $result (UTC: $utcDateTime → Local: $localDateTime)');
      return result;
    }

    // If it's just a date string "YYYY-MM-DD", parse directly
    final parts = dateString.split('-');
    if (parts.length == 3) {
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);

      final result = DateTime(year, month, day);
      print('DEBUG ShiftAssignment: Parsed date string to DateTime: $result');
      return result;
    }

    // Fallback to DateTime.parse if format is different
    print('DEBUG ShiftAssignment: Using fallback DateTime.parse');
    return DateTime.parse(dateString).toLocal();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'shift_id': shiftId,
      'assignment_date': assignmentDate.toIso8601String().split('T')[0],
      'is_replacement': isReplacement,
      'replaced_user_id': replacedUserId,
      'notes': notes,
      'created_by': createdBy,
    };
  }

  String getFormattedDate() {
    return '${assignmentDate.day}/${assignmentDate.month}/${assignmentDate.year}';
  }

  String getFormattedStartTime() {
    return startTime?.substring(0, 5) ?? '';
  }

  String getFormattedEndTime() {
    return endTime?.substring(0, 5) ?? '';
  }

  ShiftAssignment copyWith({
    int? id,
    int? userId,
    int? shiftId,
    DateTime? assignmentDate,
    bool? isReplacement,
    int? replacedUserId,
    String? notes,
    int? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userName,
    String? userPhone,
    String? shiftName,
    String? startTime,
    String? endTime,
    String? replacedUserName,
  }) {
    return ShiftAssignment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      shiftId: shiftId ?? this.shiftId,
      assignmentDate: assignmentDate ?? this.assignmentDate,
      isReplacement: isReplacement ?? this.isReplacement,
      replacedUserId: replacedUserId ?? this.replacedUserId,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      shiftName: shiftName ?? this.shiftName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      replacedUserName: replacedUserName ?? this.replacedUserName,
    );
  }
}
