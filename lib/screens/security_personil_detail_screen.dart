import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../services/security_app_service.dart';

/// Security Personil Detail Screen
/// Shows personil information and patrol history
class SecurityPersonilDetailScreen extends StatefulWidget {
  final Map<String, dynamic> personil;
  final SecurityAppService securityService;

  const SecurityPersonilDetailScreen({
    Key? key,
    required this.personil,
    required this.securityService,
  }) : super(key: key);

  @override
  State<SecurityPersonilDetailScreen> createState() =>
      _SecurityPersonilDetailScreenState();
}

class _SecurityPersonilDetailScreenState
    extends State<SecurityPersonilDetailScreen> {
  List<Map<String, dynamic>> _patrolHistory = [];
  bool _isLoading = true;

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
          },
          {
            'id': 3,
            'date': DateTime.now().subtract(const Duration(days: 2)),
            'shift': '3322013 - Pagi',
            'check_in': '06:00',
            'check_out': '14:00',
            'duration': '8j 0m',
            'patrols': 6,
            'pos_location': 'Pos Utama',
            'status': 'completed',
          },
        ];
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

  Widget _buildPatrolHistorySection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(
                Icons.history,
                color:
                    isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                size: 24,
              ),
              const SizedBox(width: 8),
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
              const Spacer(),
              if (_patrolHistory.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkPrimary.withOpacity(0.2)
                        : AppColors.lightPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_patrolHistory.length} hari',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkPrimary
                          : AppColors.lightPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
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
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada riwayat patroli',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _patrolHistory.length,
            itemBuilder: (context, index) =>
                _buildPatrolHistoryItem(_patrolHistory[index], isDark),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPatrolHistoryItem(Map<String, dynamic> patrol, bool isDark) {
    final date = patrol['date'] as DateTime;
    final isToday = DateFormat('yyyy-MM-dd').format(date) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
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
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          Divider(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            height: 1,
          ),
          const SizedBox(height: 12),

          // Details grid
          Row(
            children: [
              Expanded(
                child: _buildDetailItem(
                  icon: Icons.login,
                  label: 'Check-in',
                  value: patrol['check_in'],
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _buildDetailItem(
                  icon: Icons.logout,
                  label: 'Check-out',
                  value: patrol['check_out'],
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDetailItem(
                  icon: Icons.timer,
                  label: 'Durasi',
                  value: patrol['duration'],
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _buildDetailItem(
                  icon: Icons.location_on,
                  label: 'Patroli',
                  value: '${patrol['patrols']} lokasi',
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailItem(
            icon: Icons.place,
            label: 'Pos',
            value: patrol['pos_location'],
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color:
                    isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
