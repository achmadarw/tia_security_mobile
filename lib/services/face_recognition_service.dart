import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// Service untuk face recognition menggunakan TensorFlow Lite
/// Generate face embedding (192D) dan kirim ke backend untuk matching
/// Singleton pattern untuk memastikan hanya ada satu instance dan model di-initialize sekali
class FaceRecognitionService {
  // Singleton instance
  static final FaceRecognitionService _instance =
      FaceRecognitionService._internal();

  factory FaceRecognitionService() {
    return _instance;
  }

  FaceRecognitionService._internal();

  Interpreter? _interpreter;
  bool _isInitialized = false;
  bool _isInitializing = false;

  // Model input/output specs for MobileFaceNet
  static const int inputSize = 112; // 112x112 for MobileFaceNet
  static const int embeddingSize = 192; // 192D embedding output

  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Initialize TFLite model dengan retry mechanism
  Future<void> initialize() async {
    // Prevent concurrent initialization
    if (_isInitializing) {
      print('[FaceRecognition] Already initializing, waiting...');
      // Wait for initialization to complete
      int attempts = 0;
      while (_isInitializing && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      return;
    }

    if (_isInitialized) {
      print('[FaceRecognition] Already initialized');
      return;
    }

    _isInitializing = true;

    try {
      print('[FaceRecognition] Starting model initialization...');

      // Load model from assets
      _interpreter =
          await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');

      print('[FaceRecognition] Model loaded, allocating tensors...');

      // Allocate tensors
      _interpreter!.allocateTensors();

      // Add small delay to ensure full initialization
      await Future.delayed(const Duration(milliseconds: 200));

      // Verify interpreter is ready by checking input/output tensors
      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);

      print('[FaceRecognition] Input tensor shape: ${inputTensor.shape}');
      print('[FaceRecognition] Output tensor shape: ${outputTensor.shape}');

      _isInitialized = true;
      print('✅ Face recognition model loaded successfully');
    } catch (e) {
      print('❌ Error loading face recognition model: $e');
      _isInitialized = false;
      _interpreter = null;
      throw Exception('Failed to load face recognition model: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Generate face embedding from image
  /// Input: img.Image (112x112)
  /// Output: List<double> (192D embedding)
  Future<List<double>> generateEmbedding(img.Image faceImage) async {
    // Ensure model is initialized
    if (!_isInitialized) {
      print('[FaceRecognition] Model not initialized, initializing now...');
      await initialize();
    }

    if (_interpreter == null) {
      throw Exception('Interpreter is null after initialization');
    }

    try {
      // Ensure image is 112x112
      if (faceImage.width != inputSize || faceImage.height != inputSize) {
        faceImage =
            img.copyResize(faceImage, width: inputSize, height: inputSize);
      }

      // Prepare input tensor (1, 112, 112, 3)
      final inputData = _imageToByteListFloat32(faceImage);
      final input = inputData.reshape([1, inputSize, inputSize, 3]);

      // Prepare output tensor (1, 192)
      final output =
          List.filled(1 * embeddingSize, 0.0).reshape([1, embeddingSize]);

      print('[FaceRecognition] Running inference...');

      // Run inference
      _interpreter!.run(input, output);

      print('[FaceRecognition] Inference completed');

      // Extract embedding
      final embedding = List<double>.from(output[0]);

      // Normalize embedding (L2 normalization)
      final normalizedEmbedding = _normalizeEmbedding(embedding);

      print(
          '[FaceRecognition] Embedding generated: ${normalizedEmbedding.length}D');

      return normalizedEmbedding;
    } catch (e) {
      print('[FaceRecognition] Error generating embedding: $e');
      rethrow;
    }
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
    final magnitude = math.sqrt(sum);

    if (magnitude == 0) return embedding;

    return embedding.map((value) => value / magnitude).toList();
  }

  /// Send embedding to backend for face login with retry mechanism
  Future<Map<String, dynamic>> loginWithFace(
    List<double> embedding, {
    double? latitude,
    double? longitude,
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    Duration delay = const Duration(seconds: 1);

    while (attempt < maxRetries) {
      attempt++;

      try {
        print('[FaceRecognition] Login attempt $attempt/$maxRetries');
        print('[FaceRecognition] Embedding length: ${embedding.length}');
        print('[FaceRecognition] Location: lat=$latitude, lng=$longitude');

        final response = await _dio.post(
          ApiConfig.authFaceLogin,
          data: {
            'embedding': embedding,
            'location_lat': latitude,
            'location_lng': longitude,
          },
          options: Options(
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

        print('[FaceRecognition] Response status: ${response.statusCode}');

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
            'attendance': data['attendance'],
          };
        }

        // Non-retryable error (face not recognized, etc)
        if (response.statusCode == 401 || response.statusCode == 400) {
          return {
            'success': false,
            'message': response.data['message'] ?? 'Face not recognized',
          };
        }

        // Server error - retry
        print('[FaceRecognition] Server error, will retry...');
      } catch (e) {
        print('[FaceRecognition] Exception on attempt $attempt: $e');

        if (e is DioException) {
          print('[FaceRecognition] DioException type: ${e.type}');

          // Rate limit error - don't retry
          if (e.response?.statusCode == 429) {
            final retryAfter = e.response?.data['retryAfter'] ?? 60;
            return {
              'success': false,
              'message': e.response?.data['message'] ??
                  'Terlalu banyak percobaan. Silakan tunggu $retryAfter detik.',
            };
          }

          // Face not recognized - don't retry
          if (e.response?.statusCode == 401 || e.response?.statusCode == 400) {
            return {
              'success': false,
              'message': e.response?.data['message'] ?? 'Face not recognized',
            };
          }

          // Network/timeout errors - retry
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.connectionError) {
            if (attempt < maxRetries) {
              print(
                  '[FaceRecognition] Network error, retrying in ${delay.inSeconds}s...');
              await Future.delayed(delay);
              delay *= 2; // Exponential backoff
              continue;
            }

            return {
              'success': false,
              'message':
                  'Koneksi bermasalah. Periksa internet Anda dan coba lagi.',
            };
          }
        }

        // Last attempt failed
        if (attempt >= maxRetries) {
          return {
            'success': false,
            'message': 'Gagal menghubungi server. Silakan coba lagi nanti.',
          };
        }

        // Retry with backoff
        print('[FaceRecognition] Retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }

    return {
      'success': false,
      'message': 'Gagal setelah $maxRetries percobaan. Silakan coba lagi.',
    };
  }

  /// Register face images to backend
  /// Backend will automatically generate embeddings using Python
  Future<Map<String, dynamic>> registerFace({
    required int userId,
    required List<File> images,
    required String token,
  }) async {
    try {
      print('[FaceRecognition] Registering face for user $userId');
      print('[FaceRecognition] Images: ${images.length}');

      _dio.options.headers['Authorization'] = 'Bearer $token';

      // Create multipart form data
      final formData = FormData();

      // Add user ID (backend expects 'userId' or 'user_id')
      formData.fields.add(MapEntry('userId', userId.toString()));

      // Add images
      for (int i = 0; i < images.length; i++) {
        formData.files.add(MapEntry(
          'images',
          await MultipartFile.fromFile(
            images[i].path,
            filename: 'face_$i.jpg',
          ),
        ));
      }

      print('[FaceRecognition] Uploading ${images.length} images...');
      final response = await _dio.post(
        ApiConfig.faceRegister,
        data: formData,
      );

      print('[FaceRecognition] Response status: ${response.statusCode}');
      print('[FaceRecognition] Response data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 201) {
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

    return math.sqrt(sum);
  }

  /// Close and cleanup
  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
    _isInitializing = false;
  }
}
