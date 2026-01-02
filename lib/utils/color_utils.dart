import 'dart:math';
import 'package:flutter/material.dart';

/// Utility class for generating color variants from base colors
/// Used for roster shift colors - matches backend/portal algorithm
class ColorUtils {
  /// Parse color from various formats (hex, hsl, rgb) to Color
  static Color parseColor(String? colorString) {
    if (colorString == null || colorString.isEmpty) {
      return const Color(0xFF6B7280); // Gray default
    }

    final color = colorString.trim();

    // Already hex format
    if (color.startsWith('#')) {
      return _hexToColor(color);
    }

    // HSL format: hsl(85, 70%, 50%)
    if (color.startsWith('hsl')) {
      final match =
          RegExp(r'hsl\((\d+),\s*([\d.]+)%,\s*([\d.]+)%\)').firstMatch(color);
      if (match != null) {
        final h = int.parse(match.group(1)!);
        final s = double.parse(match.group(2)!) / 100;
        final l = double.parse(match.group(3)!) / 100;
        return _hslToColor(h, s, l);
      }
    }

    // RGB format: rgb(255, 0, 0)
    if (color.startsWith('rgb')) {
      final match = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(color);
      if (match != null) {
        final r = int.parse(match.group(1)!);
        final g = int.parse(match.group(2)!);
        final b = int.parse(match.group(3)!);
        return Color.fromARGB(255, r, g, b);
      }
    }

    // Fallback: try to parse as hex without #
    return _hexToColor('#$color');
  }

  /// Convert hex string to Color
  static Color _hexToColor(String hex) {
    try {
      final hexColor = hex.replaceAll('#', '');
      return Color(int.parse('0xFF$hexColor'));
    } catch (e) {
      return const Color(0xFF6B7280); // Gray fallback
    }
  }

  /// Convert HSL to Color
  static Color _hslToColor(int h, double s, double l) {
    final a = s * min(l, 1 - l);

    double f(int n) {
      final k = (n + h / 30) % 12;
      final color = l - a * max(min(k - 3, min(9 - k, 1)), -1);
      return (255 * color).round().toDouble();
    }

    return Color.fromARGB(
      255,
      f(0).toInt(),
      f(8).toInt(),
      f(4).toInt(),
    );
  }

  /// Generate lighter/darker color variants for backgrounds, borders and text
  /// Same algorithm as backend PDF template for consistency
  static ColorVariants generateColorVariants(Color baseColor) {
    final r = baseColor.red;
    final g = baseColor.green;
    final b = baseColor.blue;

    // Generate lighter background: blend 55% white + 45% base color
    final bgR = (r * 0.45 + 255 * 0.55).round();
    final bgG = (g * 0.45 + 255 * 0.55).round();
    final bgB = (b * 0.45 + 255 * 0.55).round();
    final bg = Color.fromARGB(255, bgR, bgG, bgB);

    // Generate stronger border: blend 20% white + 80% base color
    final borderR = (r * 0.8 + 255 * 0.2).round();
    final borderG = (g * 0.8 + 255 * 0.2).round();
    final borderB = (b * 0.8 + 255 * 0.2).round();
    final border = Color.fromARGB(255, borderR, borderG, borderB);

    // Generate darker text: reduce brightness by 65%
    final textR = (r * 0.35).round();
    final textG = (g * 0.35).round();
    final textB = (b * 0.35).round();
    final text = Color.fromARGB(255, textR, textG, textB);

    return ColorVariants(bg: bg, border: border, text: text);
  }

  /// Get color variants for a shift color string
  /// Handles both parsing and variant generation
  static ColorVariants getShiftColorVariants(String? colorString) {
    final baseColor = parseColor(colorString);
    return generateColorVariants(baseColor);
  }
}

/// Color variants for shift display
class ColorVariants {
  final Color bg;
  final Color border;
  final Color text;

  ColorVariants({
    required this.bg,
    required this.border,
    required this.text,
  });
}
