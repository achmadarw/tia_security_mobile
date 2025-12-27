import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../config/theme.dart';
import '../config/theme_provider.dart';
import 'login_screen.dart';
import 'users_screen.dart';
import 'quick_attendance_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;

  const HomeScreen({super.key, required this.authService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  int _selectedIndex = 0;
  bool _isCheckedIn = false;
  String _statusText = 'Belum Check-in';
  String _checkInTime = '--:--';
  String _checkOutTime = '--:--';
  String _totalTime = '0j 0m';
  String _currentDuration = '--';
  bool _isLoadingAttendance = false;
  int _shiftCount = 0;
  List<dynamic> _shifts = [];
  Map<String, dynamic>? _currentShift;
  List<dynamic> _completedShifts = [];
  bool _isCardExpanded = false; // For expandable card

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _fadeController.forward();
    _scaleController.forward();
    _fetchTodayAttendance();
  }

  Future<void> _fetchTodayAttendance() async {
    if (_isLoadingAttendance) return;

    setState(() {
      _isLoadingAttendance = true;
    });

    try {
      final data = await widget.authService.getTodayAttendance();

      if (data != null && mounted) {
        setState(() {
          // Multiple shifts support
          _shifts = data['shifts'] ?? [];
          _shiftCount = data['shiftCount'] ?? 0;
          _isCheckedIn = data['isCheckedIn'] ?? false;
          _currentShift = data['currentShift'];
          _completedShifts = data['completedShifts'] ?? [];

          // Display CURRENT SHIFT (not first shift)
          if (_currentShift != null) {
            // Active shift
            final checkIn = _currentShift!['checkIn'];
            if (checkIn != null) {
              final checkInDate =
                  DateTime.parse(checkIn['created_at']).toLocal();
              _checkInTime = DateFormat('HH:mm').format(checkInDate);

              // Calculate live duration
              final now = DateTime.now();
              final diff = now.difference(checkInDate);
              final hours = diff.inHours;
              final minutes = diff.inMinutes % 60;
              _currentDuration = '${hours}j ${minutes}m';
            }
            _checkOutTime = '--:--';
            _statusText =
                _shiftCount > 1 ? 'Shift $_shiftCount Aktif' : 'Shift 1 Aktif';
          } else if (_completedShifts.isNotEmpty) {
            // Between shifts or all completed
            final lastShift = _completedShifts.last;
            final lastCheckIn = lastShift['checkIn'];
            final lastCheckOut = lastShift['checkOut'];

            if (lastCheckIn != null) {
              final checkInDate =
                  DateTime.parse(lastCheckIn['created_at']).toLocal();
              _checkInTime = DateFormat('HH:mm').format(checkInDate);
            }

            if (lastCheckOut != null) {
              final checkOutDate =
                  DateTime.parse(lastCheckOut['created_at']).toLocal();
              _checkOutTime = DateFormat('HH:mm').format(checkOutDate);
            }

            final hours = lastShift['hours'] ?? 0;
            final minutes = lastShift['minutes'] ?? 0;
            _currentDuration = '${hours}j ${minutes}m';

            if (_shiftCount > 1) {
              _statusText = 'Semua Shift Selesai';
            } else {
              _statusText = 'Sedang Istirahat';
            }
          } else {
            _checkInTime = '--:--';
            _checkOutTime = '--:--';
            _currentDuration = '--';
            _statusText = 'Belum Check-in';
          }

          // Total from all shifts
          final hours = data['totalHours'] ?? 0;
          final minutes = data['totalMinutes'] ?? 0;
          _totalTime = '${hours}j ${minutes}m';
        });
      }
    } catch (e) {
      print('Error fetching attendance: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAttendance = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.currentUser;
    final now = DateTime.now();
    final greeting = _getGreeting();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Set status bar color to match header
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.light,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchTodayAttendance();
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Modern Header
            SliverToBoxAdapter(
              child: _buildModernHeader(user, greeting, now),
            ),

            // Today's Status Card
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: _buildTodayStatusCard(),
                ),
              ),
            ),

            // Quick Stats
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _buildQuickStats(),
              ),
            ),

            // Quick Actions
            SliverToBoxAdapter(
              child: _buildModernQuickActions(),
            ),

            // Recent Activity
            SliverToBoxAdapter(
              child: _buildActivityTimeline(),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActions(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Selamat Pagi';
    if (hour < 15) return 'Selamat Siang';
    if (hour < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  Widget _buildModernHeader(user, String greeting, DateTime now) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // Get status bar height
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightPrimary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Hero(
                    tag: 'user_avatar',
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: isDark
                            ? AppColors.darkPrimary
                            : AppColors.lightPrimaryLight,
                        child: Text(
                          user?.name[0].toUpperCase() ?? 'U',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.name ?? 'User',
                        style: TextStyle(
                          color:
                              isDark ? AppColors.darkTextPrimary : Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  _buildHeaderIconButton(
                    Icons.notifications_outlined,
                    () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Notifications - Coming Soon')),
                      );
                    },
                    badge: '3',
                  ),
                  const SizedBox(width: 4),
                  _buildHeaderIconButton(
                    Icons.settings_outlined,
                    () => _showSettingsMenu(context),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            DateFormat('EEEE, d MMMM yyyy').format(now),
            style: TextStyle(
              color: isDark ? AppColors.darkTextSecondary : Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            DateFormat('HH:mm').format(now),
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton(IconData icon, VoidCallback onTap,
      {String? badge}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: IconButton(
            icon: Icon(
              icon,
              color: isDark ? AppColors.darkTextPrimary : Colors.white,
              size: 24,
            ),
            onPressed: onTap,
          ),
        ),
        if (badge != null)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isDark ? AppColors.errorDark : AppColors.error,
                shape: BoxShape.circle,
              ),
              child: Text(
                badge,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTodayStatusCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dynamic color based on status
    Color cardColor;
    Color statusIconColor;
    IconData statusIcon;

    if (_isCheckedIn) {
      // Active shift - Green
      cardColor = isDark ? Colors.green.shade900 : Colors.green.shade600;
      statusIconColor = Colors.green;
      statusIcon = Icons.radio_button_checked;
    } else if (_shiftCount > 0) {
      // Between shifts or completed - Blue
      cardColor = isDark ? AppColors.darkCard : AppColors.primary;
      statusIconColor = Colors.blue;
      statusIcon = _shiftCount > 1 ? Icons.check_circle : Icons.pause_circle;
    } else {
      // Not started - Grey
      cardColor = isDark ? AppColors.darkCard : Colors.grey.shade600;
      statusIconColor = Colors.grey;
      statusIcon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: GestureDetector(
        onTap: _shiftCount > 1
            ? () {
                setState(() {
                  _isCardExpanded = !_isCardExpanded;
                });
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  isDark ? AppColors.borderDark : Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.3)
                    : cardColor.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              // Status header with icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? statusIconColor.withOpacity(0.2)
                          : Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      statusIcon,
                      color: isDark ? statusIconColor : Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusText,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (_isCheckedIn)
                          Text(
                            'Check-in: $_checkInTime',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (!_isCheckedIn && _shiftCount > 0)
                          Text(
                            'Shift Terakhir: $_checkInTime - $_checkOutTime',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 20),

              // Current shift duration or last shift info
              if (_isCheckedIn)
                Row(
                  children: [
                    Expanded(
                      child: _buildStatusInfo(
                        'Durasi',
                        _currentDuration,
                        Icons.timer_outlined,
                      ),
                    ),
                    if (_completedShifts.isNotEmpty) ...[
                      Container(
                        width: 2,
                        height: 50,
                        color: isDark
                            ? AppColors.dividerDark
                            : Colors.white.withOpacity(0.4),
                      ),
                      Expanded(
                        child: _buildStatusInfo(
                          'Shift ${_completedShifts.length}',
                          '${_completedShifts.last['hours'] ?? 0}j ${_completedShifts.last['minutes'] ?? 0}m',
                          Icons.history,
                        ),
                      ),
                    ],
                    Container(
                      width: 2,
                      height: 50,
                      color: isDark
                          ? AppColors.dividerDark
                          : Colors.white.withOpacity(0.4),
                    ),
                    Expanded(
                      child: _buildStatusInfo(
                        'Total',
                        _totalTime,
                        Icons.access_time,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    if (_shiftCount > 0) ...[
                      Expanded(
                        child: _buildStatusInfo(
                          'Durasi',
                          _currentDuration,
                          Icons.timer_outlined,
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 50,
                        color: isDark
                            ? AppColors.dividerDark
                            : Colors.white.withOpacity(0.4),
                      ),
                    ],
                    Expanded(
                      child: _buildStatusInfo(
                        'Total Hari Ini',
                        _totalTime,
                        Icons.access_time,
                      ),
                    ),
                  ],
                ),

              // Multiple shift indicator with expand hint
              if (_shiftCount > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkPrimary.withOpacity(0.2)
                          : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkPrimary.withOpacity(0.4)
                            : Colors.white.withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.work_history,
                          color: isDark ? AppColors.darkPrimary : Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_shiftCount Shift Hari Ini',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _isCardExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: isDark ? AppColors.darkPrimary : Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

              // Expanded shift details
              if (_isCardExpanded && _shifts.isNotEmpty)
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 16),
                      ...List.generate(_shifts.length, (index) {
                        final shift = _shifts[index];
                        final checkIn = shift['checkIn'];
                        final checkOut = shift['checkOut'];
                        final isActive = checkOut == null;

                        String checkInTime = '--:--';
                        String checkOutTime = '--:--';
                        String duration = '--';

                        if (checkIn != null) {
                          final checkInDate =
                              DateTime.parse(checkIn['created_at']).toLocal();
                          checkInTime = DateFormat('HH:mm').format(checkInDate);

                          if (checkOut != null) {
                            final checkOutDate =
                                DateTime.parse(checkOut['created_at'])
                                    .toLocal();
                            checkOutTime =
                                DateFormat('HH:mm').format(checkOutDate);
                            duration =
                                '${shift['hours'] ?? 0}j ${shift['minutes'] ?? 0}m';
                          } else {
                            // Active shift - calculate live duration
                            final now = DateTime.now();
                            final diff = now.difference(checkInDate);
                            duration =
                                '${diff.inHours}j ${diff.inMinutes % 60}m';
                          }
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? (isActive
                                      ? Colors.green.shade900.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.05))
                                  : (isActive
                                      ? Colors.white.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.15)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? (isActive
                                        ? Colors.green.withOpacity(0.4)
                                        : Colors.white.withOpacity(0.2))
                                    : (isActive
                                        ? Colors.white.withOpacity(0.6)
                                        : Colors.white.withOpacity(0.3)),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.radio_button_checked
                                          : Icons.check_circle_outline,
                                      color: isDark
                                          ? (isActive
                                              ? Colors.green
                                              : AppColors.darkTextPrimary)
                                          : Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Shift ${index + 1}',
                                      style: TextStyle(
                                        color: isDark
                                            ? AppColors.darkTextPrimary
                                            : Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? (isActive
                                                ? Colors.green.withOpacity(0.2)
                                                : Colors.grey.withOpacity(0.2))
                                            : (isActive
                                                ? Colors.white.withOpacity(0.3)
                                                : Colors.white
                                                    .withOpacity(0.2)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isActive ? 'Aktif' : 'Selesai',
                                        style: TextStyle(
                                          color: isDark
                                              ? (isActive
                                                  ? Colors.green
                                                  : AppColors.darkTextSecondary)
                                              : Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Check-in',
                                            style: TextStyle(
                                              color: isDark
                                                  ? AppColors.darkTextSecondary
                                                  : Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            checkInTime,
                                            style: TextStyle(
                                              color: isDark
                                                  ? AppColors.darkTextPrimary
                                                  : Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Check-out',
                                            style: TextStyle(
                                              color: isDark
                                                  ? AppColors.darkTextSecondary
                                                  : Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            checkOutTime,
                                            style: TextStyle(
                                              color: isDark
                                                  ? AppColors.darkTextPrimary
                                                  : Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Durasi',
                                            style: TextStyle(
                                              color: isDark
                                                  ? AppColors.darkTextSecondary
                                                  : Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            duration,
                                            style: TextStyle(
                                              color: isDark
                                                  ? AppColors.darkTextPrimary
                                                  : Colors.white,
                                              fontSize: 16,
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
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusInfo(String label, String value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Icon(
          icon,
          color: isDark ? AppColors.darkTextPrimary : Colors.white,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: isDark ? AppColors.darkTextPrimary : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: isDark
                ? AppColors.darkTextSecondary
                : Colors.white.withOpacity(0.9),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCardMini(
              'Hadir',
              '22',
              'Hari ini bulan',
              Icons.event_available,
              Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCardMini(
              'Terlambat',
              '2',
              'Kali bulan ini',
              Icons.access_time,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCardMini(
              'Lembur',
              '5j',
              'Bulan ini',
              Icons.work_history,
              Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardMini(
      String label, String value, String subtitle, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
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
            color: color.withOpacity(isDark ? 0.2 : 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: isDark
                ? (color.computeLuminance() > 0.5
                    ? color
                    : color.withOpacity(0.8))
                : color,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: isDark
                  ? (color.computeLuminance() > 0.5
                      ? color
                      : color.withOpacity(0.8))
                  : color,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildModernQuickActions() {
    final user = widget.authService.currentUser;
    final isAdmin = user?.role == 'admin';

    final actions = [
      _ActionData('Absensi', Icons.face_outlined, AppColors.primary, () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuickAttendanceScreen(
              authService: widget.authService,
            ),
          ),
        );
        // Refresh attendance data when returning
        if (result == true) {
          _fetchTodayAttendance();
        }
      }),
      _ActionData('Laporan', Icons.description, AppColors.primary, () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Laporan - Coming Soon')),
        );
      }),
      if (isAdmin)
        _ActionData('Users', Icons.people, Colors.purple, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  UsersScreen(authService: widget.authService),
            ),
          );
        }),
      _ActionData('Jadwal', Icons.calendar_today, Colors.teal, () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jadwal - Coming Soon')),
        );
      }),
      _ActionData('Lokasi', Icons.location_on, Colors.indigo, () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lokasi - Coming Soon')),
        );
      }),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aksi Cepat',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: actions
                .map((action) => _buildModernActionCard(action))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModernActionCard(_ActionData action) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: (MediaQuery.of(context).size.width - 64) / 3,
        padding: const EdgeInsets.symmetric(vertical: 18),
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
              color: action.color.withOpacity(isDark ? 0.2 : 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: action.color.withOpacity(isDark ? 0.2 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                action.icon,
                color: isDark && action.color.computeLuminance() < 0.3
                    ? action.color.withOpacity(0.8)
                    : action.color,
                size: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTimeline() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Aktivitas Terkini',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'Lihat Semua',
                  style: TextStyle(
                    color:
                        isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTimelineItem(
            'Check-in Berhasil',
            'Hari ini pukul 08:00',
            Icons.check_circle,
            Colors.green,
            '2j lalu',
          ),
          _buildTimelineItem(
            'Laporan Patroli Selesai',
            'Area Gedung A - Lantai 3',
            Icons.article,
            AppColors.primary,
            '4j lalu',
          ),
          _buildTimelineItem(
            'Laporan Insiden',
            'Pintu parkir B1 rusak',
            Icons.warning,
            Colors.orange,
            'Kemarin',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    String time, {
    bool isLast = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(isDark ? 0.25 : 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withOpacity(isDark ? 0.4 : 0.2),
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                color: isDark && color.computeLuminance() < 0.3
                    ? color.withOpacity(0.8)
                    : color,
                size: 22,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 60,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withOpacity(isDark ? 0.4 : 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
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
        ),
      ],
    );
  }

  Widget _buildFloatingActions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      height: 65,
      width: 65,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primaryColor,
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton(
        elevation: 0,
        backgroundColor: Colors.transparent,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => QuickAttendanceScreen(
                authService: widget.authService,
              ),
            ),
          );
          // Refresh attendance data when returning
          if (result == true && mounted) {
            _fetchTodayAttendance();
          }
        },
        child: Icon(
          Icons.face,
          size: 32,
          color: isDark ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.4)
                : Colors.grey.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        backgroundColor: Colors.transparent,
        selectedItemColor: primaryColor,
        unselectedItemColor:
            isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        selectedFontSize: 13,
        unselectedFontSize: 12,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded, size: 26), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today, size: 24), label: 'Jadwal'),
          BottomNavigationBarItem(icon: Icon(Icons.face, size: 0), label: ''),
          BottomNavigationBarItem(
              icon: Icon(Icons.assessment, size: 26), label: 'Laporan'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person, size: 26), label: 'Profil'),
        ],
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.dividerDark : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Pengaturan',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Dark Mode Toggle
            ListTile(
              leading: Icon(
                isDark ? Icons.dark_mode : Icons.light_mode,
                color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                size: 26,
              ),
              title: Text(
                'Mode ${isDark ? "Gelap" : "Terang"}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              subtitle: Text(
                isDark ? 'Untuk shift malam (hemat mata)' : 'Untuk siang hari',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              trailing: Switch(
                value: isDark,
                activeColor: AppColors.darkPrimary,
                onChanged: (value) {
                  themeProvider.toggleTheme();
                  Navigator.pop(context);
                },
              ),
            ),

            Divider(
                color: isDark ? AppColors.dividerDark : AppColors.dividerLight),

            ListTile(
              leading: Icon(
                Icons.person,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
                size: 26,
              ),
              title: Text(
                'Profile',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(
                      authService: widget.authService,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.settings,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
                size: 26,
              ),
              title: Text(
                'Pengaturan Lainnya',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings - Coming Soon')),
                );
              },
            ),
            Divider(
                color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: isDark ? AppColors.errorDark : AppColors.error,
                size: 26,
              ),
              title: Text(
                'Logout',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? AppColors.errorDark : AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                await widget.authService.logout();
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) =>
                        LoginScreen(authService: widget.authService),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionData {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _ActionData(this.label, this.icon, this.color, this.onTap);
}
