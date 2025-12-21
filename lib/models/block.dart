class Block {
  final int id;
  final String name;
  final String? description;
  final double? locationLat;
  final double? locationLng;
  final String status;
  final DateTime createdAt;

  Block({
    required this.id,
    required this.name,
    this.description,
    this.locationLat,
    this.locationLng,
    required this.status,
    required this.createdAt,
  });

  factory Block.fromJson(Map<String, dynamic> json) {
    return Block(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      locationLat: json['location_lat']?.toDouble(),
      locationLng: json['location_lng']?.toDouble(),
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isActive => status == 'active';
}
