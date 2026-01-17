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
import 'admin/shift_management_screen.dart';
import 'admin/roster_management_screen.dart';

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
  Map<String, dynamic>? _lastCompletedShift24h; // Last shift in 24 hours
  bool _isCardExpanded = false; // For expandable card
  List<dynamic> _todayAssignments = []; // Shift assignments for today
  bool _hasAssignments = false;

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

      print(
          '[HOME] getTodayAttendance response: ${data != null ? "SUCCESS" : "NULL"}');
      if (data != null) {
        print('[HOME] isCheckedIn: ${data['isCheckedIn']}');
        print('[HOME] shifts count: ${data['shifts']?.length ?? 0}');
        print(
            '[HOME] currentShift: ${data['currentShift'] != null ? "YES" : "NO"}');
        print(
            '[HOME] completedShifts: ${data['completedShifts']?.length ?? 0}');
      }

      if (data != null && mounted) {
        setState(() {
          // Shift assignments
          _todayAssignments = data['assignments'] ?? [];
          _hasAssignments = data['hasAssignments'] ?? false;

          // Multiple shifts support
          _shifts = data['shifts'] ?? [];
          _shiftCount = data['shiftCount'] ?? 0;
          _isCheckedIn = data['isCheckedIn'] ?? false;
          _currentShift = data['currentShift'];
          _completedShifts = data['completedShifts'] ?? [];
          _lastCompletedShift24h = data['lastCompletedShift24h']; // New field

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

            // Determine status based on early leave and shift count
            final isEarlyLeave = lastShift['isEarlyLeave'] == true;

            if (isEarlyLeave) {
              // User left early before shift ended
              _statusText = 'Pulang Cepat';
            } else if (_shiftCount > 1) {
              // Check if there are more shifts scheduled
              final hasMoreShifts =
                  _todayAssignments.length > _completedShifts.length;
              if (hasMoreShifts) {
                _statusText = 'Sedang Istirahat'; // Between shifts
              } else {
                _statusText = 'Semua Shift Selesai';
              }
            } else {
              // Single shift completed normally
              _statusText = 'Shift Selesai';
            }
          } else {
            // No current or completed shifts
            if (_isCheckedIn) {
              // User is checked in but no shift data yet
              _checkInTime = '--:--';
              _checkOutTime = '--:--';
              _currentDuration = '--';
              _statusText = 'Check-in Aktif';
            } else {
              // User has not checked in
              _checkInTime = '--:--';
              _checkOutTime = '--:--';
              _currentDuration = '--';
              // Check if user is OFF today but has last completed shift
              if (_lastCompletedShift24h != null && !_hasAssignments) {
                _statusText = 'Libur Hari Ini';
              } else {
                _statusText = 'Belum Check-in';
              }
            }
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
      extendBody: true,
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
      bottomNavigationBar: SizedBox(
        height: 58,
        child: _buildBottomNavBar(),
      ),
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
    } else if (_statusText == 'Libur Hari Ini') {
      // User is OFF today - Blue-friendly
      cardColor = isDark ? Colors.blue.shade800 : Colors.blue.shade600;
      statusIconColor = Colors.blue;
      statusIcon = Icons.wb_sunny;
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
                          Builder(
                            builder: (context) {
                              // Get late info from current shift
                              final isLate =
                                  _currentShift?['checkIn']?['is_late'] == true;
                              final lateMinutes = _currentShift?['checkIn']
                                      ?['late_minutes'] ??
                                  0;

                              return Text(
                                isLate && lateMinutes > 0
                                    ? 'Check-in: $_checkInTime • Telat ${lateMinutes}m'
                                    : 'Check-in: $_checkInTime',
                                style: TextStyle(
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : Colors.white.withOpacity(0.9),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
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

              // OPTION 1: Live Progress Timeline (Active Shift)
              if (_isCheckedIn && _currentShift != null)
                Builder(
                  builder: (context) {
                    // Extract shift times
                    final checkInData = _currentShift!['checkIn'];
                    final startTimeStr = checkInData?['start_time'] ?? '00:00';
                    final endTimeStr = checkInData?['shift_end_time'] ??
                        checkInData?['end_time'] ??
                        '00:00';

                    // Parse times
                    final now = DateTime.now();
                    final startParts = startTimeStr.split(':');
                    final endParts = endTimeStr.split(':');

                    final shiftStart = DateTime(now.year, now.month, now.day,
                        int.parse(startParts[0]), int.parse(startParts[1]));
                    var shiftEnd = DateTime(now.year, now.month, now.day,
                        int.parse(endParts[0]), int.parse(endParts[1]));

                    // Handle cross-midnight shifts
                    if (shiftEnd.isBefore(shiftStart)) {
                      shiftEnd = shiftEnd.add(const Duration(days: 1));
                    }

                    // Calculate progress
                    final totalDuration = shiftEnd.difference(shiftStart);
                    final elapsed = now.difference(shiftStart);
                    final remaining = shiftEnd.difference(now);

                    // Progress percentage (0-100)
                    double progress =
                        (elapsed.inMinutes / totalDuration.inMinutes)
                            .clamp(0.0, 1.0);
                    int progressPercent = (progress * 100).round();

                    // Remaining time
                    final remainingHours = remaining.inHours;
                    final remainingMinutes = remaining.inMinutes % 60;
                    final remainingText = remainingHours > 0
                        ? '${remainingHours}j ${remainingMinutes}m'
                        : '${remainingMinutes}m';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Progress Bar
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Progress Shift',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : Colors.white.withOpacity(0.85),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '$progressPercent%',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.darkTextPrimary
                                        : Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.1)
                                      : Colors.white.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.green.shade400,
                                          Colors.green.shade600,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.green.withOpacity(0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Timeline
                        Row(
                          children: [
                            Text(
                              startTimeStr,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : Colors.white.withOpacity(0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Timeline line
                                  Container(
                                    height: 2,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.green.withOpacity(0.8),
                                          isDark
                                              ? Colors.white.withOpacity(0.2)
                                              : Colors.white.withOpacity(0.4),
                                        ],
                                        stops: [progress, progress],
                                      ),
                                    ),
                                  ),
                                  // NOW marker
                                  FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.green
                                                    .withOpacity(0.5),
                                                blurRadius: 8,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                          child: Text(
                                            'NOW',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward,
                              size: 12,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : Colors.white.withOpacity(0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              endTimeStr,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : Colors.white.withOpacity(0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Metrics Grid
                        Row(
                          children: [
                            // Durasi Live
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.white.withOpacity(0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.timer_outlined,
                                          color: isDark
                                              ? Colors.green.shade300
                                              : Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.green
                                                    .withOpacity(0.6),
                                                blurRadius: 4,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _currentDuration,
                                      style: TextStyle(
                                        color: isDark
                                            ? AppColors.darkTextPrimary
                                            : Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'DURASI',
                                      style: TextStyle(
                                        color: isDark
                                            ? AppColors.darkTextSecondary
                                            : Colors.white.withOpacity(0.8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Text(
                                      '(live)',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.green.shade300
                                            : Colors.white.withOpacity(0.7),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Sisa Waktu
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.white.withOpacity(0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.alarm,
                                      color: isDark
                                          ? Colors.blue.shade300
                                          : Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      remainingText,
                                      style: TextStyle(
                                        color: isDark
                                            ? AppColors.darkTextPrimary
                                            : Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'SISA WAKTU',
                                      style: TextStyle(
                                        color: isDark
                                            ? AppColors.darkTextSecondary
                                            : Colors.white.withOpacity(0.8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Text(
                                      'selesai $endTimeStr',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.blue.shade300
                                            : Colors.white.withOpacity(0.7),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),

              // Compact Single Card: Last Completed Shift (Option 2)
              if (_lastCompletedShift24h != null &&
                  !_isCheckedIn &&
                  _completedShifts.isEmpty)
                // Last Completed Shift Section
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              Colors.green.shade800.withOpacity(0.25),
                              Colors.green.shade900.withOpacity(0.15),
                            ]
                          : [
                              Colors.green.shade600.withOpacity(0.2),
                              Colors.green.shade700.withOpacity(0.1),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.green.shade700.withOpacity(0.3)
                          : Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: isDark
                                ? Colors.green.shade300
                                : Colors.white.withOpacity(0.9),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Shift Terakhir Selesai',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : Colors.white.withOpacity(0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _lastCompletedShift24h!['shift_name'] ??
                                      'Shift',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.green.shade200
                                        : Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${DateFormat('HH:mm, dd MMM').format(DateTime.parse(_lastCompletedShift24h!['checkIn']['created_at']).toLocal())} → ${DateFormat('HH:mm, dd MMM').format(DateTime.parse(_lastCompletedShift24h!['checkOut']['created_at']).toLocal())}',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : Colors.white.withOpacity(0.75),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.green.shade700.withOpacity(0.4)
                                  : Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  color: isDark
                                      ? Colors.green.shade200
                                      : Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_lastCompletedShift24h!['hours']}j ${_lastCompletedShift24h!['minutes']}m',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.green.shade100
                                        : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
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

              // Shift assignment info (only show when NOT checked in)
              if (_hasAssignments &&
                  _todayAssignments.isNotEmpty &&
                  !_isCheckedIn)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue.shade900.withOpacity(0.3)
                        : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.blue.shade700.withOpacity(0.5)
                          : Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: isDark ? Colors.blue.shade300 : Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Shift Terjadwal',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._todayAssignments.map((assignment) {
                        // Backend returns flat structure with shift_name, start_time, end_time
                        final shiftName = assignment['shift_name'];
                        final startTime = assignment['start_time'];
                        final endTime = assignment['end_time'];

                        if (shiftName == null) return const SizedBox.shrink();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$shiftName ($startTime - $endTime)',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : Colors.white.withOpacity(0.95),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),

              // Late/Early/Overtime badges (hide Late badge for active shift, already in header)
              if (_shifts.isNotEmpty &&
                  _shifts.any((s) =>
                      (_isCheckedIn ? false : s['isLate'] == true) ||
                      s['isEarlyLeave'] == true ||
                      s['isOvertime'] == true))
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._shifts.map((shift) {
                        List<Widget> badges = [];

                        // Late badge with enhanced formatting (skip if active shift)
                        if (shift['isLate'] == true && !_isCheckedIn) {
                          final lateMinutes = shift['lateMinutes'] ?? 0;

                          // Determine severity and format
                          String lateText;
                          Color badgeColor;
                          IconData icon;

                          if (lateMinutes < 15) {
                            // Small late: minutes only
                            lateText = 'TELAT ${lateMinutes}m';
                            badgeColor = Colors.orange.shade600;
                            icon = Icons.watch_later;
                          } else if (lateMinutes < 60) {
                            // Medium late: minutes only
                            lateText = 'TELAT ${lateMinutes}m';
                            badgeColor = Colors.deepOrange.shade700;
                            icon = Icons.warning_amber_rounded;
                          } else {
                            // Large late: hours + minutes format
                            final hours = lateMinutes ~/ 60;
                            final minutes = lateMinutes % 60;
                            lateText = 'TELAT ${hours}j ${minutes}m';
                            badgeColor = Colors.red.shade800;
                            icon = Icons.error_outline;
                          }

                          badges.add(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    badgeColor,
                                    badgeColor.withOpacity(0.85),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? badgeColor.withOpacity(0.6)
                                      : badgeColor,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: badgeColor.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, color: Colors.white, size: 15),
                                  const SizedBox(width: 6),
                                  Text(
                                    lateText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // Early leave badge
                        if (shift['isEarlyLeave'] == true) {
                          badges.add(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.orange.shade900.withOpacity(0.4)
                                    : Colors.orange.shade700.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.orange.shade700
                                      : Colors.orange.shade900,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.exit_to_app,
                                      color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'PULANG CEPAT',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // Overtime badge
                        if (shift['isOvertime'] == true) {
                          badges.add(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.green.shade900.withOpacity(0.4)
                                    : Colors.green.shade700.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.green.shade700
                                      : Colors.green.shade900,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.trending_up,
                                      color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'LEMBUR ${shift['overtimeMinutes']}m',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: badges,
                        );
                      }).expand((badges) sync* {
                        yield* [badges];
                      }).toList(),
                    ],
                  ),
                ),

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
                      // Only show divider if Total will be shown
                      if (_totalTime != '0j 0m')
                        Container(
                          width: 2,
                          height: 50,
                          color: isDark
                              ? AppColors.dividerDark
                              : Colors.white.withOpacity(0.4),
                        ),
                    ],
                    // Only show "Total Hari Ini" if not 0j 0m
                    if (_totalTime != '0j 0m')
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
        // Fetch fresh data to check current status
        final data = await widget.authService.getTodayAttendance();
        final isCheckedIn = data?['isCheckedIn'] == true;
        final currentShift = data?['currentShift'];
        final completedShifts = data?['completedShifts'] as List?;

        print('[HOME] Button tap - isCheckedIn: $isCheckedIn');
        print(
            '[HOME] Button tap - completedShifts: ${completedShifts?.length ?? 0}');

        // Case 1: Already checked in (wants to checkout)
        if (isCheckedIn) {
          // Check if current shift has ended
          bool shiftEnded = true;
          String? shiftEndTime;

          if (currentShift != null && currentShift['checkIn'] != null) {
            final checkInData = currentShift['checkIn'];
            shiftEndTime = checkInData['shift_end_time'];

            if (shiftEndTime != null) {
              try {
                final now = DateTime.now();
                final endTimeParts = shiftEndTime.split(':');
                final endDateTime = DateTime(
                  now.year,
                  now.month,
                  now.day,
                  int.parse(endTimeParts[0]),
                  int.parse(endTimeParts[1]),
                );
                shiftEnded = now.isAfter(endDateTime);
                print(
                    '[HOME] Current shift end: $shiftEndTime, ended: $shiftEnded');
              } catch (e) {
                print('[HOME] Error parsing shift end time: $e');
              }
            }
          }

          // Show warning if trying to checkout before shift ends
          if (!shiftEnded) {
            final proceed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.orange, size: 32),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Shift Belum Berakhir',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'Shift Anda akan berakhir pada pukul ${shiftEndTime ?? "-"}.\n\nApakah Anda yakin ingin check-out sekarang?',
                  style: const TextStyle(fontSize: 16),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Batal',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Ya, Lanjutkan'),
                  ),
                ],
              ),
            );

            if (proceed != true) {
              print('[HOME] User cancelled early checkout');
              return;
            }

            print('[HOME] User confirmed early checkout');
          } else {
            // Normal checkout confirmation
            final confirmed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.logout, color: Colors.blue, size: 32),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Konfirmasi Check-Out',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                content: const Text(
                  'Anda sudah check-in hari ini.\n\nApakah Anda ingin melakukan check-out sekarang?',
                  style: TextStyle(fontSize: 16),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Batal',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Ya, Check-Out'),
                  ),
                ],
              ),
            );

            if (confirmed != true) {
              print('[HOME] User cancelled checkout');
              return;
            }

            print('[HOME] User confirmed checkout');
          }
        } else {
          // Case 2: Not checked in (wants to check-in)
          // Check if user already completed a shift today and shift hasn't ended
          print('[HOME] Checking completed shifts...');
          print('[HOME] completedShifts: ${completedShifts?.length ?? 0}');

          if (completedShifts != null && completedShifts.isNotEmpty) {
            print('[HOME] completedShifts data: ${completedShifts}');
            final lastCompletedShift = completedShifts.last;
            print('[HOME] Last completed shift: ${lastCompletedShift}');

            final checkInData = lastCompletedShift['checkIn'];
            final checkOutData = lastCompletedShift['checkOut'];
            print('[HOME] checkInData: ${checkInData}');
            print('[HOME] checkOutData: ${checkOutData}');

            // Try to get shift_end_time from checkIn first, fallback to checkOut
            String? lastShiftEndTime = checkInData?['shift_end_time'] ??
                checkInData?['end_time'] ??
                checkOutData?['shift_end_time'] ??
                checkOutData?['end_time'];

            print('[HOME] lastShiftEndTime: $lastShiftEndTime');

            if (lastShiftEndTime != null) {
              try {
                final now = DateTime.now();
                print('[HOME] Current time: ${now.toString()}');

                final endTimeParts = lastShiftEndTime.split(':');
                final endDateTime = DateTime(
                  now.year,
                  now.month,
                  now.day,
                  int.parse(endTimeParts[0]),
                  int.parse(endTimeParts[1]),
                );
                print('[HOME] Shift end DateTime: ${endDateTime.toString()}');

                final lastShiftEnded = now.isAfter(endDateTime);
                print(
                    '[HOME] Last shift end: $lastShiftEndTime, ended: $lastShiftEnded, now: ${now.hour}:${now.minute}');

                // Show warning if last shift hasn't ended yet
                if (!lastShiftEnded) {
                  print('[HOME] ⚠️ Shift not ended - showing warning dialog');
                  final proceed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: Row(
                        children: [
                          const Icon(Icons.schedule,
                              color: Colors.orange, size: 32),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Shift Sebelumnya Belum Berakhir',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      content: Text(
                        'Shift sebelumnya akan berakhir pada pukul ${lastShiftEndTime}.\n\nApakah Anda yakin ingin check-in untuk shift backup sekarang?',
                        style: const TextStyle(fontSize: 16),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal',
                              style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Ya, Lanjutkan'),
                        ),
                      ],
                    ),
                  );

                  if (proceed != true) {
                    print(
                        '[HOME] User cancelled early check-in for backup shift');
                    return;
                  }

                  print(
                      '[HOME] User confirmed early check-in for backup shift');
                }
              } catch (e) {
                print('[HOME] Error parsing last shift end time: $e');
              }
            }
          }
        }

        // Proceed to quick attendance screen
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
      if (isAdmin)
        _ActionData('Shifts', Icons.schedule, Colors.orange, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShiftManagementScreen(
                authService: widget.authService,
              ),
            ),
          );
        }),
      if (isAdmin)
        _ActionData('Roster', Icons.calendar_month, Colors.deepPurple, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RosterManagementScreen(
                authService: widget.authService,
              ),
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
          // Fetch fresh data to check current status
          final data = await widget.authService.getTodayAttendance();
          final isCheckedIn = data?['isCheckedIn'] == true;
          final currentShift = data?['currentShift'];
          final completedShifts = data?['completedShifts'] as List?;

          print('[HOME] FAB tap - isCheckedIn: $isCheckedIn');
          print(
              '[HOME] FAB tap - completedShifts: ${completedShifts?.length ?? 0}');

          // Case 1: Already checked in (wants to checkout)
          if (isCheckedIn) {
            // Check if shift has ended
            bool shiftEnded = true;
            String? shiftEndTime;

            if (currentShift != null && currentShift['checkIn'] != null) {
              final checkInData = currentShift['checkIn'];
              shiftEndTime = checkInData['shift_end_time'];

              if (shiftEndTime != null) {
                try {
                  final now = DateTime.now();
                  final endTimeParts = shiftEndTime.split(':');
                  final endDateTime = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    int.parse(endTimeParts[0]),
                    int.parse(endTimeParts[1]),
                  );
                  shiftEnded = now.isAfter(endDateTime);
                  print(
                      '[HOME] FAB - Shift end check: $shiftEndTime, ended: $shiftEnded');
                } catch (e) {
                  print('[HOME] FAB - Error parsing shift end time: $e');
                }
              }
            }

            // If shift not ended, show warning
            if (!shiftEnded) {
              final proceed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      const Icon(Icons.schedule,
                          color: Colors.orange, size: 32),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Shift Belum Berakhir',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    'Shift Anda akan berakhir pada pukul ${shiftEndTime ?? "-"}.\n\nApakah Anda yakin ingin check-out sekarang?',
                    style: const TextStyle(fontSize: 16),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Ya, Lanjutkan'),
                    ),
                  ],
                ),
              );

              if (proceed != true) {
                print('[HOME] FAB - User cancelled early checkout');
                return;
              }

              print('[HOME] FAB - User confirmed early checkout');
            } else {
              // Shift already ended, show normal confirmation
              final confirmed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      const Icon(Icons.logout, color: Colors.blue, size: 32),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Konfirmasi Check-Out',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: const Text(
                    'Anda sudah check-in hari ini.\n\nApakah Anda ingin melakukan check-out sekarang?',
                    style: TextStyle(fontSize: 16),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Ya, Check-Out'),
                    ),
                  ],
                ),
              );

              if (confirmed != true) {
                print('[HOME] FAB - User cancelled checkout');
                return;
              }

              print('[HOME] FAB - User confirmed checkout');
            }
          } else {
            // Case 2: Not checked in (wants to check-in)
            // Check if user already completed a shift today and shift hasn't ended
            print('[HOME] FAB - Checking completed shifts...');
            print(
                '[HOME] FAB - completedShifts: ${completedShifts?.length ?? 0}');

            if (completedShifts != null && completedShifts.isNotEmpty) {
              print('[HOME] FAB - completedShifts data: ${completedShifts}');
              final lastCompletedShift = completedShifts.last;
              print('[HOME] FAB - Last completed shift: ${lastCompletedShift}');

              final checkInData = lastCompletedShift['checkIn'];
              final checkOutData = lastCompletedShift['checkOut'];
              print('[HOME] FAB - checkInData: ${checkInData}');
              print('[HOME] FAB - checkOutData: ${checkOutData}');

              // Try to get shift_end_time from checkIn first, fallback to checkOut
              String? lastShiftEndTime = checkInData?['shift_end_time'] ??
                  checkInData?['end_time'] ??
                  checkOutData?['shift_end_time'] ??
                  checkOutData?['end_time'];

              print('[HOME] FAB - lastShiftEndTime: $lastShiftEndTime');

              if (lastShiftEndTime != null) {
                try {
                  final now = DateTime.now();
                  print('[HOME] FAB - Current time: ${now.toString()}');

                  final endTimeParts = lastShiftEndTime.split(':');
                  final endDateTime = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    int.parse(endTimeParts[0]),
                    int.parse(endTimeParts[1]),
                  );
                  print(
                      '[HOME] FAB - Shift end DateTime: ${endDateTime.toString()}');

                  final lastShiftEnded = now.isAfter(endDateTime);
                  print(
                      '[HOME] FAB - Last shift end: $lastShiftEndTime, ended: $lastShiftEnded, now: ${now.hour}:${now.minute}');

                  // Show warning if last shift hasn't ended yet
                  if (!lastShiftEnded) {
                    print(
                        '[HOME] FAB - ⚠️ Shift not ended - showing warning dialog');
                    final proceed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: Row(
                          children: [
                            const Icon(Icons.schedule,
                                color: Colors.orange, size: 32),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Shift Sebelumnya Belum Berakhir',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        content: Text(
                          'Shift sebelumnya akan berakhir pada pukul ${lastShiftEndTime}.\n\nApakah Anda yakin ingin check-in untuk shift backup sekarang?',
                          style: const TextStyle(fontSize: 16),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Batal',
                                style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Ya, Lanjutkan'),
                          ),
                        ],
                      ),
                    );

                    if (proceed != true) {
                      print(
                          '[HOME] FAB - User cancelled early check-in for backup shift');
                      return;
                    }

                    print(
                        '[HOME] FAB - User confirmed early check-in for backup shift');
                  }
                } catch (e) {
                  print('[HOME] FAB - Error parsing last shift end time: $e');
                }
              }
            }
          }

          // Proceed to quick attendance screen
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

    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 4.0,
      color: isDark ? AppColors.darkSurface : Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: isDark ? Colors.black : Colors.grey.shade400,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildBottomBarItem(
              icon: Icons.home_rounded,
              label: 'Home',
              index: 0,
            ),
            _buildBottomBarItem(
              icon: Icons.calendar_today,
              label: 'Jadwal',
              index: 1,
            ),
            const SizedBox(width: 56),
            _buildBottomBarItem(
              icon: Icons.assessment,
              label: 'Laporan',
              index: 3,
            ),
            _buildBottomBarItem(
              icon: Icons.person,
              label: 'Profil',
              index: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBarItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isSelected = _selectedIndex == index;

    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? primaryColor
                  : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                height: 1.0,
                color: isSelected
                    ? primaryColor
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
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

  Widget _buildLastShiftInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Icon(
            icon,
            color: isDark ? Colors.green.shade300 : Colors.white,
            size: 18,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : Colors.white.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
