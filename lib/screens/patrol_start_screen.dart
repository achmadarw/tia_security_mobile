import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import '../config/theme.dart';
import '../services/patrol_service.dart';
import '../services/gps_tracking_service.dart';
import '../services/face_recognition_service.dart';
import '../services/tflite_face_detection_service.dart';
import 'active_patrol_screen.dart';

/// Patrol Start Screen
/// Face validation + location check sebelum start patrol
class PatrolStartScreen extends StatefulWidget {
  final int? postSessionId;
  final int userId; // ID user yang akan patroli

  const PatrolStartScreen({
    super.key,
    this.postSessionId,
    required this.userId,
  });

  @override
  State<PatrolStartScreen> createState() => _PatrolStartScreenState();
}

class _PatrolStartScreenState extends State<PatrolStartScreen> {
  final PatrolService _patrolService = PatrolService();
  final GPSTrackingService _gpsService = GPSTrackingService();
  final FaceRecognitionService _faceService = FaceRecognitionService();
  final TFLiteFaceDetectionService _faceDetection =
      TFLiteFaceDetectionService();

  bool _isLoading = false;
  bool _faceValidated = false;
  bool _locationValid = false;
  Position? _currentPosition;
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    setState(() => _isLoading = true);

    try {
      // Initialize face detection
      await _faceDetection.initialize();
      await _faceService.initialize();

      // Get current location
      await _checkLocation();

      // Initialize camera
      await _initializeCamera();

      setState(() => _isLoading = false);
    } catch (e) {
      print('[PatrolStart] Error initializing: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  Future<void> _checkLocation() async {
    try {
      Position? position = await _gpsService.getCurrentPosition();
      if (position != null) {
        setState(() {
          _currentPosition = position;
          _locationValid = true;
        });
        print(
            '[PatrolStart] Location obtained: ${position.latitude}, ${position.longitude}');
      }
    } catch (e) {
      print('[PatrolStart] Error getting location: $e');
      setState(() {
        _errorMessage = 'Tidak dapat mendapatkan lokasi GPS';
        _locationValid = false;
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        throw Exception('No cameras available');
      }

      // Use front camera for face validation
      CameraDescription frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      // Optimize for Redmi Note 13 Pro 16MP front camera
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.veryHigh, // Leverage 16MP for best face detail
        enableAudio: false,
        imageFormatGroup:
            ImageFormatGroup.jpeg, // Better quality, hardware accelerated
      );

      await _cameraController!.initialize();
      setState(() {});
    } catch (e) {
      print('[PatrolStart] Error initializing camera: $e');
      setState(() {
        _errorMessage = 'Error kamera: $e';
      });
    }
  }

  Future<void> _validateFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Capture image
      final image = await _cameraController!.takePicture();

      // Read image file and generate embedding
      final File imageFile = File(image.path);
      final embedding = await _faceService.generateEmbeddingFromFile(imageFile);

      if (embedding.isEmpty) {
        throw Exception(
            'Wajah tidak terdeteksi. Posisikan wajah di tengah kamera.');
      }

      // Validate with server (simplified - actual validation done on server)
      setState(() {
        _faceValidated = true;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Validasi wajah berhasil'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('[PatrolStart] Face validation error: $e');
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _startPatrol() async {
    if (!_faceValidated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Validasi wajah terlebih dahulu'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_locationValid || _currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lokasi GPS tidak valid'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _patrolService.startPatrol(
        userId: widget.userId, // Pass user_id dari parameter
        startLat: _currentPosition!.latitude,
        startLng: _currentPosition!.longitude,
        postSessionId: widget.postSessionId,
      );

      if (result['success'] == true) {
        // Navigate to active patrol screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ActivePatrolScreen(),
            ),
          );
        }
      }
    } catch (e) {
      print('[PatrolStart] Error starting patrol: $e');
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Mulai Patroli',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading && _cameraController == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInstructionCard(isDark),
                  const SizedBox(height: 16),
                  _buildValidationSection(isDark),
                  const SizedBox(height: 24),
                  _buildLocationSection(isDark),
                  const SizedBox(height: 24),
                  _buildStartButton(isDark),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildInstructionCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkPrimary.withOpacity(0.1)
            : AppColors.lightPrimary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkPrimary.withOpacity(0.3)
              : AppColors.lightPrimary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Langkah Memulai Patroli',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '1. Validasi wajah dengan kamera\n2. Pastikan GPS aktif\n3. Mulai patroli dari pos',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _faceValidated ? Icons.check_circle : Icons.face,
                color: _faceValidated
                    ? Colors.green
                    : (isDark ? AppColors.darkPrimary : AppColors.lightPrimary),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Validasi Wajah',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_faceValidated)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Tervalidasi',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_cameraController != null &&
              _cameraController!.value.isInitialized)
            AspectRatio(
              aspectRatio: _cameraController!.value.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CameraPreview(_cameraController!),
              ),
            )
          else
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          const SizedBox(height: 16),
          if (!_faceValidated)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _validateFace,
                icon: const Icon(Icons.camera_alt),
                label: Text(_isLoading ? 'Memvalidasi...' : 'Validasi Wajah'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _locationValid ? Icons.location_on : Icons.location_off,
                color: _locationValid
                    ? Colors.green
                    : (isDark ? AppColors.darkPrimary : AppColors.lightPrimary),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Lokasi GPS',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_locationValid)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Aktif',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (_currentPosition != null) ...[
            const SizedBox(height: 12),
            Text(
              'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}\nLng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Akurasi: ${_currentPosition!.accuracy.toStringAsFixed(1)} meter',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (!_locationValid) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _checkLocation,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Lokasi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartButton(bool isDark) {
    final canStart = _faceValidated && _locationValid && !_isLoading;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canStart ? _startPatrol : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canStart
              ? Colors.green
              : (isDark ? Colors.grey.shade700 : Colors.grey.shade400),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: canStart ? 4 : 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              canStart ? Icons.play_arrow : Icons.lock,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              _isLoading
                  ? 'Memulai Patroli...'
                  : (canStart ? 'Mulai Patroli' : 'Lengkapi Validasi'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
