import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../services/security_app_service.dart';
import 'patrol_start_screen.dart';

/// Security Personil Detail Screen
/// Shows personil information and patrol history with modern UI/UX
class SecurityPersonilDetailScreen extends StatefulWidget {
  final Map<String, dynamic> personil;
  final SecurityAppService securityService;

  const SecurityPersonilDetailScreen({
    super.key,
    required this.personil,
    required this.securityService,
  });

  @override
  State<SecurityPersonilDetailScreen> createState() =>
      _SecurityPersonilDetailScreenState();
}

class _SecurityPersonilDetailScreenState
    extends State<SecurityPersonilDetailScreen> {
  List<Map<String, dynamic>> _patrolHistory = [];
  bool _isLoading = true;

  // Statistik kerja
  int _totalWorkingHoursToday = 0;
  int _totalWorkingMinutesToday = 0;
  int _totalWorkingHoursMonth = 0;
  int _totalLateMinutes = 0;
  int _totalEarlyMinutes = 0;

  @override
  void initState() {
    super.initState();
    _loadPatrolHistory();
  }

  Future<void> _loadPatrolHistory() async {
    setState(() => _isLoading = true);

    try {
      // TODO: Load actual patrol history from backend
      // final history = await widget.securityService.getPatrolHistory(
      //   userId: widget.personil['user_id'],
      // );

      // Mock data for now
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _patrolHistory = [
          {
            'id': 1,
            'date': DateTime.now().subtract(const Duration(days: 0)),
            'shift': '3322013 - Pagi',
            'check_in': '06:00',
            'check_out': '14:00',
            'duration': '8j 0m',
            'patrols': 5,
            'pos_location': 'Pos Utama',
            'status': 'completed',
            'late_minutes': 0,
            'early_minutes': 0,
          },
          {
            'id': 2,
            'date': DateTime.now().subtract(const Duration(days: 1)),
            'shift': '3322013 - Pagi',
            'check_in': '06:15',
            'check_out': '14:10',
            'duration': '7j 55m',
            'patrols': 4,
            'pos_location': 'Pos Utama',
            'status': 'completed',
            'late_minutes': 15,
            'early_minutes': 0,
          },
          {
            'id': 3,
            'date': DateTime.now().subtract(const Duration(days: 2)),
            'shift': '3322013 - Pagi',
            'check_in': '05:50',
            'check_out': '14:00',
            'duration': '8j 10m',
            'patrols': 6,
            'pos_location': 'Pos Utama',
            'status': 'completed',
            'late_minutes': 0,
            'early_minutes': 10,
          },
        ];
        _calculateStatistics();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat riwayat: $e')),
        );
      }
    }
  }

  void _calculateStatistics() {
    // Hitung statistik dari data patroli
    int totalHoursMonth = 0;
    int totalLate = 0;
    int totalEarly = 0;

    for (var patrol in _patrolHistory) {
      // Parse duration
      final duration = patrol['duration'] as String;
      final parts = duration.split(' ');
      if (parts.length >= 2) {
        final hours = int.tryParse(parts[0].replaceAll('j', '')) ?? 0;
        final minutes = int.tryParse(parts[1].replaceAll('m', '')) ?? 0;
        totalHoursMonth += hours;

        // Untuk hari ini
        if (patrol['date'] is DateTime) {
          final date = patrol['date'] as DateTime;
          final today = DateTime.now();
          if (date.year == today.year &&
              date.month == today.month &&
              date.day == today.day) {
            _totalWorkingHoursToday = hours;
            _totalWorkingMinutesToday = minutes;
          }
        }
      }

      // Hitung keterlambatan dan datang cepat
      totalLate += (patrol['late_minutes'] as int?) ?? 0;
      totalEarly += (patrol['early_minutes'] as int?) ?? 0;
    }

    setState(() {
      _totalWorkingHoursMonth = totalHoursMonth;
      _totalLateMinutes = totalLate;
      _totalEarlyMinutes = totalEarly;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Detail Personil',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPatrolHistory,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPersonilInfo(isDark),
              const SizedBox(height: 8),
              _buildStatisticsSection(isDark),
              const SizedBox(height: 8),
              _buildPatrolButton(isDark),
              const SizedBox(height: 16),
              _buildPatrolHistorySection(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonilInfo(bool isDark) {
    final checkInTime = widget.personil['check_in_time'];
    final posLocation = widget.personil['pos_location'];
    final isActive = widget.personil['is_active'] ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightPrimary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 48,
              backgroundColor:
                  isDark ? AppColors.darkPrimary : AppColors.lightPrimaryLight,
              child: Text(
                widget.personil['name'].toString()[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Text(
            widget.personil['name'],
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Pattern
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              (widget.personil['pattern'] is Map &&
                      widget.personil['pattern']['name'] != null)
                  ? widget.personil['pattern']['name']
                  : 'Pattern Not Set',
              style: TextStyle(
                color: isDark ? AppColors.darkTextPrimary : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.green.withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? Colors.green : Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isActive
                          ? Colors.green
                          : Colors.white.withOpacity(0.7),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isActive ? 'SEDANG BERTUGAS' : 'BELUM CHECK-IN',
                      style: TextStyle(
                        color: isActive
                            ? Colors.green
                            : Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                if (isActive && checkInTime != null) ...[
                  const SizedBox(height: 12),
                  Divider(color: Colors.white.withOpacity(0.3), height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Icon(
                            Icons.access_time,
                            color: Colors.white.withOpacity(0.9),
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Check-in',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            checkInTime,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (posLocation != null)
                        Column(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: Colors.green.shade300,
                              size: 20,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Lokasi',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              posLocation,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Statistik Kerja',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grid statistik
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.today,
                  label: 'Hari Ini',
                  value: _totalWorkingHoursToday > 0
                      ? '${_totalWorkingHoursToday}j ${_totalWorkingMinutesToday}m'
                      : 'Belum Ada',
                  color: Colors.blue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.calendar_month,
                  label: 'Bulan Ini',
                  value: _totalWorkingHoursMonth > 0
                      ? '${_totalWorkingHoursMonth}j'
                      : 'Belum Ada',
                  color: Colors.purple,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.access_time_filled,
                  label: 'Terlambat',
                  value: _totalLateMinutes > 0
                      ? '$_totalLateMinutes menit'
                      : 'Tidak Ada',
                  color: _totalLateMinutes > 0 ? Colors.red : Colors.green,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.speed,
                  label: 'Datang Cepat',
                  value: _totalEarlyMinutes > 0
                      ? '$_totalEarlyMinutes menit'
                      : 'Tidak Ada',
                  color: _totalEarlyMinutes > 0 ? Colors.green : Colors.grey,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatrolButton(bool isDark) {
    final isActive = widget.personil['is_active'] ?? false;
    final canPatrol =
        isActive; // Hanya security yang sedang aktif yang bisa patroli

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canPatrol ? _handleStartPatrol : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: canPatrol
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.green.shade600,
                        Colors.green.shade700,
                      ],
                    )
                  : null,
              color: canPatrol ? null : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(16),
              boxShadow: canPatrol
                  ? [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  canPatrol ? Icons.directions_walk : Icons.lock,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      canPatrol ? 'Mulai Patroli' : 'Patroli Tidak Tersedia',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!canPatrol)
                      const Text(
                        'Harus sedang bertugas',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleStartPatrol() {
    // Navigate to patrol start screen with personil user_id
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatrolStartScreen(
          postSessionId: widget.personil['post_session_id'],
          userId: widget
              .personil['user_id'], // Pass user_id dari personil yang dipilih
        ),
      ),
    );
  }

  Widget _buildPatrolHistorySection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkPrimary.withOpacity(0.2)
                      : AppColors.lightPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.history,
                  color:
                      isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Riwayat Patroli',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_patrolHistory.isNotEmpty)
                      Text(
                        '${_patrolHistory.length} hari terakhir',
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
              if (_patrolHistory.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkPrimary.withOpacity(0.2)
                        : AppColors.lightPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_patrolHistory.length}',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkPrimary
                          : AppColors.lightPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_patrolHistory.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.history,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum Ada Riwayat',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Riwayat patroli akan muncul di sini',
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
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _patrolHistory.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _buildPatrolHistoryItem(_patrolHistory[index], isDark),
          ),
      ],
    );
  }

  Widget _buildPatrolHistoryItem(Map<String, dynamic> patrol, bool isDark) {
    final date = patrol['date'] as DateTime;
    final isToday = DateFormat('yyyy-MM-dd').format(date) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lateMinutes = (patrol['late_minutes'] as int?) ?? 0;
    final earlyMinutes = (patrol['early_minutes'] as int?) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
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
                ? Colors.black.withOpacity(0.1)
                : Colors.grey.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // TODO: Show detail dialog
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isToday
                              ? Colors.green.withOpacity(0.1)
                              : (isDark
                                  ? AppColors.darkPrimary.withOpacity(0.1)
                                  : AppColors.lightPrimary.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: isToday
                              ? Colors.green
                              : (isDark
                                  ? AppColors.darkPrimary
                                  : AppColors.lightPrimary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isToday
                                  ? 'Hari ini'
                                  : DateFormat('EEEE, d MMM yyyy').format(date),
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              patrol['shift'] ?? '',
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Selesai',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Info Grid
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkBackground.withOpacity(0.5)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoItem(
                                icon: Icons.login,
                                label: 'Check-in',
                                value: patrol['check_in'],
                                isDark: isDark,
                              ),
                            ),
                            Container(
                              height: 30,
                              width: 1,
                              color: isDark
                                  ? AppColors.dividerDark
                                  : AppColors.dividerLight,
                            ),
                            Expanded(
                              child: _buildInfoItem(
                                icon: Icons.logout,
                                label: 'Check-out',
                                value: patrol['check_out'],
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          color: isDark
                              ? AppColors.dividerDark
                              : AppColors.dividerLight,
                          height: 1,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoItem(
                                icon: Icons.timer,
                                label: 'Durasi',
                                value: patrol['duration'],
                                isDark: isDark,
                              ),
                            ),
                            Container(
                              height: 30,
                              width: 1,
                              color: isDark
                                  ? AppColors.dividerDark
                                  : AppColors.dividerLight,
                            ),
                            Expanded(
                              child: _buildInfoItem(
                                icon: Icons.location_on,
                                label: 'Patroli',
                                value: '${patrol['patrols']} lokasi',
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Badges untuk keterlambatan/cepat
                  if (lateMinutes > 0 || earlyMinutes > 0) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (lateMinutes > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time_filled,
                                  size: 14,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Terlambat $lateMinutes menit',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (earlyMinutes > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.speed,
                                  size: 14,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Datang lebih awal $earlyMinutes menit',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],

                  // Pos location
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.place,
                        size: 16,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          patrol['pos_location'],
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color:
                    isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
