import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// High-performance face detection using TFLite
/// Processes camera frames directly without disk I/O
class TFLiteFaceDetectionService {
  Interpreter? _interpreter;
  bool _isInitialized = false;

  // Model input/output shapes (dynamically set after loading)
  int inputSize = 112; // Default, will be updated from model
  int outputSize = 192; // Default, will be updated from model
  static const int numChannels = 3;

  Future<void> initialize() async {
    if (_isInitialized) {
      print('[TFLITE] Already initialized');
      return;
    }

    try {
      print('[TFLITE] 🔄 Loading face detection model...');
      print('[TFLITE] 📁 Model path: assets/models/mobilefacenet.tflite');

      // Load model from assets
      _interpreter =
          await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');

      print('[TFLITE] ✅ Model loaded successfully');

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      print('[TFLITE] 📐 Input shape: $inputShape');
      print('[TFLITE] 📐 Output shape: $outputShape');

      // Update sizes from model
      if (inputShape.length >= 3) {
        inputSize = inputShape[1]; // Assuming [batch, height, width, channels]
        print('[TFLITE] 📏 Updated input size to: $inputSize');
      }
      if (outputShape.length >= 2) {
        outputSize = outputShape[1]; // Assuming [batch, features]
        print('[TFLITE] 📏 Updated output size to: $outputSize');
      }

      _isInitialized = true;
      print('[TFLITE] ✅ Initialization complete');
    } catch (e, stackTrace) {
      print('[TFLITE] ❌ Error loading model: $e');
      print('[TFLITE] ❌ Stack trace: $stackTrace');
      throw Exception('Failed to load TFLite model: $e');
    }
  }

  /// Process camera frame directly (FAST - no disk I/O)
  Future<FaceDetectionResult> detectFromCameraImage(CameraImage image) async {
    if (!_isInitialized) {
      print('[TFLITE] ⚠️ Not initialized yet, initializing now...');
      try {
        await initialize();
      } catch (e) {
        print('[TFLITE] ❌ Failed to initialize: $e');
        return FaceDetectionResult(
          hasFace: false,
          confidence: 0.0,
          processingTime: 0,
          error: 'Not initialized: $e',
        );
      }
    }

    if (_interpreter == null) {
      print('[TFLITE] ❌ Interpreter is null!');
      return FaceDetectionResult(
        hasFace: false,
        confidence: 0.0,
        processingTime: 0,
        error: 'Interpreter is null',
      );
    }

    try {
      final stopwatch = Stopwatch()..start();

      // OPTIMIZED: Convert directly to target size (much faster!)
      final inputBytes = _convertAndResizeNV21(image, inputSize);
      if (inputBytes == null) {
        return FaceDetectionResult(
          hasFace: false,
          confidence: 0.0,
          processingTime: stopwatch.elapsedMilliseconds,
        );
      }

      // Reshape input to [1, 112, 112, 3]
      final input = inputBytes.reshape([1, inputSize, inputSize, numChannels]);

      // Run inference
      var output = List.filled(1 * outputSize, 0.0)
          .reshape([1, outputSize]); // Face embedding output
      _interpreter!.run(input, output);

      stopwatch.stop();

      // Simple face detection: check if embedding has significant values
      final embedding = (output[0] as List).cast<double>();
      final avgValue = embedding.reduce((a, b) => a + b) / embedding.length;
      final hasFace = avgValue.abs() > 0.01; // Threshold untuk face detected

      print(
          '[TFLITE] ✅ Processing took ${stopwatch.elapsedMilliseconds}ms - Face: $hasFace, Confidence: ${avgValue.abs().toStringAsFixed(4)}');

      return FaceDetectionResult(
        hasFace: hasFace,
        confidence: avgValue.abs(),
        processingTime: stopwatch.elapsedMilliseconds,
        embedding: embedding,
      );
    } catch (e, stackTrace) {
      print('[TFLITE] ❌ Detection error: $e');
      print('[TFLITE] ❌ Stack trace: $stackTrace');
      return FaceDetectionResult(
        hasFace: false,
        confidence: 0.0,
        processingTime: 0,
        error: e.toString(),
      );
    }
  }

  /// OPTIMIZED: Convert NV21 and resize directly to target size
  /// This is much faster than converting full size then resizing
  Float32List? _convertAndResizeNV21(CameraImage image, int targetSize) {
    try {
      final int width = image.width;
      final int height = image.height;
      final bytes = image.planes[0].bytes;

      print(
          '[TFLITE] 📐 Original: ${width}x$height -> Target: ${targetSize}x$targetSize');

      // Pre-allocate output buffer
      final output = Float32List(targetSize * targetSize * 3);
      int outputIndex = 0;

      final int ySize = width * height;

      // Calculate scaling factors
      final double scaleX = width / targetSize;
      final double scaleY = height / targetSize;

      // Resize while converting (much faster!)
      for (int ty = 0; ty < targetSize; ty++) {
        for (int tx = 0; tx < targetSize; tx++) {
          // Map target pixel to source pixel (nearest neighbor)
          final int sx = (tx * scaleX).floor();
          final int sy = (ty * scaleY).floor();

          final int yIndex = sy * width + sx;
          final int uvIndex = ySize + (sy ~/ 2) * width + (sx & ~1);

          final int yp = bytes[yIndex] & 0xFF;
          final int vp = bytes[uvIndex] & 0xFF;
          final int up = bytes[uvIndex + 1] & 0xFF;

          // YUV to RGB and normalize to [-1, 1] in one step
          double r = (yp + 1.370705 * (vp - 128)) / 127.5 - 1.0;
          double g =
              (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128)) / 127.5 -
                  1.0;
          double b = (yp + 1.732446 * (up - 128)) / 127.5 - 1.0;

          // Clamp to [-1, 1]
          output[outputIndex++] = r.clamp(-1.0, 1.0);
          output[outputIndex++] = g.clamp(-1.0, 1.0);
          output[outputIndex++] = b.clamp(-1.0, 1.0);
        }
      }

      return output;
    } catch (e) {
      print('[TFLITE] ❌ Conversion error: $e');
      return null;
    }
  }

  /// Convert CameraImage to img.Image
  img.Image? _convertCameraImage(CameraImage image) {
    try {
      print('[TFLITE] 📷 Image format: ${image.format.group}');
      print('[TFLITE] 📏 Image size: ${image.width}x${image.height}');
      print('[TFLITE] 📊 Planes: ${image.planes.length}');

      if (image.format.group == ImageFormatGroup.yuv420) {
        print('[TFLITE] 🔄 Converting YUV420...');
        return _convertYUV420(image);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        print('[TFLITE] 🔄 Converting BGRA8888...');
        return _convertBGRA8888(image);
      } else if (image.format.group == ImageFormatGroup.nv21) {
        print('[TFLITE] 🔄 Converting NV21...');
        return _convertNV21(image);
      }

      print('[TFLITE] ❌ Unsupported image format: ${image.format.group}');
      return null;
    } catch (e, stackTrace) {
      print('[TFLITE] ❌ Conversion error: $e');
      print('[TFLITE] ❌ Stack trace: $stackTrace');
      return null;
    }
  }

  /// Convert NV21 format (1 plane with Y + interleaved VU)
  img.Image _convertNV21(CameraImage image) {
    try {
      final int width = image.width;
      final int height = image.height;
      final bytes = image.planes[0].bytes;

      print('[TFLITE] 📏 NV21 Conversion - size: ${width}x$height');
      print('[TFLITE] 📊 Bytes length: ${bytes.length}');

      final imgLib = img.Image(width: width, height: height);

      final int ySize = width * height;
      final int uvSize = ySize ~/ 2;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * width + x;
          final int uvIndex = ySize + (y ~/ 2) * width + (x & ~1);

          final int yp = bytes[yIndex] & 0xFF;
          final int vp = bytes[uvIndex] & 0xFF;
          final int up = bytes[uvIndex + 1] & 0xFF;

          // YUV to RGB conversion
          int r = (yp + 1.370705 * (vp - 128)).round().clamp(0, 255);
          int g = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128))
              .round()
              .clamp(0, 255);
          int b = (yp + 1.732446 * (up - 128)).round().clamp(0, 255);

          imgLib.setPixelRgb(x, y, r, g, b);
        }
      }

      print('[TFLITE] ✅ NV21 conversion successful');
      return imgLib;
    } catch (e, stackTrace) {
      print('[TFLITE] ❌ NV21 conversion error: $e');
      print('[TFLITE] ❌ Stack: $stackTrace');
      rethrow;
    }
  }

  img.Image _convertYUV420(CameraImage image) {
    try {
      final int width = image.width;
      final int height = image.height;

      print('[TFLITE] 📏 YUV Conversion - size: ${width}x$height');
      print('[TFLITE] 📊 Planes count: ${image.planes.length}');

      if (image.planes.length < 3) {
        print('[TFLITE] ❌ Not enough planes: ${image.planes.length}');
        throw Exception('YUV420 needs 3 planes, got ${image.planes.length}');
      }

      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel!;

      print(
          '[TFLITE] 📊 UV stride: $uvRowStride, pixel stride: $uvPixelStride');

      final imgLib = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int uvIndex =
              uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
          final int index = y * width + x;

          final yp = image.planes[0].bytes[index];
          final up = image.planes[1].bytes[uvIndex];
          final vp = image.planes[2].bytes[uvIndex];

          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
              .round()
              .clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

          imgLib.setPixelRgb(x, y, r, g, b);
        }
      }

      print('[TFLITE] ✅ YUV conversion successful');
      return imgLib;
    } catch (e, stackTrace) {
      print('[TFLITE] ❌ YUV conversion error: $e');
      print('[TFLITE] ❌ Stack: $stackTrace');
      rethrow;
    }
  }

  img.Image _convertBGRA8888(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }

  /// Convert image to normalized float32 array
  Float32List _imageToByteListFloat32(img.Image image) {
    var convertedBytes = Float32List(1 * inputSize * inputSize * numChannels);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    for (int i = 0; i < inputSize; i++) {
      for (int j = 0; j < inputSize; j++) {
        var pixel = image.getPixel(j, i);

        // Normalize to [-1, 1]
        buffer[pixelIndex++] = (pixel.r / 127.5) - 1.0;
        buffer[pixelIndex++] = (pixel.g / 127.5) - 1.0;
        buffer[pixelIndex++] = (pixel.b / 127.5) - 1.0;
      }
    }

    return convertedBytes;
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
    print('[TFLITE] Service disposed');
  }
}

/// Result dari face detection
class FaceDetectionResult {
  final bool hasFace;
  final double confidence;
  final int processingTime;
  final List<double>? embedding;
  final String? error;

  FaceDetectionResult({
    required this.hasFace,
    required this.confidence,
    required this.processingTime,
    this.embedding,
    this.error,
  });
}
