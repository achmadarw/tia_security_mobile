import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Reusable Toast Utility
/// Modern, beautiful, and user-friendly toast messages
class AppToast {
  static FToast? _fToast;

  /// Initialize toast (call in build or initState)
  static void init(BuildContext context) {
    _fToast = FToast();
    _fToast!.init(context);
  }

  /// Show success toast with green theme
  static void success(String message, {int durationSeconds = 3}) {
    _showCustomToast(
      message: message,
      icon: Icons.check_circle,
      backgroundColor: const Color(0xFF2ECC71),
      iconColor: Colors.white,
      durationSeconds: durationSeconds,
    );
  }

  /// Show error toast with red theme
  static void error(String message, {int durationSeconds = 4}) {
    _showCustomToast(
      message: message,
      icon: Icons.error,
      backgroundColor: const Color(0xFFE74C3C),
      iconColor: Colors.white,
      durationSeconds: durationSeconds,
    );
  }

  /// Show warning toast with orange theme
  static void warning(String message, {int durationSeconds = 3}) {
    _showCustomToast(
      message: message,
      icon: Icons.warning_amber_rounded,
      backgroundColor: const Color(0xFFF39C12),
      iconColor: Colors.white,
      durationSeconds: durationSeconds,
    );
  }

  /// Show info toast with blue theme
  static void info(String message, {int durationSeconds = 3}) {
    _showCustomToast(
      message: message,
      icon: Icons.info,
      backgroundColor: const Color(0xFF3498DB),
      iconColor: Colors.white,
      durationSeconds: durationSeconds,
    );
  }

  /// Internal method to show custom toast
  static void _showCustomToast({
    required String message,
    required IconData icon,
    required Color backgroundColor,
    required Color iconColor,
    required int durationSeconds,
  }) {
    if (_fToast == null) {
      // Fallback to fluttertoast if FToast not initialized
      Fluttertoast.showToast(
        msg: message,
        toastLength:
            durationSeconds > 3 ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: backgroundColor,
        textColor: Colors.white,
        fontSize: 14.0,
      );
      return;
    }

    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
      margin: const EdgeInsets.only(top: 100.0), // Below header
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.0),
        color: backgroundColor,
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.4),
            blurRadius: 16.0,
            offset: const Offset(0, 6),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20.0,
            ),
          ),
          const SizedBox(width: 12.0),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.0,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    _fToast!.showToast(
      child: toast,
      gravity: ToastGravity.TOP,
      toastDuration: Duration(seconds: durationSeconds),
    );
  }

  /// Cancel all active toasts
  static void cancelAll() {
    _fToast?.removeCustomToast();
  }

  /// Quick static methods (no init required) - uses default Fluttertoast
  static void quickSuccess(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: const Color(0xFF2ECC71),
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  static void quickError(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: const Color(0xFFE74C3C),
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  static void quickWarning(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: const Color(0xFFF39C12),
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  static void quickInfo(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: const Color(0xFF3498DB),
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }
}
