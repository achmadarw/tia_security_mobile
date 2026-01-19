import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// GPS Tracking Service
/// Handles real-time GPS tracking untuk patrol dengan background support
class GPSTrackingService {
  static final GPSTrackingService _instance = GPSTrackingService._internal();
  factory GPSTrackingService() => _instance;
  GPSTrackingService._internal();

  StreamController<Position>? _positionController;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  bool _isTracking = false;

  /// Get stream of position updates
  Stream<Position>? get positionStream => _positionController?.stream;

  /// Check if currently tracking
  bool get isTracking => _isTracking;

  /// Get last known position
  Position? get lastPosition => _lastPosition;

  /// Request location permissions
  Future<bool> requestPermissions() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('[GPS] Location services are disabled');
      return false;
    }

    // Request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('[GPS] Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('[GPS] Location permissions are permanently denied');
      return false;
    }

    // Request background location for continuous tracking
    var status = await Permission.locationAlways.request();
    if (!status.isGranted) {
      print('[GPS] Background location permission denied');
      // Still allow foreground tracking
    }

    print('[GPS] Location permissions granted');
    return true;
  }

  /// Start GPS tracking
  /// [intervalSeconds] - Update interval in seconds (default 1)
  Future<bool> startTracking({int intervalSeconds = 1}) async {
    if (_isTracking) {
      print('[GPS] Already tracking');
      return true;
    }

    // Request permissions first
    bool hasPermission = await requestPermissions();
    if (!hasPermission) {
      return false;
    }

    try {
      _positionController = StreamController<Position>.broadcast();
      _isTracking = true;

      // Configure location settings for high accuracy
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Minimum 5 meters movement to trigger update
      );

      print('[GPS] Starting GPS tracking with ${intervalSeconds}s interval');

      // Start listening to position stream
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _lastPosition = position;
          _positionController?.add(position);
          print(
              '[GPS] Position updated: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
        },
        onError: (error) {
          print('[GPS] Error: $error');
        },
      );

      // Get initial position
      try {
        Position initialPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _lastPosition = initialPosition;
        _positionController?.add(initialPosition);
        print('[GPS] Initial position obtained');
      } catch (e) {
        print('[GPS] Error getting initial position: $e');
      }

      return true;
    } catch (e) {
      print('[GPS] Error starting tracking: $e');
      _isTracking = false;
      return false;
    }
  }

  /// Stop GPS tracking
  Future<void> stopTracking() async {
    if (!_isTracking) {
      print('[GPS] Not tracking');
      return;
    }

    print('[GPS] Stopping GPS tracking');

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    await _positionController?.close();
    _positionController = null;

    _isTracking = false;
    print('[GPS] GPS tracking stopped');
  }

  /// Get current position once (without starting continuous tracking)
  Future<Position?> getCurrentPosition() async {
    try {
      bool hasPermission = await requestPermissions();
      if (!hasPermission) {
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _lastPosition = position;
      return position;
    } catch (e) {
      print('[GPS] Error getting current position: $e');
      return null;
    }
  }

  /// Calculate distance between two positions in meters
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Check if position is within radius of target
  bool isWithinRadius({
    required Position current,
    required double targetLat,
    required double targetLon,
    required double radiusMeters,
  }) {
    double distance = calculateDistance(
      current.latitude,
      current.longitude,
      targetLat,
      targetLon,
    );
    return distance <= radiusMeters;
  }

  /// Cleanup resources
  void dispose() {
    stopTracking();
  }
}
