class RosterPattern {
  final int id;
  final String name;
  final String? description;
  final int personilCount;
  final List<List<int>> patternData;
  final bool isDefault;
  final int? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int usageCount;
  final DateTime? lastUsedAt;

  RosterPattern({
    required this.id,
    required this.name,
    this.description,
    required this.personilCount,
    required this.patternData,
    required this.isDefault,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.usageCount,
    this.lastUsedAt,
  });

  factory RosterPattern.fromJson(Map<String, dynamic> json) {
    return RosterPattern(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      personilCount: json['personil_count'] as int,
      patternData: (json['pattern_data'] as List)
          .map((row) => (row as List).map((shift) => shift as int).toList())
          .toList(),
      isDefault: json['is_default'] as bool,
      createdBy: json['created_by'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      usageCount: json['usage_count'] as int,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'personil_count': personilCount,
      'pattern_data': patternData,
      'is_default': isDefault,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'usage_count': usageCount,
      'last_used_at': lastUsedAt?.toIso8601String(),
    };
  }

  /// Get pattern name for display
  String getDisplayName() {
    if (isDefault) {
      return '$name ⭐';
    }
    return name;
  }

  /// Get pattern description for display
  String getDisplayDescription() {
    final parts = <String>[];
    parts.add('$personilCount personil');

    if (description != null && description!.isNotEmpty) {
      parts.add(description!);
    }

    if (usageCount > 0) {
      parts.add('Digunakan $usageCount kali');
    }

    return parts.join(' • ');
  }

  /// Get shift name for a specific shift number
  static String getShiftName(int shiftNumber) {
    switch (shiftNumber) {
      case 0:
        return 'OFF';
      case 1:
        return 'Pagi';
      case 2:
        return 'Siang';
      case 3:
        return 'Sore';
      default:
        return 'Unknown';
    }
  }

  /// Get pattern preview text (first row only)
  String getPreviewText() {
    if (patternData.isEmpty) return '';

    final firstRow = patternData[0];
    final preview =
        firstRow.map((shift) => getShiftName(shift)).take(4).join(', ');

    if (firstRow.length > 4) {
      return '$preview...';
    }
    return preview;
  }
}
