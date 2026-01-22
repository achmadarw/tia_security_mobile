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

  // Token cache to avoid repeated SharedPreferences access
  String? _cachedToken;
  int? _cachedUserId;

  /// Get current patrol session
  PatrolSession? get currentSession => _currentSession;

  /// Check if patrol is active
  bool get isPatrolActive => _currentSession?.isActive ?? false;

  /// Get access token (try security_access_token first, fallback to pos_token)
  Future<String?> _getToken() async {
    // Return cached token if available
    if (_cachedToken != null) {
      return _cachedToken;
    }

    final prefs = await SharedPreferences.getInstance();

    // Try security_access_token first (from select security)
    String? token = prefs.getString('security_access_token');
    if (token != null) {
      _cachedToken = token;
      return token;
    }

    // Fallback to pos_token (from pos login)
    token = prefs.getString('security_pos_token');
    if (token != null) {
      _cachedToken = token;
      return token;
    }

    print('[Patrol] ❌ No authentication token found!');
    return null;
  }

  /// Get user_id from stored session data
  Future<int?> _getUserId() async {
    // Return cached user ID if available
    if (_cachedUserId != null) {
      return _cachedUserId;
    }

    final prefs = await SharedPreferences.getInstance();

    // Try security_user_data first (from select security flow)
    final securityUserData = prefs.getString('security_user_data');
    if (securityUserData != null) {
      try {
        final userData = jsonDecode(securityUserData);
        final userId = userData['id'] as int?;
        if (userId != null) {
          _cachedUserId = userId;
          return userId;
        }
      } catch (e) {
        print('[Patrol] ⚠️ Error parsing security_user_data: $e');
      }
    }

    // Fallback to user_data (from face login flow)
    final userData = prefs.getString('user_data');
    if (userData != null) {
      try {
        final data = jsonDecode(userData);
        final userId = data['id'] as int?;
        if (userId != null) {
          _cachedUserId = userId;
          return userId;
        }
      } catch (e) {
        print('[Patrol] ⚠️ Error parsing user_data: $e');
      }
    }

    print('[Patrol] ❌ No user_id found in session data!');
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
          final blocks = data['data']['blocks'];
          if (blocks != null) {
            _setupGeofences(blocks);
            // Save blocks to session for resume
            await _saveBlocksData(blocks);
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
      // Parse coordinates safely (could be String or num from API)
      double lat = 0.0;
      double lng = 0.0;
      double radius = 5.0;

      try {
        print('[Patrol] 🔍 Parsing block: ${block['name']}');

        // Try 'latitude' first (new format from /patrol/start), then 'location_lat' (old format)
        final latField = block['latitude'] ?? block['location_lat'];
        final lngField = block['longitude'] ?? block['location_lng'];
        final radiusField = block['radius'] ?? block['checkpoint_radius'];

        print('[Patrol] Raw data: lat=$latField, lng=$lngField');

        if (latField is String) {
          lat = double.parse(latField);
        } else {
          lat = (latField as num?)?.toDouble() ?? 0.0;
        }

        if (lngField is String) {
          lng = double.parse(lngField);
        } else {
          lng = (lngField as num?)?.toDouble() ?? 0.0;
        }

        if (radiusField != null) {
          if (radiusField is String) {
            radius = double.parse(radiusField);
          } else {
            radius = (radiusField as num).toDouble();
          }
        }

        print('[Patrol] ✅ Parsed: lat=$lat, lng=$lng, radius=$radius');
      } catch (e) {
        print('[Patrol] ⚠️ Error parsing block coordinates: $e');
        print('[Patrol] Block data: $block');
      }

      return GeofenceZone(
        id: block['id'],
        name: block['name'] ?? 'Block ${block['id']}',
        latitude: lat,
        longitude: lng,
        radiusMeters: radius,
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
    zones.forEach((zone) {
      print(
          '[Patrol]   - ${zone.name}: ${zone.latitude}, ${zone.longitude} (${zone.radiusMeters}m)');
    });
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
          'user_id': _currentSession
              ?.userId, // Add user_id for pos_token authentication
          'patrol_session_id': _currentSession?.id,
          'end_lat': endLat,
          'end_lng': endLng,
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
    print('[Patrol] 📂 Loading session from storage...');
    final startTime = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString('current_patrol_session');

    if (sessionJson != null) {
      _currentSession = PatrolSession.fromJson(jsonDecode(sessionJson));
      print(
          '[Patrol] ✅ Session loaded in ${DateTime.now().difference(startTime).inMilliseconds}ms');

      // Restore geofence zones from saved blocks
      final blocksStartTime = DateTime.now();
      final blocksJson = prefs.getString('current_patrol_blocks');
      if (blocksJson != null) {
        final blocks = jsonDecode(blocksJson) as List;
        _setupGeofences(blocks);
        print(
            '[Patrol] ✅ Restored ${blocks.length} zones in ${DateTime.now().difference(blocksStartTime).inMilliseconds}ms');
      } else {
        // Fallback: fetch blocks from API if not in storage
        print('[Patrol] ⚠️ No blocks in storage, fetching from API...');
        await _fetchAndSetupBlocks();
      }

      // Resume tracking if session is active
      if (_currentSession!.isActive) {
        print('[Patrol] 🔄 Resuming patrol tracking');
        await _gpsService.startTracking(intervalSeconds: 1);
        _startBackgroundTracking();
      }

      print(
          '[Patrol] 🎉 Total load time: ${DateTime.now().difference(startTime).inMilliseconds}ms');
    } else {
      print('[Patrol] ❌ No session found in storage');
    }
  }

  /// Fetch blocks from API and setup geofences
  Future<void> _fetchAndSetupBlocks() async {
    try {
      final token = await _getToken();
      if (token == null) {
        print('[Patrol] No token, cannot fetch blocks');
        return;
      }

      print('[Patrol] Fetching blocks from API...');
      final url = Uri.parse('${ApiConfig.serverUrl}/api/blocks');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('[Patrol] ⚠️ Blocks API timeout after 5 seconds');
          throw TimeoutException('Blocks API timeout');
        },
      );

      print('[Patrol] Blocks API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[Patrol] Blocks data type: ${data.runtimeType}');
        print('[Patrol] Blocks data: $data');

        // API /api/blocks returns array directly
        if (data is List) {
          print('[Patrol] Processing ${data.length} blocks...');
          _setupGeofences(data);
          await _saveBlocksData(data);
          print('[Patrol] ✅ Fetched and setup ${data.length} blocks from API');
        } else {
          print('[Patrol] ❌ Unexpected data format: ${data.runtimeType}');
        }
      } else {
        print('[Patrol] ❌ Failed to fetch blocks: ${response.statusCode}');
      }
    } catch (e) {
      print('[Patrol] ❌ Error fetching blocks: $e');
    }
  }

  /// Save blocks data for resume
  Future<void> _saveBlocksData(List<dynamic> blocks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_patrol_blocks', jsonEncode(blocks));
  }

  /// Clear current session
  Future<void> _clearCurrentSession() async {
    _currentSession = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_patrol_session');
    await prefs.remove('current_patrol_blocks');
  }

  /// Cleanup
  void dispose() {
    _stopTracking();
    _gpsService.dispose();
    _geofenceService.dispose();
  }
}
