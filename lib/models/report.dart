class Report {
  final int id;
  final int userId;
  final String? userName;
  final int blockId;
  final String? blockName;
  final int? shiftId;
  final String? shiftName;
  final String type; // normal_patrol, incident
  final String? title;
  final String? description;
  final String? photoUrl;
  final String status; // pending, reviewed
  final int? reviewedBy;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final double? locationLat;
  final double? locationLng;
  final DateTime createdAt;

  Report({
    required this.id,
    required this.userId,
    this.userName,
    required this.blockId,
    this.blockName,
    this.shiftId,
    this.shiftName,
    required this.type,
    this.title,
    this.description,
    this.photoUrl,
    required this.status,
    this.reviewedBy,
    this.reviewedByName,
    this.reviewedAt,
    this.locationLat,
    this.locationLng,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'],
      userId: json['user_id'],
      userName: json['user_name'],
      blockId: json['block_id'],
      blockName: json['block_name'],
      shiftId: json['shift_id'],
      shiftName: json['shift_name'],
      type: json['type'],
      title: json['title'],
      description: json['description'],
      photoUrl: json['photo_url'],
      status: json['status'],
      reviewedBy: json['reviewed_by'],
      reviewedByName: json['reviewed_by_name'],
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'])
          : null,
      locationLat: json['location_lat']?.toDouble(),
      locationLng: json['location_lng']?.toDouble(),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'block_id': blockId,
      'block_name': blockName,
      'shift_id': shiftId,
      'shift_name': shiftName,
      'type': type,
      'title': title,
      'description': description,
      'photo_url': photoUrl,
      'status': status,
      'reviewed_by': reviewedBy,
      'reviewed_by_name': reviewedByName,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'location_lat': locationLat,
      'location_lng': locationLng,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isNormalPatrol => type == 'normal_patrol';
  bool get isIncident => type == 'incident';
  bool get isPending => status == 'pending';
  bool get isReviewed => status == 'reviewed';
}
