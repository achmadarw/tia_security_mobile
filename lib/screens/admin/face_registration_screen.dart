import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../services/face_detection_service.dart';
import '../../services/face_recognition_service.dart';
import '../../config/theme.dart';
import '../../models/user.dart';

class FaceRegistrationScreen extends StatefulWidget {
  final User user;
  final String token;

  const FaceRegistrationScreen({
    Key? key,
    required this.user,
    required this.token,
  }) : super(key: key);

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  CameraController? _cameraController;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FaceRecognitionService _faceRecognitionService =
      FaceRecognitionService();

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isDetecting = false;

  String _statusMessage = 'Initializing camera...';
  Color _statusColor = Colors.orange;

  // Captured photos
  List<File> _capturedPhotos = [];
  List<List<double>> _embeddings = [];

  // Target: 10-15 photos from different angles
  final int _targetPhotos = 12;
  final List<String> _photoInstructions = [
    'Face straight ahead',
    'Slight left turn',
    'Slight right turn',
    'Slight up',
    'Slight down',
    'Smile',
    'Serious face',
    'Glasses on (if any)',
    'Glasses off (if any)',
    'Different lighting',
    'Neutral expression',
    'Final verification',
  ];

  int _currentPhotoIndex = 0;

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
        _statusMessage = _photoInstructions[_currentPhotoIndex];
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

        setState(() {
          _detectedFaces = faces;
          _imageSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );
        });

        if (faces.isNotEmpty && !_isProcessing) {
          final face = faces.first;

          // Check face quality
          final qualityCheck = _faceDetectionService.checkFaceQuality(
            face,
            _imageSize!,
          );

          if (!_isProcessing) {
            setState(() {
              if (qualityCheck['isGood']) {
                _statusMessage =
                    '✓ ${_photoInstructions[_currentPhotoIndex]} - Tap to capture';
                _statusColor = Colors.green;
              } else {
                _statusMessage = qualityCheck['message'];
                _statusColor = Colors.orange;
              }
            });
          }
        } else {
          if (!_isProcessing) {
            setState(() {
              _statusMessage = 'No face detected';
              _statusColor = Colors.orange;
            });
          }
        }
      } catch (e) {
        print('Detection error: $e');
      }

      _isDetecting = false;
    });
  }

  Future<void> _capturePhoto() async {
    if (_isProcessing) return;
    if (_detectedFaces.isEmpty) {
      _showSnackbar('No face detected', Colors.red);
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Capturing...';
      _statusColor = Colors.blue;
    });

    try {
      // Stop image stream temporarily
      await _cameraController?.stopImageStream();

      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();
      final File file = File(imageFile.path);

      // Detect face
      final faces = await _faceDetectionService.detectFacesFromFile(file);

      if (faces.isEmpty) {
        _showSnackbar('No face detected in captured image', Colors.red);
        _restartDetection();
        return;
      }

      final face = faces.first;

      // Extract face region
      final faceImage =
          await _faceDetectionService.extractFaceImage(file, face);

      if (faceImage == null) {
        _showSnackbar('Failed to extract face', Colors.red);
        _restartDetection();
        return;
      }

      // Generate embedding
      final embedding =
          await _faceRecognitionService.generateEmbedding(faceImage);

      // Save photo and embedding
      setState(() {
        _capturedPhotos.add(file);
        _embeddings.add(embedding);
        _currentPhotoIndex++;
      });

      _showSnackbar('Photo ${_capturedPhotos.length}/$_targetPhotos captured!',
          Colors.green);

      // Check if done
      if (_currentPhotoIndex >= _targetPhotos) {
        _uploadEmbeddings();
      } else {
        setState(() {
          _statusMessage = _photoInstructions[_currentPhotoIndex];
          _statusColor = AppColors.primary;
        });
        _restartDetection();
      }
    } catch (e) {
      _showSnackbar('Error: $e', Colors.red);
      _restartDetection();
    }
  }

  Future<void> _uploadEmbeddings() async {
    setState(() {
      _statusMessage = 'Uploading face data...';
      _statusColor = Colors.blue;
    });

    try {
      final result = await _faceRecognitionService.registerFace(
        userId: widget.user.id,
        embeddings: _embeddings,
        token: widget.token,
      );

      if (result['success']) {
        _showSnackbar('Face registration successful!', Colors.green);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop(true); // Return success
        }
      } else {
        _showSnackbar(result['message'] ?? 'Upload failed', Colors.red);
        setState(() {
          _statusMessage = 'Upload failed. Try again?';
          _statusColor = Colors.red;
        });
      }
    } catch (e) {
      _showSnackbar('Error uploading: $e', Colors.red);
    }
  }

  void _restartDetection() {
    setState(() {
      _isProcessing = false;
    });
    _startFaceDetection();
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _retakePhoto() {
    if (_capturedPhotos.isEmpty) return;

    setState(() {
      _capturedPhotos.removeLast();
      _embeddings.removeLast();
      _currentPhotoIndex--;
      _statusMessage = _photoInstructions[_currentPhotoIndex];
      _statusColor = AppColors.primary;
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Register Face - ${widget.user.name}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_capturedPhotos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _retakePhoto,
              tooltip: 'Retake last photo',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          if (_isInitialized && _cameraController != null)
            Center(
              child: AspectRatio(
                aspectRatio: _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            ),

          // Face detection overlay
          if (_isInitialized)
            CustomPaint(
              painter: FaceDetectorPainter(
                faces: _detectedFaces,
                imageSize: _imageSize ?? Size.zero,
                cameraPreviewSize: Size(
                  MediaQuery.of(context).size.width,
                  MediaQuery.of(context).size.height,
                ),
              ),
            ),

          // Status message
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _capturedPhotos.length / _targetPhotos,
                    backgroundColor: Colors.white30,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_capturedPhotos.length}/$_targetPhotos photos',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Thumbnail gallery
          if (_capturedPhotos.isNotEmpty)
            Positioned(
              left: 20,
              right: 20,
              bottom: 120,
              child: SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _capturedPhotos.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green, width: 2),
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(_capturedPhotos[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Capture button
          if (!_isProcessing && _currentPhotoIndex < _targetPhotos)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton.extended(
                  onPressed: _capturePhoto,
                  backgroundColor: _statusColor == Colors.green
                      ? Colors.green
                      : AppColors.primary,
                  icon: const Icon(Icons.camera_alt, size: 32),
                  label: Text(
                    'CAPTURE (${_capturedPhotos.length}/$_targetPhotos)',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),

          // Processing indicator
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Processing...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter for face detection overlay (reused from FaceLoginScreen)
class FaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final Size cameraPreviewSize;

  FaceDetectorPainter({
    required this.faces,
    required this.imageSize,
    required this.cameraPreviewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.greenAccent;

    for (final Face face in faces) {
      // Scale coordinates
      final scaleX = cameraPreviewSize.width / imageSize.width;
      final scaleY = cameraPreviewSize.height / imageSize.height;

      final rect = Rect.fromLTRB(
        face.boundingBox.left * scaleX,
        face.boundingBox.top * scaleY,
        face.boundingBox.right * scaleX,
        face.boundingBox.bottom * scaleY,
      );

      canvas.drawRect(rect, paint);

      // Draw center circle
      final center = Offset(
        rect.left + (rect.width / 2),
        rect.top + (rect.height / 2),
      );
      canvas.drawCircle(center, 5, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.faces != faces;
  }
}
