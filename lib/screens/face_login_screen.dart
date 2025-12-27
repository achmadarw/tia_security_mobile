import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:geolocator/geolocator.dart';
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../services/auth_service.dart';
import '../utils/error_handler.dart';
import '../config/theme.dart';
import 'home_screen.dart';

class FaceLoginScreen extends StatefulWidget {
  final AuthService authService;

  const FaceLoginScreen({Key? key, required this.authService})
      : super(key: key);

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  CameraController? _cameraController;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FaceRecognitionService _faceRecognitionService =
      FaceRecognitionService();

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isDetecting = false;
  bool _hasError = false;

  String _statusMessage = 'Initializing camera...';
  Color _statusColor = Colors.orange;

  List<Face> _detectedFaces = [];
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _faceDetectionService.initialize();
    await _faceRecognitionService.initialize();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _statusMessage = 'No camera found';
          _statusColor = Colors.red;
        });
        return;
      }

      // Use front camera
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Posisikan wajah Anda di dalam frame';
        _statusColor = AppColors.primary;
      });

      // Start face detection
      _startFaceDetection();
    } catch (e) {
      setState(() {
        _statusMessage = 'Camera error: $e';
        _statusColor = Colors.red;
      });
    }
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting || _isProcessing) return;

      _isDetecting = true;

      try {
        final faces = await _faceDetectionService.detectFacesFromCamera(image);

        if (mounted) {
          setState(() {
            _detectedFaces = faces;
            _imageSize = Size(
              image.width.toDouble(),
              image.height.toDouble(),
            );

            // Don't update status if there's an error showing
            if (!_hasError) {
              if (faces.isEmpty) {
                _statusMessage = 'Posisikan wajah Anda di dalam frame';
                _statusColor = Colors.orange;
              } else if (faces.length > 1) {
                _statusMessage = 'Hanya 1 wajah yang diperbolehkan';
                _statusColor = Colors.red;
              } else {
                _statusMessage = 'Wajah terdeteksi! Tap untuk login';
                _statusColor = Colors.green;
              }
            }
          });
        }
      } catch (e) {
        print('Detection error: $e');
        if (mounted) {
          setState(() {
            _statusMessage = 'Tap tombol untuk login';
            _statusColor = AppColors.primary;
          });
        }
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<void> _captureAndRecognize() async {
    if (_isProcessing) return;

    print('[FACE_LOGIN] === Starting face recognition process ===');

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing...';
      _statusColor = Colors.blue;
    });

    try {
      print('[FACE_LOGIN] Stopping image stream...');
      // Stop image stream
      await _cameraController?.stopImageStream();

      print('[FACE_LOGIN] Capturing image...');
      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();
      final File file = File(imageFile.path);
      print('[FACE_LOGIN] Image captured: ${file.path}');

      print('[FACE_LOGIN] Detecting faces...');
      // Detect face
      final faces = await _faceDetectionService.detectFacesFromFile(file);
      print('[FACE_LOGIN] Faces detected: ${faces.length}');

      if (faces.isEmpty) {
        print('[FACE_LOGIN] ERROR: No face detected');
        _showError('Wajah tidak terdeteksi\n\n'
            '• Pastikan wajah Anda terlihat jelas\n'
            '• Hindari cahaya dari belakang\n'
            '• Lepas masker/kacamata hitam\n'
            '• Coba posisi lebih dekat');
        await Future.delayed(const Duration(seconds: 3));
        _restartDetection();
        return;
      }

      if (faces.length > 1) {
        print('[FACE_LOGIN] ERROR: Multiple faces detected (${faces.length})');
        _showError('Terdeteksi ${faces.length} wajah\n\n'
            '• Hanya 1 orang yang diperbolehkan\n'
            '• Pastikan tidak ada orang lain di frame\n'
            '• Coba lagi dengan posisi yang tepat');
        await Future.delayed(const Duration(seconds: 3));
        _restartDetection();
        return;
      }

      final face = faces.first;
      print('[FACE_LOGIN] Face bounding box: ${face.boundingBox}');

      print('[FACE_LOGIN] Extracting face region...');
      // Extract face region
      final faceImage =
          await _faceDetectionService.extractFaceImage(file, face);

      if (faceImage == null) {
        print('[FACE_LOGIN] ERROR: Failed to extract face');
        _showError('Failed to extract face');
        _restartDetection();
        return;
      }

      print(
          '[FACE_LOGIN] Face extracted successfully: ${faceImage.width}x${faceImage.height}');

      // Generate embedding
      setState(() {
        _statusMessage = 'Recognizing face...';
      });

      print('[FACE_LOGIN] Generating embedding...');

      // Generate face embedding using TFLite model
      List<double> embedding;
      try {
        embedding = await _faceRecognitionService.generateEmbedding(faceImage);
        print(
            '[FACE_LOGIN] Embedding generated: ${embedding.length} dimensions');
      } catch (e) {
        print('[FACE_LOGIN] ERROR: Failed to generate embedding: $e');
        _showError('Failed to generate face embedding. Please try again.');
        _restartDetection();
        return;
      }

      print('[FACE_LOGIN] Sending to backend for recognition...');

      // Get location
      Position? position;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
            ).timeout(const Duration(seconds: 5));
            print(
                '[FACE_LOGIN] Location: ${position.latitude}, ${position.longitude}');
          }
        }
      } catch (e) {
        print('[FACE_LOGIN] Location error (continuing without it): $e');
      }

      // Send to backend for recognition
      final result = await widget.authService.loginWithFace(
        embedding,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      print('[FACE_LOGIN] Backend response: $result');

      if (result['success']) {
        print('[FACE_LOGIN] SUCCESS: Login successful!');

        // Get attendance info
        final attendance = result['attendance'];
        String attendanceMsg = '';
        if (attendance != null) {
          final type = attendance['type'];
          attendanceMsg =
              '\n${type == 'check_in' ? '✓ Clock In' : '✓ Clock Out'} recorded';
        }

        // Login successful
        _showSuccess(
          'Login successful!${attendanceMsg}\nConfidence: ${(result['confidence']).toStringAsFixed(1)}%',
        );

        // Navigate to home
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                authService: widget.authService,
              ),
            ),
          );
        }
      } else {
        print('[FACE_LOGIN] FAILED: ${result['error']}');
        _showError(result['error'] ?? 'Wajah tidak dikenali');
        // Don't auto-restart, let user manually retry
      }
    } catch (e, stackTrace) {
      ErrorHandler.logError('FACE_LOGIN', e, stackTrace: stackTrace);
      _showError(ErrorHandler.getUserFriendlyMessage(e));
      // Don't auto-restart, let user manually retry
    }
  }

  void _restartDetection() {
    setState(() {
      _isProcessing = false;
      _hasError = false;
      _statusMessage = 'Position your face in the frame';
      _statusColor = AppColors.primary;
    });
    _startFaceDetection();
  }

  void _showError(String message) async {
    // Stop image stream to prevent status message from being overwritten
    try {
      if (_cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      print('[FACE_LOGIN] Error stopping stream: $e');
    }

    setState(() {
      _isProcessing = false; // Remove overlay so error is visible
      _hasError = true;
      _statusMessage = message;
      _statusColor = Colors.red;
    });
  }

  void _showSuccess(String message) {
    setState(() {
      _hasError = false;
      _statusMessage = message;
      _statusColor = Colors.green;
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetectionService.dispose();
    _faceRecognitionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary,
              AppColors.primary.withOpacity(0.8),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Camera preview with proper sizing
              if (_isInitialized && _cameraController != null)
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cameraController!.value.previewSize!.height,
                      height: _cameraController!.value.previewSize!.width,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),

              // Face-shaped frame overlay (same as registration)
              Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.85,
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: CustomPaint(
                    painter: FaceFramePainter(
                      frameColor: _detectedFaces.isNotEmpty
                          ? Colors.green
                          : Colors.white,
                      strokeWidth: 4.0,
                    ),
                  ),
                ),
              ),

              // Header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Face Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Status message
              Positioned(
                top: 80,
                left: 20,
                right: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (_hasError)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.error_outline,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  _statusMessage,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          // Retry button for errors
                          if (_hasError)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: ElevatedButton.icon(
                                onPressed: _restartDetection,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Coba Lagi'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red.shade700,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Processing indicator
              if (_isProcessing)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                ),

              // Manual capture button
              if (!_isProcessing && _isInitialized)
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _captureAndRecognize,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: _detectedFaces.isNotEmpty
                                ? Colors.green
                                : Colors.white,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: AppColors.primary,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom painter for face-shaped frame (same as registration)
class FaceFramePainter extends CustomPainter {
  final Color frameColor;
  final double strokeWidth;

  FaceFramePainter({
    required this.frameColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    // Create smooth face outline similar to face mesh border
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Start from top center of head - perfectly rounded dome
    path.moveTo(centerX, size.height * 0.06);

    // Top-right forehead curve - smooth arc WITHOUT dip
    path.cubicTo(
      size.width * 0.58, size.height * 0.055, // Control point 1 - slightly UP
      size.width * 0.75, size.height * 0.10, // Control point 2 - gradual down
      size.width * 0.89, size.height * 0.25, // End point
    );

    // Right temple to cheekbone
    path.cubicTo(
      size.width * 0.95, size.height * 0.38, // Control point 1
      size.width * 0.94, size.height * 0.54, // Control point 2
      size.width * 0.90, size.height * 0.68, // End point
    );

    // Right cheek to jaw
    path.cubicTo(
      size.width * 0.85, size.height * 0.80, // Control point 1
      size.width * 0.75, size.height * 0.90, // Control point 2
      size.width * 0.62, size.height * 0.96, // End point
    );

    // Right jaw to chin
    path.cubicTo(
      size.width * 0.55, size.height * 0.99, // Control point 1
      size.width * 0.45, size.height * 0.99, // Control point 2
      size.width * 0.38, size.height * 0.96, // End point (chin)
    );

    // Left jaw
    path.cubicTo(
      size.width * 0.25, size.height * 0.90, // Control point 1
      size.width * 0.15, size.height * 0.80, // Control point 2
      size.width * 0.10, size.height * 0.68, // End point
    );

    // Left cheekbone to temple
    path.cubicTo(
      size.width * 0.06, size.height * 0.54, // Control point 1
      size.width * 0.05, size.height * 0.38, // Control point 2
      size.width * 0.11, size.height * 0.25, // End point
    );

    // Left forehead - smooth arc WITHOUT dip, mirror of right side
    path.cubicTo(
      size.width * 0.25, size.height * 0.10, // Control point 1 - gradual down
      size.width * 0.42, size.height * 0.055, // Control point 2 - slightly UP
      centerX, size.height * 0.06, // Back to top
    );

    // Draw the smooth face outline
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant FaceFramePainter oldDelegate) {
    return oldDelegate.frameColor != frameColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
