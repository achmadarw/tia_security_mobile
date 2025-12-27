import 'dart:io';
import 'package:http/http.dart' as http;

class ErrorHandler {
  /// Convert technical error messages to user-friendly messages
  static String getUserFriendlyMessage(dynamic error) {
    String errorString = error.toString();

    // Network errors
    if (errorString.contains('SocketException') ||
        errorString.contains('No route to host')) {
      return 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.';
    }

    if (errorString.contains('Connection refused')) {
      return 'Server tidak dapat dijangkau. Silakan coba lagi nanti.';
    }

    if (errorString.contains('Connection timed out') ||
        errorString.contains('TimeoutException')) {
      return 'Koneksi timeout. Silakan coba lagi.';
    }

    if (errorString.contains('Failed host lookup')) {
      return 'Server tidak ditemukan. Periksa koneksi internet Anda.';
    }

    // HTTP errors
    if (errorString.contains('401') || errorString.contains('Unauthorized')) {
      return 'Sesi telah berakhir. Silakan login kembali.';
    }

    if (errorString.contains('403') || errorString.contains('Forbidden')) {
      return 'Akses ditolak. Anda tidak memiliki izin.';
    }

    if (errorString.contains('404') || errorString.contains('Not Found')) {
      return 'Data tidak ditemukan.';
    }

    if (errorString.contains('500') ||
        errorString.contains('Internal Server Error')) {
      return 'Terjadi kesalahan pada server. Silakan coba lagi nanti.';
    }

    // Format/Parse errors
    if (errorString.contains('FormatException') ||
        errorString.contains('JSON')) {
      return 'Terjadi kesalahan format data. Silakan coba lagi.';
    }

    // Default fallback
    return 'Terjadi kesalahan. Silakan coba lagi.';
  }

  /// Handle HTTP response errors
  static String handleHttpError(http.Response response) {
    switch (response.statusCode) {
      case 400:
        try {
          final data = response.body;
          return data.isNotEmpty ? data : 'Permintaan tidak valid.';
        } catch (e) {
          return 'Permintaan tidak valid.';
        }
      case 401:
        return 'Sesi telah berakhir. Silakan login kembali.';
      case 403:
        return 'Akses ditolak. Anda tidak memiliki izin.';
      case 404:
        return 'Data tidak ditemukan.';
      case 500:
        return 'Terjadi kesalahan pada server. Silakan coba lagi nanti.';
      case 503:
        return 'Server sedang sibuk. Silakan coba lagi nanti.';
      default:
        return 'Terjadi kesalahan (${response.statusCode}). Silakan coba lagi.';
    }
  }

  /// Get specific error message for face recognition errors
  static String getFaceRecognitionError(String? error) {
    if (error == null) return 'Wajah tidak dikenali.';

    if (error.contains('not found') || error.contains('not recognized')) {
      return 'Wajah tidak dikenali. Pastikan Anda sudah terdaftar.';
    }

    if (error.contains('confidence') || error.contains('threshold')) {
      return 'Wajah tidak cocok. Posisikan wajah dengan jelas di depan kamera.';
    }

    if (error.contains('multiple faces')) {
      return 'Terdeteksi lebih dari satu wajah. Pastikan hanya ada Anda di frame.';
    }

    if (error.contains('no face')) {
      return 'Wajah tidak terdeteksi. Posisikan wajah Anda di dalam frame.';
    }

    return getUserFriendlyMessage(error);
  }

  /// Show user-friendly error in console with original error for debugging
  static void logError(String context, dynamic error,
      {StackTrace? stackTrace}) {
    print('[$context] ERROR: ${getUserFriendlyMessage(error)}');
    print('[$context] Technical details: $error');
    if (stackTrace != null) {
      print('[$context] Stack trace: $stackTrace');
    }
  }
}
