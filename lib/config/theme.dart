import 'package:flutter/material.dart';

/// Theme optimized for security guards (night shift workers, age 50+)
///
/// Design principles:
/// 1. High contrast for better readability (WCAG AAA: 7:1)
/// 2. Larger fonts (minimum 16sp) for older users
/// 3. No gradients - solid colors only
/// 4. Dark mode for night shift workers
/// 5. Simple, professional design
class AppColors {
  // ========== LIGHT MODE COLORS ==========

  // Primary Colors - Professional Blue (high contrast)
  static const Color lightPrimary =
      Color(0xFF0D47A1); // Dark Blue (better than bright blue)
  static const Color lightPrimaryLight = Color(0xFF1976D2);
  static const Color lightPrimaryDark = Color(0xFF01579B);
  static const Color lightAccent = Color(0xFF2E7D32); // Green for success

  // Background & Surface (Light Mode)
  static const Color lightBackground =
      Color(0xFFFAFAFA); // Off-white (easier on eyes than pure white)
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF5F5F5);
  static const Color lightCard = Color(0xFFFFFFFF);

  // Text Colors (Light Mode) - High contrast
  static const Color lightTextPrimary = Color(0xFF1A1A1A); // Almost black
  static const Color lightTextSecondary = Color(0xFF616161); // Dark gray
  static const Color lightTextTertiary = Color(0xFF9E9E9E); // Medium gray
  static const Color lightTextOnPrimary = Color(0xFFFFFFFF); // White on primary

  // ========== DARK MODE COLORS ==========

  // Primary Colors (Dark Mode) - Muted for night viewing
  static const Color darkPrimary =
      Color(0xFF42A5F5); // Lighter blue for dark bg
  static const Color darkPrimaryLight = Color(0xFF64B5F6);
  static const Color darkPrimaryDark = Color(0xFF2196F3);
  static const Color darkAccent = Color(0xFF66BB6A); // Light green

  // Background & Surface (Dark Mode) - Material Design dark theme
  static const Color darkBackground = Color(0xFF121212); // True dark
  static const Color darkSurface = Color(0xFF1E1E1E); // Elevated surface
  static const Color darkSurfaceVariant = Color(0xFF2C2C2C); // Higher elevation
  static const Color darkCard = Color(0xFF252525);

  // Text Colors (Dark Mode) - Muted whites to reduce eye strain
  static const Color darkTextPrimary = Color(0xFFE1E1E1); // Off-white
  static const Color darkTextSecondary = Color(0xFFB0B0B0); // Light gray
  static const Color darkTextTertiary = Color(0xFF808080); // Medium gray
  static const Color darkTextOnPrimary =
      Color(0xFF000000); // Black on light primary

  // ========== STATUS COLORS (Same for both modes) ==========
  static const Color success = Color(0xFF2E7D32); // Green
  static const Color warning = Color(0xFFF57C00); // Orange
  static const Color error = Color(0xFFC62828); // Red
  static const Color info = Color(0xFF1976D2); // Blue

  // Status colors for dark mode (lighter versions)
  static const Color successDark = Color(0xFF66BB6A);
  static const Color warningDark = Color(0xFFFFB74D);
  static const Color errorDark = Color(0xFFEF5350);
  static const Color infoDark = Color(0xFF42A5F5);

  // ========== FUNCTIONAL COLORS ==========
  static const Color dividerLight = Color(0xFFE0E0E0);
  static const Color dividerDark = Color(0xFF3A3A3A);

  static const Color borderLight = Color(0xFFBDBDBD);
  static const Color borderDark = Color(0xFF424242);

  // ========== LEGACY SUPPORT (for backward compatibility) ==========
  static const Color primary = lightPrimary;
  static const Color secondary = lightAccent;
  static const Color background = lightBackground;
  static const Color surface = lightSurface;
  static const Color textPrimary = lightTextPrimary;
  static const Color textSecondary = lightTextSecondary;
  static const Color divider = dividerLight;
}

class AppTheme {
  // ========== TEXT THEME (Larger fonts for 50+ age group) ==========
  static TextTheme _buildTextTheme(Color primaryColor, Color secondaryColor) {
    return TextTheme(
      // Display styles - Extra large
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: primaryColor,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: primaryColor,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: primaryColor,
      ),

      // Headline styles - Headers
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: primaryColor,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primaryColor,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: primaryColor,
      ),

      // Title styles
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primaryColor,
        letterSpacing: 0.15,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: primaryColor,
      ),
      titleSmall: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),

      // Body styles - Main content (16sp minimum for readability)
      bodyLarge: TextStyle(
        fontSize: 18, // Larger than standard (16sp) for older users
        fontWeight: FontWeight.normal,
        color: primaryColor,
        height: 1.5, // Better line spacing
      ),
      bodyMedium: TextStyle(
        fontSize: 16, // Minimum readable size
        fontWeight: FontWeight.normal,
        color: primaryColor,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: secondaryColor,
        height: 1.4,
      ),

      // Label styles - Buttons, chips
      labelLarge: const TextStyle(
        fontSize: 16, // Larger button text
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      labelMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
        letterSpacing: 0.5,
      ),
    );
  }

  // ========== LIGHT THEME ==========
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    // Color scheme
    colorScheme: ColorScheme.light(
      primary: AppColors.lightPrimary,
      primaryContainer: AppColors.lightPrimaryLight,
      onPrimary: AppColors.lightTextOnPrimary,
      secondary: AppColors.lightAccent,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      surfaceContainerHighest: AppColors.lightSurfaceVariant,
      outline: AppColors.borderLight,
    ),

    // Background
    scaffoldBackgroundColor: AppColors.lightBackground,

    // Text theme
    textTheme: _buildTextTheme(
      AppColors.lightTextPrimary,
      AppColors.lightTextSecondary,
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.lightPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 0.15,
      ),
      iconTheme: const IconThemeData(
        color: Colors.white,
        size: 26, // Larger icons
      ),
    ),

    // Card
    cardTheme: CardTheme(
      elevation: 2,
      color: AppColors.lightCard,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(8),
    ),

    // Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.lightPrimary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
            horizontal: 32, vertical: 18), // Larger touch targets
        minimumSize:
            const Size(120, 52), // Minimum button size (48dp + padding)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        elevation: 2,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.lightPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        minimumSize: const Size(120, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(color: AppColors.lightPrimary, width: 2),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.lightPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Icon theme
    iconTheme: IconThemeData(
      color: AppColors.lightTextPrimary,
      size: 26, // Larger icons for better visibility
    ),

    // Input decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderLight, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderLight, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightPrimary, width: 2.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 2.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: TextStyle(
        fontSize: 16,
        color: AppColors.lightTextSecondary,
      ),
      hintStyle: TextStyle(
        fontSize: 16,
        color: AppColors.lightTextTertiary,
      ),
    ),

    // Divider
    dividerTheme: DividerThemeData(
      color: AppColors.dividerLight,
      thickness: 1,
      space: 16,
    ),

    // Bottom Navigation Bar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.lightSurface,
      selectedItemColor: AppColors.lightPrimary,
      unselectedItemColor: AppColors.lightTextSecondary,
      selectedIconTheme: const IconThemeData(size: 28),
      unselectedIconTheme: const IconThemeData(size: 26),
      selectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
      ),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
  );

  // ========== DARK THEME (For Night Shift Workers) ==========
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    // Color scheme
    colorScheme: ColorScheme.dark(
      primary: AppColors.darkPrimary,
      primaryContainer: AppColors.darkPrimaryDark,
      onPrimary: AppColors.darkTextOnPrimary,
      secondary: AppColors.darkAccent,
      onSecondary: Colors.black,
      error: AppColors.errorDark,
      onError: Colors.black,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      surfaceContainerHighest: AppColors.darkSurfaceVariant,
      outline: AppColors.borderDark,
    ),

    // Background
    scaffoldBackgroundColor: AppColors.darkBackground,

    // Text theme
    textTheme: _buildTextTheme(
      AppColors.darkTextPrimary,
      AppColors.darkTextSecondary,
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.darkTextPrimary,
        letterSpacing: 0.15,
      ),
      iconTheme: IconThemeData(
        color: AppColors.darkTextPrimary,
        size: 26,
      ),
    ),

    // Card
    cardTheme: CardTheme(
      elevation: 4,
      color: AppColors.darkCard,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(8),
    ),

    // Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.darkPrimary,
        foregroundColor: AppColors.darkTextOnPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        minimumSize: const Size(120, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        elevation: 4,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.darkPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        minimumSize: const Size(120, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(color: AppColors.darkPrimary, width: 2),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.darkPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Icon theme
    iconTheme: IconThemeData(
      color: AppColors.darkTextPrimary,
      size: 26,
    ),

    // Input decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderDark, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderDark, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.darkPrimary, width: 2.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.errorDark, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.errorDark, width: 2.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: TextStyle(
        fontSize: 16,
        color: AppColors.darkTextSecondary,
      ),
      hintStyle: TextStyle(
        fontSize: 16,
        color: AppColors.darkTextTertiary,
      ),
    ),

    // Divider
    dividerTheme: DividerThemeData(
      color: AppColors.dividerDark,
      thickness: 1,
      space: 16,
    ),

    // Bottom Navigation Bar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      selectedItemColor: AppColors.darkPrimary,
      unselectedItemColor: AppColors.darkTextSecondary,
      selectedIconTheme: const IconThemeData(size: 28),
      unselectedIconTheme: const IconThemeData(size: 26),
      selectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
      ),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
  );
}
