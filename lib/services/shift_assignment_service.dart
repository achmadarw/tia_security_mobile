import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/shift_assignment.dart';

class ShiftAssignmentService {
  final String baseUrl = ApiConfig.baseUrl;

  // Get assignments by date range
  Future<List<ShiftAssignment>> getCalendar(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
    int? userId,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) {
      queryParams['start_date'] = startDate.toIso8601String().split('T')[0];
    }
    if (endDate != null) {
      queryParams['end_date'] = endDate.toIso8601String().split('T')[0];
    }
    if (userId != null) {
      queryParams['user_id'] = userId.toString();
    }

    final uri = Uri.parse('$baseUrl/shift-assignments/calendar')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List assignmentsJson = data['data'];
      return assignmentsJson
          .map((json) => ShiftAssignment.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to load calendar: ${response.body}');
    }
  }

  // Get assignments for specific date
  Future<List<ShiftAssignment>> getDateAssignments(
    String token,
    DateTime date,
  ) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final response = await http.get(
      Uri.parse('$baseUrl/shift-assignments/date/$dateStr'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List assignmentsJson = data['data'];
      return assignmentsJson
          .map((json) => ShiftAssignment.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to load date assignments: ${response.body}');
    }
  }

  // Get user's assignments
  Future<List<ShiftAssignment>> getUserAssignments(
    String token,
    int userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) {
      queryParams['start_date'] = startDate.toIso8601String().split('T')[0];
    }
    if (endDate != null) {
      queryParams['end_date'] = endDate.toIso8601String().split('T')[0];
    }

    final uri = Uri.parse('$baseUrl/shift-assignments/user/$userId')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List assignmentsJson = data['data'];
      return assignmentsJson
          .map((json) => ShiftAssignment.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to load user assignments: ${response.body}');
    }
  }

  // Create single assignment (admin only)
  Future<ShiftAssignment> createAssignment(
    String token, {
    required int userId,
    required int shiftId,
    required DateTime assignmentDate,
    bool isReplacement = false,
    int? replacedUserId,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/shift-assignments'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'user_id': userId,
        'shift_id': shiftId,
        'assignment_date': assignmentDate.toIso8601String().split('T')[0],
        'is_replacement': isReplacement,
        'replaced_user_id': replacedUserId,
        'notes': notes,
      }),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return ShiftAssignment.fromJson(data['data']);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to create assignment');
    }
  }

  // Bulk create assignments (admin only)
  Future<Map<String, dynamic>> createBulkAssignments(
    String token,
    List<Map<String, dynamic>> assignments,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/shift-assignments/bulk'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'assignments': assignments,
      }),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to create bulk assignments');
    }
  }

  // Update assignment (admin only)
  Future<ShiftAssignment> updateAssignment(
    String token,
    int id, {
    int? userId,
    int? shiftId,
    DateTime? assignmentDate,
    bool? isReplacement,
    int? replacedUserId,
    String? notes,
  }) async {
    final Map<String, dynamic> body = {};
    if (userId != null) body['user_id'] = userId;
    if (shiftId != null) body['shift_id'] = shiftId;
    if (assignmentDate != null) {
      body['assignment_date'] = assignmentDate.toIso8601String().split('T')[0];
    }
    if (isReplacement != null) body['is_replacement'] = isReplacement;
    if (replacedUserId != null) body['replaced_user_id'] = replacedUserId;
    if (notes != null) body['notes'] = notes;

    final response = await http.put(
      Uri.parse('$baseUrl/shift-assignments/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return ShiftAssignment.fromJson(data['data']);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to update assignment');
    }
  }

  // Delete assignment (admin only)
  Future<Map<String, dynamic>> deleteAssignment(String token, int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/shift-assignments/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to delete assignment');
    }
  }
}
