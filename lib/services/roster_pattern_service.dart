import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:tia_mobile/config/api_config.dart';
import '../models/roster_pattern.dart';

class RosterPatternService {
  final String baseUrl = ApiConfig.baseUrl;

  /// Get all roster patterns with optional filters
  Future<List<RosterPattern>> getPatterns({
    String? token,
    int? personilCount,
    bool? isDefault,
    String? search,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (personilCount != null) {
        queryParams['personil_count'] = personilCount.toString();
      }
      if (isDefault != null) {
        queryParams['is_default'] = isDefault.toString();
      }
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final uri = Uri.parse('$baseUrl/roster-patterns').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(
        uri,
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final patterns = (data['data'] as List)
            .map((pattern) => RosterPattern.fromJson(pattern))
            .toList();
        return patterns;
      } else {
        throw Exception('Failed to load patterns: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching patterns: $e');
      rethrow;
    }
  }

  /// Get pattern by ID
  Future<RosterPattern?> getPatternById(int id, {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/roster-patterns/$id'),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RosterPattern.fromJson(data['data']);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to load pattern: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching pattern by ID: $e');
      rethrow;
    }
  }

  /// Get default pattern for specific personil count
  Future<RosterPattern?> getDefaultPattern(int personilCount,
      {String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/roster-patterns/default/$personilCount'),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RosterPattern.fromJson(data['data']);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception(
            'Failed to load default pattern: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching default pattern: $e');
      rethrow;
    }
  }

  /// Record pattern usage (increment usage count)
  Future<void> recordUsage(int id, {String? token}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/roster-patterns/$id/use'),
        headers: _getHeaders(token),
      );

      if (response.statusCode != 200) {
        print(
            'Warning: Failed to record pattern usage: ${response.statusCode}');
        // Don't throw error, just log it
      }
    } catch (e) {
      print('Error recording pattern usage: $e');
      // Don't throw error, this is not critical
    }
  }

  /// Get headers with auth token
  Map<String, String> _getHeaders(String? token) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }
}
