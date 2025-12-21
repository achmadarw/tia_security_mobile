import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/user.dart';
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../services/user_service.dart';
import '../config/theme.dart';

class FaceRegistrationScreen extends StatefulWidget {
  final User user;

  const FaceRegistrationScreen({super.key, required this.user});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  CameraController? _cameraController;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FaceRecognitionService _faceRecognitionService =
      FaceRecognitionService();
  final UserService _userService = UserService();

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isDetecting = false;
  bool _isUploading = false;

  List<File> _capturedImages = [];
  final int _requiredImages = 15;
  final int _minImages = 10;

  String _statusMessage = 'Initializing camera...';
  Color _statusColor = Colors.orange;

  List<Face> _detectedFaces = [];
  int _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
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
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Position your face in the frame';
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
      if (_isDetecting || _isProcessing || _isUploading) return;

      _isDetecting = true;

      try {
        final faces = await _faceDetectionService.detectFacesFromCamera(image);

        if (mounted) {
          setState(() {
            _detectedFaces = faces;

            if (faces.isEmpty) {
              _statusMessage = 'Posisikan wajah Anda di dalam frame';
              _statusColor = Colors.orange;
            } else if (faces.length > 1) {
              _statusMessage = 'Hanya 1 wajah yang diperbolehkan';
              _statusColor = Colors.red;
            } else {
              _statusMessage = 'Wajah terdeteksi! Tap untuk ambil foto';
              _statusColor = Colors.green;
            }
          });
        }
      } catch (e) {
        print('Face detection error: $e');
        if (mounted) {
          setState(() {
            _statusMessage = 'Tap tombol untuk ambil foto';
            _statusColor = AppColors.primary;
          });
        }
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<void> _captureImage() async {
    if (_isProcessing || _capturedImages.length >= _requiredImages) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await _cameraController!.stopImageStream();

      final image = await _cameraController!.takePicture();
      final file = File(image.path);

      setState(() {
        _capturedImages.add(file);
        _isProcessing = false;
        _statusMessage =
            'Foto ${_capturedImages.length}/$_requiredImages berhasil diambil';
        _statusColor = AppColors.primary;
      });

      if (_capturedImages.length < _requiredImages) {
        await Future.delayed(const Duration(milliseconds: 500));
        _startFaceDetection();
      } else {
        setState(() {
          _statusMessage = 'Semua foto sudah diambil! Siap upload';
          _statusColor = Colors.green;
        });
      }
    } catch (e) {
      print('Capture error: $e');
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error mengambil foto: $e';
        _statusColor = Colors.red;
      });
      _startFaceDetection();
    }
  }

  Future<void> _uploadImages() async {
    if (_capturedImages.length < _minImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Minimal $_minImages foto diperlukan')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _statusMessage = 'Memproses wajah...';
    });

    try {
      print('[FACE_REG] Starting upload for user: ${widget.user.id}');
      print('[FACE_REG] Number of images: ${_capturedImages.length}');

      // Skip embedding extraction for now - will be generated on-demand during login
      // This avoids TFLite initialization issues
      print('[FACE_REG] Uploading images without pre-computed embeddings');

      if (mounted) {
        setState(() {
          _statusMessage = 'Mengunggah...';
        });
      }

      final result = await _userService.registerFaceImages(
        userId: widget.user.id,
        images: _capturedImages,
        embeddings: null, // Will be computed on backend or on-demand
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _uploadProgress = ((current / total) * 100).round();
            });
          }
          print('[FACE_REG] Upload progress: $current/$total');
        },
      );

      print('[FACE_REG] Upload completed: $result');
      print('[FACE_REG] Mounted status: $mounted');

      if (!mounted) return;

      print('[FACE_REG] Showing success snackbar');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto wajah berhasil didaftarkan!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Delay to show success message before going back
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      print('[FACE_REG] Calling Navigator.pop');
      Navigator.pop(context, true);
      print('[FACE_REG] Navigator.pop called successfully');
    } catch (e) {
      print('[FACE_REG] Upload error: $e');
      setState(() => _isUploading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error upload: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _deleteImage(int index) {
    setState(() {
      _capturedImages.removeAt(index);
      if (_capturedImages.length < _requiredImages && !_isProcessing) {
        _statusMessage =
            'Capture more images (${_capturedImages.length}/$_requiredImages)';
        _statusColor = AppColors.primary;
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
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
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Column(
                  children: [
                    // Camera Preview
                    Expanded(
                      flex: 3,
                      child: _buildCameraPreview(),
                    ),

                    // Progress
                    _buildProgress(),

                    // Captured Images Grid
                    Expanded(
                      flex: 2,
                      child: _buildCapturedImagesGrid(),
                    ),

                    // Actions
                    _buildActions(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftarkan Wajah',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.user.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera with proper sizing
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

        // Face guide overlay
        Center(
          child: Container(
            width: 280,
            height: 350,
            decoration: BoxDecoration(
              border: Border.all(
                color: _detectedFaces.isNotEmpty ? Colors.green : Colors.white,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(180),
            ),
          ),
        ),

        // Status message
        Positioned(
          top: 16,
          left: 16,
          right: 16,
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
            ),
          ),
        ),

        // Capture button - Always show, not just when face detected
        if (_capturedImages.length < _requiredImages &&
            !_isProcessing &&
            !_isUploading)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _captureImage,
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
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_capturedImages.length}/$_requiredImages Foto',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_capturedImages.length >= _minImages)
                const Text(
                  'Siap Upload ✓',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _capturedImages.length / _requiredImages,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                _capturedImages.length >= _minImages
                    ? Colors.green
                    : AppColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapturedImagesGrid() {
    if (_capturedImages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 48, color: Colors.white38),
            const SizedBox(height: 8),
            const Text(
              'No images captured yet',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _capturedImages.length,
      itemBuilder: (context, index) {
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _capturedImages[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _deleteImage(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActions() {
    if (_isUploading) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Uploading... $_uploadProgress%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _uploadProgress / 100,
                minHeight: 10,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          if (_capturedImages.isNotEmpty)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _capturedImages.clear();
                    _statusMessage = 'Position your face in the frame';
                    _statusColor = AppColors.primary;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('RESET'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_capturedImages.isNotEmpty) const SizedBox(width: 16),
          if (_capturedImages.length >= _minImages)
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _uploadImages,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('UPLOAD'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
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
}

class FaceOverlayPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;

  FaceOverlayPainter({required this.faces, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.greenAccent;

    for (final face in faces) {
      final scaleX = size.width / imageSize.width;
      final scaleY = size.height / imageSize.height;

      final rect = Rect.fromLTRB(
        face.boundingBox.left * scaleX,
        face.boundingBox.top * scaleY,
        face.boundingBox.right * scaleX,
        face.boundingBox.bottom * scaleY,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
