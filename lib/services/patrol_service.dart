import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../config/api_config.dart';
import '../models/patrol_session.dart';
import 'gps_tracking_service.dart';
import 'geofencing_service.dart';

/// Patrol Service
/// Handles patrol operations dengan offline support
class PatrolService {
  static final PatrolService _instance = PatrolService._internal();
  factory PatrolService() => _instance;
  PatrolService._internal();

  final GPSTrackingService _gpsService = GPSTrackingService();
  final GeofencingService _geofenceService = GeofencingService();

  PatrolSession? _currentSession;
  final List<PatrolTrackPoint> _offlineTrackPoints = [];
  final List<PatrolCheckpoint> _offlineCheckpoints = [];
  Timer? _syncTimer;

  /// Get current patrol session
  PatrolSession? get currentSession => _currentSession;

  /// Check if patrol is active
  bool get isPatrolActive => _currentSession?.isActive ?? false;

  /// Get access token (try security_access_token first, fallback to pos_token)
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    // Debug: Print all available keys
    final allKeys = prefs.getKeys();
    print('[Patrol] SharedPreferences keys: $allKeys');

    // Try security_access_token first (from select security)
    String? token = prefs.getString('security_access_token');
    if (token != null) {
      print('[Patrol] Using security_access_token');
      return token;
    }

    // Fallback to pos_token (from pos login)
    token = prefs.getString('security_pos_token');
    if (token != null) {
      print('[Patrol] Using security_pos_token (fallback)');
      return token;
    }

    print('[Patrol] ERROR: No authentication token found!');
    return null;
  }

  /// Get user_id from stored session data
  Future<int?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();

    // Try security_user_data first (from select security flow)
    final securityUserData = prefs.getString('security_user_data');
    if (securityUserData != null) {
      try {
        final userData = jsonDecode(securityUserData);
        final userId = userData['id'];
        print('[Patrol] User ID from security_user_data: $userId');
        return userId;
      } catch (e) {
        print('[Patrol] Error parsing security_user_data: $e');
      }
    }

    // Fallback to user_data (from face login flow)
    final userData = prefs.getString('user_data');
    if (userData != null) {
      try {
        final data = jsonDecode(userData);
        final userId = data['id'];
        print('[Patrol] User ID from user_data: $userId');
        return userId;
      } catch (e) {
        print('[Patrol] Error parsing user_data: $e');
      }
    }

    print('[Patrol] ERROR: No user_id found in session data!');
    return null;
  }

  /// Start patrol session
  Future<Map<String, dynamic>> startPatrol({
    required int userId, // User ID personil yang patroli
    required double startLat,
    required double startLng,
    int? postSessionId,
  }) async {
    try {
      final token = await _getToken();
      print(
          '[Patrol] Token retrieved: ${token != null ? "✓ (${token.length} chars)" : "✗ NULL"}');

      if (token == null) {
        print('[Patrol] ERROR: No token found in SharedPreferences!');
        print(
            '[Patrol] Please ensure you have selected a security identity first.');
        throw Exception('Not authenticated');
      }

      final url =
          Uri.parse('${ApiConfig.serverUrl}/api/security-app/patrol/start');

      print('[Patrol] Starting patrol session');
      print('[Patrol] User ID: $userId (from personil)');
      print('[Patrol] Location: $startLat, $startLng');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userId,
          'start_lat':
              startLat, // Fix: backend expect start_lat not start_location_lat
          'start_lng':
              startLng, // Fix: backend expect start_lng not start_location_lng
          'post_session_id': postSessionId,
        }),
      );

      print('[Patrol] Response: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          // Create local session
          _currentSession = PatrolSession(
            id: data['data']['patrol_session_id'],
            userId: data['data']['user_id'],
            postSessionId: postSessionId,
            startedAt: DateTime.now(),
            startLocationLat: startLat,
            startLocationLng: startLng,
            status: 'in_progress',
          );

          // Save to local storage
          await _saveCurrentSession();

          // Start GPS tracking
          await _gpsService.startTracking(intervalSeconds: 1);

          // Setup geofences from blocks
          if (data['data']['blocks'] != null) {
            _setupGeofences(data['data']['blocks']);
          }

          // Start tracking and syncing
          _startBackgroundTracking();

          print('[Patrol] Patrol started successfully');
          return {
            'success': true,
            'session': _currentSession,
            'message': data['message'] ?? 'Patrol started',
          };
        } else {
          throw Exception(data['error'] ?? 'Failed to start patrol');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to start patrol');
      }
    } catch (e) {
      print('[Patrol] Error starting patrol: $e');
      rethrow;
    }
  }

  /// Setup geofences for blocks
  void _setupGeofences(List<dynamic> blocks) {
    _geofenceService.clearZones();

    List<GeofenceZone> zones = blocks.map((block) {
      return GeofenceZone(
        id: block['id'],
        name: block['name'] ?? 'Block ${block['id']}',
        latitude: block['location_lat']?.toDouble() ?? 0.0,
        longitude: block['location_lng']?.toDouble() ?? 0.0,
        radiusMeters: (block['checkpoint_radius'] ?? 50).toDouble(),
        metadata: block,
      );
    }).toList();

    _geofenceService.addZones(zones);
    _geofenceService.startMonitoring();

    // Listen to geofence events
    _geofenceService.eventStream?.listen((event) {
      _handleGeofenceEvent(event);
    });

    print('[Patrol] Setup ${zones.length} geofence zones');
  }

  /// Handle geofence events
  void _handleGeofenceEvent(GeofenceEvent event) {
    print('[Patrol] Geofence event: ${event.type} - ${event.zone.name}');

    if (event.type == GeofenceEventType.enter) {
      // Auto-record checkpoint when entering block
      _recordCheckpoint(
        blockId: event.zone.id,
        blockName: event.zone.name,
        position: event.position,
        distance: event.distance,
      );
    } else if (event.type == GeofenceEventType.exit) {
      // Update checkpoint exit time and duration
      _updateCheckpointExit(
        blockId: event.zone.id,
        dwellSeconds: _geofenceService.getDwellTime(event.zone.id),
      );
    }
  }

  /// Record checkpoint visit
  void _recordCheckpoint({
    required int blockId,
    required String blockName,
    required Position position,
    required double distance,
  }) {
    final checkpoint = PatrolCheckpoint(
      patrolSessionId: _currentSession?.id,
      blockId: blockId,
      blockName: blockName,
      visitedAt: DateTime.now(),
      locationLat: position.latitude,
      locationLng: position.longitude,
      distanceFromBlock: distance,
    );

    _offlineCheckpoints.add(checkpoint);

    // Update current session
    if (_currentSession != null) {
      _currentSession = PatrolSession(
        id: _currentSession!.id,
        userId: _currentSession!.userId,
        postSessionId: _currentSession!.postSessionId,
        startedAt: _currentSession!.startedAt,
        startLocationLat: _currentSession!.startLocationLat,
        startLocationLng: _currentSession!.startLocationLng,
        status: _currentSession!.status,
        checkpoints: [..._currentSession!.checkpoints, checkpoint],
        trackPoints: _currentSession!.trackPoints,
      );
      _saveCurrentSession();
    }

    print('[Patrol] Checkpoint recorded: $blockName');
  }

  /// Update checkpoint exit
  void _updateCheckpointExit({
    required int blockId,
    required int dwellSeconds,
  }) {
    // Find the latest checkpoint for this block
    for (int i = _offlineCheckpoints.length - 1; i >= 0; i--) {
      if (_offlineCheckpoints[i].blockId == blockId &&
          _offlineCheckpoints[i].exitedAt == null) {
        final checkpoint = _offlineCheckpoints[i];
        _offlineCheckpoints[i] = PatrolCheckpoint(
          id: checkpoint.id,
          patrolSessionId: checkpoint.patrolSessionId,
          blockId: checkpoint.blockId,
          blockName: checkpoint.blockName,
          visitedAt: checkpoint.visitedAt,
          exitedAt: DateTime.now(),
          locationLat: checkpoint.locationLat,
          locationLng: checkpoint.locationLng,
          distanceFromBlock: checkpoint.distanceFromBlock,
          dwellSeconds: dwellSeconds,
          photoUrl: checkpoint.photoUrl,
          notes: checkpoint.notes,
        );
        print(
            '[Patrol] Updated checkpoint exit: ${checkpoint.blockName} (${dwellSeconds}s)');
        break;
      }
    }
  }

  /// Start background tracking and syncing
  void _startBackgroundTracking() {
    // Listen to GPS updates
    _gpsService.positionStream?.listen((position) {
      // Record track point
      final trackPoint = PatrolTrackPoint(
        patrolSessionId: _currentSession?.id,
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
      );

      _offlineTrackPoints.add(trackPoint);

      // Update geofencing
      _geofenceService.updatePosition(position);

      // Limit offline queue size (keep last 1000 points)
      if (_offlineTrackPoints.length > 1000) {
        _offlineTrackPoints.removeAt(0);
      }
    });

    // Start periodic sync (every 30 seconds)
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _syncOfflineData();
    });

    print('[Patrol] Background tracking started');
  }

  /// Sync offline data to server
  Future<void> _syncOfflineData() async {
    if (_offlineTrackPoints.isEmpty && _offlineCheckpoints.isEmpty) {
      return;
    }

    try {
      final token = await _getToken();
      if (token == null) return;

      final url =
          Uri.parse('${ApiConfig.serverUrl}/api/security-app/patrol/sync-data');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'patrol_session_id': _currentSession?.id,
              'track_points':
                  _offlineTrackPoints.map((t) => t.toJson()).toList(),
              'checkpoints':
                  _offlineCheckpoints.map((c) => c.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Clear synced data
          _offlineTrackPoints.clear();
          _offlineCheckpoints.clear();
          print('[Patrol] Data synced successfully');
        }
      }
    } catch (e) {
      print('[Patrol] Sync error (will retry): $e');
      // Data stays in offline queue for next sync
    }
  }

  /// Complete patrol
  Future<Map<String, dynamic>> completePatrol({
    required double endLat,
    required double endLng,
    String? notes,
  }) async {
    try {
      // Sync any remaining offline data first
      await _syncOfflineData();

      final token = await _getToken();
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final url =
          Uri.parse('${ApiConfig.serverUrl}/api/security-app/patrol/complete');

      print('[Patrol] Completing patrol');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'patrol_session_id': _currentSession?.id,
          'end_location_lat': endLat,
          'end_location_lng': endLng,
          'notes': notes,
        }),
      );

      print('[Patrol] Complete response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Stop tracking
        await _stopTracking();

        // Clear session
        await _clearCurrentSession();

        print('[Patrol] Patrol completed successfully');
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'] ?? 'Patrol completed',
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to complete patrol');
      }
    } catch (e) {
      print('[Patrol] Error completing patrol: $e');
      rethrow;
    }
  }

  /// Stop tracking
  Future<void> _stopTracking() async {
    await _gpsService.stopTracking();
    _geofenceService.stopMonitoring();
    _syncTimer?.cancel();
    _syncTimer = null;
    print('[Patrol] Tracking stopped');
  }

  /// Save current session to local storage
  Future<void> _saveCurrentSession() async {
    if (_currentSession == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'current_patrol_session',
      jsonEncode(_currentSession!.toJson()),
    );
  }

  /// Load current session from local storage
  Future<void> loadCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString('current_patrol_session');

    if (sessionJson != null) {
      _currentSession = PatrolSession.fromJson(jsonDecode(sessionJson));
      print('[Patrol] Loaded existing patrol session');

      // Resume tracking if session is active
      if (_currentSession!.isActive) {
        print('[Patrol] Resuming patrol tracking');
        await _gpsService.startTracking(intervalSeconds: 1);
        _startBackgroundTracking();
      }
    }
  }

  /// Clear current session
  Future<void> _clearCurrentSession() async {
    _currentSession = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_patrol_session');
  }

  /// Cleanup
  void dispose() {
    _stopTracking();
    _gpsService.dispose();
    _geofenceService.dispose();
  }
}
