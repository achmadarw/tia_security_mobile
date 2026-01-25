import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../config/theme.dart';
import '../services/patrol_service.dart';
import '../services/gps_tracking_service.dart';
import '../services/geofencing_service.dart';
import '../models/patrol_session.dart';
import 'patrol_complete_screen.dart';

/// Active Patrol Screen
/// Live map dengan GPS tracking real-time (1 detik interval)
class ActivePatrolScreen extends StatefulWidget {
  const ActivePatrolScreen({Key? key}) : super(key: key);

  @override
  State<ActivePatrolScreen> createState() => _ActivePatrolScreenState();
}

class _ActivePatrolScreenState extends State<ActivePatrolScreen> {
  final PatrolService _patrolService = PatrolService();
  final GPSTrackingService _gpsService = GPSTrackingService();
  final GeofencingService _geofencingService = GeofencingService();

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<GeofenceEvent>? _geofenceSubscription;

  Position? _currentPosition;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<LatLng> _routePoints = [];

  PatrolSession? _currentSession;
  String? _currentBlock;
  int _visitedBlocks = 0;
  final Set<String> _visitedBlockNames = {}; // Track which blocks visited
  Duration _patrolDuration = Duration.zero;
  Timer? _durationTimer;

  bool _isLoading = true;
  String? _errorMessage;

  // Motor patrol optimizations
  double _currentSpeed = 0.0; // km/h
  double _smoothedDistance = 0.0; // For distance smoothing
  final List<double> _recentSpeeds =
      []; // For speed smoothing (last 3 readings)
  final Set<String> _notifiedBlocks =
      {}; // Track which blocks we've alerted for
  int _gpsAccuracy = 0; // meters
  String _gpsQuality = 'Mencari GPS...'; // Excellent/Good/Poor
  Color _gpsQualityColor = Colors.grey;

  // GPS Loss Detection
  int _gpsLossSeconds = 0;
  Timer? _gpsHealthTimer;
  DateTime? _lastGpsUpdate;
  bool _showGpsLossWarning = false;

  // Manual Check-in
  List<CameraDescription>? _cameras;
  final Map<String, String> _manualCheckIns = {}; // blockName -> photoPath

  @override
  void initState() {
    super.initState();
    _initializePatrol();
    _initializeCamera();
    _startGpsHealthMonitoring();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      print('[ActivePatrol] 📷 ${_cameras?.length ?? 0} cameras available');
    } catch (e) {
      print('[ActivePatrol] ⚠️ Camera initialization error: $e');
    }
  }

  void _startGpsHealthMonitoring() {
    // Monitor GPS health every second
    _gpsHealthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      final now = DateTime.now();

      // Check if GPS is healthy (recent update within 5 seconds)
      if (_lastGpsUpdate == null ||
          now.difference(_lastGpsUpdate!) > const Duration(seconds: 5)) {
        _gpsLossSeconds++;

        // Show warning after 30 seconds
        if (_gpsLossSeconds == 30 && !_showGpsLossWarning) {
          setState(() => _showGpsLossWarning = true);
          _showGpsLossWarningSnackbar();
        }

        // Show critical dialog after 2 minutes
        if (_gpsLossSeconds == 120) {
          _showGpsLossCriticalDialog();
        }
      } else {
        // GPS recovered
        if (_gpsLossSeconds > 0) {
          print('[ActivePatrol] ✅ GPS recovered after ${_gpsLossSeconds}s');
        }
        _gpsLossSeconds = 0;
        if (_showGpsLossWarning) {
          setState(() => _showGpsLossWarning = false);
        }
      }
    });
  }

  Future<void> _initializePatrol() async {
    setState(() => _isLoading = true);

    try {
      print('[ActivePatrol] 🚀 Starting initialization...');
      final startTime = DateTime.now();

      // Load current patrol session with FRESH blocks from API
      // forceFreshBlocks=true ensures we get latest block coordinates (not cached)
      // This is critical when admin just updated block coordinates before patrol start
      await _patrolService.loadCurrentSession(forceFreshBlocks: true);
      _currentSession = _patrolService.currentSession;

      if (_currentSession == null) {
        throw Exception('Tidak ada sesi patroli aktif');
      }

      print(
          '[ActivePatrol] Session loaded in ${DateTime.now().difference(startTime).inMilliseconds}ms');
      print(
          '[ActivePatrol] Geofence zones available: ${_geofencingService.zones.length}');

      // Start GPS tracking (non-blocking)
      _gpsService.startTracking().then((_) {
        print('[ActivePatrol] GPS tracking started');
      });

      // Subscribe to position updates (1 second interval)
      _positionSubscription = _gpsService.positionStream?.listen((position) {
        _updatePosition(position);
      });

      // Subscribe to geofence events
      _geofenceSubscription = _geofencingService.eventStream?.listen((event) {
        _handleGeofenceEvent(event);
      });

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_currentSession != null) {
          setState(() {
            _patrolDuration =
                DateTime.now().difference(_currentSession!.startedAt);
          });
        }
      });

      // Check for geofence zones only once after 1 second (instead of every 500ms)
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _geofencingService.zones.isNotEmpty) {
          print(
              '[ActivePatrol] Zones ready: ${_geofencingService.zones.length}');
          setState(() {}); // Single rebuild when zones available
        }
      });

      print(
          '[ActivePatrol] ✅ Initialization complete in ${DateTime.now().difference(startTime).inMilliseconds}ms');
      setState(() => _isLoading = false);
    } catch (e) {
      print('[ActivePatrol] Error initializing: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _updatePosition(Position position) {
    // Track GPS health
    _lastGpsUpdate = DateTime.now();

    setState(() {
      // Calculate speed from position (m/s -> km/h)
      double speedKmh = position.speed * 3.6;

      // Smooth speed using moving average (last 3 readings)
      _recentSpeeds.add(speedKmh);
      if (_recentSpeeds.length > 3) {
        _recentSpeeds.removeAt(0);
      }
      _currentSpeed =
          _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;

      // Update GPS quality indicator
      _gpsAccuracy = position.accuracy.round();
      if (position.accuracy <= 5) {
        _gpsQuality = 'Excellent';
        _gpsQualityColor = Colors.green;
      } else if (position.accuracy <= 10) {
        _gpsQuality = 'Good';
        _gpsQualityColor = Colors.blue;
      } else if (position.accuracy <= 20) {
        _gpsQuality = 'Fair';
        _gpsQualityColor = Colors.orange;
      } else {
        _gpsQuality = 'Poor';
        _gpsQualityColor = Colors.red;
      }

      _currentPosition = position;

      // Update marker
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('current_position'),
          position: LatLng(position.latitude, position.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Lokasi Anda'),
        ),
      );

      // Add to route
      _routePoints.add(LatLng(position.latitude, position.longitude));

      // Update polyline
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('patrol_route'),
          points: _routePoints,
          color: Colors.blue,
          width: 4,
        ),
      );
    });

    // Move camera to follow position
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 17,
        ),
      ),
    );

    // Update geofencing with current position
    _geofencingService.updatePosition(position);

    // Check proximity alerts for checkpoints (<20m)
    _checkProximityAlerts();

    // Log distance to all blocks for verification
    for (var zone in _geofencingService.zones) {
      final dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        zone.latitude,
        zone.longitude,
      );
      print(
          '[ActivePatrol] 📍 Distance to ${zone.name}: ${dist.toStringAsFixed(1)}m (threshold: ${zone.radiusMeters}m)');
    }
  }

  /// Check proximity to checkpoints and trigger vibration/alert
  void _checkProximityAlerts() {
    if (_currentPosition == null) return;

    for (var zone in _geofencingService.zones) {
      // Skip if already visited or already notified
      if (_visitedBlockNames.contains(zone.name) ||
          _notifiedBlocks.contains(zone.name)) {
        continue;
      }

      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        zone.latitude,
        zone.longitude,
      );

      // Alert when within 20 meters
      if (distance <= 20) {
        _notifiedBlocks.add(zone.name);

        // Vibrate
        HapticFeedback.mediumImpact();

        // Show snackbar notification
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('📍 Mendekati checkpoint: ${zone.name}'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        print(
            '[ActivePatrol] 🔔 Proximity alert: ${zone.name} at ${distance.toStringAsFixed(1)}m');
      }
    }
  }

  void _handleGeofenceEvent(GeofenceEvent event) {
    print('[ActivePatrol] Geofence event: ${event.type} - ${event.zone.name}');

    // Update visited blocks tracking using Set to avoid duplicates
    if (event.type == GeofenceEventType.enter) {
      if (!_visitedBlockNames.contains(event.zone.name)) {
        _visitedBlockNames.add(event.zone.name);
        setState(() {
          _currentBlock = event.zone.name;
          _visitedBlocks = _visitedBlockNames.length; // Use Set size
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Memasuki blok: ${event.zone.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else if (event.type == GeofenceEventType.exit) {
      setState(() {
        _currentBlock = null;
      });
    }
  }

  void _stopPatrol() async {
    // Confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selesaikan Patrol?'),
        content: Text(
          'Anda telah mengunjungi $_visitedBlocks dari ${_geofencingService.zones.length} blok.\n\nSelesaikan patrol sekarang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // Get current position (fallback if _currentPosition is null)
      Position? endPosition = _currentPosition;

      if (endPosition == null) {
        print('[ActivePatrol] Getting current GPS position...');
        endPosition = await _gpsService.getCurrentPosition();
      }

      if (endPosition == null) {
        throw Exception(
            'Tidak dapat mengambil lokasi GPS. Pastikan GPS aktif.');
      }

      if (_currentSession != null) {
        // Save stats before completing
        final duration = _formatDuration(_patrolDuration);
        final visitedBlocks = _visitedBlocks;
        final totalBlocks = _geofencingService.zones.length;

        // Complete patrol
        final result = await _patrolService.completePatrol(
          endLat: endPosition.latitude,
          endLng: endPosition.longitude,
          notes:
              'Patroli selesai. $visitedBlocks dari $totalBlocks blok dikunjungi.',
        );

        // Stop tracking
        await _gpsService.stopTracking();
        _durationTimer?.cancel();

        // Show success dialog and return to home
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 32),
                  SizedBox(width: 12),
                  Text('Patroli Selesai'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Patroli telah berhasil diselesaikan.'),
                  const SizedBox(height: 16),
                  _buildSummaryItem('Durasi', duration),
                  _buildSummaryItem(
                      'Blok Dikunjungi', '$visitedBlocks/$totalBlocks'),
                  if (result['data'] != null &&
                      result['data']['statistics'] != null)
                    _buildSummaryItem(
                      'Titik GPS',
                      '${result['data']['statistics']['total_track_points'] ?? 0}',
                    ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Back to home screen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      print('[ActivePatrol] Error stopping patrol: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  double _calculateTotalDistance() {
    if (_routePoints.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 0; i < _routePoints.length - 1; i++) {
      totalDistance += Geolocator.distanceBetween(
        _routePoints[i].latitude,
        _routePoints[i].longitude,
        _routePoints[i + 1].latitude,
        _routePoints[i + 1].longitude,
      );
    }
    return totalDistance;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _geofenceSubscription?.cancel();
    _durationTimer?.cancel();
    _gpsHealthTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// GPS Loss Warning - Show snackbar after 30s
  void _showGpsLossWarningSnackbar() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.gps_off, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '⚠️ Sinyal GPS hilang. Pastikan Anda di area terbuka.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );

    // Vibrate
    HapticFeedback.heavyImpact();

    print('[ActivePatrol] 🚨 GPS loss warning shown after ${_gpsLossSeconds}s');
  }

  /// GPS Loss Critical Dialog - Show after 2 minutes
  void _showGpsLossCriticalDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.gps_off, color: Colors.red.shade700, size: 32),
            const SizedBox(width: 12),
            const Text('GPS Bermasalah'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sinyal GPS hilang selama ${(_gpsLossSeconds / 60).toStringAsFixed(0)} menit.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Saran:'),
            const SizedBox(height: 8),
            const Text('• Pastikan GPS aktif di pengaturan'),
            const Text('• Pindah ke area terbuka'),
            const Text('• Restart aplikasi jika perlu'),
            const Text('• Gunakan Check-in Manual dengan foto'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Checkpoint detection otomatis tidak akan bekerja tanpa GPS.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );

    print(
        '[ActivePatrol] 🆘 GPS loss CRITICAL dialog shown after ${_gpsLossSeconds}s');
  }

  /// Manual Check-in - Take photo as proof
  Future<void> _manualCheckIn(String blockName) async {
    if (_cameras == null || _cameras!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Kamera tidak tersedia'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Navigate to camera screen
      final XFile? photo = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _ManualCheckInCamera(
            camera: _cameras!.first,
            blockName: blockName,
          ),
        ),
      );

      if (photo != null) {
        // Save photo path
        setState(() {
          _manualCheckIns[blockName] = photo.path;

          // Mark as visited
          if (!_visitedBlockNames.contains(blockName)) {
            _visitedBlockNames.add(blockName);
            _visitedBlocks = _visitedBlockNames.length;
          }
        });

        // Show success
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('✅ Check-in manual: $blockName')),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );

          HapticFeedback.mediumImpact();
        }

        print('[ActivePatrol] 📸 Manual check-in: $blockName at ${photo.path}');
      }
    } catch (e) {
      print('[ActivePatrol] ❌ Manual check-in error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        appBar: AppBar(
          title: const Text('Patrol Aktif'),
          backgroundColor:
              isDark ? AppColors.darkSurface : AppColors.lightPrimary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kembali'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // GPS Loss Warning Banner (if GPS lost > 30s)
            if (_showGpsLossWarning)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.red.shade300, width: 2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.gps_off, color: Colors.red.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⚠️ GPS TIDAK TERDETEKSI (${_gpsLossSeconds}s)',
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Checkpoint tidak akan terdeteksi otomatis. Gunakan Check-in Manual.',
                            style: TextStyle(
                              color: Colors.red.shade800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // GPS Status Banner (jika belum ready)
            if (_currentPosition == null && !_showGpsLossWarning)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.blue.shade200, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Mencari sinyal GPS... Pastikan Anda berada di area terbuka',
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(Icons.gps_not_fixed,
                        color: Colors.blue.shade600, size: 20),
                  ],
                ),
              ),

            // Top panel (stats header)
            _buildTopPanel(),

            // Map/Visual rute (takes remaining space)
            Expanded(
              child: _buildMap(),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildStopButton(),
    );
  }

  Widget _buildTopPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.security,
                color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Patroli Aktif',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _gpsQualityColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.gps_fixed, color: _gpsQualityColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _gpsQuality,
                      style: TextStyle(
                        color: _gpsQualityColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Speed & GPS Accuracy Row
          if (_currentPosition != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Speed indicator
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.blue.shade900.withOpacity(0.3)
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.speed,
                          size: 16,
                          color: isDark
                              ? Colors.blue.shade300
                              : Colors.blue.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_currentSpeed.toStringAsFixed(1)} km/h',
                          style: TextStyle(
                            color: isDark
                                ? Colors.blue.shade300
                                : Colors.blue.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // GPS Accuracy
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _gpsQualityColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.my_location,
                          size: 16,
                          color: _gpsQualityColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '±${_gpsAccuracy}m',
                          style: TextStyle(
                            color: _gpsQualityColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  label: 'Durasi',
                  value: _formatDuration(_patrolDuration),
                  icon: Icons.timer,
                  color: Colors.blue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  label: 'Blok Dikunjungi',
                  value: '$_visitedBlocks/${_geofencingService.zones.length}',
                  icon: Icons.location_on,
                  color: Colors.orange,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  label: 'Blok Saat Ini',
                  value: _currentBlock ?? '-',
                  icon: Icons.my_location,
                  color: Colors.green,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    // Selalu tampilkan blocks list, tidak perlu tunggu GPS
    // Distance akan update real-time saat GPS ready
    return _buildBlockRouteVisual();
  }

  /// Build visual rute blok dengan checklist & distance
  Widget _buildBlockRouteVisual() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final geofenceZones = _geofencingService.zones;

    if (geofenceZones.isEmpty) {
      return Container(
        color: isDark ? AppColors.darkCard : Colors.grey.shade100,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.route, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('Tidak ada blok dalam rute patrol'),
            ],
          ),
        ),
      );
    }

    // Calculate progress
    final totalBlocks = geofenceZones.length;
    final visitedCount = _visitedBlocks;
    final progressPercent = (visitedCount / totalBlocks * 100).round();

    return Container(
      color: isDark ? AppColors.darkCard : Colors.grey.shade50,
      child: Column(
        children: [
          // Progress header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.route,
                      color: isDark
                          ? AppColors.darkPrimary
                          : AppColors.lightPrimary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rute Patrol - $totalBlocks Blok',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$visitedCount dari $totalBlocks blok dikunjungi ($progressPercent%)',
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
                    CircularProgressIndicator(
                      value: visitedCount / totalBlocks,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progressPercent == 100 ? Colors.green : Colors.blue,
                      ),
                      strokeWidth: 6,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: visitedCount / totalBlocks,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progressPercent == 100 ? Colors.green : Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Block list with route visualization
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: geofenceZones.length,
              itemBuilder: (context, index) {
                final zone = geofenceZones[index];
                return _buildBlockRouteItem(zone, index, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build individual block route item dengan status & distance
  Widget _buildBlockRouteItem(
    GeofenceZone zone,
    int index,
    bool isDark,
  ) {
    // Check if visited using _visitedBlockNames Set
    final isVisited = _visitedBlockNames.contains(zone.name);
    final isCurrentBlock = _currentBlock == zone.name;

    // Calculate distance from current position using Geolocator
    double? distance;
    if (_currentPosition != null) {
      distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        zone.latitude,
        zone.longitude,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCurrentBlock
            ? (isDark ? Colors.blue.shade900 : Colors.blue.shade50)
            : (isDark ? AppColors.darkSurface : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentBlock
              ? Colors.blue
              : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
          width: isCurrentBlock ? 2 : 1,
        ),
        boxShadow: isCurrentBlock
            ? [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Route number & checkmark
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isVisited
                    ? Colors.green
                    : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isVisited
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),

            // Block info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          zone.name,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isCurrentBlock)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Lokasi Anda',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      // Checkpoint-focused UX: Only show distance when meaningful (<50m)
                      // For motor patrol, hide far distances to reduce clutter
                      if (distance == null) ...[
                        // GPS belum ready - show loading indicator
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.blue.shade300 : Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Mencari GPS...',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else if (distance > 50) ...[
                        // Far away - just show direction indicator
                        Text(
                          'Sedang menuju...',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else ...[
                        // Close enough (<50m) - show animated distance
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: animation,
                                child: child,
                              ),
                            );
                          },
                          child: Row(
                            key: ValueKey<int>(distance.round()),
                            children: [
                              // Proximity warning for <20m
                              if (distance <= 20) ...[
                                Icon(
                                  Icons.notifications_active,
                                  size: 14,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                '${distance.toStringAsFixed(0)} m',
                                style: TextStyle(
                                  color: distance <= 20
                                      ? Colors.orange
                                      : (isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.textSecondary),
                                  fontSize: 12,
                                  fontWeight: distance <= 20
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isVisited ||
                          _manualCheckIns.containsKey(zone.name)) ...[
                        const SizedBox(width: 12),
                        Icon(
                          _manualCheckIns.containsKey(zone.name)
                              ? Icons.camera_alt
                              : Icons.check_circle,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _manualCheckIns.containsKey(zone.name)
                              ? 'Check-in Manual'
                              : 'Dikunjungi',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Manual Check-in button (show if GPS poor or not visited)
                  if (!isVisited &&
                      !_manualCheckIns.containsKey(zone.name) &&
                      (_gpsQuality == 'Poor' || _showGpsLossWarning)) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _manualCheckIn(zone.name),
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text(
                          'Check-in Manual',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: BorderSide(color: Colors.orange.shade300),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Arrow icon
            Icon(
              Icons.chevron_right,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopButton() {
    return FloatingActionButton.extended(
      onPressed: _stopPatrol,
      backgroundColor: Colors.red,
      icon: const Icon(Icons.stop, color: Colors.white),
      label: const Text(
        'Selesai',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}j ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}d';
    } else {
      return '${seconds}d';
    }
  }
}

/// Manual Check-in Camera Screen
class _ManualCheckInCamera extends StatefulWidget {
  final CameraDescription camera;
  final String blockName;

  const _ManualCheckInCamera({
    required this.camera,
    required this.blockName,
  });

  @override
  State<_ManualCheckInCamera> createState() => _ManualCheckInCameraState();
}

class _ManualCheckInCameraState extends State<_ManualCheckInCamera> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
    );
    _initializeControllerFuture = _controller!.initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final XFile photo = await _controller!.takePicture();

      if (mounted) {
        Navigator.pop(context, photo);
      }
    } catch (e) {
      print('[ManualCheckIn] Error taking picture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                // Camera preview
                Positioned.fill(
                  child: CameraPreview(_controller!),
                ),

                // Header
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Check-in Manual',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  widget.blockName,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Instructions overlay
                Positioned(
                  bottom: 150,
                  left: 0,
                  right: 0,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.photo_camera, color: Colors.white, size: 32),
                        SizedBox(height: 8),
                        Text(
                          'Ambil foto checkpoint sebagai bukti kunjungan',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Capture button
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _takePicture,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: Colors.white,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: Colors.blue.shade700,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
        },
      ),
    );
  }
}
