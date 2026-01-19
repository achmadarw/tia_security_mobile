/// Patrol Session Model
class PatrolSession {
  final int? id;
  final int userId;
  final int? postSessionId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final double? startLocationLat;
  final double? startLocationLng;
  final double? endLocationLat;
  final double? endLocationLng;
  final String status; // 'in_progress', 'completed', 'abandoned'
  final String? notes;
  final String? abandonReason;
  final List<PatrolCheckpoint> checkpoints;
  final List<PatrolTrackPoint> trackPoints;

  PatrolSession({
    this.id,
    required this.userId,
    this.postSessionId,
    required this.startedAt,
    this.completedAt,
    this.startLocationLat,
    this.startLocationLng,
    this.endLocationLat,
    this.endLocationLng,
    required this.status,
    this.notes,
    this.abandonReason,
    this.checkpoints = const [],
    this.trackPoints = const [],
  });

  /// Get duration in minutes
  int get durationMinutes {
    DateTime end = completedAt ?? DateTime.now();
    return end.difference(startedAt).inMinutes;
  }

  /// Get formatted duration
  String get formattedDuration {
    int minutes = durationMinutes;
    int hours = minutes ~/ 60;
    int mins = minutes % 60;
    if (hours > 0) {
      return '${hours}j ${mins}m';
    }
    return '${mins}m';
  }

  /// Check if patrol is active
  bool get isActive => status == 'in_progress';

  /// Get visited blocks count
  int get visitedBlocksCount => checkpoints.length;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'post_session_id': postSessionId,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'start_location_lat': startLocationLat,
      'start_location_lng': startLocationLng,
      'end_location_lat': endLocationLat,
      'end_location_lng': endLocationLng,
      'status': status,
      'notes': notes,
      'abandon_reason': abandonReason,
      'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
      'track_points': trackPoints.map((t) => t.toJson()).toList(),
    };
  }

  factory PatrolSession.fromJson(Map<String, dynamic> json) {
    return PatrolSession(
      id: json['id'],
      userId: json['user_id'],
      postSessionId: json['post_session_id'],
      startedAt: DateTime.parse(json['started_at']),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      startLocationLat: json['start_location_lat']?.toDouble(),
      startLocationLng: json['start_location_lng']?.toDouble(),
      endLocationLat: json['end_location_lat']?.toDouble(),
      endLocationLng: json['end_location_lng']?.toDouble(),
      status: json['status'] ?? 'in_progress',
      notes: json['notes'],
      abandonReason: json['abandon_reason'],
      checkpoints: (json['checkpoints'] as List<dynamic>?)
              ?.map((c) => PatrolCheckpoint.fromJson(c))
              .toList() ??
          [],
      trackPoints: (json['track_points'] as List<dynamic>?)
              ?.map((t) => PatrolTrackPoint.fromJson(t))
              .toList() ??
          [],
    );
  }
}

/// Patrol Checkpoint (Block Visit)
class PatrolCheckpoint {
  final int? id;
  final int? patrolSessionId;
  final int blockId;
  final String blockName;
  final DateTime visitedAt;
  final DateTime? exitedAt;
  final double locationLat;
  final double locationLng;
  final double distanceFromBlock;
  final int dwellSeconds;
  final String? photoUrl;
  final String? notes;

  PatrolCheckpoint({
    this.id,
    this.patrolSessionId,
    required this.blockId,
    required this.blockName,
    required this.visitedAt,
    this.exitedAt,
    required this.locationLat,
    required this.locationLng,
    required this.distanceFromBlock,
    this.dwellSeconds = 0,
    this.photoUrl,
    this.notes,
  });

  /// Get formatted dwell time
  String get formattedDwellTime {
    int minutes = dwellSeconds ~/ 60;
    int secs = dwellSeconds % 60;
    return '${minutes}m ${secs}s';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patrol_session_id': patrolSessionId,
      'block_id': blockId,
      'block_name': blockName,
      'visited_at': visitedAt.toIso8601String(),
      'exited_at': exitedAt?.toIso8601String(),
      'location_lat': locationLat,
      'location_lng': locationLng,
      'distance_from_block': distanceFromBlock,
      'dwell_seconds': dwellSeconds,
      'photo_url': photoUrl,
      'notes': notes,
    };
  }

  factory PatrolCheckpoint.fromJson(Map<String, dynamic> json) {
    return PatrolCheckpoint(
      id: json['id'],
      patrolSessionId: json['patrol_session_id'],
      blockId: json['block_id'],
      blockName: json['block_name'] ?? 'Unknown Block',
      visitedAt: DateTime.parse(json['visited_at']),
      exitedAt:
          json['exited_at'] != null ? DateTime.parse(json['exited_at']) : null,
      locationLat: json['location_lat']?.toDouble() ?? 0.0,
      locationLng: json['location_lng']?.toDouble() ?? 0.0,
      distanceFromBlock: json['distance_from_block']?.toDouble() ?? 0.0,
      dwellSeconds: json['dwell_seconds'] ?? 0,
      photoUrl: json['photo_url'],
      notes: json['notes'],
    );
  }
}

/// GPS Track Point (untuk breadcrumb trail)
class PatrolTrackPoint {
  final int? id;
  final int? patrolSessionId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;

  PatrolTrackPoint({
    this.id,
    this.patrolSessionId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patrol_session_id': patrolSessionId,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
    };
  }

  factory PatrolTrackPoint.fromJson(Map<String, dynamic> json) {
    return PatrolTrackPoint(
      id: json['id'],
      patrolSessionId: json['patrol_session_id'],
      timestamp: DateTime.parse(json['timestamp']),
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      accuracy: json['accuracy']?.toDouble(),
      altitude: json['altitude']?.toDouble(),
      speed: json['speed']?.toDouble(),
      heading: json['heading']?.toDouble(),
    );
  }
}

/// Patrol Statistics
class PatrolStatistics {
  final int totalDistance; // meters
  final int totalDuration; // seconds
  final int blocksVisited;
  final int photosTaken;
  final double averageSpeed; // m/s

  PatrolStatistics({
    required this.totalDistance,
    required this.totalDuration,
    required this.blocksVisited,
    required this.photosTaken,
    required this.averageSpeed,
  });

  String get formattedDistance {
    if (totalDistance < 1000) {
      return '$totalDistance m';
    }
    return '${(totalDistance / 1000).toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    int minutes = totalDuration ~/ 60;
    int hours = minutes ~/ 60;
    int mins = minutes % 60;
    if (hours > 0) {
      return '${hours}j ${mins}m';
    }
    return '${mins}m';
  }

  String get formattedSpeed {
    return '${(averageSpeed * 3.6).toStringAsFixed(1)} km/h';
  }
}
