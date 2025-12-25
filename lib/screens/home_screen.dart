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
import 'face_login_screen.dart';

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
          await Future.delayed(const Duration(seconds: 1));
          setState(() {});
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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : primaryColor,
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
                  : primaryColor.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status Hari Ini',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : Colors.white.withOpacity(0.9),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isCheckedIn ? 'Sudah Check-in' : 'Belum Check-in',
                      style: TextStyle(
                        color:
                            isDark ? AppColors.darkTextPrimary : Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkPrimary.withOpacity(0.3)
                        : Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isCheckedIn ? Icons.check_circle : Icons.schedule,
                    color: isDark ? AppColors.darkPrimary : Colors.white,
                    size: 36,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatusInfo(
                    'Check-in',
                    _isCheckedIn ? '08:00' : '--:--',
                    Icons.login,
                  ),
                ),
                Container(
                  width: 2,
                  height: 50,
                  color: isDark
                      ? AppColors.dividerDark
                      : Colors.white.withOpacity(0.4),
                ),
                Expanded(
                  child: _buildStatusInfo(
                    'Check-out',
                    '--:--',
                    Icons.logout,
                  ),
                ),
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
                    '0j 0m',
                    Icons.timer,
                  ),
                ),
              ],
            ),
          ],
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
      _ActionData('Check In', Icons.login, AppColors.success, () {
        setState(() => _isCheckedIn = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Check-in berhasil!')),
        );
      }),
      _ActionData('Check Out', Icons.logout, AppColors.error, () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-out - Coming Soon')),
        );
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
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FaceLoginScreen()),
          );
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile - Coming Soon')),
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
