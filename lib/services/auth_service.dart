import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';

class AuthService {
  String? _accessToken;
  String? _refreshToken;
  User? _currentUser;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _accessToken != null;

  // Initialize - Load saved tokens
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');

    if (_accessToken != null) {
      await getCurrentUser();
    }
  }

  // Login with phone and password
  Future<Map<String, dynamic>> login(String phone, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.authLogin}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        _accessToken = data['accessToken'];
        _refreshToken = data['refreshToken'];
        _currentUser = User.fromJson(data['user']);

        // Save tokens
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _accessToken!);
        await prefs.setString('refresh_token', _refreshToken!);

        return {'success': true, 'user': _currentUser};
      } else {
        final error = jsonDecode(response.body);
        return {'success': false, 'error': error['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Login with face recognition
  Future<Map<String, dynamic>> loginWithFace(List<double> embedding,
      {double? latitude, double? longitude}) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.authLogin}/face'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'embedding': embedding,
          'location_lat': latitude,
          'location_lng': longitude,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        _accessToken = data['accessToken'];
        _refreshToken = data['refreshToken'];
        _currentUser = User.fromJson(data['user']);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _accessToken!);
        await prefs.setString('refresh_token', _refreshToken!);

        return {
          'success': true,
          'user': _currentUser,
          'confidence': data['confidence'],
          'attendance': data['attendance'], // Include attendance data
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['error'] ?? 'Face not recognized'
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Get current user
  Future<void> getCurrentUser() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.authMe}'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode == 200) {
        _currentUser = User.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print('Get user error: $e');
    }
  }

  // Logout
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  // Get auth headers
  Map<String, String> getAuthHeaders() {
    return {
      'Authorization': 'Bearer $_accessToken',
      'Content-Type': 'application/json',
    };
  }
}
