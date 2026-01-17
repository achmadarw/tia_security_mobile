import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui';
import '../services/security_app_service.dart';
import '../services/auth_service.dart';
import '../config/theme.dart';
import 'app_selector_screen.dart';

/// Security Home Screen V2
/// Flexible interface for multiple security with check-in/check-out
class SecurityHomeScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  final AuthService? authService;

  const SecurityHomeScreen({
    Key? key,
    required this.sessionData,
    this.authService,
  }) : super(key: key);

  @override
  State<SecurityHomeScreen> createState() => _SecurityHomeScreenState();
}

class _SecurityHomeScreenState extends State<SecurityHomeScreen> {
  Map<String, dynamic>? _selectedPersonil;
  bool _hasActiveSession = false;
  List<Map<String, dynamic>> _todayTimeline = [];

  final SecurityAppService _service = SecurityAppService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();

    // Check if coming from session restore
    if (widget.sessionData.containsKey('user')) {
      _hasActiveSession = true;
      _selectedPersonil = widget.sessionData['user'];

      // Ensure pattern exists, use pattern from sessionData if not in user
      if (_selectedPersonil != null &&
          (_selectedPersonil!['pattern'] == null ||
              !(_selectedPersonil!['pattern'] is Map))) {
        if (widget.sessionData.containsKey('pattern')) {
          _selectedPersonil!['pattern'] = widget.sessionData['pattern'];
        }
      }
    }

    _loadTodayTimeline();
  }

  Future<void> _loadTodayTimeline() async {
    // TODO: Load today's check-in/check-out timeline
  }

  Future<void> _selectPersonil() async {
    final roster = widget.sessionData['roster'] as List?;
    if (roster == null || roster.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tidak ada roster'), backgroundColor: Colors.orange),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Pilih Personil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...roster.map((person) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(
                      person['name'].toString()[0].toUpperCase(),
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(person['name']),
                  subtitle: Text('Pattern: ${person['pattern']['name']}'),
                  onTap: () => Navigator.pop(context, person),
                )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() => _selectedPersonil = selected);
      if (!_hasActiveSession) {
        await _handleStartSession();
      }
    }
  }

  Future<void> _handleStartSession() async {
    if (_selectedPersonil == null) return;

    try {
      final posToken = widget.sessionData['pos_token'];
      if (posToken == null) {
        throw Exception('Pos token tidak tersedia. Silakan login ulang.');
      }

      final result = await _service.selectSecurity(
        posToken: posToken,
        userId: _selectedPersonil!['user_id'],
        assignmentId: _selectedPersonil!['assignment_id'],
      );

      setState(() {
        _hasActiveSession = true;
        widget.sessionData.addAll(result);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✓ Sesi dimulai'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('GPS tidak aktif');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Izin GPS ditolak');
      }
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _handleCheckIn() async {
    if (!_hasActiveSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Pilih personil dulu'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      // Take photo
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );
      if (photo == null) return;

      // Get GPS
      final position = await _getCurrentLocation();

      // TODO: Upload photo, then check-in with photo ID
      await _service.checkIn(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      await _loadTodayTimeline();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✓ Check-in berhasil'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Check-in gagal: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleCheckOut() async {
    if (!_hasActiveSession) return;

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );
      if (photo == null) return;

      final position = await _getCurrentLocation();

      await _service.checkOut(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      await _loadTodayTimeline();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✓ Check-out berhasil'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Check-out gagal: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleSwitchPersonil() async {
    if (_hasActiveSession) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ganti Personil'),
          content: const Text('Akhiri sesi saat ini dan ganti personil?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ganti'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      await _service.endSession();
      setState(() {
        _hasActiveSession = false;
        _selectedPersonil = null;
      });
    }

    await _selectPersonil();
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.sessionData['pos'] ?? {};
    final roster = widget.sessionData['roster'] ?? [];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, Colors.grey[100]!],
            stops: const [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (pos is Map && pos['name'] != null)
                                ? pos['name']
                                : 'Pos Security',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Kode: ${(pos is Map && pos['code'] != null) ? pos['code'].toString().toUpperCase() : '-'}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      onPressed: () async {
                        if (_hasActiveSession) {
                          await _service.endSession();
                        }
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AppSelectorScreen(
                                  authService: widget.authService!),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Personil Selector
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: Icon(
                              _selectedPersonil == null
                                  ? Icons.person_add
                                  : Icons.person,
                              color: AppColors.primary,
                            ),
                          ),
                          title: Text(
                            _selectedPersonil == null
                                ? 'Pilih Personil'
                                : _selectedPersonil!['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: _selectedPersonil != null
                              ? Text(
                                  'Pattern: ${(_selectedPersonil!['pattern'] is Map && _selectedPersonil!['pattern']['name'] != null) ? _selectedPersonil!['pattern']['name'] : '-'}')
                              : const Text('Tap untuk memilih'),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _handleSwitchPersonil,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Check-in Button
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton.icon(
                          onPressed: _hasActiveSession ? _handleCheckIn : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt, size: 28),
                          label: const Text(
                            'Check-in (GPS + Foto)',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Check-out Button
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton.icon(
                          onPressed: _hasActiveSession ? _handleCheckOut : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt, size: 28),
                          label: const Text(
                            'Check-out (GPS + Foto)',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Patrol Button
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: OutlinedButton.icon(
                          onPressed: _hasActiveSession
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Fitur Patrol segera hadir'),
                                    ),
                                  );
                                }
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side:
                                BorderSide(color: AppColors.primary, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.my_location, size: 28),
                          label: const Text(
                            'Mulai Patrol',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Timeline
                      if (_todayTimeline.isNotEmpty) ...[
                        const Text(
                          'Timeline Hari Ini',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._todayTimeline.map((item) => Card(
                              child: ListTile(
                                leading: Icon(
                                  item['type'] == 'check-in'
                                      ? Icons.login
                                      : Icons.logout,
                                  color: item['type'] == 'check-in'
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                title: Text(item['name']),
                                subtitle: Text(item['time']),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
