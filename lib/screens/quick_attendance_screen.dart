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

  const QuickAttendanceScreen({super.key, required this.authService});

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
  final bool _needsCheckoutConfirmation = false;

  String _statusMessage = 'Checking attendance status...';
  Color _statusColor = Colors.orange;

  List<Face> _detectedFaces = [];

  // Liveness detection
  LivenessStep _currentLivenessStep = LivenessStep.initial;
  bool _eyesWereOpen = false;
  final List<File> _capturedImages = [];
  int _currentStep = 0;
  final int _totalSteps = 1; // Only blink detection, no head turn

  // Shift assignment
  Map<String, dynamic>? _todayAssignment;
  bool _isLoadingAssignment = true;

  @override
  void initState() {
    super.initState();
    _fetchTodayAssignment();
    _requestPermissions();
  }

  Future<void> _fetchTodayAssignment() async {
    try {
      final response = await widget.authService.getTodayAttendance();
      if (response != null) {
        // Response is direct from backend (no 'success' or 'data' wrapper)
        final assignments = response['assignments'] as List?;

        print('[QUICK_ATTENDANCE] Fetched assignment data');

        setState(() {
          _todayAssignment =
              assignments?.isNotEmpty == true ? assignments!.first : null;
          _isLoadingAssignment = false;
        });
      } else {
        setState(() {
          _isLoadingAssignment = false;
        });
      }
    } catch (e) {
      print('[QUICK_ATTENDANCE] Error fetching shift assignment: $e');
      setState(() {
        _isLoadingAssignment = false;
      });
    }
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

    // Always initialize camera (confirmation already done in home screen)
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

      // Optimize for Redmi Note 13 Pro 16MP front camera
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.veryHigh, // Leverage 16MP sensor for best face detail
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg, // Optimized compression
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
          _statusMessage = 'Kedipkan mata Anda';
          _statusColor = Colors.blue;
        });
      }
    } else if (_currentLivenessStep == LivenessStep.blinkFirst) {
      if (!_eyesWereOpen && eyesOpen) {
        // Eyes reopened after blink
        setState(() {
          _eyesWereOpen = true;
          _currentLivenessStep = LivenessStep.completed;
          _statusMessage = 'Liveness terverifikasi! Memproses...';
          _statusColor = Colors.green;
        });
        // Auto-capture after blink detected
        Future.delayed(const Duration(milliseconds: 300), () {
          _processAttendance();
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
        _currentStep = 1;
        _statusMessage = 'Kedipan terdeteksi! Buka mata...';
        _statusColor = Colors.orange;
        _eyesWereOpen = false;
      });
    }
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
      // EXACT same flow as face_login: Stop stream before capture
      if (_cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }

      // Capture image NOW (same as face_login)
      print('[QUICK_ATTENDANCE] Capturing image...');
      final XFile imageFile = await _cameraController!.takePicture();
      final File file = File(imageFile.path);
      print('[QUICK_ATTENDANCE] Image captured: ${file.path}');

      print('[QUICK_ATTENDANCE] Detecting faces...');
      final faces = await _faceDetectionService.detectFacesFromFile(file);
      print('[QUICK_ATTENDANCE] Faces detected: ${faces.length}');

      if (faces.isEmpty) {
        _showError('Wajah tidak terdeteksi. Silakan coba lagi.');
        return;
      }

      if (faces.length > 1) {
        _showError('Terdeteksi lebih dari 1 wajah.');
        return;
      }

      final face = faces.first;
      print('[QUICK_ATTENDANCE] Extracting embedding...');

      final faceImage =
          await _faceDetectionService.extractFaceImage(file, face);

      if (faceImage == null) {
        _showError('Gagal mengekstrak wajah.');
        return;
      }

      print(
          '[QUICK_ATTENDANCE] Face extracted: ${faceImage.width}x${faceImage.height}');

      // DEBUG: Log face detection details
      print('[QUICK_ATTENDANCE] === Face Detection Debug ===');
      print(
          '[QUICK_ATTENDANCE] Face bounding box: ${face.boundingBox.left.toInt()},${face.boundingBox.top.toInt()} ${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()}');
      print(
          '[QUICK_ATTENDANCE] Head angles: Y=${face.headEulerAngleY?.toStringAsFixed(2)}°, Z=${face.headEulerAngleZ?.toStringAsFixed(2)}°');

      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      if (leftEye != null && rightEye != null) {
        print(
            '[QUICK_ATTENDANCE] Left eye: (${leftEye.position.x.toInt()}, ${leftEye.position.y.toInt()})');
        print(
            '[QUICK_ATTENDANCE] Right eye: (${rightEye.position.x.toInt()}, ${rightEye.position.y.toInt()})');

        final deltaY = rightEye.position.y - leftEye.position.y;
        final deltaX = rightEye.position.x - leftEye.position.x;
        final angleRad = atan2(deltaY, deltaX);
        final angleDeg = angleRad * 180 / pi;
        print(
            '[QUICK_ATTENDANCE] Eye rotation angle: ${angleDeg.toStringAsFixed(2)}°');
      }

      print(
          '[QUICK_ATTENDANCE] Left eye open: ${face.leftEyeOpenProbability?.toStringAsFixed(2)}');
      print(
          '[QUICK_ATTENDANCE] Right eye open: ${face.rightEyeOpenProbability?.toStringAsFixed(2)}');
      print('[QUICK_ATTENDANCE] === End Debug ===');

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Memvalidasi kualitas foto...';
      });

      print('[QUICK_ATTENDANCE] Generating embedding with quality checks...');

      // EXACT same method as face_login
      List<double> embedding;
      try {
        final result =
            await _faceRecognitionService.generateEmbeddingWithQuality(
          faceImage,
          face,
          isStrictMode: false, // Same as face_login
        );

        embedding = result['embedding'];
        final qualityScore = result['qualityScore'] ?? 0.0;

        print(
            '[QUICK_ATTENDANCE] ✅ Embedding generated: ${embedding.length} dimensions');
        print('[QUICK_ATTENDANCE] Quality score: $qualityScore%');

        if (!mounted) return;

        setState(() {
          _statusMessage = 'Mengenali wajah...';
        });
      } catch (e) {
        print('[QUICK_ATTENDANCE] Embedding generation error: $e');
        _showError('Gagal generate embedding: $e');
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

      // Determine attendance type based on current status
      String attendanceType = 'check_in';
      try {
        final todayData = await widget.authService.getTodayAttendance();
        if (todayData != null && todayData['isCheckedIn'] == true) {
          attendanceType = 'check_out';
        }
      } catch (e) {
        print(
            '[QUICK_ATTENDANCE] Error checking status, defaulting to check_in: $e');
      }

      print('[QUICK_ATTENDANCE] Submitting attendance: $attendanceType');

      // Submit attendance to backend
      final result = await widget.authService.submitAttendanceWithFace(
        embedding,
        attendanceType,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      print('[QUICK_ATTENDANCE] Attendance result: ${result['success']}');

      if (result['success']) {
        final data = result['data'];
        final confidence = result['confidence'] ?? 0.0;

        if (result['requiresReverification'] == true) {
          _showSuccessDialog(
            'Attendance Pending Review',
            'Your attendance has been submitted for manual verification.\nConfidence: ${confidence.toStringAsFixed(1)}%',
          );
        } else {
          final type = data['type'] ?? attendanceType;
          final time = data['checkTime'] ?? DateTime.now().toString();

          _showSuccessDialog(
            type == 'check_in' ? 'Check-in Berhasil!' : 'Check-out Berhasil!',
            'Waktu: $time\nConfidence: ${confidence.toStringAsFixed(1)}%',
          );
        }
      } else {
        // Check for non-retryable errors (dialog instead of retry button)
        final error = result['error'];
        if (error != null &&
            error.toString().toUpperCase() == 'ALREADY_CHECKED_IN') {
          _showAlreadyCheckedInDialog();
          return;
        }

        if (error != null &&
            error.toString().toUpperCase() == 'SHIFT_NOT_ENDED') {
          _showShiftNotEndedDialog(result['message']);
          return;
        }

        if (result['requiresReverification'] == true) {
          _showError(
              'Absensi menunggu verifikasi: ${_translateErrorReason(result['reason'])}');
        } else {
          String errorMsg = _translateAttendanceError(result['error']) ??
              'Wajah tidak dikenali';

          // Add confidence info if available
          if (result['confidence'] != null) {
            final confidence = result['confidence'];
            errorMsg +=
                '\n\nTingkat kepercayaan: ${confidence.toStringAsFixed(1)}%';
          }

          _showError(errorMsg);
        }
      }
    } catch (e, stackTrace) {
      ErrorHandler.logError('QUICK_ATTENDANCE', e, stackTrace: stackTrace);
      _showError(ErrorHandler.getUserFriendlyMessage(e));
    }
  }

  // Translate attendance error codes to Indonesian
  String _translateAttendanceError(String? error) {
    if (error == null) return 'Wajah tidak dikenali';

    final errorUpper = error.toUpperCase();

    // Check for specific error codes
    if (errorUpper.contains('CONFIDENCE_TOO_LOW') ||
        errorUpper.contains('CONFIDENCE TOO LOW') ||
        errorUpper == 'CONFIDENCE_TOO_LOW') {
      return 'Silakan coba lagi dengan pencahayaan lebih baik dan posisi wajah lebih jelas.';
    }

    if (errorUpper.contains('INSUFFICIENT_MARGIN') ||
        errorUpper.contains('MARGIN')) {
      return 'Wajah terlalu mirip dengan pengguna lain.\nSilakan coba lagi dengan pencahayaan lebih baik.';
    }

    if (errorUpper.contains('NO_MATCH') ||
        errorUpper.contains('NOT_RECOGNIZED')) {
      return 'Wajah tidak dikenali.\nPastikan Anda sudah terdaftar dan pencahayaan cukup.';
    }

    if (errorUpper.contains('QUALITY')) {
      return 'Kualitas gambar tidak memenuhi syarat.\nSilakan coba lagi dengan pencahayaan lebih baik.';
    }

    if (errorUpper.contains('NO REGISTERED FACE') ||
        errorUpper.contains('NO_EMBEDDINGS')) {
      return 'Anda belum mendaftarkan wajah.\nSilakan daftar wajah terlebih dahulu.';
    }

    if (errorUpper.contains('MULTIPLE_FACES')) {
      return 'Terdeteksi lebih dari satu wajah.\nPastikan hanya wajah Anda yang terlihat.';
    }

    if (errorUpper.contains('SHIFT_NOT_ENDED')) {
      return 'Anda sudah menyelesaikan shift hari ini.\nAnda dapat check-in lagi setelah jam shift berakhir.';
    }

    // Return original error if no translation found
    return error;
  }

  // Translate error reason to Indonesian
  String _translateErrorReason(String? reason) {
    if (reason == null) return 'Confidence rendah';

    switch (reason.toLowerCase()) {
      case 'low_confidence':
        return 'Confidence rendah';
      case 'multiple_matches':
        return 'Terlalu mirip dengan pengguna lain';
      case 'anomaly_detected':
        return 'Terdeteksi anomali';
      case 'manual_request':
        return 'Permintaan manual';
      case 'quality_poor':
        return 'Kualitas gambar buruk';
      default:
        return reason;
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
                  context, true); // Close attendance screen with result=true
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCheckoutConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.blue, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Konfirmasi Check-Out',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Anda sudah check-in hari ini.\n\nApakah Anda ingin melakukan check-out sekarang?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close attendance screen
            },
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              // Initialize camera for checkout
              setState(() {
                _statusMessage = 'Initializing camera for check-out...';
              });
              await _initializeServices();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ya, Check-Out'),
          ),
        ],
      ),
    );
  }

  void _showAlreadyCheckedInDialog() async {
    // Stop camera stream
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
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sudah Check-In',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Anda sudah melakukan check-in hari ini.\n\nJika ingin check-out, silakan gunakan fitur check-out.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close attendance screen
            },
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showShiftNotEndedDialog(String? message) async {
    // Stop camera stream
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
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.schedule, color: Colors.orange, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Shift Belum Berakhir',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message ??
              'Anda sudah menyelesaikan shift hari ini. Anda dapat check-in lagi setelah jam shift berakhir.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close attendance screen
            },
            child: const Text('Tutup'),
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
              // Loading indicator while checking status
              if (_isLoadingAssignment && !_isInitialized)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: Colors.white,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _statusMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

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
                child: Column(
                  children: [
                    // Shift assignment card

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
                  !_isProcessing)
                Positioned(
                  top: 120,
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
                            'Step $_currentStep/$_totalSteps',
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
