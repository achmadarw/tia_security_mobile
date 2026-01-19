import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// Geofence Zone
class GeofenceZone {
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final Map<String, dynamic>? metadata;

  GeofenceZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.metadata,
  });

  /// Check if position is inside this geofence
  bool contains(Position position) {
    double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      latitude,
      longitude,
    );
    return distance <= radiusMeters;
  }

  /// Get distance from position to geofence center
  double distanceFrom(Position position) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      latitude,
      longitude,
    );
  }
}

/// Geofence Event
class GeofenceEvent {
  final GeofenceZone zone;
  final GeofenceEventType type;
  final Position position;
  final DateTime timestamp;
  final double distance;

  GeofenceEvent({
    required this.zone,
    required this.type,
    required this.position,
    required this.timestamp,
    required this.distance,
  });
}

/// Geofence Event Type
enum GeofenceEventType {
  enter, // Entered the geofence
  exit, // Exited the geofence
  dwell, // Still inside the geofence
}

/// Geofencing Service
/// Auto-detect ketika security masuk/keluar dari block zones
class GeofencingService {
  static final GeofencingService _instance = GeofencingService._internal();
  factory GeofencingService() => _instance;
  GeofencingService._internal();

  final List<GeofenceZone> _zones = [];
  final Set<int> _currentZones = {}; // Zone IDs where user is currently inside
  final Map<int, DateTime> _enterTimes = {}; // Track when entered each zone
  final Map<int, int> _dwellSeconds = {}; // Total seconds spent in each zone

  StreamController<GeofenceEvent>? _eventController;
  Timer? _dwellTimer;

  /// Get stream of geofence events
  Stream<GeofenceEvent>? get eventStream => _eventController?.stream;

  /// Get list of all zones
  List<GeofenceZone> get zones => List.unmodifiable(_zones);

  /// Get current zones (where user is inside)
  Set<int> get currentZones => Set.unmodifiable(_currentZones);

  /// Add geofence zone
  void addZone(GeofenceZone zone) {
    // Remove existing zone with same ID
    _zones.removeWhere((z) => z.id == zone.id);
    _zones.add(zone);
    print('[Geofence] Added zone: ${zone.name} (${zone.radiusMeters}m radius)');
  }

  /// Add multiple zones
  void addZones(List<GeofenceZone> zones) {
    for (var zone in zones) {
      addZone(zone);
    }
  }

  /// Remove zone by ID
  void removeZone(int zoneId) {
    _zones.removeWhere((z) => z.id == zoneId);
    _currentZones.remove(zoneId);
    _enterTimes.remove(zoneId);
    _dwellSeconds.remove(zoneId);
    print('[Geofence] Removed zone ID: $zoneId');
  }

  /// Clear all zones
  void clearZones() {
    _zones.clear();
    _currentZones.clear();
    _enterTimes.clear();
    _dwellSeconds.clear();
    print('[Geofence] Cleared all zones');
  }

  /// Start monitoring geofences
  void startMonitoring() {
    if (_eventController != null) {
      print('[Geofence] Already monitoring');
      return;
    }

    _eventController = StreamController<GeofenceEvent>.broadcast();

    // Start dwell timer (check every second)
    _dwellTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateDwellTime();
    });

    print('[Geofence] Started monitoring ${_zones.length} zones');
  }

  /// Stop monitoring geofences
  void stopMonitoring() {
    _eventController?.close();
    _eventController = null;

    _dwellTimer?.cancel();
    _dwellTimer = null;

    _currentZones.clear();
    _enterTimes.clear();
    _dwellSeconds.clear();

    print('[Geofence] Stopped monitoring');
  }

  /// Update position and check geofences
  void updatePosition(Position position) {
    if (_eventController == null) return;

    Set<int> newCurrentZones = {};

    // Check each zone
    for (var zone in _zones) {
      bool isInside = zone.contains(position);
      bool wasInside = _currentZones.contains(zone.id);

      if (isInside) {
        newCurrentZones.add(zone.id);

        if (!wasInside) {
          // ENTER event
          _onEnterZone(zone, position);
        }
      } else {
        if (wasInside) {
          // EXIT event
          _onExitZone(zone, position);
        }
      }
    }

    _currentZones.clear();
    _currentZones.addAll(newCurrentZones);
  }

  /// Handle zone enter
  void _onEnterZone(GeofenceZone zone, Position position) {
    DateTime now = DateTime.now();
    _enterTimes[zone.id] = now;
    _dwellSeconds[zone.id] = 0;

    double distance = zone.distanceFrom(position);

    GeofenceEvent event = GeofenceEvent(
      zone: zone,
      type: GeofenceEventType.enter,
      position: position,
      timestamp: now,
      distance: distance,
    );

    _eventController?.add(event);

    print(
        '[Geofence] ENTER: ${zone.name} (${distance.toStringAsFixed(1)}m from center)');
  }

  /// Handle zone exit
  void _onExitZone(GeofenceZone zone, Position position) {
    DateTime now = DateTime.now();
    DateTime? enterTime = _enterTimes[zone.id];
    int dwellSeconds = _dwellSeconds[zone.id] ?? 0;

    if (enterTime != null) {
      dwellSeconds = now.difference(enterTime).inSeconds;
    }

    double distance = zone.distanceFrom(position);

    GeofenceEvent event = GeofenceEvent(
      zone: zone,
      type: GeofenceEventType.exit,
      position: position,
      timestamp: now,
      distance: distance,
    );

    _eventController?.add(event);

    _enterTimes.remove(zone.id);
    _dwellSeconds.remove(zone.id);

    print(
        '[Geofence] EXIT: ${zone.name} (stayed ${dwellSeconds}s, now ${distance.toStringAsFixed(1)}m away)');
  }

  /// Update dwell time for current zones
  void _updateDwellTime() {
    for (int zoneId in _currentZones) {
      _dwellSeconds[zoneId] = (_dwellSeconds[zoneId] ?? 0) + 1;
    }
  }

  /// Get dwell time in seconds for a zone
  int getDwellTime(int zoneId) {
    if (_currentZones.contains(zoneId)) {
      DateTime? enterTime = _enterTimes[zoneId];
      if (enterTime != null) {
        return DateTime.now().difference(enterTime).inSeconds;
      }
    }
    return _dwellSeconds[zoneId] ?? 0;
  }

  /// Get formatted dwell time
  String getFormattedDwellTime(int zoneId) {
    int seconds = getDwellTime(zoneId);
    int minutes = seconds ~/ 60;
    int secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  /// Check if currently inside a specific zone
  bool isInsideZone(int zoneId) {
    return _currentZones.contains(zoneId);
  }

  /// Get zone by ID
  GeofenceZone? getZone(int zoneId) {
    try {
      return _zones.firstWhere((z) => z.id == zoneId);
    } catch (e) {
      return null;
    }
  }

  /// Cleanup
  void dispose() {
    stopMonitoring();
  }
}
