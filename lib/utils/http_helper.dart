import 'dart:convert';
import 'package:http/http.dart' as http;
import './session_manager.dart';
import './error_handler.dart';

/// HTTP Helper with automatic 401 handling
class HttpHelper {
  static final SessionManager _sessionManager = SessionManager();

  /// Make authenticated GET request with 401 handling
  static Future<http.Response> get(
    String url, {
    required String? token,
    Map<String, String>? headers,
  }) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        ...?headers,
      },
    );

    await _handleResponse(response);
    return response;
  }

  /// Make authenticated POST request with 401 handling
  static Future<http.Response> post(
    String url, {
    required String? token,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        ...?headers,
      },
      body: body != null ? jsonEncode(body) : null,
    );

    await _handleResponse(response);
    return response;
  }

  /// Make authenticated PUT request with 401 handling
  static Future<http.Response> put(
    String url, {
    required String? token,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await http.put(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        ...?headers,
      },
      body: body != null ? jsonEncode(body) : null,
    );

    await _handleResponse(response);
    return response;
  }

  /// Make authenticated DELETE request with 401 handling
  static Future<http.Response> delete(
    String url, {
    required String? token,
    Map<String, String>? headers,
  }) async {
    final response = await http.delete(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        ...?headers,
      },
    );

    await _handleResponse(response);
    return response;
  }

  /// Handle response and check for 401
  static Future<void> _handleResponse(http.Response response) async {
    if (response.statusCode == 401) {
      print('[HTTP] 401 Unauthorized - Session expired');

      // Try to parse error message from response
      String? message;
      try {
        final data = jsonDecode(response.body);
        message = data['error'] ?? data['message'];
      } catch (e) {
        message = null;
      }

      // Trigger session expired handler
      await _sessionManager.handleSessionExpired(message: message);

      // Throw exception to stop further processing
      throw Exception(message ?? 'Sesi telah berakhir. Silakan login kembali.');
    }
  }

  /// Get user-friendly error message from response
  static String getErrorMessage(http.Response response) {
    return ErrorHandler.handleHttpError(response);
  }

  /// Parse JSON response with error handling
  static Map<String, dynamic> parseJson(String body) {
    try {
      return jsonDecode(body);
    } catch (e) {
      throw const FormatException('Invalid JSON response');
    }
  }
}
