import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../../models/shift.dart';
import '../../services/shift_service.dart';
import '../../services/auth_service.dart';
import '../../config/theme.dart';
import 'add_shift_screen.dart';

class ShiftManagementScreen extends StatefulWidget {
  final AuthService authService;

  const ShiftManagementScreen({
    Key? key,
    required this.authService,
  }) : super(key: key);

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  final ShiftService _shiftService = ShiftService();
  List<Shift> _shifts = [];
  List<Shift> _filteredShifts = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _filterStatus = 'all'; // 'all', 'active', 'inactive'

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  Future<void> _loadShifts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = widget.authService.accessToken;
      if (token == null) {
        throw Exception('No authentication token');
      }

      final shifts = await _shiftService.getShifts(token);

      setState(() {
        _shifts = shifts;
        _filteredShifts = shifts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterShifts() {
    setState(() {
      _filteredShifts = _shifts.where((shift) {
        final matchesSearch =
            shift.name.toLowerCase().contains(_searchQuery.toLowerCase());

        final matchesStatus = _filterStatus == 'all' ||
            (_filterStatus == 'active' && shift.isActive) ||
            (_filterStatus == 'inactive' && !shift.isActive);

        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  Future<void> _deleteShift(Shift shift) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text('Yakin ingin menghapus shift "${shift.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final token = widget.authService.accessToken;
        if (token == null) throw Exception('No token');

        final result = await _shiftService.deleteShift(token, shift.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(result['message'] ?? 'Shift berhasil dihapus')),
        );

        _loadShifts();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final activeCount = _shifts.where((s) => s.isActive).length;
    final inactiveCount = _shifts.where((s) => !s.isActive).length;

    // Set status bar color
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
          _buildHeader(isDark, primaryColor),
          _buildStatsBar(isDark, activeCount, inactiveCount),
          _buildSearchAndFilter(isDark),
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _error != null
                    ? _buildError()
                    : _buildShiftsList(isDark),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddShiftScreen(
                authService: widget.authService,
              ),
            ),
          );

          if (result == true) {
            _loadShifts();
          }
        },
        icon: const Icon(Icons.add, size: 24),
        label: const Text(
          'TAMBAH SHIFT',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: primaryColor,
        foregroundColor: isDark ? Colors.black : Colors.white,
        elevation: 4,
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color primaryColor) {
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
                  'Manajemen Shift',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_filteredShifts.length} shift',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : Colors.white.withOpacity(0.85),
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
              Icons.schedule,
              color: isDark ? AppColors.darkTextPrimary : Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(bool isDark, int activeCount, int inactiveCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(
                color: AppColors.borderDark,
                width: 1,
              )
            : null,
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'Total',
            _shifts.length,
            Icons.grid_view,
            isDark ? AppColors.darkPrimaryDark : AppColors.primary,
            isDark,
          ),
          Container(
            width: 1,
            height: 40,
            color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
          ),
          _buildStatItem(
            'Aktif',
            activeCount,
            Icons.check_circle,
            Colors.green,
            isDark,
          ),
          Container(
            width: 1,
            height: 40,
            color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
          ),
          _buildStatItem(
            'Nonaktif',
            inactiveCount,
            Icons.cancel,
            Colors.red,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, int count, IconData icon, Color color, bool isDark) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 6),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color:
                isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilter(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Modern Search bar
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.lightSurfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                width: 1.5,
              ),
            ),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _filterShifts();
                });
              },
              style: TextStyle(
                fontSize: 15,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Cari nama shift...',
                hintStyle: TextStyle(
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextSecondary,
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  size: 24,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _filterShifts();
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Modern filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Semua', 'all', Icons.grid_view, isDark),
                _buildFilterChip('Aktif', 'active', Icons.check_circle, isDark),
                _buildFilterChip('Nonaktif', 'inactive', Icons.cancel, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
      String label, String value, IconData icon, bool isDark) {
    final isSelected = _filterStatus == value;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected
              ? Colors.white
              : (isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary),
        ),
        backgroundColor: isDark ? AppColors.darkCard : Colors.grey.shade100,
        selectedColor: primaryColor,
        checkmarkColor: Colors.white,
        side: BorderSide(
          color: isSelected
              ? primaryColor
              : (isDark ? AppColors.borderDark : Colors.grey.shade300),
          width: 1.5,
        ),
        onSelected: (selected) {
          setState(() {
            _filterStatus = value;
            _filterShifts();
          });
        },
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: $_error'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadShifts,
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftsList(bool isDark) {
    if (_filteredShifts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 64,
              color: isDark ? AppColors.darkTextTertiary : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Tidak ada shift yang sesuai pencarian'
                  : 'Belum ada shift',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? AppColors.darkTextSecondary : Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadShifts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredShifts.length,
        itemBuilder: (context, index) {
          final shift = _filteredShifts[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isDark
                  ? Border.all(color: AppColors.borderDark, width: 1)
                  : null,
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
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Color indicator bar
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: shift.colorValue,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // Color circle avatar
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: shift.colorValue.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.access_time,
                              color: shift.colorValue,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Text content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Title with active badge
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        shift.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isDark
                                              ? AppColors.darkTextPrimary
                                              : AppColors.lightTextPrimary,
                                        ),
                                      ),
                                    ),
                                    // Active/Inactive badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: shift.isActive
                                            ? Colors.green.withOpacity(0.15)
                                            : Colors.red.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            shift.isActive
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            size: 12,
                                            color: shift.isActive
                                                ? Colors.green.shade700
                                                : Colors.red.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            shift.isActive
                                                ? 'AKTIF'
                                                : 'NONAKTIF',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: shift.isActive
                                                  ? Colors.green.shade700
                                                  : Colors.red.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Time
                                Row(
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      size: 16,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${shift.getFormattedStartTime()} - ${shift.getFormattedEndTime()}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.lightTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Duration
                                Row(
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 14,
                                      color: isDark
                                          ? AppColors.darkTextTertiary
                                          : AppColors.lightTextSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      shift.getDuration(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? AppColors.darkTextTertiary
                                            : AppColors.lightTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                // Description
                                if (shift.description != null &&
                                    shift.description!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      shift.description!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? AppColors.darkTextTertiary
                                            : AppColors.lightTextSecondary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Menu button
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AddShiftScreen(
                                      authService: widget.authService,
                                      shift: shift,
                                    ),
                                  ),
                                );

                                if (result == true) {
                                  _loadShifts();
                                }
                              } else if (value == 'delete') {
                                _deleteShift(shift);
                              } else if (value == 'toggle') {
                                _toggleShiftActive(shift);
                              }
                            },
                            icon: Icon(
                              Icons.more_vert,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Row(
                                  children: [
                                    Icon(
                                      shift.isActive
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(shift.isActive
                                        ? 'Nonaktifkan'
                                        : 'Aktifkan'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete,
                                        size: 20, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text(
                                      'Hapus',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleShiftActive(Shift shift) async {
    try {
      final token = widget.authService.accessToken;
      if (token == null) throw Exception('No token');

      await _shiftService.updateShift(
        token,
        shift.id,
        isActive: !shift.isActive,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(shift.isActive ? 'Shift dinonaktifkan' : 'Shift diaktifkan'),
        ),
      );

      _loadShifts();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }
}
