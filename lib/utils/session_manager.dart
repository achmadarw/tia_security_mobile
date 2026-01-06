import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';

/// Session Manager for handling token expiration globally
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  BuildContext? _context;
  AuthService? _authService;
  bool _isSessionExpiredDialogShown = false;

  /// Register app context for navigation
  void setContext(BuildContext context, {AuthService? authService}) {
    _context = context;
    _authService = authService;
  }

  /// Handle session expiration - show dialog and redirect to login
  Future<void> handleSessionExpired({String? message}) async {
    if (_context == null || _isSessionExpiredDialogShown) return;

    _isSessionExpiredDialogShown = true;

    await showDialog(
      context: _context!,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text(
              'Sesi Berakhir',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message ??
              'Sesi Anda telah berakhir. Silakan login kembali untuk melanjutkan.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _redirectToLogin(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Login Kembali', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  /// Handle session expired silently (no dialog, direct redirect)
  Future<void> handleSessionExpiredSilent() async {
    if (_context == null) return;
    _redirectToLogin(_context!);
  }

  /// Redirect to login screen and clear navigation stack
  void _redirectToLogin(BuildContext context) {
    _isSessionExpiredDialogShown = false;

    // Create new AuthService instance if not provided
    final authService = _authService ?? AuthService();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => LoginScreen(authService: authService),
      ),
      (route) => false, // Remove all previous routes
    );
  }

  /// Reset dialog state (call when user successfully logs in again)
  void reset() {
    _isSessionExpiredDialogShown = false;
  }

  /// Check if should show warning before expiry (for future implementation)
  bool shouldShowExpiryWarning(DateTime? expiryTime) {
    if (expiryTime == null) return false;
    final now = DateTime.now();
    final timeUntilExpiry = expiryTime.difference(now);
    return timeUntilExpiry.inMinutes <= 5 && timeUntilExpiry.inMinutes > 0;
  }
}
