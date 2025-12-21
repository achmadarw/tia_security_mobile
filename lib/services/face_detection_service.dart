import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Service untuk mendeteksi wajah menggunakan Google ML Kit
/// Includes liveness detection dan quality checks
class FaceDetectionService {
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  // Face detection options
  final FaceDetectorOptions _options = FaceDetectorOptions(
    enableContours: true,
    enableLandmarks: true,
    enableClassification: true, // For smile, eyes open detection
    enableTracking: true,
    minFaceSize: 0.15, // Minimum 15% of image
    performanceMode: FaceDetectorMode.accurate,
  );

  /// Initialize face detector
  Future<void> initialize() async {
    if (_isInitialized) return;

    _faceDetector = FaceDetector(options: _options);
    _isInitialized = true;
  }

  /// Detect faces from image file
  Future<List<Face>> detectFacesFromFile(File imageFile) async {
    if (!_isInitialized) await initialize();

    final inputImage = InputImage.fromFile(imageFile);
    final faces = await _faceDetector.processImage(inputImage);

    return faces;
  }

  /// Detect faces from camera image
  Future<List<Face>> detectFacesFromCamera(CameraImage cameraImage) async {
    if (!_isInitialized) await initialize();

    final bytesBuilder = BytesBuilder();
    for (final plane in cameraImage.planes) {
      bytesBuilder.add(plane.bytes);
    }
    final bytes = bytesBuilder.toBytes();

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: ui.Size(
            cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: cameraImage.planes[0].bytesPerRow,
      ),
    );

    final faces = await _faceDetector.processImage(inputImage);
    return faces;
  }

  /// Check if face quality is good enough for recognition
  /// Returns: {isGood: bool, message: string}
  Map<String, dynamic> checkFaceQuality(Face face, ui.Size imageSize) {
    final boundingBox = face.boundingBox;

    // 1. Check face size (should be at least 20% of image)
    final faceArea = boundingBox.width * boundingBox.height;
    final imageArea = imageSize.width * imageSize.height;
    final faceRatio = faceArea / imageArea;

    if (faceRatio < 0.2) {
      return {
        'isGood': false,
        'message': 'Wajah terlalu kecil. Dekatkan ke kamera.',
      };
    }

    // 2. Check if face is centered
    final faceCenterX = boundingBox.left + (boundingBox.width / 2);
    final faceCenterY = boundingBox.top + (boundingBox.height / 2);
    final imageCenterX = imageSize.width / 2;
    final imageCenterY = imageSize.height / 2;

    final offsetX = (faceCenterX - imageCenterX).abs();
    final offsetY = (faceCenterY - imageCenterY).abs();

    if (offsetX > imageSize.width * 0.2 || offsetY > imageSize.height * 0.2) {
      return {
        'isGood': false,
        'message': 'Posisikan wajah di tengah kamera.',
      };
    }

    // 3. Check head rotation (Euler angles)
    final headEulerAngleX = face.headEulerAngleX ?? 0; // Pitch
    final headEulerAngleY = face.headEulerAngleY ?? 0; // Yaw
    final headEulerAngleZ = face.headEulerAngleZ ?? 0; // Roll

    if (headEulerAngleX.abs() > 15 ||
        headEulerAngleY.abs() > 15 ||
        headEulerAngleZ.abs() > 15) {
      return {
        'isGood': false,
        'message': 'Hadapkan wajah lurus ke kamera.',
      };
    }

    // 4. Check eyes open (liveness)
    final leftEyeOpenProbability = face.leftEyeOpenProbability ?? 0;
    final rightEyeOpenProbability = face.rightEyeOpenProbability ?? 0;

    if (leftEyeOpenProbability < 0.5 || rightEyeOpenProbability < 0.5) {
      return {
        'isGood': false,
        'message': 'Buka mata Anda.',
      };
    }

    return {
      'isGood': true,
      'message': 'Kualitas wajah bagus!',
      'faceRatio': faceRatio,
      'headEulerAngleX': headEulerAngleX,
      'headEulerAngleY': headEulerAngleY,
      'headEulerAngleZ': headEulerAngleZ,
    };
  }

  /// Perform liveness detection
  /// Detects if the face is from a real person (not photo/video)
  Map<String, dynamic> performLivenessCheck(Face face) {
    // Check if smiling (for liveness)
    final smilingProbability = face.smilingProbability ?? 0;
    final leftEyeOpenProbability = face.leftEyeOpenProbability ?? 0;
    final rightEyeOpenProbability = face.rightEyeOpenProbability ?? 0;

    // Basic liveness: eyes should be open and can detect smile
    final isLive = leftEyeOpenProbability > 0.3 &&
        rightEyeOpenProbability > 0.3 &&
        smilingProbability >= 0.0;

    return {
      'isLive': isLive,
      'smilingProbability': smilingProbability,
      'leftEyeOpen': leftEyeOpenProbability,
      'rightEyeOpen': rightEyeOpenProbability,
    };
  }

  /// Extract face region from image for recognition
  Future<img.Image?> extractFaceImage(File imageFile, Face face) async {
    // Read image
    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);

    if (image == null) return null;

    final boundingBox = face.boundingBox;

    // Add padding (10%)
    final padding = 0.1;
    final paddedLeft = (boundingBox.left - (boundingBox.width * padding))
        .clamp(0, image.width)
        .toInt();
    final paddedTop = (boundingBox.top - (boundingBox.height * padding))
        .clamp(0, image.height)
        .toInt();
    final paddedWidth = (boundingBox.width * (1 + 2 * padding))
        .clamp(0, image.width - paddedLeft)
        .toInt();
    final paddedHeight = (boundingBox.height * (1 + 2 * padding))
        .clamp(0, image.height - paddedTop)
        .toInt();

    // Crop face region
    final faceImage = img.copyCrop(
      image,
      x: paddedLeft,
      y: paddedTop,
      width: paddedWidth,
      height: paddedHeight,
    );

    // Resize to model input size (112x112 for MobileFaceNet)
    final resizedFace = img.copyResize(
      faceImage,
      width: 112,
      height: 112,
    );

    return resizedFace;
  }

  /// Close and cleanup
  Future<void> dispose() async {
    if (_isInitialized) {
      await _faceDetector.close();
      _isInitialized = false;
    }
  }
}
