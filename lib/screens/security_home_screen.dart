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
    }

    _loadTodayTimeline();
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
      extendBody:
          true, // Body extends behind BottomAppBar - notch jadi transparan!
      extendBodyBehindAppBar: true,
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (pos is Map && pos['name'] != null)
                            ? pos['name']
                            : 'Pos Security',
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
                        _selectedPersonil != null
                            ? _selectedPersonil!['name']
                            : 'Pilih Personil',
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
                            content: Text('Notifikasi - Segera Hadir')),
                      );
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
    // Dynamic color based on status
    Color cardColor;
    Color statusIconColor;
    IconData statusIcon;

    if (_hasActiveSession) {
      // Active session - Green
      cardColor = isDark ? Colors.green.shade900 : Colors.green.shade600;
      statusIconColor = Colors.green;
      statusIcon = Icons.radio_button_checked;
    } else {
      // Not started - Grey
      cardColor = isDark ? AppColors.darkCard : Colors.grey.shade600;
      statusIconColor = Colors.grey;
      statusIcon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : Colors.white.withOpacity(0.3),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Fitur Patrol - Segera Hadir')),
                    );
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pilih personil terlebih dahulu'),
                  backgroundColor: Colors.orange,
                ),
              );
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
        _updateStatusFromSession();
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
        setState(() {
          _checkInTime = DateFormat('HH:mm').format(DateTime.now());
          _statusText = 'Shift Aktif';
        });

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
        setState(() {
          _checkOutTime = DateFormat('HH:mm').format(DateTime.now());
        });

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
