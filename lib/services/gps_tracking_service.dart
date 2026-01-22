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
  Position? _lastValidPosition; // For filtering
  bool _isTracking = false;
  
  // GPS filtering thresholds
  static const double _maxAccuracyMeters = 20.0; // Reject accuracy > 20m
  static const double _maxSpeedKmh = 30.0; // Reject speed > 30 km/h (sprint speed)
  static const double _maxJumpMeters = 100.0; // Reject jumps > 100m in 1 second

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
          // Apply GPS filtering
          if (_isValidPosition(position)) {
            _lastPosition = position;
            _lastValidPosition = position;
            _positionController?.add(position);
            print(
                '[GPS] ✅ Valid position: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
          } else {
            print(
                '[GPS] ❌ Filtered out: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
          }
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

  /// Validate GPS position to filter out erratic readings
  bool _isValidPosition(Position position) {
    // 1. Check accuracy - reject if > 20 meters
    if (position.accuracy > _maxAccuracyMeters) {
      print('[GPS Filter] Rejected: Poor accuracy ${position.accuracy}m (max ${_maxAccuracyMeters}m)');
      return false;
    }

    // 2. If no previous valid position, accept this one
    if (_lastValidPosition == null) {
      print('[GPS Filter] Accepted: First valid position');
      return true;
    }

    // 3. Calculate distance from last valid position
    double distance = Geolocator.distanceBetween(
      _lastValidPosition!.latitude,
      _lastValidPosition!.longitude,
      position.latitude,
      position.longitude,
    );

    // 4. Calculate time difference in seconds
    double timeDiff = position.timestamp
        .difference(_lastValidPosition!.timestamp)
        .inMilliseconds / 1000.0;

    // Avoid division by zero
    if (timeDiff < 0.1) {
      print('[GPS Filter] Rejected: Too soon (${timeDiff}s)');
      return false;
    }

    // 5. Calculate speed in km/h
    double speedKmh = (distance / timeDiff) * 3.6;

    // 6. Check for unrealistic speed (> 30 km/h = sprint speed)
    if (speedKmh > _maxSpeedKmh) {
      print('[GPS Filter] Rejected: Speed too high ${speedKmh.toStringAsFixed(1)} km/h (max ${_maxSpeedKmh} km/h)');
      return false;
    }

    // 7. Check for sudden jumps (> 100m in 1 second)
    double maxDistance = _maxJumpMeters * timeDiff;
    if (distance > maxDistance) {
      print('[GPS Filter] Rejected: Jump too large ${distance.toStringAsFixed(1)}m in ${timeDiff.toStringAsFixed(1)}s');
      return false;
    }

    // Position passed all filters
    print('[GPS Filter] Accepted: ${distance.toStringAsFixed(1)}m in ${timeDiff.toStringAsFixed(1)}s (${speedKmh.toStringAsFixed(1)} km/h)');
    return true;
  }

  /// Cleanup resources
  void dispose() {
    stopTracking();
  }
}
