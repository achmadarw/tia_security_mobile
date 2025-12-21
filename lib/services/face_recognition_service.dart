import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// Service untuk face recognition menggunakan TensorFlow Lite
/// Generate face embedding (512D) dan kirim ke backend untuk matching
class FaceRecognitionService {
  Interpreter? _interpreter;
  bool _isInitialized = false;

  // Model input/output specs
  static const int inputSize = 112; // 112x112 for MobileFaceNet
  static const int embeddingSize = 512; // 512D embedding output

  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Initialize TFLite model
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load model from assets
      _interpreter =
          await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');

      // Allocate tensors
      _interpreter!.allocateTensors();

      _isInitialized = true;
      print('✅ Face recognition model loaded successfully');
    } catch (e) {
      print('❌ Error loading face recognition model: $e');
      throw Exception('Failed to load face recognition model: $e');
    }
  }

  /// Generate face embedding from image
  /// Input: img.Image (112x112)
  /// Output: List<double> (512D embedding)
  Future<List<double>> generateEmbedding(img.Image faceImage) async {
    if (!_isInitialized) await initialize();

    // Ensure image is 112x112
    if (faceImage.width != inputSize || faceImage.height != inputSize) {
      faceImage =
          img.copyResize(faceImage, width: inputSize, height: inputSize);
    }

    // Prepare input tensor (1, 112, 112, 3)
    final input = _imageToByteListFloat32(faceImage);

    // Prepare output tensor (1, 512)
    final output =
        List.filled(1 * embeddingSize, 0.0).reshape([1, embeddingSize]);

    // Run inference
    _interpreter!.run(input, output);

    // Extract embedding
    final embedding = List<double>.from(output[0]);

    // Normalize embedding (L2 normalization)
    final normalizedEmbedding = _normalizeEmbedding(embedding);

    return normalizedEmbedding;
  }

  /// Generate embedding from file path
  Future<List<double>> generateEmbeddingFromFile(File imageFile) async {
    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    return await generateEmbedding(image);
  }

  /// Convert img.Image to ByteBuffer for model input
  /// Format: Float32, normalized to [-1, 1]
  Float32List _imageToByteListFloat32(img.Image image) {
    final convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    final buffer = Float32List.view(convertedBytes.buffer);

    int pixelIndex = 0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);

        // Normalize RGB values to [-1, 1]
        buffer[pixelIndex++] = (pixel.r / 127.5) - 1.0;
        buffer[pixelIndex++] = (pixel.g / 127.5) - 1.0;
        buffer[pixelIndex++] = (pixel.b / 127.5) - 1.0;
      }
    }

    return convertedBytes;
  }

  /// L2 normalization for embedding
  List<double> _normalizeEmbedding(List<double> embedding) {
    double sum = 0.0;
    for (var value in embedding) {
      sum += value * value;
    }
    final magnitude = Math.sqrt(sum);

    if (magnitude == 0) return embedding;

    return embedding.map((value) => value / magnitude).toList();
  }

  /// Send embedding to backend for face login
  Future<Map<String, dynamic>> loginWithFace(List<double> embedding) async {
    try {
      print('[FaceRecognition] Logging in with face embedding');
      print('[FaceRecognition] Embedding length: ${embedding.length}');
      print(
          '[FaceRecognition] Endpoint: ${ApiConfig.baseUrl}${ApiConfig.authFaceLogin}');

      final response = await _dio.post(
        ApiConfig.authFaceLogin,
        data: {
          'embedding': embedding,
        },
      );

      print('[FaceRecognition] Response status: ${response.statusCode}');
      print('[FaceRecognition] Response data: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;

        // Save tokens
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', data['accessToken']);
        await prefs.setString('refresh_token', data['refreshToken']);

        return {
          'success': true,
          'user': data['user'],
          'confidence': data['confidence'],
        };
      }

      return {
        'success': false,
        'message': 'Login failed',
      };
    } catch (e) {
      print('[FaceRecognition] Exception: $e');
      if (e is DioException) {
        print('[FaceRecognition] DioException type: ${e.type}');
        print('[FaceRecognition] DioException message: ${e.message}');
        print('[FaceRecognition] DioException response: ${e.response?.data}');
        return {
          'success': false,
          'message': e.response?.data['message'] ?? 'Network error',
        };
      }

      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

  /// Register face embeddings to backend
  /// Upload multiple embeddings for better accuracy
  Future<Map<String, dynamic>> registerFace({
    required int userId,
    required List<List<double>> embeddings,
    required String token,
  }) async {
    try {
      _dio.options.headers['Authorization'] = 'Bearer $token';

      final response = await _dio.post(
        ApiConfig.faceRegister,
        data: {
          'userId': userId,
          'embeddings': embeddings,
        },
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Face registered successfully',
        };
      }

      return {
        'success': false,
        'message': 'Registration failed',
      };
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'message': e.response?.data['message'] ?? 'Network error',
        };
      }

      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

  /// Calculate similarity between two embeddings (Euclidean distance)
  /// Lower distance = more similar
  double calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw Exception('Embeddings must have same length');
    }

    double sum = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      final diff = embedding1[i] - embedding2[i];
      sum += diff * diff;
    }

    return Math.sqrt(sum);
  }

  /// Close and cleanup
  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }
}

// Math helper since dart:math sqrt conflicts with some packages
class Math {
  static double sqrt(double value) {
    return value < 0 ? 0 : _sqrtImpl(value);
  }

  static double _sqrtImpl(double value) {
    double guess = value / 2;
    double epsilon = 0.00001;

    while ((guess * guess - value).abs() > epsilon) {
      guess = (guess + value / guess) / 2;
    }

    return guess;
  }
}
