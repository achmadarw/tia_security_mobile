class ApiConfig {
  // Base URL - change this to your backend URL
  static const String baseUrl = 'http://192.168.18.20:3008/api';

  // Auth endpoints
  static const String authLogin = '/auth/login';
  static const String authFaceLogin = '/auth/login/face';
  static const String authRefresh = '/auth/refresh';
  static const String authMe = '/auth/me';

  // Face endpoints
  static const String faceRegister = '/face/register';
  static const String faceRecognize = '/face/recognize';
  static const String faceImages = '/face/images';

  // Attendance endpoints
  static const String attendanceCheckIn = '/attendance/check-in';
  static const String attendanceCheckOut = '/attendance/check-out';
  static const String attendanceToday = '/attendance/today';
  static const String attendanceHistory = '/attendance/history';
  static const String attendanceStats = '/attendance/stats';

  // Report endpoints
  static const String reports = '/reports';
  static const String reportStats = '/reports/stats';

  // User endpoints
  static const String users = '/users';

  // Block endpoints
  static const String blocks = '/blocks';

  // Dashboard endpoints
  static const String dashboardStats = '/dashboard/stats';
  static const String dashboardActivities = '/dashboard/activities';

  // Face Recognition
  static const double faceMatchThreshold = 0.6;
  static const double minFaceConfidence = 0.95;

  // File Upload
  static const int maxFileSize = 5 * 1024 * 1024; // 5MB
}
