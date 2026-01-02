import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Validation result with detailed feedback
class ValidationResult {
  final bool isValid;
  final Map<String, bool> checks;
  final Map<String, double> metrics;
  final String? failureReason;

  ValidationResult({
    required this.isValid,
    required this.checks,
    required this.metrics,
    this.failureReason,
  });

  /// Get user-friendly failure message
  String getFailureMessage() {
    if (isValid) return 'Image quality is good';

    if (failureReason != null) return failureReason!;

    final failedChecks =
        checks.entries.where((e) => !e.value).map((e) => e.key).toList();

    if (failedChecks.isEmpty) return 'Unknown quality issue';

    // Generate user-friendly messages
    if (failedChecks.contains('brightness')) {
      final brightness = metrics['brightness'] ?? 0;
      if (brightness < ImageQualityValidator.minBrightness) {
        return 'Gambar terlalu gelap. Coba di tempat yang lebih terang.';
      } else {
        return 'Gambar terlalu terang. Hindari cahaya langsung.';
      }
    }

    if (failedChecks.contains('blur')) {
      return 'Gambar tidak fokus. Pegang kamera dengan stabil.';
    }

    if (failedChecks.contains('contrast')) {
      return 'Kontras gambar kurang. Gunakan latar belakang yang berbeda.';
    }

    if (failedChecks.contains('pose')) {
      return 'Posisi wajah terlalu miring. Hadap langsung ke kamera.';
    }

    if (failedChecks.contains('size')) {
      return 'Wajah terlalu kecil. Dekatkan kamera ke wajah.';
    }

    return 'Kualitas gambar kurang baik. Coba lagi.';
  }
}

/// Image Quality Validator
///
/// Validates face image quality for reliable embedding generation.
/// Checks blur, brightness, contrast, and face pose.
///
/// Performance: <30ms per image
class ImageQualityValidator {
  // Quality thresholds
  static const double minBrightness = 30.0; // 0-255 scale (lebih toleran)
  static const double maxBrightness =
      230.0; // Lebih toleran untuk cahaya terang
  static const double minContrast =
      15.0; // Standard deviation (dikurangi dari 30 → 15)
  static const double maxBlurScore = 100.0; // Laplacian variance
  static const double maxHeadEulerY = 25.0; // degrees (yaw) - lebih toleran
  static const double maxHeadEulerZ = 20.0; // degrees (roll) - lebih toleran
  static const double minFaceSize =
      60.0; // pixels (min width/height) - lebih kecil OK

  /// Validate face image quality
  ///
  /// Performs comprehensive quality checks:
  /// - Brightness (not too dark/bright)
  /// - Blur detection (sharp focus)
  /// - Contrast (sufficient detail)
  /// - Face pose (frontal view)
  /// - Face size (sufficient resolution)
  ///
  /// [isStrictMode] = true untuk registration (quality tinggi required)
  ///               = false untuk login (lebih toleran)
  Future<ValidationResult> validateImage(
    img.Image faceImage,
    Face? face, {
    bool isStrictMode = true, // Default strict untuk registration
  }) async {
    final checks = <String, bool>{};
    final metrics = <String, double>{};

    // Adjust thresholds based on mode
    final minContrastThreshold =
        isStrictMode ? minContrast : minContrast * 0.6; // Login: 9.0
    final minBrightnessThreshold =
        isStrictMode ? minBrightness : minBrightness * 0.8; // Login: 24.0

    try {
      // 1. Check brightness
      final brightness = _calculateBrightness(faceImage);
      metrics['brightness'] = brightness;
      checks['brightness'] =
          brightness >= minBrightnessThreshold && brightness <= maxBrightness;

      // 2. Check blur
      final blurScore = await _calculateBlurScore(faceImage);
      metrics['blur'] = blurScore;
      checks['blur'] = blurScore >= maxBlurScore;

      // 3. Check contrast
      final contrast = _calculateContrast(faceImage);
      metrics['contrast'] = contrast;
      checks['contrast'] =
          contrast >= minContrastThreshold; // Use adjusted threshold

      // 4. Check face pose (if face data available)
      if (face != null) {
        final poseValid = _checkFacePose(face, isStrictMode: isStrictMode);
        checks['pose'] = poseValid;

        // Store pose angles for debugging
        if (face.headEulerAngleY != null) {
          metrics['yaw'] = face.headEulerAngleY!.abs();
        }
        if (face.headEulerAngleZ != null) {
          metrics['roll'] = face.headEulerAngleZ!.abs();
        }

        // Check face size
        final boundingBox = face.boundingBox;
        final faceSize = math.min(boundingBox.width, boundingBox.height);
        metrics['faceSize'] = faceSize;
        checks['size'] = faceSize >= minFaceSize;
      } else {
        checks['pose'] = true; // Skip pose check if no face data
        checks['size'] = true; // Skip size check if no face data
      }

      // Determine overall validity
      final isValid = checks.values.every((check) => check);

      // Generate failure reason if invalid
      String? failureReason;
      if (!isValid) {
        failureReason = ValidationResult(
          isValid: false,
          checks: checks,
          metrics: metrics,
        ).getFailureMessage();
      }

      print('[ImageQuality] Validation result: $isValid');
      print('[ImageQuality] Checks: $checks');
      print('[ImageQuality] Metrics: $metrics');

      return ValidationResult(
        isValid: isValid,
        checks: checks,
        metrics: metrics,
        failureReason: failureReason,
      );
    } catch (e, stackTrace) {
      print('[ImageQuality] ❌ Validation error: $e');
      print(stackTrace);
      return ValidationResult(
        isValid: false,
        checks: checks,
        metrics: metrics,
        failureReason: 'Error validating image quality',
      );
    }
  }

  /// Calculate average brightness (0-255)
  double _calculateBrightness(img.Image image) {
    double totalBrightness = 0;
    final pixels = image.width * image.height;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Calculate perceived brightness using standard formula
        // 0.299*R + 0.587*G + 0.114*B (human eye perception weights)
        final brightness = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        totalBrightness += brightness;
      }
    }

    return totalBrightness / pixels;
  }

  /// Calculate blur score using Laplacian variance
  ///
  /// Higher score = sharper image
  /// Lower score = more blur
  Future<double> _calculateBlurScore(img.Image image) async {
    // Convert to grayscale for faster processing
    final gray = img.grayscale(image);

    // Apply Laplacian filter to detect edges
    // Laplacian kernel: [[0, 1, 0], [1, -4, 1], [0, 1, 0]]
    double totalVariance = 0;
    int count = 0;

    for (int y = 1; y < gray.height - 1; y++) {
      for (int x = 1; x < gray.width - 1; x++) {
        final center = gray.getPixel(x, y).r;
        final top = gray.getPixel(x, y - 1).r;
        final bottom = gray.getPixel(x, y + 1).r;
        final left = gray.getPixel(x - 1, y).r;
        final right = gray.getPixel(x + 1, y).r;

        // Laplacian response
        final laplacian = (top + bottom + left + right - 4 * center).abs();
        totalVariance += laplacian * laplacian;
        count++;
      }
    }

    // Return variance (higher = sharper)
    return totalVariance / count;
  }

  /// Calculate image contrast (standard deviation of brightness)
  double _calculateContrast(img.Image image) {
    // Calculate mean brightness first
    final mean = _calculateBrightness(image);

    // Calculate variance
    double variance = 0;
    final pixels = image.width * image.height;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final brightness = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        final diff = brightness - mean;
        variance += diff * diff;
      }
    }

    // Return standard deviation (higher = more contrast)
    return math.sqrt(variance / pixels);
  }

  /// Check if face pose is frontal (not too tilted)
  bool _checkFacePose(Face face, {bool isStrictMode = true}) {
    final maxYaw =
        isStrictMode ? maxHeadEulerY : maxHeadEulerY * 1.5; // Login: 37.5°
    final maxRoll =
        isStrictMode ? maxHeadEulerZ : maxHeadEulerZ * 1.5; // Login: 30°

    // Check yaw (left-right rotation)
    final yaw = face.headEulerAngleY?.abs() ?? 0;
    if (yaw > maxYaw) {
      print(
          '[ImageQuality] ⚠️ Yaw angle too large: ${yaw.toStringAsFixed(1)}° (max: ${maxYaw.toStringAsFixed(1)}°)');
      return false;
    }

    // Check roll (head tilt)
    final roll = face.headEulerAngleZ?.abs() ?? 0;
    if (roll > maxRoll) {
      print(
          '[ImageQuality] ⚠️ Roll angle too large: ${roll.toStringAsFixed(1)}° (max: ${maxRoll.toStringAsFixed(1)}°)');
      return false;
    }

    return true;
  }

  /// Quick brightness check (for real-time preview feedback)
  bool isWellLit(img.Image image) {
    final brightness = _calculateBrightness(image);
    return brightness >= minBrightness && brightness <= maxBrightness;
  }

  /// Quick blur check (for real-time preview feedback)
  Future<bool> isSharp(img.Image image) async {
    final blurScore = await _calculateBlurScore(image);
    return blurScore >= maxBlurScore;
  }

  /// Get quality score (0-100)
  ///
  /// Useful for showing quality indicator to user
  Future<double> getQualityScore(img.Image faceImage, Face? face) async {
    final result = await validateImage(faceImage, face);

    double score = 0;
    final totalChecks = result.checks.length;

    for (final check in result.checks.values) {
      if (check) score += 100 / totalChecks;
    }

    return score;
  }
}
