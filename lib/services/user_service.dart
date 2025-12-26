import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';

class UserService {
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Get all users
  Future<List<User>> getUsers() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.users}'),
        headers: headers,
      );

      print('Get users response status: ${response.statusCode}');
      print('Get users response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Handle different response structures
        List<dynamic> usersJson;
        if (data is Map<String, dynamic> && data.containsKey('data')) {
          usersJson = data['data'];
        } else if (data is List) {
          usersJson = data;
        } else {
          throw Exception('Unexpected response format');
        }

        return usersJson.map((json) => User.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load users: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getUsers: $e');
      throw Exception('Error loading users: $e');
    }
  }

  /// Get user by ID
  Future<User> getUserById(int userId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.users}/$userId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return User.fromJson(data['data']);
      } else {
        throw Exception('Failed to load user: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading user: $e');
    }
  }

  /// Create new user
  Future<User> createUser({
    required String name,
    required String phone,
    required String password,
    String? email,
    required String role,
    int? departmentId,
    int? shiftId,
  }) async {
    try {
      final headers = await _getHeaders();
      final body = {
        'name': name,
        'phone': phone,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
        'role': role,
        if (departmentId != null) 'department_id': departmentId,
        if (shiftId != null) 'shift_id': shiftId,
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.users}'),
        headers: headers,
        body: json.encode(body),
      );

      print('Create user response status: ${response.statusCode}');
      print('Create user response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);

        // Handle different response structures
        if (data is Map<String, dynamic>) {
          // If response has 'data' field
          if (data.containsKey('data') && data['data'] != null) {
            return User.fromJson(data['data']);
          }
          // If response is the user object directly
          else if (data.containsKey('id')) {
            return User.fromJson(data);
          }
        }

        throw Exception('Invalid response format');
      } else {
        final error = json.decode(response.body);
        throw Exception(
            error['error'] ?? error['message'] ?? 'Failed to create user');
      }
    } catch (e) {
      throw Exception('Error creating user: $e');
    }
  }

  /// Update user
  Future<User> updateUser({
    required int userId,
    String? name,
    String? phone,
    String? email,
    String? role,
    int? departmentId,
    int? shiftId,
    String? password,
  }) async {
    try {
      final headers = await _getHeaders();
      final body = <String, dynamic>{};

      if (name != null) body['name'] = name;
      if (phone != null) body['phone'] = phone;
      if (email != null) body['email'] = email;
      if (role != null) body['role'] = role;
      if (departmentId != null) body['department_id'] = departmentId;
      if (shiftId != null) body['shift_id'] = shiftId;
      if (password != null && password.isNotEmpty) body['password'] = password;

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.users}/$userId'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return User.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to update user');
      }
    } catch (e) {
      throw Exception('Error updating user: $e');
    }
  }

  /// Delete user
  Future<void> deleteUser(int userId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.users}/$userId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to delete user');
      }
    } catch (e) {
      throw Exception('Error deleting user: $e');
    }
  }

  /// Register face images for user
  Future<Map<String, dynamic>> registerFaceImages({
    required int userId,
    required List<File> images,
    List<List<double>>? embeddings,
    Function(int, int)? onProgress,
  }) async {
    try {
      print('[UserService] Registering face images for user: $userId');
      print('[UserService] Number of images: ${images.length}');
      print('[UserService] Number of embeddings: ${embeddings?.length ?? 0}');

      final token = await _getToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faceRegister}'),
      );

      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['user_id'] = userId.toString();

      // Add embeddings if provided
      if (embeddings != null && embeddings.isNotEmpty) {
        request.fields['embeddings'] = json.encode(embeddings);
        print('[UserService] Embeddings added to request');
      }

      // Add images
      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        // Extract filename from path (already renamed with descriptive format)
        final filename = image.path.split('/').last;
        final multipartFile = await http.MultipartFile.fromPath(
          'images',
          image.path,
          contentType: MediaType('image', 'jpeg'),
          filename: filename, // Use custom filename
        );
        request.files.add(multipartFile);

        // Progress callback for preparing files
        if (onProgress != null) {
          onProgress(i + 1, images.length);
        }
      }

      print(
          '[UserService] Sending request to: ${ApiConfig.baseUrl}${ApiConfig.faceRegister}');
      final streamedResponse = await request.send();

      print(
          '[UserService] Response status code: ${streamedResponse.statusCode}');
      final response = await http.Response.fromStream(streamedResponse);

      print('[UserService] Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = json.decode(response.body);
        print('[UserService] Success: $result');
        return result;
      } else {
        final error = json.decode(response.body);
        print('[UserService] Error response: $error');
        throw Exception(error['message'] ??
            error['error'] ??
            'Failed to register face images');
      }
    } catch (e) {
      print('[UserService] Exception: $e');
      throw Exception('Error registering face images: $e');
    }
  }

  /// Get user's face images count
  Future<int> getFaceImagesCount(int userId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.users}/$userId/face-images'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data']['count'] ?? 0;
      } else {
        return 0;
      }
    } catch (e) {
      return 0;
    }
  }
}
