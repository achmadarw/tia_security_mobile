import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  Timer? _zonesCheckTimer;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePatrol();
  }

  Future<void> _initializePatrol() async {
    setState(() => _isLoading = true);

    try {
      // Load current patrol session (this will also fetch and setup blocks if needed)
      await _patrolService.loadCurrentSession();
      _currentSession = _patrolService.currentSession;

      if (_currentSession == null) {
        throw Exception('Tidak ada sesi patroli aktif');
      }

      // Wait a bit for zones to be setup
      await Future.delayed(const Duration(milliseconds: 500));

      print(
          '[ActivePatrol] Geofence zones available: ${_geofencingService.zones.length}');

      // Start GPS tracking
      await _gpsService.startTracking();

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

      // Check for geofence zones periodically (zones loaded asynchronously from API)
      _zonesCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (_geofencingService.zones.isNotEmpty) {
          setState(() {}); // Rebuild UI when zones available
        }
      });

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
    setState(() {
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
        _zonesCheckTimer?.cancel();

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
    _zonesCheckTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
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
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.gps_fixed, color: Colors.green, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Aktif',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    if (_currentPosition == null) {
      return Container(
        color: Colors.grey.shade300,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Visual rute blok user-friendly tanpa Google Maps
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
                      Text(
                        distance != null
                            ? distance < 1000
                                ? '${distance.toStringAsFixed(0)} m'
                                : '${(distance / 1000).toStringAsFixed(2)} km'
                            : 'Menghitung...',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (isVisited) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Dikunjungi',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
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
