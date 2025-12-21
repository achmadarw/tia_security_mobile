class Attendance {
  final int id;
  final int userId;
  final String? userName;
  final int? shiftId;
  final String? shiftName;
  final String type; // check_in, check_out
  final DateTime timestamp;
  final double? locationLat;
  final double? locationLng;
  final double? faceConfidence;
  final String? photoUrl;

  Attendance({
    required this.id,
    required this.userId,
    this.userName,
    this.shiftId,
    this.shiftName,
    required this.type,
    required this.timestamp,
    this.locationLat,
    this.locationLng,
    this.faceConfidence,
    this.photoUrl,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['id'],
      userId: json['user_id'],
      userName: json['user_name'],
      shiftId: json['shift_id'],
      shiftName: json['shift_name'],
      type: json['type'],
      timestamp: DateTime.parse(json['timestamp']),
      locationLat: json['location_lat']?.toDouble(),
      locationLng: json['location_lng']?.toDouble(),
      faceConfidence: json['face_confidence']?.toDouble(),
      photoUrl: json['photo_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'shift_id': shiftId,
      'shift_name': shiftName,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'location_lat': locationLat,
      'location_lng': locationLng,
      'face_confidence': faceConfidence,
      'photo_url': photoUrl,
    };
  }

  bool get isCheckIn => type == 'check_in';
  bool get isCheckOut => type == 'check_out';
}
