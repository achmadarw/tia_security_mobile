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
      // Load current patrol session
      await _patrolService.loadCurrentSession();
      _currentSession = _patrolService.currentSession;

      if (_currentSession == null) {
        throw Exception('Tidak ada sesi patroli aktif');
      }

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

      // Add to route
      final latLng = LatLng(position.latitude, position.longitude);
      _routePoints.add(latLng);

      // Update current position marker
      _markers.removeWhere((m) => m.markerId.value == 'current_position');
      _markers.add(
        Marker(
          markerId: const MarkerId('current_position'),
          position: latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Posisi Saya'),
        ),
      );

      // Update polyline (route trail)
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('patrol_route'),
          points: _routePoints,
          color: Colors.blue,
          width: 4,
        ),
      );

      // Move camera to current position
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(latLng),
      );
    });

    // Update geofencing service
    _geofencingService.updatePosition(position);
  }

  void _handleGeofenceEvent(GeofenceEvent event) {
    print('[ActivePatrol] Geofence event: ${event.type} - ${event.zone.name}');

    if (event.type == GeofenceEventType.enter) {
      // Mark block as visited
      if (!_visitedBlockNames.contains(event.zone.name)) {
        _visitedBlockNames.add(event.zone.name);
        setState(() {
          _currentBlock = event.zone.name;
          _visitedBlocks = _visitedBlockNames.length;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✓ ${event.zone.name} dikunjungi (${_visitedBlocks}/${_geofencingService.zones.length})'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          _currentBlock = event.zone.name;
        });
      }

      // Add checkpoint marker
      _markers.add(
        Marker(
          markerId: MarkerId('checkpoint_${event.zone.name}'),
          position: LatLng(event.position.latitude, event.position.longitude),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: event.zone.name,
            snippet: 'Checkpoint',
          ),
        ),
      );
    } else if (event.type == GeofenceEventType.exit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Meninggalkan ${event.zone.name}'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _stopPatrol() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selesaikan Patroli?'),
        content: const Text(
          'Apakah Anda yakin ingin menyelesaikan patroli? Anda dapat menambahkan catatan pada halaman berikutnya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ya, Selesaikan'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Stop GPS tracking
      await _gpsService.stopTracking();

      // Navigate to completion screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const PatrolCompleteScreen(),
          ),
        );
      }
    }
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Error'),
          backgroundColor:
              isDark ? AppColors.darkSurface : AppColors.lightPrimary,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kembali'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Google Maps
          _buildMap(),

          // Top info panel
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopPanel(isDark),
          ),

          // Bottom stats panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(isDark),
          ),

          // Stop button (floating)
          Positioned(
            bottom: 200,
            right: 16,
            child: _buildStopButton(),
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
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 140), // Space for top panel
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
        ),
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

    // Calculate distance from current position
    double? distance;
    if (_currentPosition != null) {
      final lat1 = _currentPosition!.latitude;
      final lon1 = _currentPosition!.longitude;
      final lat2 = zone.latitude;
      final lon2 = zone.longitude;
      distance = _calculateDistance(lat1, lon1, lat2, lon2);
    }

    final isNearby = distance != null && distance < zone.radiusMeters;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route line connector
          Column(
            children: [
              // Status icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isVisited
                      ? Colors.green
                      : isCurrentBlock
                          ? Colors.blue
                          : isNearby
                              ? Colors.orange
                              : Colors.grey.shade300,
                  border: Border.all(
                    color: isCurrentBlock
                        ? Colors.blue.shade700
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: Icon(
                  isVisited
                      ? Icons.check_circle
                      : isCurrentBlock
                          ? Icons.my_location
                          : isNearby
                              ? Icons.near_me
                              : Icons.circle_outlined,
                  color: isVisited || isCurrentBlock || isNearby
                      ? Colors.white
                      : Colors.grey.shade600,
                  size: 20,
                ),
              ),

              // Connector line to next block
              if (index < _geofencingService.zones.length - 1)
                Container(
                  width: 2,
                  height: 40,
                  color:
                      isVisited ? Colors.green.shade300 : Colors.grey.shade300,
                ),
            ],
          ),

          const SizedBox(width: 12),

          // Block info card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCurrentBlock
                    ? Colors.blue.shade50
                    : isDark
                        ? AppColors.darkSurface
                        : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCurrentBlock
                      ? Colors.blue
                      : isNearby
                          ? Colors.orange
                          : Colors.grey.shade300,
                  width: isCurrentBlock ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
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
                            fontWeight: isCurrentBlock
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isVisited)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 14, color: Colors.green),
                              SizedBox(width: 4),
                              Text(
                                'Dikunjungi',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isCurrentBlock)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.my_location,
                                  size: 14, color: Colors.blue),
                              SizedBox(width: 4),
                              Text(
                                'Di Lokasi',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  if (distance != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.near_me,
                          size: 14,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          distance < 1000
                              ? '${distance.round()} meter'
                              : '${(distance / 1000).toStringAsFixed(1)} km',
                          style: TextStyle(
                            color: isNearby
                                ? Colors.orange
                                : isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight:
                                isNearby ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (isNearby) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'DEKAT',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // Coordinates (small text)
                  const SizedBox(height: 4),
                  Text(
                    'Lat: ${zone.latitude.toStringAsFixed(6)}, Lng: ${zone.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Calculate distance between two points in meters (Haversine formula)
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }

  Widget _buildTopPanel(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 48, left: 16, right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkCard.withOpacity(0.95)
            : Colors.white.withOpacity(0.95),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.navigate_next,
                  color: Colors.green,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patroli Aktif',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _currentBlock ?? 'Belum ada blok',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.white, size: 8),
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(_patrolDuration),
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
        ],
      ),
    );
  }

  Widget _buildBottomPanel(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Stats grid
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.location_on,
                  label: 'Blok Dikunjungi',
                  value: '$_visitedBlocks',
                  color: Colors.blue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.route,
                  label: 'Titik GPS',
                  value: '${_routePoints.length}',
                  color: Colors.orange,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.speed,
                  label: 'Kecepatan',
                  value: _currentPosition != null
                      ? '${_currentPosition!.speed.toStringAsFixed(1)} m/s'
                      : '0 m/s',
                  color: Colors.green,
                  isDark: isDark,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // GPS accuracy info
          if (_currentPosition != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkPrimary.withOpacity(0.1)
                    : AppColors.lightPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.gps_fixed,
                    size: 16,
                    color:
                        isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Akurasi GPS: ${_currentPosition!.accuracy.toStringAsFixed(1)}m',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Update: 1 detik',
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
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
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
