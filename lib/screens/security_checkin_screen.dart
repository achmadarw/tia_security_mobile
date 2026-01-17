import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:geolocator/geolocator.dart';
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../services/security_app_service.dart';
import '../utils/error_handler.dart';
import '../config/theme.dart';

// Liveness detection steps (blink detection only)
enum LivenessStep {
  initial,
  blinkFirst,
  blinkSecond,
  completed,
}

class SecurityCheckinScreen extends StatefulWidget {
  final SecurityAppService securityService;
  final bool isCheckOut;

  const SecurityCheckinScreen({
    Key? key,
    required this.securityService,
    this.isCheckOut = false,
  }) : super(key: key);

  @override
  State<SecurityCheckinScreen> createState() => _SecurityCheckinScreenState();
}

class _SecurityCheckinScreenState extends State<SecurityCheckinScreen> {
  CameraController? _cameraController;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FaceRecognitionService _faceRecognitionService =
      FaceRecognitionService();

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isDetecting = false;
  bool _hasError = false;

  String _statusMessage = 'Initializing...';
  Color _statusColor = Colors.orange;

  List<Face> _detectedFaces = [];

  // Liveness detection
  LivenessStep _currentLivenessStep = LivenessStep.initial;
  bool _eyesWereOpen = false;
  List<File> _capturedImages = [];
  int _currentStep = 0;
  final int _totalSteps = 1; // Only blink detection, no head turn

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
        print('[SECURITY_CHECKIN] Location permission denied forever');
      } else if (permission == LocationPermission.denied) {
        print('[SECURITY_CHECKIN] Location permission denied');
      } else {
        print('[SECURITY_CHECKIN] Location permission granted: $permission');
      }
    } catch (e) {
      print('[SECURITY_CHECKIN] Location permission error: $e');
    }

    // Initialize camera
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

      // Use front camera
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

    // Check basic face detection quality
    final leftEye = face.leftEyeOpenProbability;
    final rightEye = face.rightEyeOpenProbability;

    if (leftEye == null || rightEye == null) {
      _statusMessage = 'Posisikan wajah dengan jelas';
      _statusColor = Colors.orange;
      return;
    }

    // Blink detection for liveness
    final eyesOpen = leftEye > 0.5 && rightEye > 0.5;
    final eyesClosed = leftEye < 0.3 && rightEye < 0.3;

    if (_currentLivenessStep == LivenessStep.initial) {
      if (eyesOpen) {
        setState(() {
          _eyesWereOpen = true;
          _statusMessage = 'Kedipkan mata Anda dua kali';
          _statusColor = Colors.blue;
        });
      }
    } else if (_currentLivenessStep == LivenessStep.blinkFirst) {
      if (!_eyesWereOpen && eyesOpen) {
        // Eyes reopened after first blink
        setState(() {
          _eyesWereOpen = true;
          _currentStep = 1;
          _statusMessage = 'Kedipkan mata sekali lagi';
          _statusColor = Colors.blue;
          _currentLivenessStep = LivenessStep.blinkSecond;
        });
      } else if (eyesClosed) {
        _eyesWereOpen = false;
      }
    } else if (_currentLivenessStep == LivenessStep.blinkSecond) {
      if (!_eyesWereOpen && eyesOpen) {
        // Eyes reopened after second blink
        setState(() {
          _eyesWereOpen = true;
          _currentLivenessStep = LivenessStep.completed;
          _statusMessage = 'Liveness terverifikasi! Memproses...';
          _statusColor = Colors.green;
        });
        // Auto-capture and process
        Future.delayed(const Duration(milliseconds: 300), () {
          _processCheckIn();
        });
      } else if (eyesClosed) {
        _eyesWereOpen = false;
      }
    }

    // Detect first blink
    if (_currentLivenessStep == LivenessStep.initial &&
        _eyesWereOpen &&
        eyesClosed) {
      setState(() {
        _currentLivenessStep = LivenessStep.blinkFirst;
        _statusMessage = 'Kedipan pertama terdeteksi! Buka mata...';
        _statusColor = Colors.orange;
        _eyesWereOpen = false;
      });
    }
  }

  Future<void> _processCheckIn() async {
    if (_isProcessing) return;

    print(
        '[SECURITY_CHECKIN] === Processing ${widget.isCheckOut ? 'check-out' : 'check-in'} ===');

    if (!mounted) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Memproses...';
      _statusColor = Colors.blue;
    });

    try {
      // Stop stream before capture
      if (_cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }

      // Capture image
      print('[SECURITY_CHECKIN] Capturing image...');
      final XFile imageFile = await _cameraController!.takePicture();
      final File file = File(imageFile.path);
      print('[SECURITY_CHECKIN] Image captured: ${file.path}');

      print('[SECURITY_CHECKIN] Detecting faces...');
      final faces = await _faceDetectionService.detectFacesFromFile(file);
      print('[SECURITY_CHECKIN] Faces detected: ${faces.length}');

      if (faces.isEmpty) {
        _showError('Wajah tidak terdeteksi. Silakan coba lagi.');
        return;
      }

      if (faces.length > 1) {
        _showError('Terdeteksi lebih dari 1 wajah.');
        return;
      }

      final face = faces.first;
      print('[SECURITY_CHECKIN] Extracting embedding...');

      final faceImage =
          await _faceDetectionService.extractFaceImage(file, face);

      if (faceImage == null) {
        _showError('Gagal mengekstrak wajah.');
        return;
      }

      print(
          '[SECURITY_CHECKIN] Face extracted: ${faceImage.width}x${faceImage.height}');

      // DEBUG: Log face detection details
      print('[SECURITY_CHECKIN] === Face Detection Debug ===');
      print(
          '[SECURITY_CHECKIN] Face bounding box: ${face.boundingBox.left.toInt()},${face.boundingBox.top.toInt()} ${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()}');
      print(
          '[SECURITY_CHECKIN] Head angles: Y=${face.headEulerAngleY?.toStringAsFixed(2)}°, Z=${face.headEulerAngleZ?.toStringAsFixed(2)}°');

      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      if (leftEye != null && rightEye != null) {
        print(
            '[SECURITY_CHECKIN] Left eye: (${leftEye.position.x.toInt()}, ${leftEye.position.y.toInt()})');
        print(
            '[SECURITY_CHECKIN] Right eye: (${rightEye.position.x.toInt()}, ${rightEye.position.y.toInt()})');

        final deltaY = rightEye.position.y - leftEye.position.y;
        final deltaX = rightEye.position.x - leftEye.position.x;
        final angleRad = atan2(deltaY, deltaX);
        final angleDeg = angleRad * 180 / pi;
        print(
            '[SECURITY_CHECKIN] Eye rotation angle: ${angleDeg.toStringAsFixed(2)}°');
      }

      print(
          '[SECURITY_CHECKIN] Left eye open: ${face.leftEyeOpenProbability?.toStringAsFixed(2)}');
      print(
          '[SECURITY_CHECKIN] Right eye open: ${face.rightEyeOpenProbability?.toStringAsFixed(2)}');
      print('[SECURITY_CHECKIN] === End Debug ===');

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Memvalidasi kualitas foto...';
      });

      print('[SECURITY_CHECKIN] Generating embedding with quality checks...');

      // Generate embedding
      List<double> embedding;
      try {
        final result =
            await _faceRecognitionService.generateEmbeddingWithQuality(
          faceImage,
          face,
          isStrictMode: false,
        );

        embedding = result['embedding'];
        final qualityScore = result['qualityScore'] ?? 0.0;

        print(
            '[SECURITY_CHECKIN] ✅ Embedding generated: ${embedding.length} dimensions');
        print('[SECURITY_CHECKIN] Quality score: $qualityScore%');

        if (!mounted) return;

        setState(() {
          _statusMessage = 'Mengambil lokasi GPS...';
        });
      } catch (e) {
        print('[SECURITY_CHECKIN] Embedding generation error: $e');
        _showError('Gagal generate embedding: $e');
        return;
      }

      // Get GPS location
      Position? position;
      try {
        print('[SECURITY_CHECKIN] Checking location service...');
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        print('[SECURITY_CHECKIN] Location service enabled: $serviceEnabled');

        if (!serviceEnabled) {
          print('[SECURITY_CHECKIN] Location service is disabled');
          _showError('Layanan lokasi tidak aktif. Silakan aktifkan GPS.');
          return;
        } else {
          LocationPermission permission = await Geolocator.checkPermission();
          print('[SECURITY_CHECKIN] Current permission: $permission');

          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
            print('[SECURITY_CHECKIN] Permission after request: $permission');
          }

          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            print('[SECURITY_CHECKIN] Getting current position...');
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
            ).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                print('[SECURITY_CHECKIN] Location timeout');
                throw Exception('Location timeout');
              },
            );
            print(
                '[SECURITY_CHECKIN] Position: ${position.latitude}, ${position.longitude}');
          } else {
            print(
                '[SECURITY_CHECKIN] Location permission not granted: $permission');
            _showError('Izin lokasi diperlukan untuk check-in.');
            return;
          }
        }
      } catch (e) {
        print('[SECURITY_CHECKIN] Location error: $e');
        _showError('Gagal mendapatkan lokasi GPS: $e');
        return;
      }

      if (position == null) {
        _showError('Gagal mendapatkan lokasi GPS.');
        return;
      }

      setState(() {
        _statusMessage = widget.isCheckOut
            ? 'Melakukan check-out...'
            : 'Melakukan check-in...';
      });

      print(
          '[SECURITY_CHECKIN] Submitting ${widget.isCheckOut ? 'check-out' : 'check-in'}');

      // Submit check-in or check-out to SecurityAppService
      final Map<String, dynamic> result;
      if (widget.isCheckOut) {
        result = await widget.securityService.checkOut(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } else {
        result = await widget.securityService.checkIn(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      print('[SECURITY_CHECKIN] Result: $result');

      // Success
      final checkTime = result['check_time'] ?? DateTime.now().toString();
      final location = result['location'] ?? 'Unknown';

      _showSuccessDialog(
        widget.isCheckOut ? 'Check-out Berhasil!' : 'Check-in Berhasil!',
        'Waktu: $checkTime\nLokasi: $location',
      );
    } catch (e, stackTrace) {
      ErrorHandler.logError('SECURITY_CHECKIN', e, stackTrace: stackTrace);
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
              Navigator.pop(
                  context, true); // Close check-in screen with result=true
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
      print('[SECURITY_CHECKIN] Error stopping stream: $e');
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
                    Text(
                      widget.isCheckOut
                          ? 'Security Check-Out'
                          : 'Security Check-In',
                      style: const TextStyle(
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
                child: Column(
                  children: [
                    // Status message
                    ClipRRect(
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
                              if (_currentLivenessStep !=
                                      LivenessStep.initial &&
                                  _currentLivenessStep !=
                                      LivenessStep.completed &&
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
                  ],
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

              // Progress indicator for liveness steps
              if (_currentLivenessStep != LivenessStep.initial &&
                  !_isProcessing &&
                  !_hasError)
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _currentLivenessStep == LivenessStep.completed
                                ? Icons.check_circle
                                : Icons.remove_red_eye,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _currentLivenessStep == LivenessStep.completed
                                ? 'Liveness Verified ✓'
                                : 'Blink Detection',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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
