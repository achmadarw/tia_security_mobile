import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// Security App Service
/// Handles all API calls for TIA Security App (Guards Only)
class SecurityAppService {
  /// Helper methods for token and data storage
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('security_access_token');
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('security_access_token', token);
  }

  Future<void> _saveUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('security_user_data', jsonEncode(userData));
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('security_access_token');
    await prefs.remove('security_user_data');
    await prefs.remove('security_pos_data');
  }

  static const String baseEndpoint = '/api/security-app';

  /// Login to pos with code and password
  /// Returns: { pos_token, pos info, roster list }
  static Future<Map<String, dynamic>> loginToPos({
    required String posCode,
    required String password,
  }) async {
    try {
      final url = Uri.parse('${ApiConfig.serverUrl}$baseEndpoint/login');

      print('[Security Login] POST $url');
      print('[Security Login] Pos: $posCode');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pos_code': posCode,
          'password': password,
        }),
      );

      print('[Security Login] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        } else {
          throw Exception(data['error'] ?? 'Login failed');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Login failed');
      }
    } catch (e) {
      print('[Security Login] Error: $e');
      rethrow;
    }
  }

  /// Select security identity from roster and start session
  /// Returns: { user, pos, session, pattern, access_token }
  Future<Map<String, dynamic>> selectSecurity({
    required String posToken,
    required int userId,
    required int assignmentId,
  }) async {
    try {
      final url =
          Uri.parse('${ApiConfig.serverUrl}$baseEndpoint/select-security');

      print('[Select Security] POST $url');
      print('[Select Security] User ID: $userId');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pos_token': posToken,
          'user_id': userId,
          'assignment_id': assignmentId,
        }),
      );

      print('[Select Security] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Save access token
          final accessToken = data['data']['access_token'];
          await _saveToken(accessToken);

          // Save user data
          await _saveUserData(data['data']['user']);

          return data['data'];
        } else {
          throw Exception(data['error'] ?? 'Selection failed');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Selection failed');
      }
    } catch (e) {
      print('[Select Security] Error: $e');
      rethrow;
    }
  }

  /// Get current active session
  Future<Map<String, dynamic>> getCurrentSession() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }

      final url =
          Uri.parse('${ApiConfig.serverUrl}$baseEndpoint/current-session');

      print('[Current Session] GET $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('[Current Session] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        } else {
          throw Exception(data['error'] ?? 'Failed to get session');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Tidak ada sesi aktif');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to get session');
      }
    } catch (e) {
      print('[Current Session] Error: $e');
      rethrow;
    }
  }

  /// Check-in attendance
  Future<Map<String, dynamic>> checkIn({
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }

      final url = Uri.parse('${ApiConfig.serverUrl}$baseEndpoint/check-in');

      print('[Check-in] POST $url');
      print('[Check-in] Location: $latitude, $longitude');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          if (notes != null) 'notes': notes,
        }),
      );

      print('[Check-in] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        } else {
          throw Exception(data['error'] ?? 'Check-in failed');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Check-in failed');
      }
    } catch (e) {
      print('[Check-in] Error: $e');
      rethrow;
    }
  }

  /// Check-out attendance
  Future<Map<String, dynamic>> checkOut({
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }

      final url = Uri.parse('${ApiConfig.serverUrl}$baseEndpoint/check-out');

      print('[Check-out] POST $url');
      print('[Check-out] Location: $latitude, $longitude');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          if (notes != null) 'notes': notes,
        }),
      );

      print('[Check-out] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        } else {
          throw Exception(data['error'] ?? 'Check-out failed');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Check-out failed');
      }
    } catch (e) {
      print('[Check-out] Error: $e');
      rethrow;
    }
  }

  /// End session (logout from pos)
  Future<Map<String, dynamic>> endSession() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }

      final url = Uri.parse('${ApiConfig.serverUrl}$baseEndpoint/end-session');

      print('[End Session] POST $url');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('[End Session] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Clear local session
          await _clearSession();
          return data['data'];
        } else {
          throw Exception(data['error'] ?? 'End session failed');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'End session failed');
      }
    } catch (e) {
      print('[End Session] Error: $e');
      rethrow;
    }
  }
}
