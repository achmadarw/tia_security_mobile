import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/block_service.dart';
import '../../models/block.dart';

class BlockFormScreen extends StatefulWidget {
  final AuthService authService;
  final Block? block; // null for create, non-null for edit

  const BlockFormScreen({
    super.key,
    required this.authService,
    this.block,
  });

  @override
  State<BlockFormScreen> createState() => _BlockFormScreenState();
}

class _BlockFormScreenState extends State<BlockFormScreen> {
  final BlockService _blockService = BlockService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _latController;
  late TextEditingController _lngController;

  bool _isActive = true;
  bool _isLoading = false;
  bool _isGettingGPS = false;
  Position? _currentPosition;
  
  // GPS Warm-up tracking
  bool _isWarmingUp = false;
  int _warmupSeconds = 0;
  double _bestAccuracy = double.infinity;
  Position? _bestPosition;
  int _gpsReadCount = 0;
  final List<double> _accuracyHistory = [];

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing data if editing
    _nameController = TextEditingController(text: widget.block?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.block?.description ?? '');
    _latController = TextEditingController(
      text: widget.block?.locationLat.toStringAsFixed(8) ?? '',
    );
    _lngController = TextEditingController(
      text: widget.block?.locationLng.toStringAsFixed(8) ?? '',
    );

    if (widget.block != null) {
      _isActive = widget.block!.isActive;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingGPS = true;
      _isWarmingUp = true;
      _warmupSeconds = 0;
      _bestAccuracy = double.infinity;
      _bestPosition = null;
      _gpsReadCount = 0;
      _accuracyHistory.clear();
    });

    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Izin lokasi ditolak');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'Izin lokasi ditolak permanen. Buka pengaturan untuk mengaktifkan.');
      }

      print('[BlockForm] 🛰️ Starting GPS warm-up sequence...');
      
      // GPS Warm-up: Poll multiple times for best accuracy
      const maxDuration = 90; // seconds (extended for optimal satellite + fused location lock)
      const pollInterval = 3; // seconds (optimal GPS update interval)
      const targetAccuracy = 8.0; // meters (excellent target with Fused Location)
      
      for (int i = 0; i < (maxDuration / pollInterval); i++) {
        if (!mounted || !_isWarmingUp) break;
        
        try {
          _warmupSeconds = i * pollInterval;
          _gpsReadCount++;
          
          print('[BlockForm] 📡 GPS read #$_gpsReadCount (${_warmupSeconds}s)...');
          
          // Get current position with highest accuracy
          // Use Google Fused Location (GPS + WiFi + Cell) for best static position
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best, // Highest accuracy for static points
            forceAndroidLocationManager: false, // Use Google Fused Location Provider
            timeLimit: Duration(seconds: pollInterval + 1),
          );
          
          final accuracy = position.accuracy;
          
          // Filter extreme outliers (GPS temporary loss/spike)
          if (accuracy > 50.0) {
            print('[BlockForm] 🚫 Outlier rejected: ${accuracy.toStringAsFixed(1)}m');
            continue; // Skip this reading
          }
          
          _accuracyHistory.add(accuracy);
          
          print('[BlockForm] 📍 Accuracy: ${accuracy.toStringAsFixed(1)}m');
          
          // Track best position
          if (accuracy < _bestAccuracy) {
            _bestAccuracy = accuracy;
            _bestPosition = position;
            print('[BlockForm] ✨ New best accuracy: ${accuracy.toStringAsFixed(1)}m');
          }
          
          // Update UI
          if (mounted) {
            setState(() {
              _currentPosition = _bestPosition;
            });
          }
          
          // Early exit if excellent accuracy achieved
          if (accuracy <= targetAccuracy) {
            print('[BlockForm] ✅ Target accuracy reached: ${accuracy.toStringAsFixed(1)}m');
            break;
          }
          
          // Wait before next poll (except last iteration)
          if (i < (maxDuration / pollInterval) - 1) {
            await Future.delayed(Duration(seconds: pollInterval));
          }
          
        } catch (e) {
          print('[BlockForm] ⚠️ GPS read failed: $e');
          // Continue trying
        }
      }
      
      // Use best position obtained
      if (_bestPosition != null) {
        print('[BlockForm] 🎯 GPS warm-up complete!');
        print('[BlockForm] Best accuracy: ${_bestAccuracy.toStringAsFixed(1)}m from $_gpsReadCount reads');
        
        setState(() {
          _currentPosition = _bestPosition;
          _latController.text = _bestPosition!.latitude.toStringAsFixed(8);
          _lngController.text = _bestPosition!.longitude.toStringAsFixed(8);
          _isGettingGPS = false;
          _isWarmingUp = false;
        });

        // Show result based on accuracy achieved
        if (_bestAccuracy <= 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ GPS Optimal!\n'
                'Akurasi: ${_bestAccuracy.toStringAsFixed(1)}m (Excellent)\n'
                'Reads: $_gpsReadCount dalam ${_warmupSeconds}s',
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (_bestAccuracy <= 10) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ GPS Berhasil\n'
                'Akurasi: ${_bestAccuracy.toStringAsFixed(1)}m (Good)\n'
                'Reads: $_gpsReadCount dalam ${_warmupSeconds}s',
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (_bestAccuracy <= 20) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ GPS Cukup\n'
                'Akurasi: ${_bestAccuracy.toStringAsFixed(1)}m (Fair)\n'
                'Tip: Tunggu lebih lama atau pindah ke area lebih terbuka',
              ),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'COBA LAGI',
                textColor: Colors.white,
                onPressed: _getCurrentLocation,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ Akurasi Rendah\n'
                'Akurasi: ${_bestAccuracy.toStringAsFixed(1)}m (Poor)\n\n'
                'Untuk hasil terbaik:\n'
                '• Pindah ke area terbuka\n'
                '• Pastikan langit terlihat\n'
                '• Tunggu lebih lama (1-2 menit)\n'
                '• Aktifkan "High Accuracy" di pengaturan',
              ),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'COBA LAGI',
                textColor: Colors.white,
                onPressed: _getCurrentLocation,
              ),
            ),
          );
        }
      } else {
        throw Exception('Tidak dapat mendapatkan posisi GPS');
      }
      
    } catch (e) {
      print('[BlockForm] GPS error: $e');
      setState(() {
        _isGettingGPS = false;
        _isWarmingUp = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mendapatkan lokasi GPS: $e'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate GPS accuracy if coordinates were obtained via GPS
    if (_currentPosition != null && _currentPosition!.accuracy > 20) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('Akurasi GPS Rendah'),
            ],
          ),
          content: Text(
            'Akurasi GPS saat ini ${_currentPosition!.accuracy.toStringAsFixed(1)}m.\n\n'
            'Untuk sistem patrol yang akurat (geofencing 5m), disarankan akurasi ≤20m.\n\n'
            'Akurasi rendah dapat menyebabkan:\n'
            '• Check-in patrol tidak akurat\n'
            '• False positive/negative detection\n'
            '• Data patrol tidak reliable\n\n'
            'Rekomendasi:\n'
            '1. Pindah ke area terbuka\n'
            '2. Tunggu GPS stabil\n'
            '3. Ambil koordinat lagi\n\n'
            'Tetap lanjutkan simpan dengan akurasi ini?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('BATAL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('LANJUTKAN'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        return; // User cancelled
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim();
      final lat = double.parse(_latController.text.trim());
      final lng = double.parse(_lngController.text.trim());

      final blockData = Block(
        id: widget.block?.id,
        name: name,
        description: description.isNotEmpty ? description : null,
        locationLat: lat,
        locationLng: lng,
        status: _isActive ? 'active' : 'inactive',
      );

      print('[BlockForm] Submitting block: $blockData');

      Block result;
      if (widget.block == null) {
        // Create new block
        result = await _blockService.createBlock(blockData);
        print('[BlockForm] Block created: ${result.id}');
      } else {
        // Update existing block
        result = await _blockService.updateBlock(widget.block!.id!, blockData);
        print('[BlockForm] Block updated: ${result.id}');
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.block == null
                ? 'Blok "${result.name}" berhasil ditambahkan'
                : 'Blok "${result.name}" berhasil diperbarui',
          ),
          backgroundColor: AppColors.success,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      print('[BlockForm] Submit error: $e');
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan blok: $e'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isEditing = widget.block != null;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          _buildHeader(isDark, primaryColor, isEditing),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // GPS Location Button
                    _buildGPSLocationCard(isDark, primaryColor),
                    const SizedBox(height: 24),

                    // Block Information Section
                    _buildSectionTitle('INFORMASI BLOK', isDark),
                    const SizedBox(height: 16),

                    // Name field
                    _buildTextField(
                      controller: _nameController,
                      label: 'Nama Blok',
                      hint: 'Contoh: Blok NW, Pintu Utara',
                      icon: Icons.label,
                      isDark: isDark,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Nama blok wajib diisi';
                        }
                        if (value.trim().length < 3) {
                          return 'Nama blok minimal 3 karakter';
                        }
                        if (value.trim().length > 50) {
                          return 'Nama blok maksimal 50 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Description field
                    _buildTextField(
                      controller: _descriptionController,
                      label: 'Deskripsi (Opsional)',
                      hint: 'Dekat pintu masuk utara, sebelah kantin',
                      icon: Icons.notes,
                      isDark: isDark,
                      maxLines: 3,
                      validator: (value) {
                        if (value != null && value.trim().length > 200) {
                          return 'Deskripsi maksimal 200 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Coordinates Section
                    _buildSectionTitle('KOORDINAT GPS', isDark),
                    const SizedBox(height: 8),
                    if (_currentPosition != null)
                      _buildAccuracyIndicator(isDark),
                    const SizedBox(height: 16),

                    // Latitude field
                    _buildTextField(
                      controller: _latController,
                      label: 'Latitude',
                      hint: '-6.512958',
                      icon: Icons.my_location,
                      isDark: isDark,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Latitude wajib diisi';
                        }
                        try {
                          final lat = double.parse(value.trim());
                          if (lat < -90 || lat > 90) {
                            return 'Latitude harus antara -90 dan 90';
                          }
                        } catch (e) {
                          return 'Format latitude tidak valid';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Longitude field
                    _buildTextField(
                      controller: _lngController,
                      label: 'Longitude',
                      hint: '106.802615',
                      icon: Icons.location_on,
                      isDark: isDark,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Longitude wajib diisi';
                        }
                        try {
                          final lng = double.parse(value.trim());
                          if (lng < -180 || lng > 180) {
                            return 'Longitude harus antara -180 dan 180';
                          }
                        } catch (e) {
                          return 'Format longitude tidak valid';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Status Section
                    _buildSectionTitle('STATUS BLOK', isDark),
                    const SizedBox(height: 16),
                    _buildStatusSelector(isDark, primaryColor),
                    const SizedBox(height: 32),

                    // Submit button
                    _buildSubmitButton(isDark, primaryColor, isEditing),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color primaryColor, bool isEditing) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding + 12, 16, 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : primaryColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isDark ? AppColors.darkTextPrimary : Colors.white,
                size: 24,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit Blok' : 'Tambah Blok',
                  style: TextStyle(
                    color: isDark ? AppColors.darkTextPrimary : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEditing
                      ? 'Perbarui informasi blok'
                      : 'Gunakan lokasi GPS saat ini',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isEditing ? Icons.edit_location : Icons.add_location,
              color: isDark ? AppColors.darkTextPrimary : Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGPSLocationCard(bool isDark, Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            isDark ? Border.all(color: AppColors.borderDark, width: 1) : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isGettingGPS || _isLoading ? null : _getCurrentLocation,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isGettingGPS
                      ? SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: primaryColor,
                          ),
                        )
                      : Icon(
                          Icons.gps_fixed,
                          color: primaryColor,
                          size: 28,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isGettingGPS
                            ? (_isWarmingUp 
                                ? '🛰️ Warming up GPS... (${_warmupSeconds}s)'
                                : 'Mencari sinyal GPS...')
                            : 'Gunakan Lokasi GPS Saat Ini',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isGettingGPS
                            ? (_isWarmingUp
                                ? 'Reads: $_gpsReadCount | Best: ${_bestAccuracy == double.infinity ? "--" : "${_bestAccuracy.toStringAsFixed(1)}m"}'
                                : 'Menghubungi satelit GPS...')
                            : _currentPosition != null
                                ? 'GPS terdeteksi • Akurasi ${_currentPosition!.accuracy.toStringAsFixed(1)}m'
                                : 'Pastikan GPS aktif dan Anda berada di lokasi blok',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccuracyIndicator(bool isDark) {
    if (_currentPosition == null) return const SizedBox.shrink();

    final accuracy = _currentPosition!.accuracy;
    Color color;
    String label;
    String description;
    IconData icon;

    // Calculate accuracy improvement if history available
    String improvementText = '';
    if (_accuracyHistory.length >= 2) {
      final first = _accuracyHistory.first;
      final last = _accuracyHistory.last;
      final improvement = first - last;
      if (improvement > 1) {
        improvementText = ' (Improved ${improvement.toStringAsFixed(1)}m from ${_gpsReadCount} reads)';
      }
    }

    if (accuracy <= 5) {
      color = isDark ? AppColors.successDark : AppColors.success;
      label = 'Akurasi Sangat Baik';
      description =
          'GPS accuracy: ${accuracy.toStringAsFixed(1)}m - Ideal untuk patrol geofencing 5m$improvementText';
      icon = Icons.check_circle;
    } else if (accuracy <= 10) {
      color = isDark ? AppColors.infoDark : AppColors.info;
      label = 'Akurasi Baik';
      description =
          'GPS accuracy: ${accuracy.toStringAsFixed(1)}m - Cocok untuk patrol$improvementText';
      icon = Icons.check_circle_outline;
    } else if (accuracy <= 20) {
      color = isDark ? AppColors.warningDark : AppColors.warning;
      label = 'Akurasi Cukup';
      description =
          'GPS accuracy: ${accuracy.toStringAsFixed(1)}m - Minimal untuk patrol$improvementText';
      icon = Icons.warning_amber;
    } else {
      color = isDark ? AppColors.errorDark : AppColors.error;
      label = 'Akurasi Rendah - TIDAK DISARANKAN';
      description =
          'GPS accuracy: ${accuracy.toStringAsFixed(1)}m - Terlalu tidak akurat untuk patrol! Pindah ke area terbuka.$improvementText';
      icon = Icons.error_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color:
            isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            isDark ? Border.all(color: AppColors.borderDark, width: 1) : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.grey.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: TextStyle(
          color:
              isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(
            icon,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
          labelStyle: TextStyle(
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
          hintStyle: TextStyle(
            color: isDark
                ? AppColors.darkTextTertiary
                : AppColors.lightTextSecondary,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: maxLines > 1 ? 16 : 14,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSelector(bool isDark, Color primaryColor) {
    return Row(
      children: [
        Expanded(
          child: _buildStatusOption(
            'Aktif',
            true,
            Icons.check_circle,
            isDark,
            primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatusOption(
            'Nonaktif',
            false,
            Icons.cancel,
            isDark,
            primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusOption(
    String label,
    bool value,
    IconData icon,
    bool isDark,
    Color primaryColor,
  ) {
    final isSelected = _isActive == value;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? primaryColor
              : (isDark ? AppColors.borderDark : AppColors.borderLight),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: primaryColor.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _isActive = value;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? primaryColor
                      : (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary),
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? primaryColor
                        : (isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(bool isDark, Color primaryColor, bool isEditing) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading || _isGettingGPS ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: isDark ? Colors.black : Colors.white,
          disabledBackgroundColor:
              isDark ? AppColors.darkTextTertiary : Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: primaryColor.withOpacity(0.3),
        ),
        child: _isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: isDark ? Colors.black : Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isEditing ? Icons.check : Icons.add_location,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'PERBARUI BLOK' : 'SIMPAN BLOK',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
