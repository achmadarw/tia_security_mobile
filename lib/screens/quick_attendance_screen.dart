import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:geolocator/geolocator.dart';
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../services/auth_service.dart';
import '../utils/error_handler.dart';
import '../config/theme.dart';

// Quick liveness detection steps
enum LivenessStep {
  initial,
  blinkFirst,
  blinkSecond,
  turnLeft,
  turnRight,
  completed,
}

class QuickAttendanceScreen extends StatefulWidget {
  final AuthService authService;

  const QuickAttendanceScreen({Key? key, required this.authService})
      : super(key: key);

  @override
  State<QuickAttendanceScreen> createState() => _QuickAttendanceScreenState();
}

class _QuickAttendanceScreenState extends State<QuickAttendanceScreen> {
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

  // Liveness detection
  LivenessStep _currentLivenessStep = LivenessStep.initial;
  bool _eyesWereOpen = false;
  List<File> _capturedImages = [];
  int _currentStep = 0;
  final int _totalSteps = 2;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request location permission first
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        print('[QUICK_ATTENDANCE] Location permission denied forever');
      } else if (permission == LocationPermission.denied) {
        print('[QUICK_ATTENDANCE] Location permission denied');
      } else {
        print('[QUICK_ATTENDANCE] Location permission granted: $permission');
      }
    } catch (e) {
      print('[QUICK_ATTENDANCE] Location permission error: $e');
    }

    // Initialize camera after permission
    await _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _faceDetectionService.initialize();
    await _faceRecognitionService.initialize();
    await _initializeCamera();
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

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Posisikan wajah Anda di dalam frame';
        _statusColor = AppColors.primary;
      });

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

            if (!_hasError && !_isProcessing) {
              _processLivenessDetection(faces);
            }
          });
        }
      } catch (e) {
        print('Detection error: $e');
      } finally {
        _isDetecting = false;
      }
    });
  }

  void _processLivenessDetection(List<Face> faces) {
    if (faces.isEmpty) {
      _statusMessage = 'Posisikan wajah Anda di dalam frame';
      _statusColor = Colors.orange;
      return;
    }

    if (faces.length > 1) {
      _statusMessage = 'Hanya 1 wajah yang diperbolehkan';
      _statusColor = Colors.red;
      return;
    }

    final face = faces.first;

    switch (_currentLivenessStep) {
      case LivenessStep.initial:
        _currentLivenessStep = LivenessStep.blinkFirst;
        _statusMessage = 'Kedipkan mata Anda';
        _statusColor = Colors.blue;
        break;

      case LivenessStep.blinkFirst:
        _detectBlink(face, isFirstBlink: true);
        break;

      case LivenessStep.blinkSecond:
        _detectBlink(face, isFirstBlink: false);
        break;

      case LivenessStep.turnLeft:
        _detectHeadTurn(face, isLeft: true);
        break;

      case LivenessStep.turnRight:
        _detectHeadTurn(face, isLeft: false);
        break;

      case LivenessStep.completed:
        break;
    }
  }

  void _detectBlink(Face face, {required bool isFirstBlink}) {
    final leftEyeProb = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeProb = face.rightEyeOpenProbability ?? 1.0;

    if (leftEyeProb > 0.7 && rightEyeProb > 0.7) {
      if (!_eyesWereOpen) {
        _eyesWereOpen = true;
        _statusMessage =
            isFirstBlink ? 'Kedipkan mata Anda' : 'Kedipkan sekali lagi';
        _statusColor = Colors.blue;
      }
    }

    if (_eyesWereOpen && leftEyeProb < 0.3 && rightEyeProb < 0.3) {
      if (isFirstBlink) {
        _currentLivenessStep = LivenessStep.blinkSecond;
        _eyesWereOpen = false;
        _statusMessage = 'Bagus! Kedipkan sekali lagi';
        _statusColor = Colors.green;
      } else {
        _eyesWereOpen = false;
        _waitForEyesOpenThenCapture();
      }
    }
  }

  Future<void> _waitForEyesOpenThenCapture() async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    if (_detectedFaces.isNotEmpty) {
      final face = _detectedFaces.first;
      final leftEyeProb = face.leftEyeOpenProbability ?? 0.0;
      final rightEyeProb = face.rightEyeOpenProbability ?? 0.0;

      if (leftEyeProb > 0.7 && rightEyeProb > 0.7) {
        await _captureStep(restartStream: true);

        if (!mounted) return;

        setState(() {
          _currentStep++;

          _currentLivenessStep = Random().nextBool()
              ? LivenessStep.turnLeft
              : LivenessStep.turnRight;

          _statusMessage = _currentLivenessStep == LivenessStep.turnLeft
              ? 'Palingkan kepala ke KIRI'
              : 'Palingkan kepala ke KANAN';
          _statusColor = Colors.blue;
        });
      }
    }
  }

  void _detectHeadTurn(Face face, {required bool isLeft}) {
    final headYaw = face.headEulerAngleY ?? 0.0;

    if (isLeft) {
      if (headYaw < -20) {
        _captureStepAndComplete();
      } else if (headYaw < -10) {
        _statusMessage = 'Palingkan lebih ke KIRI';
        _statusColor = Colors.orange;
      }
    } else {
      if (headYaw > 20) {
        _captureStepAndComplete();
      } else if (headYaw > 10) {
        _statusMessage = 'Palingkan lebih ke KANAN';
        _statusColor = Colors.orange;
      }
    }
  }

  Future<void> _captureStep({bool restartStream = true}) async {
    try {
      if (_cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }

      final XFile imageFile = await _cameraController!.takePicture();
      final File file = File(imageFile.path);
      _capturedImages.add(file);

      print(
          '[QUICK_ATTENDANCE] Captured image ${_capturedImages.length}: ${file.path}');

      if (restartStream) {
        await Future.delayed(const Duration(milliseconds: 300));
        _startFaceDetection();
      }
    } catch (e) {
      print('[QUICK_ATTENDANCE] Capture error: $e');
      if (mounted) {
        _showError('Gagal mengambil foto. Silakan coba lagi.');
      }
    }
  }

  Future<void> _captureStepAndComplete() async {
    await _captureStep(restartStream: false);

    if (!mounted) return;

    setState(() {
      _currentStep++;
      _currentLivenessStep = LivenessStep.completed;
    });

    await _processAttendance();
  }

  Future<void> _processAttendance() async {
    if (_isProcessing) return;

    print('[QUICK_ATTENDANCE] === Processing attendance ===');

    if (!mounted) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Memproses absensi...';
      _statusColor = Colors.blue;
    });

    try {
      if (_cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }

      if (_capturedImages.isEmpty) {
        _showError('Tidak ada foto yang berhasil diambil.');
        return;
      }

      final file = _capturedImages.last;
      final faces = await _faceDetectionService.detectFacesFromFile(file);

      if (faces.isEmpty) {
        _showError('Wajah tidak terdeteksi. Silakan coba lagi.');
        return;
      }

      if (faces.length > 1) {
        _showError('Terdeteksi lebih dari 1 wajah.');
        return;
      }

      final face = faces.first;
      final faceImage =
          await _faceDetectionService.extractFaceImage(file, face);

      if (faceImage == null) {
        _showError('Gagal mengekstrak wajah.');
        return;
      }

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Mengenali wajah...';
      });

      List<double> embedding;
      try {
        embedding = await _faceRecognitionService.generateEmbedding(faceImage);
      } catch (e) {
        _showError('Gagal generate embedding.');
        return;
      }

      // Get location
      Position? position;
      try {
        print('[QUICK_ATTENDANCE] Checking location service...');
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        print('[QUICK_ATTENDANCE] Location service enabled: $serviceEnabled');

        if (!serviceEnabled) {
          print('[QUICK_ATTENDANCE] Location service is disabled');
        } else {
          LocationPermission permission = await Geolocator.checkPermission();
          print('[QUICK_ATTENDANCE] Current permission: $permission');

          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
            print('[QUICK_ATTENDANCE] Permission after request: $permission');
          }

          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            print('[QUICK_ATTENDANCE] Getting current position...');
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
            ).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                print('[QUICK_ATTENDANCE] Location timeout');
                throw Exception('Location timeout');
              },
            );
            print(
                '[QUICK_ATTENDANCE] Position: ${position.latitude}, ${position.longitude}');
          } else {
            print(
                '[QUICK_ATTENDANCE] Location permission not granted: $permission');
          }
        }
      } catch (e) {
        print('[QUICK_ATTENDANCE] Location error: $e');
        // Continue without location - attendance will still work
      }

      // Process attendance via backend
      final result = await widget.authService.loginWithFace(
        embedding,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      if (result['success']) {
        final attendance = result['attendance'];
        if (attendance != null) {
          final type = attendance['type'];
          final time = attendance['time'] ?? 'Now';

          _showSuccessDialog(
            type == 'check_in' ? 'Clock In Berhasil!' : 'Clock Out Berhasil!',
            'Waktu: $time\nKonfidence: ${(result['confidence']).toStringAsFixed(1)}%',
          );
        } else {
          _showSuccessDialog(
            'Verifikasi Berhasil!',
            'Confidence: ${(result['confidence']).toStringAsFixed(1)}%',
          );
        }
      } else {
        _showError(result['error'] ?? 'Wajah tidak dikenali');
      }
    } catch (e, stackTrace) {
      ErrorHandler.logError('QUICK_ATTENDANCE', e, stackTrace: stackTrace);
      _showError(ErrorHandler.getUserFriendlyMessage(e));
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close attendance screen
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) async {
    try {
      if (_cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      print('[QUICK_ATTENDANCE] Error stopping stream: $e');
    }

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _hasError = true;
      _statusMessage = message;
      _statusColor = Colors.red;
    });
  }

  void _restartDetection() {
    setState(() {
      _isProcessing = false;
      _hasError = false;
      _currentLivenessStep = LivenessStep.initial;
      _eyesWereOpen = false;
      _capturedImages.clear();
      _currentStep = 0;
      _statusMessage = 'Posisikan wajah Anda di dalam frame';
      _statusColor = AppColors.primary;
    });
    _startFaceDetection();
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
              // Camera preview
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

              // Face-shaped frame
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
                top: 20,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Quick Attendance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
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
                          // Progress dots
                          if (_currentLivenessStep != LivenessStep.initial &&
                              _currentLivenessStep != LivenessStep.completed &&
                              !_hasError)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  _totalSteps,
                                  (index) => Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: index < _currentStep
                                          ? Colors.green
                                          : Colors.white.withOpacity(0.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
                          // Retry button
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

              // Info text at bottom
              if (!_isProcessing &&
                  _isInitialized &&
                  !_hasError &&
                  _currentLivenessStep != LivenessStep.completed)
                Positioned(
                  bottom: 40,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Ikuti instruksi untuk verifikasi liveness',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
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

// Custom painter for face-shaped frame
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
    final centerX = size.width / 2;

    path.moveTo(centerX, size.height * 0.06);

    path.cubicTo(
      size.width * 0.58,
      size.height * 0.055,
      size.width * 0.75,
      size.height * 0.10,
      size.width * 0.89,
      size.height * 0.25,
    );

    path.cubicTo(
      size.width * 0.95,
      size.height * 0.38,
      size.width * 0.94,
      size.height * 0.54,
      size.width * 0.90,
      size.height * 0.68,
    );

    path.cubicTo(
      size.width * 0.85,
      size.height * 0.80,
      size.width * 0.75,
      size.height * 0.90,
      size.width * 0.62,
      size.height * 0.96,
    );

    path.cubicTo(
      size.width * 0.55,
      size.height * 0.99,
      size.width * 0.45,
      size.height * 0.99,
      size.width * 0.38,
      size.height * 0.96,
    );

    path.cubicTo(
      size.width * 0.25,
      size.height * 0.90,
      size.width * 0.15,
      size.height * 0.80,
      size.width * 0.10,
      size.height * 0.68,
    );

    path.cubicTo(
      size.width * 0.06,
      size.height * 0.54,
      size.width * 0.05,
      size.height * 0.38,
      size.width * 0.11,
      size.height * 0.25,
    );

    path.cubicTo(
      size.width * 0.25,
      size.height * 0.10,
      size.width * 0.42,
      size.height * 0.055,
      centerX,
      size.height * 0.06,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant FaceFramePainter oldDelegate) {
    return oldDelegate.frameColor != frameColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
