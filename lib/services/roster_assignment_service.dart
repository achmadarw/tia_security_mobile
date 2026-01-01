import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/roster_assignment.dart';

class RosterAssignmentService {
  final String baseUrl = ApiConfig.baseUrl;

  /// Get roster assignments for a specific month
  /// Returns list of user-pattern assignments including pattern data
  Future<List<RosterAssignment>> getMonthAssignments(
    String token,
    int year,
    int month,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/roster-assignments/month/$year/$month'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List assignmentsJson = data['data'];
        return assignmentsJson
            .map((json) => RosterAssignment.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to load roster assignments: ${response.body}');
      }
    } catch (e) {
      print('Error fetching roster assignments: $e');
      rethrow;
    }
  }

  /// Get roster assignments with query params
  Future<List<RosterAssignment>> getAssignments(
    String token, {
    String? month, // Format: "YYYY-MM-DD"
    int? userId,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;
      if (userId != null) queryParams['user_id'] = userId.toString();

      final uri = Uri.parse('$baseUrl/roster-assignments').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);

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
            .map((json) => RosterAssignment.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to load roster assignments: ${response.body}');
      }
    } catch (e) {
      print('Error fetching roster assignments: $e');
      rethrow;
    }
  }

  /// Create roster assignment
  Future<RosterAssignment> createAssignment(
    String token, {
    required int userId,
    required int patternId,
    required String assignmentMonth, // Format: "YYYY-MM-DD"
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/roster-assignments'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user_id': userId,
          'pattern_id': patternId,
          'assignment_month': assignmentMonth,
          'notes': notes,
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return RosterAssignment.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to create roster assignment');
      }
    } catch (e) {
      print('Error creating roster assignment: $e');
      rethrow;
    }
  }

  /// Update roster assignment
  Future<RosterAssignment> updateAssignment(
    String token,
    int id, {
    int? patternId,
    String? notes,
  }) async {
    try {
      final Map<String, dynamic> body = {};
      if (patternId != null) body['pattern_id'] = patternId;
      if (notes != null) body['notes'] = notes;

      final response = await http.put(
        Uri.parse('$baseUrl/roster-assignments/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RosterAssignment.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to update roster assignment');
      }
    } catch (e) {
      print('Error updating roster assignment: $e');
      rethrow;
    }
  }

  /// Delete roster assignment
  Future<Map<String, dynamic>> deleteAssignment(String token, int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/roster-assignments/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to delete roster assignment');
      }
    } catch (e) {
      print('Error deleting roster assignment: $e');
      rethrow;
    }
  }

  /// Bulk assign patterns to multiple users
  Future<Map<String, dynamic>> bulkAssign(
    String token, {
    required String assignmentMonth,
    required List<Map<String, dynamic>> assignments,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/roster-assignments/bulk'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'assignment_month': assignmentMonth,
          'assignments': assignments,
        }),
      );

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to bulk assign');
      }
    } catch (e) {
      print('Error bulk assigning: $e');
      rethrow;
    }
  }
}
