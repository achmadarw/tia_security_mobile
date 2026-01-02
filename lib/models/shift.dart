import 'package:flutter/material.dart';

class Shift {
  final int id;
  final String name;
  final String? code; // Shift code (e.g., "1", "2", "3")
  final String startTime; // Format: "HH:mm:ss"
  final String endTime;
  final String? description;
  final String? color; // Hex color code
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Shift({
    required this.id,
    required this.name,
    this.code,
    required this.startTime,
    required this.endTime,
    this.description,
    this.color,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id'],
      name: json['name'],
      code: json['code'],
      startTime: json['start_time'],
      endTime: json['end_time'],
      description: json['description'],
      color: json['color'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'start_time': startTime,
      'end_time': endTime,
      'description': description,
      'color': color,
      'is_active': isActive,
    };
  }

  // Format time for display (HH:mm)
  String getFormattedStartTime() {
    return startTime.substring(0, 5);
  }

  String getFormattedEndTime() {
    return endTime.substring(0, 5);
  }

  // Get color value from hex string
  Color get colorValue {
    if (color == null || color!.isEmpty) {
      return Colors.blue; // Default color
    }
    try {
      final hexColor = color!.replaceAll('#', '');
      return Color(int.parse('0xFF$hexColor'));
    } catch (e) {
      return Colors.blue; // Fallback if parsing fails
    }
  }

  // Get duration in hours
  String getDuration() {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);

    int hours;
    if (end.isBefore(start)) {
      // Shift crosses midnight
      final endOfDay = DateTime(start.year, start.month, start.day, 23, 59, 59);
      final startOfDay = DateTime(end.year, end.month, end.day, 0, 0, 0);
      hours = endOfDay.difference(start).inHours +
          end.difference(startOfDay).inHours +
          1;
    } else {
      hours = end.difference(start).inHours;
    }

    return '${hours}h';
  }

  DateTime _parseTime(String time) {
    final parts = time.split(':');
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
      parts.length > 2 ? int.parse(parts[2]) : 0,
    );
  }

  Shift copyWith({
    int? id,
    String? name,
    String? startTime,
    String? endTime,
    String? description,
    String? color,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Shift(
      id: id ?? this.id,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      description: description ?? this.description,
      color: color ?? this.color,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
