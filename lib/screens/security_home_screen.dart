import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui';
import '../services/security_app_service.dart';
import '../utils/app_toast.dart';
import '../services/auth_service.dart';
import '../config/theme.dart';
import 'app_selector_screen.dart';
import 'security_checkin_screen.dart';
import 'security_personil_detail_screen.dart';

/// Security Home Screen V3
/// Modern redesign matching community app UI/UX
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

class _SecurityHomeScreenState extends State<SecurityHomeScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _selectedPersonil;
  bool _hasActiveSession = false;
  List<Map<String, dynamic>> _todayTimeline = [];
  String _statusText = 'Belum Check-in';
  int _selectedIndex = 0;
  String _checkInTime = '--:--';
  String _checkOutTime = '--:--';
  String _currentDuration = '--';
  int _totalCheckIns = 0;
  int _totalPatrols = 0;
  final Map<int, bool> _expandedPersonil = {};

  final SecurityAppService _service = SecurityAppService();
  final ImagePicker _imagePicker = ImagePicker();

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Animations
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

      _updateStatusFromSession();

      // Mark active personil in roster
      _markActivePersonil();
    }

    _loadTodayTimeline();
  }

  void _markActivePersonil() {
    final roster = widget.sessionData['roster'] as List?;
    if (roster != null && _selectedPersonil != null) {
      for (var personil in roster) {
        if (personil['user_id'] == _selectedPersonil!['user_id']) {
          personil['is_active'] = true;
          personil['check_in_time'] = _checkInTime;
          personil['pos_location'] =
              widget.sessionData['pos']?['name'] ?? 'Pos Utama';
        } else {
          personil['is_active'] = false;
        }
      }
    }
  }

  void _updateStatusFromSession() {
    if (!_hasActiveSession) {
      _statusText = 'Belum Check-in';
      _checkInTime = '--:--';
      _checkOutTime = '--:--';
      _currentDuration = '--';
    } else {
      _statusText = 'Shift Aktif';
      // TODO: Load actual check-in time from backend
      _checkInTime = DateFormat('HH:mm').format(DateTime.now());
      _checkOutTime = '--:--';
      _currentDuration = '0j 0m';
    }
  }

  Future<void> _loadTodayTimeline() async {
    // TODO: Load today's check-in/check-out timeline from backend
    setState(() {
      _totalCheckIns = _todayTimeline.length;
      _totalPatrols = 0; // TODO: Load from backend
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Selamat Pagi';
    if (hour < 15) return 'Selamat Siang';
    if (hour < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  @override
  Widget build(BuildContext context) {
    // Initialize toast
    AppToast.init(context);

    final pos = widget.sessionData['pos'] ?? {};
    final roster = widget.sessionData['roster'] ?? [];
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
      floatingActionButtonAnimator:
          null, // Disable FAB animation when SnackBar shows
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadTodayTimeline();
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Modern Header
            SliverToBoxAdapter(
              child: _buildModernHeader(greeting, now, isDark, pos),
            ),

            // Status Card
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: _buildStatusCard(isDark),
                ),
              ),
            ),

            // Roster Personil Bertugas
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _buildPersonilRoster(isDark, roster),
              ),
            ),

            // Quick Stats
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _buildQuickStats(isDark),
              ),
            ),

            // Quick Actions
            SliverToBoxAdapter(
              child: _buildQuickActions(isDark),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: SizedBox(
        height: 58, // Compact height
        child: _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildModernHeader(
      String greeting, DateTime now, bool isDark, Map<String, dynamic> pos) {
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
              Expanded(
                child: Row(
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
                            _selectedPersonil != null
                                ? _selectedPersonil!['name']
                                    .toString()[0]
                                    .toUpperCase()
                                : 'S',
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (pos is Map && pos['name'] != null)
                                ? pos['name']
                                : 'Pos Security',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (pos is Map && pos['address'] != null)
                                ? pos['address']
                                : (pos is Map &&
                                        pos['location_description'] != null)
                                    ? pos['location_description']
                                    : 'Area Perumahan',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _buildHeaderIconButton(
                    Icons.notifications_outlined,
                    () {
                      AppToast.info('Notifikasi - Segera Hadir');
                    },
                    isDark: isDark,
                    badge: '3',
                  ),
                  const SizedBox(width: 4),
                  _buildHeaderIconButton(
                    Icons.settings_outlined,
                    () => _showSettingsMenu(context),
                    isDark: isDark,
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
      {bool isDark = false, String? badge}) {
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

  Widget _buildStatusCard(bool isDark) {
    // Only show if has active session
    if (!_hasActiveSession) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.green.shade900 : Colors.green.shade600,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : Colors.white.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.green.withOpacity(0.3),
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
                      ? Colors.green.withOpacity(0.2)
                      : Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.radio_button_checked,
                  color: isDark ? Colors.green : Colors.white,
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
                        color:
                            isDark ? AppColors.darkTextPrimary : Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (_hasActiveSession)
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
                  ],
                ),
              ),
            ],
          ),

          if (_selectedPersonil != null) ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 20),

            // Shift Info
            Container(
              padding: const EdgeInsets.all(14),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.assignment_ind,
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.white.withOpacity(0.9),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Shift Terjadwal',
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (_selectedPersonil!['pattern'] is Map &&
                                    _selectedPersonil!['pattern']['name'] !=
                                        null)
                                ? _selectedPersonil!['pattern']['name']
                                : '-',
                            style: TextStyle(
                              color:
                                  isDark ? Colors.blue.shade200 : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pattern',
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
                      if (_hasActiveSession)
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
                                _currentDuration,
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
          ],
        ],
      ),
    );
  }

  // OLD FUNCTION - TO BE DELETED
  Widget _buildPersonilRosterOLD(bool isDark, List roster) {
    if (roster.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Fixed Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkPrimary.withOpacity(0.1)
                  : AppColors.lightPrimary.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.people,
                  color:
                      isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Personil Bertugas',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${roster.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Personil List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: roster.length,
            separatorBuilder: (context, index) => Divider(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              height: 1,
              indent: 16,
              endIndent: 16,
            ),
            itemBuilder: (context, index) {
              final personil = roster[index];
              final userId = personil['user_id'] ?? index;
              final isExpanded = _expandedPersonil[userId] ?? false;

              return _buildPersonilCardOLD(
                  personil, isExpanded, isDark, userId);
            },
          ),
        ],
      ),
    );
  }

  // OLD FUNCTION - TO BE DELETED
  Widget _buildPersonilCardOLD(
      Map<String, dynamic> personil, bool isExpanded, bool isDark, int userId) {
    final name = personil['name'] ?? 'Unknown';
    final pattern = personil['pattern'];
    final patternName =
        (pattern is Map && pattern['name'] != null) ? pattern['name'] : '-';
    final checkInTime = personil['check_in_time'];
    final posLocation = personil['pos_location'];
    final isActive = personil['is_active'] ?? false;

    return InkWell(
      onTap: () {
        // Navigate to personil detail
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SecurityPersonilDetailScreen(
              personil: {
                ...personil,
                'is_active': isActive,
                'check_in_time': checkInTime,
                'pos_location': posLocation,
              },
              securityService: _service,
            ),
          ),
        );
      },
      child: Column(
        children: [
          // Main Card (Always Visible)
          InkWell(
            onTap: () {
              setState(() {
                _expandedPersonil[userId] = !isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? Colors.green.withOpacity(0.2)
                          : (isDark
                              ? AppColors.darkPrimary.withOpacity(0.2)
                              : AppColors.lightPrimary.withOpacity(0.1)),
                      border: Border.all(
                        color: isActive
                            ? Colors.green
                            : (isDark
                                ? AppColors.darkPrimary
                                : AppColors.lightPrimary),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        name[0].toUpperCase(),
                        style: TextStyle(
                          color: isActive
                              ? Colors.green
                              : (isDark
                                  ? AppColors.darkPrimary
                                  : AppColors.lightPrimary),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name (Highlighted)
                        Text(
                          name,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Pattern
                        Text(
                          patternName,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Status
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive
                                    ? Colors.green
                                    : Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isActive ? 'Sudah Check-in' : 'Belum Check-in',
                              style: TextStyle(
                                color: isActive
                                    ? Colors.green
                                    : Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (isActive && checkInTime != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• $checkInTime',
                                style: TextStyle(
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Pos Location (if checked in - highlighted)
                        if (isActive && posLocation != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                posLocation,
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Expand Icon
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content (Duration Progress)
          if (isExpanded && isActive)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Divider(
                    color:
                        isDark ? AppColors.dividerDark : AppColors.dividerLight,
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                  _buildDurationProgressOLD(personil, isDark),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // OLD FUNCTION - TO BE DELETED
  Widget _buildDurationProgressOLD(Map<String, dynamic> personil, bool isDark) {
    // Calculate duration (mock for now)
    final checkInTime = personil['check_in_time'] ?? '00:00';
    final now = DateTime.now();

    // Parse check-in time
    final checkInParts = checkInTime.split(':');
    final checkInDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.tryParse(checkInParts[0]) ?? 0,
      int.tryParse(checkInParts[1]) ?? 0,
    );

    final duration = now.difference(checkInDateTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    // Expected shift duration (8 hours)
    const shiftDurationHours = 8;
    final progress = (hours / shiftDurationHours).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.green.shade900.withOpacity(0.2)
            : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.green.shade700.withOpacity(0.3)
              : Colors.green.shade200,
          width: 1,
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
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color:
                        isDark ? Colors.green.shade300 : Colors.green.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Durasi Shift',
                    style: TextStyle(
                      color: isDark
                          ? Colors.green.shade200
                          : Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${hours}j ${minutes}m',
                style: TextStyle(
                  color: isDark ? Colors.green.shade100 : Colors.green.shade900,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? Colors.green.shade400 : Colors.green.shade600,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).toInt()}% dari target 8 jam',
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonilRoster(bool isDark, List roster) {
    if (roster.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkPrimary.withOpacity(0.2)
                      : AppColors.lightPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.people,
                  color:
                      isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Personil Bertugas',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkPrimary.withOpacity(0.2)
                      : AppColors.lightPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '${roster.length} Orang',
                  style: TextStyle(
                    color:
                        isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Horizontal Scrollable Cards
        SizedBox(
          height: 100,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: roster.length,
            itemBuilder: (context, index) {
              final personil = roster[index];
              final isActive = personil['is_active'] ?? false;
              final name = personil['name'] ?? 'Unknown';
              final checkInTime = personil['check_in_time'];

              // Extract shift information
              final shift = personil['shift'];

              // Try to get shift data from multiple sources
              String shiftCode = '';
              String shiftName = '';
              String shiftStartTime = '';
              String shiftEndTime = '';

              if (shift is Map) {
                shiftCode = shift['code']?.toString() ?? '';
                shiftName = shift['name']?.toString() ?? '';
                // Format time: remove seconds (HH:MM:SS -> HH:MM)
                final rawStart = shift['start_time']?.toString() ?? '';
                final rawEnd = shift['end_time']?.toString() ?? '';
                shiftStartTime = rawStart.isNotEmpty && rawStart.length >= 5
                    ? rawStart.substring(0, 5)
                    : rawStart;
                shiftEndTime = rawEnd.isNotEmpty && rawEnd.length >= 5
                    ? rawEnd.substring(0, 5)
                    : rawEnd;
              }

              // Fallback: try to get from assignment if shift is null
              if (shiftCode.isEmpty && personil['assignment'] != null) {
                final assignment = personil['assignment'];
                if (assignment is Map && assignment['shift'] != null) {
                  final assignmentShift = assignment['shift'];
                  if (assignmentShift is Map) {
                    shiftCode = assignmentShift['code']?.toString() ?? '';
                    shiftName = assignmentShift['name']?.toString() ?? '';
                    final rawStart =
                        assignmentShift['start_time']?.toString() ?? '';
                    final rawEnd =
                        assignmentShift['end_time']?.toString() ?? '';
                    shiftStartTime = rawStart.isNotEmpty && rawStart.length >= 5
                        ? rawStart.substring(0, 5)
                        : rawStart;
                    shiftEndTime = rawEnd.isNotEmpty && rawEnd.length >= 5
                        ? rawEnd.substring(0, 5)
                        : rawEnd;
                  }
                }
              }

              // Debug: Print shift data
              print(
                  '🔍 Personil ${personil['name']}: shift=$shift, assignment=${personil['assignment']}, code=$shiftCode, time=$shiftStartTime-$shiftEndTime');

              // Determine shift color based on code
              Color shiftColor;
              Color shiftBgColor;
              if (shiftCode.toLowerCase().contains('pagi') ||
                  (shiftStartTime.isNotEmpty &&
                      shiftStartTime.startsWith('0'))) {
                shiftColor = Colors.orange.shade700;
                shiftBgColor = Colors.orange.shade50;
              } else if (shiftCode.toLowerCase().contains('siang') ||
                  (shiftStartTime.isNotEmpty &&
                      (shiftStartTime.startsWith('1') ||
                          shiftStartTime.startsWith('12') ||
                          shiftStartTime.startsWith('13') ||
                          shiftStartTime.startsWith('14')))) {
                shiftColor = Colors.blue.shade700;
                shiftBgColor = Colors.blue.shade50;
              } else if (shiftCode.toLowerCase().contains('malam') ||
                  (shiftStartTime.isNotEmpty &&
                      (shiftStartTime.startsWith('2') ||
                          shiftStartTime.startsWith('18') ||
                          shiftStartTime.startsWith('19')))) {
                shiftColor = Colors.purple.shade700;
                shiftBgColor = Colors.purple.shade50;
              } else {
                shiftColor = Colors.grey.shade700;
                shiftBgColor = Colors.grey.shade100;
              }

              final posLocation = personil['pos_location'] ??
                  (widget.sessionData['pos']?['name'] ?? 'Pos Security');

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SecurityPersonilDetailScreen(
                        personil: {
                          ...personil,
                          'is_active': isActive,
                          'check_in_time': checkInTime,
                          'pos_location': posLocation,
                        },
                        securityService: _service,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 300,
                  margin: const EdgeInsets.only(right: 12, bottom: 4),
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.green.shade600,
                              Colors.green.shade700,
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    AppColors.darkCard,
                                    AppColors.darkCard,
                                  ]
                                : [
                                    Colors.white,
                                    Colors.grey.shade50,
                                  ],
                          ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isActive
                          ? Colors.green.shade400
                          : (isDark
                              ? AppColors.borderDark
                              : Colors.grey.shade200),
                      width: isActive ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isActive
                            ? Colors.green.withOpacity(0.3)
                            : (isDark
                                ? Colors.black.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.15)),
                        blurRadius: isActive ? 12 : 8,
                        offset: const Offset(0, 4),
                        spreadRadius: isActive ? 1 : 0,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Main Content - Horizontal Layout
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            // Avatar with active ring
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isActive
                                    ? LinearGradient(
                                        colors: [
                                          Colors.greenAccent.shade400,
                                          Colors.green.shade300,
                                        ],
                                      )
                                    : null,
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: Colors.greenAccent
                                              .withOpacity(0.4),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isActive
                                      ? Colors.white
                                      : (isDark
                                          ? AppColors.darkPrimary
                                              .withOpacity(0.2)
                                          : AppColors.lightPrimary
                                              .withOpacity(0.1)),
                                  border: Border.all(
                                    color: isActive
                                        ? Colors.white
                                        : (isDark
                                            ? AppColors.darkPrimary
                                            : AppColors.lightPrimary),
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    name[0].toUpperCase(),
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.green.shade700
                                          : (isDark
                                              ? AppColors.darkPrimary
                                              : AppColors.lightPrimary),
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Info Section
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Name & Shift Badge Row
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            color: isActive
                                                ? Colors.white
                                                : (isDark
                                                    ? AppColors.darkTextPrimary
                                                    : AppColors.textPrimary),
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (shiftName.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? Colors.white.withOpacity(0.3)
                                                : shiftBgColor,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isActive
                                                  ? Colors.white
                                                      .withOpacity(0.5)
                                                  : shiftColor.withOpacity(0.4),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            shiftName,
                                            style: TextStyle(
                                              color: isActive
                                                  ? Colors.white
                                                  : shiftColor,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),

                                  // Shift Time (if available)
                                  if (shiftStartTime.isNotEmpty &&
                                      shiftEndTime.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.schedule_rounded,
                                            size: 12,
                                            color: isActive
                                                ? Colors.white.withOpacity(0.8)
                                                : (isDark
                                                    ? AppColors
                                                        .darkTextSecondary
                                                    : AppColors.textSecondary),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '$shiftStartTime - $shiftEndTime',
                                            style: TextStyle(
                                              color: isActive
                                                  ? Colors.white
                                                      .withOpacity(0.9)
                                                  : (isDark
                                                      ? AppColors
                                                          .darkTextSecondary
                                                      : AppColors
                                                          .textSecondary),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // Location
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_rounded,
                                        size: 12,
                                        color: isActive
                                            ? Colors.white.withOpacity(0.8)
                                            : (isDark
                                                ? AppColors.darkTextSecondary
                                                : AppColors.textSecondary),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          posLocation,
                                          style: TextStyle(
                                            color: isActive
                                                ? Colors.white.withOpacity(0.9)
                                                : (isDark
                                                    ? AppColors
                                                        .darkTextSecondary
                                                    : AppColors.textSecondary),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Status Login Indicator
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? Colors.green.withOpacity(0.2)
                                              : Colors.grey.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isActive
                                                ? Colors.green.withOpacity(0.4)
                                                : Colors.grey.withOpacity(0.3),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                color: isActive
                                                    ? Colors.green
                                                    : Colors.grey,
                                                shape: BoxShape.circle,
                                                boxShadow: isActive
                                                    ? [
                                                        BoxShadow(
                                                          color: Colors.green
                                                              .withOpacity(0.5),
                                                          blurRadius: 4,
                                                          spreadRadius: 1,
                                                        )
                                                      ]
                                                    : null,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isActive ? 'Login' : 'Offline',
                                              style: TextStyle(
                                                color: isActive
                                                    ? Colors.green.shade700
                                                    : Colors.grey.shade600,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Check-in Time (if active)
                                  if (isActive && checkInTime != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 12,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          checkInTime,
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.9),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Active Indicator Badge (Top Right)
                      if (isActive)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.green.shade600,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.withOpacity(0.5),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'AKTIF',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
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
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildQuickStats(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.check_circle_outline,
              value: _totalCheckIns.toString(),
              label: 'Check-in',
              subLabel: 'Hari ini',
              color: Colors.green,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.access_time,
              value: _currentDuration,
              label: 'Durasi',
              subLabel: _hasActiveSession ? 'Shift' : 'Total',
              color: Colors.orange,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.location_on_outlined,
              value: _totalPatrols.toString(),
              label: 'Patroli',
              subLabel: 'Bulan ini',
              color: Colors.blue,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required String subLabel,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subLabel,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aksi Cepat',
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.camera_alt,
                  label: 'Check-in',
                  color: Colors.green,
                  onTap: _handleCheckIn,
                  enabled: _hasActiveSession,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.exit_to_app,
                  label: 'Check-out',
                  color: Colors.orange,
                  onTap: _handleCheckOut,
                  enabled: _hasActiveSession,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.radio_button_checked,
                  label: 'Mulai Patrol',
                  color: Colors.blue,
                  onTap: () {
                    AppToast.info('Fitur Patrol - Segera Hadir');
                  },
                  enabled: _hasActiveSession,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.swap_horiz,
                  label:
                      _hasActiveSession ? 'Ganti Personil' : 'Pilih Personil',
                  color: Colors.purple,
                  onTap: _handleSwitchPersonil,
                  enabled: true,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool enabled,
    required bool isDark,
  }) {
    final isEnabled = enabled;
    final buttonColor = isEnabled ? color : Colors.grey;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isDark
                ? buttonColor.withOpacity(0.2)
                : buttonColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? buttonColor.withOpacity(0.3)
                  : buttonColor.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isEnabled
                    ? (isDark ? buttonColor.withOpacity(0.8) : buttonColor)
                    : Colors.grey.shade400,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled
                      ? (isDark ? buttonColor.withOpacity(0.9) : buttonColor)
                      : Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppColors.darkCard : Colors.white,
        // NO SHADOW - area notch akan transparan
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            if (!_hasActiveSession) {
              AppToast.warning('Pilih personil terlebih dahulu');
              return;
            }
            _handleCheckIn();
          },
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            child: Icon(
              Icons.camera_alt,
              size: 30,
              weight: 600,
              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
            ),
          ),
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
            // Left side - 2 items
            _buildBottomBarItem(
              icon: Icons.home_rounded,
              label: 'Home',
              index: 0,
            ),
            _buildBottomBarItem(
              icon: Icons.calendar_today,
              label: 'Patrol',
              index: 1,
            ),
            // Center space for FAB
            const SizedBox(width: 56),
            // Right side - 2 items
            _buildBottomBarItem(
              icon: Icons.history,
              label: 'Riwayat',
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
            ListTile(
              leading: Icon(
                Icons.person,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
                size: 26,
              ),
              title: Text(
                'Info Personil',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              subtitle: Text(
                _selectedPersonil != null
                    ? _selectedPersonil!['name']
                    : 'Belum dipilih',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.swap_horiz,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
                size: 26,
              ),
              title: Text(
                'Ganti Personil',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleSwitchPersonil();
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
                'Logout dari Pos',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? AppColors.errorDark : AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleLogout();
              },
            ),
          ],
        ),
      ),
    );
  }

  // === ACTION HANDLERS ===

  Future<void> _selectPersonil() async {
    final roster = widget.sessionData['roster'] as List?;

    // Debug logging
    print('=== DEBUG ROSTER ===');
    print('SessionData keys: ${widget.sessionData.keys.toList()}');
    print('Roster data: $roster');
    print('Roster length: ${roster?.length ?? 0}');
    print('===================');

    if (roster == null || roster.isEmpty) {
      AppToast.warning('Belum ada jadwal personil hari ini');
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
                  subtitle: Text(
                      'Pattern: ${(person['pattern'] is Map && person['pattern']['name'] != null) ? person['pattern']['name'] : '-'}'),
                  onTap: () => Navigator.pop(context, person),
                )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedPersonil = selected;
        _checkInTime = DateFormat('HH:mm').format(DateTime.now());
      });
      if (!_hasActiveSession) {
        await _handleStartSession();
      } else {
        // Update active personil in roster
        _markActivePersonil();
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
        _updateStatusFromSession();
        _markActivePersonil();
      });

      AppToast.success('✓ Sesi dimulai');
    } catch (e) {
      AppToast.error('Gagal: $e');
    }
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('GPS tidak aktif');
    }

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
      AppToast.warning('Pilih personil dulu');
      return;
    }

    // Navigate to SecurityCheckinScreen with face recognition
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SecurityCheckinScreen(
          securityService: _service,
          isCheckOut: false,
        ),
      ),
    );

    // Refresh timeline if check-in successful
    if (result == true && mounted) {
      await _loadTodayTimeline();
      setState(() {
        _checkInTime = DateFormat('HH:mm').format(DateTime.now());
        _statusText = 'Shift Aktif';
      });
    }
  }

  Future<void> _handleCheckOut() async {
    if (!_hasActiveSession) return;

    // Navigate to SecurityCheckinScreen with face recognition for checkout
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SecurityCheckinScreen(
          securityService: _service,
          isCheckOut: true,
        ),
      ),
    );

    // Refresh timeline if check-out successful
    if (result == true && mounted) {
      await _loadTodayTimeline();
      setState(() {
        _checkOutTime = DateFormat('HH:mm').format(DateTime.now());
        _statusText = 'Shift Selesai';
      });
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
        _updateStatusFromSession();
      });
    }

    await _selectPersonil();
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Keluar dari pos security?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (_hasActiveSession) {
      await _service.endSession();
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              AppSelectorScreen(authService: widget.authService!),
        ),
      );
    }
  }
}
