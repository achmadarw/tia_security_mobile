class Block {
  final int? id;
  final String name;
  final String? description;
  final double locationLat;
  final double locationLng;
  final String status; // 'active' or 'inactive'
  final DateTime? createdAt;

  Block({
    this.id,
    required this.name,
    this.description,
    required this.locationLat,
    required this.locationLng,
    this.status = 'active',
    this.createdAt,
  });

  // Factory constructor from JSON
  factory Block.fromJson(Map<String, dynamic> json) {
    return Block(
      id: json['id'] as int?,
      name: json['name'] as String,
      description: json['description'] as String?,
      // Handle both string and double types from backend
      locationLat: _parseCoordinate(json['location_lat']),
      locationLng: _parseCoordinate(json['location_lng']),
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  // Helper to parse coordinates (handles String, int, double)
  static double _parseCoordinate(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.parse(value);
    throw FormatException('Invalid coordinate value: $value');
  }

  // Convert to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (description != null && description!.isNotEmpty)
        'description': description,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'status': status,
    };
  }

  // Coordinate validation
  bool get isValidCoordinates {
    return locationLat >= -90 &&
        locationLat <= 90 &&
        locationLng >= -180 &&
        locationLng <= 180;
  }

  // Status helpers
  bool get isActive => status.toLowerCase() == 'active';

  // Display formatted coordinates
  String get coordinatesText =>
      '${locationLat.toStringAsFixed(6)}, ${locationLng.toStringAsFixed(6)}';

  // Create a copy with updated fields
  Block copyWith({
    int? id,
    String? name,
    String? description,
    double? locationLat,
    double? locationLng,
    String? status,
    DateTime? createdAt,
  }) {
    return Block(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Block(id: $id, name: $name, coordinates: $coordinatesText, status: $status)';
  }
}
