import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../config/theme.dart';
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primary.withOpacity(0.8),
              Colors.white,
            ],
            stops: const [0.0, 0.25, 0.4],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Colors.white, Colors.white.withOpacity(0.5)],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white,
                        child: Text(
                          user?.name[0].toUpperCase() ?? 'U',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.name ?? 'User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            DateFormat('HH:mm').format(now),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton(IconData icon, VoidCallback onTap,
      {String? badge}) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 22),
            onPressed: onTap,
          ),
        ),
        if (badge != null)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: Text(
                badge,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTodayStatusCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withOpacity(0.95),
              AppColors.primary.withOpacity(0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
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
                    const Text(
                      'Status Hari Ini',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isCheckedIn ? 'Sudah Check-in' : 'Belum Check-in',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isCheckedIn ? Icons.check_circle : Icons.schedule,
                    color: Colors.white,
                    size: 34,
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
                  width: 1,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.1),
                        Colors.white.withOpacity(0.5),
                        Colors.white.withOpacity(0.1),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _buildStatusInfo(
                    'Check-out',
                    '--:--',
                    Icons.logout,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.1),
                        Colors.white.withOpacity(0.5),
                        Colors.white.withOpacity(0.1),
                      ],
                    ),
                  ),
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
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black26,
                blurRadius: 4,
              ),
            ],
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 9,
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

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aksi Cepat',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
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
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: (MediaQuery.of(context).size.width - 64) / 3,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: action.color.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: action.color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, color: action.color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTimeline() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Aktivitas Terkini',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('Lihat Semua'),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
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
                    colors: [color.withOpacity(0.3), Colors.transparent],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
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
    return Container(
      height: 65,
      width: 65,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
        child: const Icon(Icons.face, size: 32),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
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
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: 'Jadwal'),
          BottomNavigationBarItem(icon: Icon(Icons.face), label: ''),
          BottomNavigationBarItem(
              icon: Icon(Icons.assessment), label: 'Laporan'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile - Coming Soon')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings - Coming Soon')),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
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
