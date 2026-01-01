import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Real-time face detection using BlazeFace TFLite model
/// This is a proper face detection model (not embedding model)
class BlazeFaceDetectionService {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  bool _loggedFormat = false; // Track if we've logged format info

  // BlazeFace typically uses 128x128 input
  static const int inputSize = 128;
  static const int numChannels = 3;

  // Detection confidence threshold
  static const double confidenceThreshold = 0.5;

  Future<void> initialize() async {
    if (_isInitialized) {
      print('[BLAZEFACE] Already initialized');
      return;
    }

    try {
      print('[BLAZEFACE] 🔄 Loading face detection model...');
      print(
          '[BLAZEFACE] 📁 Model path: assets/models/face_detection_back.tflite');

      _interpreter = await Interpreter.fromAsset(
          'assets/models/face_detection_back.tflite');

      print('[BLAZEFACE] ✅ Model loaded successfully');

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      print('[BLAZEFACE] 📐 Input shape: $inputShape');
      print('[BLAZEFACE] 📐 Output shape: $outputShape');

      _isInitialized = true;
      print('[BLAZEFACE] ✅ Initialization complete');
    } catch (e, stackTrace) {
      print('[BLAZEFACE] ❌ Failed to initialize: $e');
      print('[BLAZEFACE] Stack trace: $stackTrace');
      throw Exception('Failed to initialize BlazeFace: $e');
    }
  }

  /// Detect faces from camera image
  Future<BlazeFaceResult> detectFromCamera(CameraImage image) async {
    if (!_isInitialized) {
      throw Exception('BlazeFace not initialized. Call initialize() first.');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Debug: Log image format info (only once)
      if (!_loggedFormat) {
        print(
            '[BLAZEFACE] 📷 Image format: ${image.format.group}, planes: ${image.planes.length}');
        for (int i = 0; i < image.planes.length; i++) {
          print(
              '[BLAZEFACE]   Plane $i: ${image.planes[i].bytes.length} bytes, bytesPerRow: ${image.planes[i].bytesPerRow}');
        }
        _loggedFormat = true;
      }

      // Convert and resize NV21 image to model input
      final input = _convertAndResizeNV21(image, inputSize);
      if (input == null) {
        return BlazeFaceResult(
          hasFace: false,
          confidence: 0.0,
          processingTime: stopwatch.elapsedMilliseconds,
        );
      }

      // Prepare output buffers
      // BlazeFace output format varies by model, typically:
      // - Detection scores
      // - Bounding boxes
      // - Number of detections

      var outputScores = List.filled(1, 0.0).reshape([1, 1]);
      var outputBoxes = List.filled(4, 0.0).reshape([1, 4]);

      // Run inference
      _interpreter!.runForMultipleInputs(
        [
          input.reshape([1, inputSize, inputSize, numChannels])
        ],
        {
          0: outputScores,
          1: outputBoxes,
        },
      );

      stopwatch.stop();

      // Parse results
      final score = (outputScores[0] as List)[0] as double;
      final hasFace = score > confidenceThreshold;

      if (hasFace) {
        final boxes = (outputBoxes[0] as List).cast<double>();
        print(
            '[BLAZEFACE] ✅ Face detected! Score: ${score.toStringAsFixed(3)}, Box: [${boxes.map((b) => b.toStringAsFixed(2)).join(', ')}]');
      }

      print(
          '[BLAZEFACE] Detection in ${stopwatch.elapsedMilliseconds}ms - Face: $hasFace (${(score * 100).toStringAsFixed(1)}%)');

      return BlazeFaceResult(
        hasFace: hasFace,
        confidence: score,
        processingTime: stopwatch.elapsedMilliseconds,
        boundingBox: hasFace ? (outputBoxes[0] as List).cast<double>() : null,
      );
    } catch (e, stackTrace) {
      print('[BLAZEFACE] ❌ Detection error: $e');
      print('[BLAZEFACE] Stack trace: $stackTrace');
      stopwatch.stop();
      return BlazeFaceResult(
        hasFace: false,
        confidence: 0.0,
        processingTime: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  /// Convert NV21 to RGB and resize in one pass
  Float32List? _convertAndResizeNV21(CameraImage image, int targetSize) {
    try {
      final int width = image.width;
      final int height = image.height;

      // Handle different plane configurations
      if (image.planes.isEmpty) {
        print('[BLAZEFACE] ❌ No image planes available');
        return null;
      }

      final yPlane = image.planes[0].bytes;

      // Check if we have separate UV plane or packed data
      Uint8List? uvPlane;
      if (image.planes.length >= 2) {
        uvPlane = image.planes[1].bytes;
      }

      // Pre-allocate output buffer (normalized to 0.0-1.0)
      final output = Float32List(targetSize * targetSize * 3);
      int outputIndex = 0;

      // Calculate stride for downsampling
      final double scaleX = width / targetSize;
      final double scaleY = height / targetSize;

      for (int y = 0; y < targetSize; y++) {
        final int srcY = (y * scaleY).toInt();

        for (int x = 0; x < targetSize; x++) {
          final int srcX = (x * scaleX).toInt();

          // Get Y component
          final int yIndex = srcY * width + srcX;
          if (yIndex >= yPlane.length) continue;

          final int yValue = yPlane[yIndex];

          int r, g, b;

          if (uvPlane != null && uvPlane.isNotEmpty) {
            // NV21 format: Y plane + interleaved VU plane
            // Get UV components (subsampled 2x2)
            final int uvIndex = (srcY ~/ 2) * width + (srcX & ~1);

            if (uvIndex + 1 < uvPlane.length) {
              final int vValue = uvPlane[uvIndex];
              final int uValue = uvPlane[uvIndex + 1];

              // YUV to RGB conversion
              r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
              g = (yValue -
                      0.344136 * (uValue - 128) -
                      0.714136 * (vValue - 128))
                  .clamp(0, 255)
                  .toInt();
              b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();
            } else {
              // Fallback: use Y value as grayscale
              r = g = b = yValue;
            }
          } else {
            // No UV plane: treat as grayscale (just use Y)
            r = g = b = yValue;
          }

          // Normalize to [0, 1] range (common for face detection models)
          output[outputIndex++] = r / 255.0;
          output[outputIndex++] = g / 255.0;
          output[outputIndex++] = b / 255.0;
        }
      }

      return output;
    } catch (e, stackTrace) {
      print('[BLAZEFACE] ❌ Image conversion error: $e');
      print('[BLAZEFACE] Stack: $stackTrace');
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    print('[BLAZEFACE] Service disposed');
  }
}

/// Result from BlazeFace detection
class BlazeFaceResult {
  final bool hasFace;
  final double confidence;
  final int processingTime;
  final List<double>? boundingBox; // [ymin, xmin, ymax, xmax] normalized
  final String? error;

  BlazeFaceResult({
    required this.hasFace,
    required this.confidence,
    required this.processingTime,
    this.boundingBox,
    this.error,
  });

  @override
  String toString() {
    return 'BlazeFaceResult(hasFace: $hasFace, confidence: ${(confidence * 100).toStringAsFixed(1)}%, time: ${processingTime}ms)';
  }
}
