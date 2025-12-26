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

// Liveness detection steps
enum LivenessStep {
  initial, // Initial face detection
  blinkFirst, // Blink 1st time
  blinkSecond, // Blink 2nd time (captured)
  turnLeft, // Turn head left
  turnRight, // Turn head right
  tiltUp, // Tilt head up
  tiltDown, // Tilt head down
  smile, // Smile
  neutral, // Neutral/serious expression
  completed, // All steps completed (7 photos total)
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
  DateTime? _neutralStepStartTime; // Track when neutral step started
  bool _isUploading = false;

  List<File> _capturedImages = [];
  final int _requiredImages =
      7; // 7 liveness photos: blink2, turnLeft, turnRight, tiltUp, tiltDown, smile, neutral
  final int _minImages = 7; // Require all 7 liveness photos

  String _statusMessage = 'Initializing camera...';
  Color _statusColor = Colors.orange;

  List<Face> _detectedFaces = [];
  int _uploadProgress = 0;

  // Lighting detection
  double _lightingQuality = 0.0; // 0.0 to 1.0
  String _lightingStatus = 'Memeriksa...';
  bool _isLightingGood = false;
  bool _isStreaming = false; // Track camera stream state

  // Liveness detection
  LivenessStep _currentLivenessStep = LivenessStep.initial;
  bool _livenessCompleted = false;
  bool _eyesWereOpen = false; // Track if eyes were open (for blink detection)
  bool _isInLivenessMode = true; // Start with liveness check first
  bool _isPendingCapture = false; // Prevent multiple capture triggers

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    print('[DEBUG] Initializing face registration services...');
    await _faceDetectionService.initialize();
    print('[DEBUG] Face detection service initialized');
    await _faceRecognitionService.initialize();
    print('[DEBUG] Face recognition service initialized');
    await _initializeCamera();
    print('[DEBUG] Camera initialized');
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
      print('[DEBUG] Cannot start face detection - camera not initialized');
      return;
    }

    if (_isStreaming) {
      print('[DEBUG] Image stream already running, skipping start');
      return;
    }

    print('[DEBUG] Starting face detection image stream...');
    _isStreaming = true;
    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting || _isProcessing || _isUploading) return;

      _isDetecting = true;

      try {
        // Detect lighting quality from camera image
        _detectLightingQuality(image);

        final faces = await _faceDetectionService.detectFacesFromCamera(image);
        print('[DEBUG] Faces detected: ${faces.length}');

        if (mounted) {
          setState(() {
            _detectedFaces = faces;

            if (faces.isEmpty) {
              _statusMessage = 'Posisikan wajah Anda di dalam frame';
              _statusColor = Colors.orange;
              print('[DEBUG] Status: No face detected');
            } else if (faces.length > 1) {
              _statusMessage = 'Hanya 1 wajah yang diperbolehkan';
              _statusColor = Colors.red;
              print(
                  '[DEBUG] Status: Multiple faces detected (${faces.length})');
            } else {
              // Single face detected
              if (_isInLivenessMode && !_livenessCompleted) {
                // Liveness detection mode
                _performLivenessDetection(faces.first);
              } else {
                // Normal capture mode
                _statusMessage = 'Wajah terdeteksi! Tap untuk ambil foto';
                _statusColor = Colors.green;
                print('[DEBUG] Status: Face detected and ready for capture');
              }
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

  void _performLivenessDetection(Face face) {
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    final headYaw = face.headEulerAngleY ?? 0.0; // Left/Right turn
    final smiling = face.smilingProbability ?? 0.0;

    bool bothEyesOpen = leftEyeOpen > 0.5 && rightEyeOpen > 0.5;
    bool bothEyesClosed = leftEyeOpen < 0.3 && rightEyeOpen < 0.3;
    bool isLookingStraight = headYaw.abs() < 10;
    bool isTurnedLeft =
        headYaw < -30; // Increased threshold for clearer left turn
    bool isTurnedRight =
        headYaw > 30; // Increased threshold for clearer right turn
    bool isSmiling = smiling > 0.7;

    switch (_currentLivenessStep) {
      case LivenessStep.initial:
        if (bothEyesOpen) {
          setState(() {
            _statusMessage = 'Kedipkan mata Anda (1/2)';
            _statusColor = Colors.blue;
            _currentLivenessStep = LivenessStep.blinkFirst;
            _eyesWereOpen = true;
          });
        } else {
          setState(() {
            _statusMessage = 'Buka mata Anda';
            _statusColor = Colors.orange;
          });
        }
        break;

      case LivenessStep.blinkFirst:
        if (_eyesWereOpen && bothEyesClosed) {
          // Eyes closed after being open = blink detected
          _eyesWereOpen = false;
          print('[LIVENESS] First blink detected!');
        } else if (!_eyesWereOpen && bothEyesOpen) {
          // Eyes opened again
          setState(() {
            _statusMessage = 'Bagus! Kedipkan lagi (2/2)';
            _statusColor = Colors.green;
            _currentLivenessStep = LivenessStep.blinkSecond;
            _eyesWereOpen = true;
          });
          print('[LIVENESS] First blink completed!');
        } else if (bothEyesOpen) {
          _eyesWereOpen = true;
        }
        break;

      case LivenessStep.blinkSecond:
        if (_eyesWereOpen && bothEyesClosed) {
          // Second blink started - eyes are closed now
          _eyesWereOpen = false;
          print('[LIVENESS] Second blink detected!');

          // Capture IMMEDIATELY while eyes are CLOSED
          if (!_isPendingCapture) {
            _isPendingCapture = true;
            print('[LIVENESS] Capturing blink2 while eyes CLOSED!');

            _captureImage().then((_) {
              if (mounted) {
                setState(() {
                  _statusMessage = 'Sempurna! Foto berhasil 📸';
                  _statusColor = Colors.green;
                });

                Future.delayed(const Duration(milliseconds: 800), () {
                  if (mounted) {
                    setState(() {
                      _currentLivenessStep = LivenessStep.turnLeft;
                      _isPendingCapture = false;
                      _statusMessage = 'Tengok kepala ke KIRI';
                      _statusColor = Colors.blue;
                      print(
                          '[LIVENESS] 📸 Photos captured: ${_capturedImages.length}/$_requiredImages');
                    });
                  }
                });
              }
            }).catchError((error) {
              print('[LIVENESS] Capture error: $error');
              if (mounted) {
                setState(() {
                  _isPendingCapture = false;
                  _statusMessage = 'Error capture, coba lagi';
                  _statusColor = Colors.red;
                });
              }
            });
          }
        } else if (!_eyesWereOpen && bothEyesOpen) {
          // Eyes opened again after being closed - just track state
          _eyesWereOpen = true;
        } else if (bothEyesOpen) {
          _eyesWereOpen = true;
        }
        break;

      case LivenessStep.turnLeft:
        print(
            '[LIVENESS] TurnLeft check - HeadYaw: $headYaw, isTurnedLeft: $isTurnedLeft');

        if (isTurnedLeft && !_isPendingCapture) {
          _isPendingCapture = true; // Prevent multiple triggers
          print('[LIVENESS] Head turned left - capturing immediately!');

          // Capture immediately while pose is held
          _captureImage().then((_) {
            if (mounted) {
              // Show success feedback and update step together
              setState(() {
                _statusMessage = 'Bagus! Foto berhasil 📸';
                _statusColor = Colors.green;
              });

              // Update to next step after brief delay
              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) {
                  setState(() {
                    _currentLivenessStep = LivenessStep.turnRight;
                    _isPendingCapture = false; // Reset flag
                    _statusMessage = 'Tengok kepala ke KANAN';
                    _statusColor = Colors.blue;
                    print(
                        '[LIVENESS] Photos captured: ${_capturedImages.length}/$_requiredImages');
                  });
                }
              });
            }
          }).catchError((error) {
            print('[LIVENESS] Capture error: $error');
            // Reset flag on error to allow retry
            if (mounted) {
              setState(() {
                _isPendingCapture = false;
                _statusMessage = 'Error capture, coba lagi';
                _statusColor = Colors.red;
              });
            }
          });
        } else if (isLookingStraight) {
          setState(() {
            _statusMessage = 'Tengok kepala ke KIRI';
            _statusColor = Colors.blue;
          });
        }
        break;

      case LivenessStep.turnRight:
        print(
            '[LIVENESS] TurnRight check - HeadYaw: $headYaw, isTurnedRight: $isTurnedRight');

        if (isTurnedRight && !_isPendingCapture) {
          _isPendingCapture = true; // Prevent multiple triggers
          print('[LIVENESS] Head turned right - capturing immediately!');

          // Capture immediately while pose is held
          _captureImage().then((_) {
            if (mounted) {
              setState(() {
                _statusMessage = 'Sempurna! Foto berhasil 📸';
                _statusColor = Colors.green;
              });

              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) {
                  setState(() {
                    _currentLivenessStep = LivenessStep.tiltUp;
                    _isPendingCapture = false;
                    _statusMessage = 'Dongakkan kepala ke ATAS';
                    _statusColor = Colors.blue;
                    print(
                        '[LIVENESS] 📸 Photos captured: ${_capturedImages.length}/$_requiredImages');
                  });
                }
              });
            }
          }).catchError((error) {
            print('[LIVENESS] Capture error: $error');
            if (mounted) {
              setState(() {
                _isPendingCapture = false;
                _statusMessage = 'Error capture, coba lagi';
                _statusColor = Colors.red;
              });
            }
          });
        } else if (isLookingStraight) {
          setState(() {
            _statusMessage = 'Tengok kepala ke KANAN';
            _statusColor = Colors.blue;
          });
        }
        break;

      case LivenessStep.tiltUp:
        final headPitch = face.headEulerAngleX ?? 0.0; // Up/Down tilt
        bool isTiltedUp =
            headPitch > 20; // POSITIVE = looking up (increased threshold)

        print(
            '[LIVENESS] TiltUp check - HeadPitch: $headPitch, isTiltedUp: $isTiltedUp');

        if (isTiltedUp && !_isPendingCapture) {
          _isPendingCapture = true; // Prevent multiple triggers
          print('[LIVENESS] Head tilted up - capturing immediately!');

          // Capture immediately while pose is held
          _captureImage().then((_) {
            if (mounted) {
              setState(() {
                _statusMessage = 'Bagus! Foto berhasil 📸';
                _statusColor = Colors.green;
              });

              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) {
                  setState(() {
                    _currentLivenessStep = LivenessStep.tiltDown;
                    _isPendingCapture = false;
                    _statusMessage = 'Tundukkan kepala ke BAWAH';
                    _statusColor = Colors.blue;
                    print(
                        '[LIVENESS] 📸 Photos captured: ${_capturedImages.length}/$_requiredImages');
                  });
                }
              });
            }
          }).catchError((error) {
            print('[LIVENESS] Capture error: $error');
            if (mounted) {
              setState(() {
                _isPendingCapture = false;
                _statusMessage = 'Error capture, coba lagi';
                _statusColor = Colors.red;
              });
            }
          });
        } else {
          setState(() {
            _statusMessage = 'Dongakkan kepala ke ATAS';
            _statusColor = Colors.blue;
          });
        }
        break;

      case LivenessStep.tiltDown:
        final headPitchDown = face.headEulerAngleX ?? 0.0;
        bool isTiltedDown =
            headPitchDown < -20; // NEGATIVE = looking down (increased from -15)

        print(
            '[LIVENESS] TiltDown check - HeadPitch: $headPitchDown, isTiltedDown: $isTiltedDown');

        if (isTiltedDown && !_isPendingCapture) {
          _isPendingCapture = true; // Prevent multiple triggers
          print('[LIVENESS] Head tilted down - capturing immediately!');

          // Capture immediately while pose is held
          _captureImage().then((_) {
            if (mounted) {
              setState(() {
                _statusMessage = 'Sempurna! Foto berhasil 📸';
                _statusColor = Colors.green;
              });

              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) {
                  setState(() {
                    _currentLivenessStep = LivenessStep.smile;
                    _isPendingCapture = false;
                    _statusMessage = 'TERSENYUM 😊';
                    _statusColor = Colors.blue;
                    print(
                        '[LIVENESS] 📸 Photos captured: ${_capturedImages.length}/$_requiredImages');
                  });
                }
              });
            }
          }).catchError((error) {
            print('[LIVENESS] Capture error: $error');
            if (mounted) {
              setState(() {
                _isPendingCapture = false;
                _statusMessage = 'Error capture, coba lagi';
                _statusColor = Colors.red;
              });
            }
          });
        } else {
          setState(() {
            _statusMessage = 'Tundukkan kepala ke BAWAH';
            _statusColor = Colors.blue;
          });
        }
        break;

      case LivenessStep.smile:
        if (isSmiling && !_isPendingCapture) {
          _isPendingCapture = true; // Prevent multiple triggers
          print('[LIVENESS] Smile detected - capturing immediately!');

          // Capture immediately while smiling
          _captureImage().then((_) {
            if (mounted) {
              setState(() {
                _statusMessage = 'Sempurna! Foto berhasil 📸';
                _statusColor = Colors.green;
              });

              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) {
                  setState(() {
                    _currentLivenessStep = LivenessStep.neutral;
                    _isPendingCapture = false;
                    _statusMessage = 'Wajah NETRAL (jangan senyum)';
                    _statusColor = Colors.blue;
                    print(
                        '[LIVENESS] 📸 Photos captured: ${_capturedImages.length}/$_requiredImages');
                  });
                }
              });
            }
          }).catchError((error) {
            print('[LIVENESS] Capture error: $error');
            if (mounted) {
              setState(() {
                _isPendingCapture = false;
                _statusMessage = 'Error capture, coba lagi';
                _statusColor = Colors.red;
              });
            }
          });
        } else {
          setState(() {
            _statusMessage = 'TERSENYUM 😊';
            _statusColor = Colors.blue;
          });
        }
        break;

      case LivenessStep.neutral:
        bool isNotSmiling = smiling < 0.3; // Not smiling

        // Initialize timer when entering neutral step
        if (_neutralStepStartTime == null) {
          _neutralStepStartTime = DateTime.now();
        }

        // Require 2 seconds in neutral state to ensure transition from smile
        final neutralDuration =
            DateTime.now().difference(_neutralStepStartTime!);
        final isNeutralLongEnough = neutralDuration.inMilliseconds >= 2000;

        if (isNotSmiling &&
            bothEyesOpen &&
            isNeutralLongEnough &&
            !_isPendingCapture) {
          _isPendingCapture = true; // Prevent multiple triggers
          print(
              '[LIVENESS] Neutral face detected (held for ${neutralDuration.inSeconds}s) - capturing immediately!');

          // Capture immediately while neutral
          _captureImage().then((_) {
            if (mounted) {
              setState(() {
                _statusMessage = 'Bagus! Foto berhasil 📸';
                _statusColor = Colors.green;
              });

              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) {
                  setState(() {
                    _currentLivenessStep = LivenessStep.completed;
                    _livenessCompleted = true;
                    _isInLivenessMode = false;
                    _isPendingCapture = false;
                    _neutralStepStartTime = null; // Reset timer
                    _statusMessage = 'Verifikasi Liveness Berhasil! ✓';
                    _statusColor = Colors.green;
                    print(
                        '[LIVENESS] All steps completed! Total photos: ${_capturedImages.length}/$_requiredImages');
                  });
                }
              });
            }
          }).catchError((error) {
            print('[LIVENESS] Capture error: $error');
            if (mounted) {
              setState(() {
                _isPendingCapture = false;
                _statusMessage = 'Error capture, coba lagi';
                _statusColor = Colors.red;
              });
            }
          });
        } else {
          setState(() {
            if (!isNotSmiling) {
              _statusMessage = 'Wajah NETRAL (jangan senyum)';
            } else if (!isNeutralLongEnough) {
              final remaining = 2 - neutralDuration.inSeconds;
              _statusMessage = 'Tahan netral... ($remaining detik)';
            }
            _statusColor = Colors.blue;
          });
        }
        break;

      case LivenessStep.completed:
        // All 7 photos captured - ready to upload
        // No action needed, just display completed state
        break;
    }
  }

  void _detectLightingQuality(CameraImage image) {
    // Calculate average brightness from Y plane (luminance)
    if (image.planes.isEmpty) return;

    final yPlane = image.planes[0];
    final int totalPixels = yPlane.bytes.length;

    if (totalPixels == 0) return;

    int sum = 0;
    for (int i = 0; i < totalPixels; i++) {
      sum += yPlane.bytes[i];
    }

    final double averageBrightness = sum / totalPixels;

    // Normalize to 0.0 - 1.0 scale
    _lightingQuality = averageBrightness / 255.0;

    // Determine lighting status
    // Good lighting: 0.25 - 0.85 (avoid too dark or overexposed)
    if (_lightingQuality < 0.15) {
      _lightingStatus = 'Terlalu Gelap';
      _isLightingGood = false;
    } else if (_lightingQuality > 0.90) {
      _lightingStatus = 'Terlalu Terang';
      _isLightingGood = false;
    } else if (_lightingQuality < 0.25) {
      _lightingStatus = 'Kurang Cahaya';
      _isLightingGood = false;
    } else {
      _lightingStatus = 'Bagus';
      _isLightingGood = true;
    }

    print(
        '[DEBUG] Lighting: ${(_lightingQuality * 100).toStringAsFixed(1)}% - $_lightingStatus');
  }

  Future<void> _captureImage() async {
    print('[DEBUG] Capture button pressed!');

    // Skip liveness check for auto-capture during liveness steps
    // Manual capture after liveness will check via button visibility

    if (!_isLightingGood) {
      print(
          '[DEBUG] Cannot capture - lighting quality is poor: $_lightingStatus');
      if (mounted) {
        // Reset pending flag to allow retry
        _isPendingCapture = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Pencahayaan $_lightingStatus - Perbaiki pencahayaan terlebih dahulu'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (_isProcessing || _capturedImages.length >= _requiredImages) {
      print(
          '[DEBUG] Cannot capture - isProcessing: $_isProcessing, captured: ${_capturedImages.length}/$_requiredImages');
      return;
    }

    print('[DEBUG] Starting image capture...');
    setState(() => _isProcessing = true);

    try {
      // Stop image stream only if it's running
      if (_isStreaming) {
        await _cameraController!.stopImageStream();
        _isStreaming = false;
        print('[DEBUG] Image stream stopped for capture');
      }

      final image = await _cameraController!.takePicture();
      final originalFile = File(image.path);

      // Generate descriptive filename with timestamp
      String poseVariation = _getLivenessStepName(_currentLivenessStep);
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String newFileName =
          'face_${widget.user.id}_${poseVariation}_$timestamp.jpg';

      // Create new path with descriptive name
      final directory = originalFile.parent;
      final newPath = '${directory.path}/$newFileName';
      final file = await originalFile.copy(newPath);

      print('[DEBUG] Image captured and renamed: $newFileName');

      setState(() {
        _capturedImages.add(file);
        _isProcessing = false;
        _statusMessage =
            'Foto ${_capturedImages.length}/$_requiredImages berhasil diambil';
        _statusColor = AppColors.primary;
      });
      print(
          '[DEBUG] ✅ Total images captured: ${_capturedImages.length}/$_requiredImages');
      print('[DEBUG] 📊 Progress updated in UI');

      if (_capturedImages.length < _requiredImages) {
        await Future.delayed(const Duration(milliseconds: 500));
        print('[DEBUG] Restarting face detection for next capture');
        _startFaceDetection();
      } else {
        print('[DEBUG] All required images captured!');
        setState(() {
          _statusMessage = 'Semua foto sudah diambil! Siap upload';
          _statusColor = Colors.green;
        });
      }
    } catch (e) {
      print('Capture error: $e');
      _isStreaming = false; // Reset stream state
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error mengambil foto: $e';
        _statusColor = Colors.red;
      });
      // Wait a bit before restarting to avoid rapid retry
      await Future.delayed(const Duration(milliseconds: 300));
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

      if (mounted) {
        setState(() {
          _statusMessage = 'Mengunggah...';
        });
      }

      final result = await _userService.registerFaceImages(
        userId: widget.user.id,
        images: _capturedImages,
        embeddings: null,
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto wajah berhasil didaftarkan!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.pop(context, true);
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

  String _getLivenessStepName(LivenessStep step) {
    switch (step) {
      case LivenessStep.initial:
        return 'initial';
      case LivenessStep.blinkFirst:
        return 'blink1';
      case LivenessStep.blinkSecond:
        return 'blink2';
      case LivenessStep.turnLeft:
        return 'turn_left';
      case LivenessStep.turnRight:
        return 'turn_right';
      case LivenessStep.tiltUp:
        return 'tilt_up';
      case LivenessStep.tiltDown:
        return 'tilt_down';
      case LivenessStep.smile:
        return 'smile';
      case LivenessStep.neutral:
        return 'neutral';
      case LivenessStep.completed:
        return 'completed';
    }
  }

  IconData _getLivenessIcon() {
    switch (_currentLivenessStep) {
      case LivenessStep.initial:
        return Icons.face;
      case LivenessStep.blinkFirst:
      case LivenessStep.blinkSecond:
        return Icons.remove_red_eye;
      case LivenessStep.turnLeft:
        return Icons.arrow_forward; // Panah kanan untuk putar kiri (mirrored)
      case LivenessStep.turnRight:
        return Icons.arrow_back; // Panah kiri untuk putar kanan (mirrored)
      case LivenessStep.tiltUp:
        return Icons.arrow_upward;
      case LivenessStep.tiltDown:
        return Icons.arrow_downward;
      case LivenessStep.smile:
        return Icons.sentiment_satisfied_alt;
      case LivenessStep.neutral:
        return Icons.sentiment_neutral;
      case LivenessStep.completed:
        return Icons.check_circle;
    }
  }

  @override
  void dispose() async {
    // Safely stop image stream before disposing
    try {
      if (_isStreaming && _cameraController?.value.isStreamingImages == true) {
        await _cameraController?.stopImageStream();
        _isStreaming = false;
        print('[DEBUG] Image stream stopped in dispose');
      }
    } catch (e) {
      print('[DEBUG] Error stopping stream in dispose: $e');
    }
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fullscreen camera preview (with frame and labels ONLY, no button)
          _buildFullscreenCamera(),

          // Floating header at top with gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: _buildModernHeader(),
              ),
            ),
          ),

          // Progress and thumbnails at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildProgress(),
                    // Thumbnail strip removed - using progress dots instead
                    _buildModernActions(),
                  ],
                ),
              ),
            ),
          ),

          // CAPTURE BUTTON - placed AFTER bottom overlay so it's on top
          // During liveness: hidden/disabled
          // After liveness: enabled for manual capture
          if (_livenessCompleted && _capturedImages.length < _requiredImages)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: (_isProcessing || !_isLightingGood)
                      ? null
                      : _captureImage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 75,
                    height: 75,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_isProcessing || !_isLightingGood)
                          ? Colors.grey[400]
                          : Colors.white,
                      border: Border.all(
                        color: (_isProcessing || !_isLightingGood)
                            ? Colors.grey[600]!
                            : Colors.grey[300]!,
                        width: 5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: _isProcessing
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                              color: Colors.grey,
                              strokeWidth: 3,
                            ),
                          )
                        : Icon(
                            Icons.camera_alt,
                            size: 35,
                            color: !_isLightingGood
                                ? Colors.grey[600]
                                : Colors.grey[700],
                          ),
                  ),
                ),
              ),
            ),

          // Upload progress overlay
          if (_isUploading)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'Uploading... $_uploadProgress%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
                color: _statusColor,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(200),
            ),
          ),
        ),

        // Status message
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _detectedFaces.isEmpty
                      ? Icons.face
                      : _detectedFaces.length == 1
                          ? Icons.check_circle
                          : Icons.warning,
                  color: _statusColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Capture button
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton.large(
              onPressed: _isProcessing ? null : _captureImage,
              backgroundColor: _isProcessing ? Colors.grey : Colors.white,
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.camera_alt, size: 32, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Foto ${_capturedImages.length}/$_requiredImages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${((_capturedImages.length / _requiredImages) * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _capturedImages.length / _requiredImages,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildCapturedImagesGrid() {
    if (_capturedImages.isEmpty) {
      return const SizedBox.shrink();
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
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _capturedImages[index],
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _deleteImage(index),
                child: Container(
                  padding: const EdgeInsets.all(2),
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
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _capturedImages.length >= _minImages && !_isUploading
                  ? _uploadImages
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isUploading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Uploading... $_uploadProgress%',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Upload (${_capturedImages.length}/$_minImages)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Modern UI methods
  Widget _buildModernHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
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
          // Counter badge moved to separate positioned widget
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${_capturedImages.length}/$_requiredImages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullscreenCamera() {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Fullscreen camera
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _cameraController!.value.previewSize!.height,
              height: _cameraController!.value.previewSize!.width,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),

        // Face-shaped frame - WHITE border
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            height: MediaQuery.of(context).size.height * 0.55,
            child: CustomPaint(
              painter: FaceFramePainter(
                frameColor: Colors.white,
                strokeWidth: 4.0,
              ),
            ),
          ),
        ),

        // Progress dots indicator - top center
        Positioned(
          top: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                _requiredImages,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < _capturedImages.length
                        ? Colors.green
                        : Colors.grey.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Liveness status badge - center below dots
        if (_isInLivenessMode && !_livenessCompleted)
          Positioned(
            top: 140,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _statusColor.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getLivenessIcon(),
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
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
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt, color: Colors.white70, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Auto Capture',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Lighting quality badge - top left
        Positioned(
          top: 120,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _isLightingGood
                  ? Colors.green.withOpacity(0.8)
                  : Colors.orange.withOpacity(0.8),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLightingGood ? Icons.wb_sunny : Icons.wb_cloudy,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _lightingStatus,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Top label ABOVE frame - centered
        // REMOVED for clean UI

        // Bottom label BELOW frame - centered
        // REMOVED for clean UI
      ],
    );
  }

  Widget _buildThumbnailStrip() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _capturedImages.length,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(right: 8),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _capturedImages[index],
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _deleteImage(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: _capturedImages.length >= _minImages && !_isUploading
            ? _uploadImages
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: Colors.grey[800],
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          'Upload (${_capturedImages.length}/$_minImages)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
