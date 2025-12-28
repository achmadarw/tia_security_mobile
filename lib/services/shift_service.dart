import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/shift.dart';

class ShiftService {
  final String baseUrl = ApiConfig.baseUrl;

  // Get all active shifts
  Future<List<Shift>> getShifts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/shifts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List shiftsJson = data['data'];
      return shiftsJson.map((json) => Shift.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load shifts: ${response.body}');
    }
  }

  // Get shift by ID
  Future<Shift> getShift(String token, int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/shifts/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Shift.fromJson(data['data']);
    } else {
      throw Exception('Failed to load shift: ${response.body}');
    }
  }

  // Create new shift (admin only)
  Future<Shift> createShift(
    String token, {
    required String name,
    required String startTime,
    required String endTime,
    String? description,
    bool isActive = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/shifts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'name': name,
        'start_time': startTime,
        'end_time': endTime,
        'description': description,
        'is_active': isActive,
      }),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return Shift.fromJson(data['data']);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to create shift');
    }
  }

  // Update shift (admin only)
  Future<Shift> updateShift(
    String token,
    int id, {
    String? name,
    String? startTime,
    String? endTime,
    String? description,
    bool? isActive,
  }) async {
    final Map<String, dynamic> body = {};
    if (name != null) body['name'] = name;
    if (startTime != null) body['start_time'] = startTime;
    if (endTime != null) body['end_time'] = endTime;
    if (description != null) body['description'] = description;
    if (isActive != null) body['is_active'] = isActive;

    final response = await http.put(
      Uri.parse('$baseUrl/shifts/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Shift.fromJson(data['data']);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to update shift');
    }
  }

  // Delete shift (admin only)
  Future<Map<String, dynamic>> deleteShift(String token, int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/shifts/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to delete shift');
    }
  }
}
