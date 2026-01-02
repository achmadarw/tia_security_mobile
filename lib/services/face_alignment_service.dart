import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Face Alignment Service
///
/// Aligns detected faces to frontal position using eye landmarks.
/// This significantly improves embedding consistency by normalizing
/// face orientation before feature extraction.
///
/// Performance: <50ms per image
class FaceAlignmentService {
  /// Minimum rotation angle to perform alignment (degrees)
  /// Rotations smaller than this are skipped to avoid unnecessary processing
  static const double minRotationThreshold = 2.0;

  /// Align face image to frontal position
  ///
  /// Uses eye landmarks to calculate rotation angle and corrects
  /// the face orientation to have eyes on a horizontal line.
  ///
  /// Returns:
  /// - Aligned image if alignment successful
  /// - Original image if eyes not detected or angle too small
  /// - null if alignment fails critically
  Future<img.Image?> alignFace(img.Image faceImage, Face face) async {
    try {
      // Get eye landmarks from ML Kit detection
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];

      // Check if both eyes are detected
      if (leftEye == null || rightEye == null) {
        print('[FaceAlignment] ⚠️ Eyes not detected, skipping alignment');
        return faceImage; // Return original if eyes not found
      }

      // Calculate rotation angle between eyes
      final angle = _calculateEyeAngle(leftEye, rightEye);

      // Skip alignment if angle is negligible (< 2 degrees)
      // This avoids unnecessary processing and potential quality loss
      if (angle.abs() < minRotationThreshold) {
        print(
            '[FaceAlignment] ℹ️ Angle ${angle.toStringAsFixed(2)}° < threshold, no rotation needed');
        return faceImage;
      }

      // Rotate image to align eyes horizontally
      // Negative angle because we want to counter-rotate
      final aligned = img.copyRotate(faceImage, angle: -angle);

      print(
          '[FaceAlignment] ✅ Face aligned, rotated by ${angle.toStringAsFixed(2)}°');
      return aligned;
    } catch (e, stackTrace) {
      print('[FaceAlignment] ❌ Alignment error: $e');
      print(stackTrace);
      return faceImage; // Fallback to original on error
    }
  }

  /// Calculate angle between two eyes in degrees
  ///
  /// Uses arctangent to determine the tilt angle of the line
  /// connecting the two eyes. Positive angle means right eye is higher.
  ///
  /// Returns: Angle in degrees (-180 to 180)
  double _calculateEyeAngle(FaceLandmark leftEye, FaceLandmark rightEye) {
    // Calculate deltas
    final deltaY = rightEye.position.y - leftEye.position.y;
    final deltaX = rightEye.position.x - leftEye.position.x;

    // Calculate angle in radians using atan2
    // atan2 handles all quadrants correctly
    final angleRad = math.atan2(deltaY, deltaX);

    // Convert to degrees
    return angleRad * 180 / math.pi;
  }

  /// Align multiple faces in an image (batch processing)
  ///
  /// Useful for group photos or when multiple faces detected.
  /// Aligns all faces to the average angle.
  Future<img.Image?> alignMultipleFaces(
    img.Image image,
    List<Face> faces,
  ) async {
    if (faces.isEmpty) return image;

    try {
      // Calculate average angle from all faces
      double totalAngle = 0;
      int validFaces = 0;

      for (final face in faces) {
        final leftEye = face.landmarks[FaceLandmarkType.leftEye];
        final rightEye = face.landmarks[FaceLandmarkType.rightEye];

        if (leftEye != null && rightEye != null) {
          totalAngle += _calculateEyeAngle(leftEye, rightEye);
          validFaces++;
        }
      }

      if (validFaces == 0) {
        print('[FaceAlignment] No valid faces for alignment');
        return image;
      }

      // Calculate average angle
      final avgAngle = totalAngle / validFaces;

      if (avgAngle.abs() < minRotationThreshold) {
        return image;
      }

      // Rotate entire image by average angle
      final aligned = img.copyRotate(image, angle: -avgAngle);

      print(
          '[FaceAlignment] ✅ Aligned $validFaces faces by ${avgAngle.toStringAsFixed(2)}°');
      return aligned;
    } catch (e) {
      print('[FaceAlignment] ❌ Multi-face alignment error: $e');
      return image;
    }
  }

  /// Check if face needs alignment
  ///
  /// Returns true if rotation angle exceeds threshold
  bool needsAlignment(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];

    if (leftEye == null || rightEye == null) return false;

    final angle = _calculateEyeAngle(leftEye, rightEye);
    return angle.abs() >= minRotationThreshold;
  }

  /// Get rotation angle for a face (for debugging/metrics)
  double? getRotationAngle(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];

    if (leftEye == null || rightEye == null) return null;

    return _calculateEyeAngle(leftEye, rightEye);
  }
}
