import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/shift.dart';
import '../../config/theme.dart';
import '../../models/shift_assignment.dart';
import '../../models/user.dart';
import '../../models/roster_pattern.dart';
import '../../services/shift_service.dart';
import '../../services/shift_assignment_service.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../services/roster_pattern_service.dart';
import '../../services/roster_assignment_service.dart';
import '../../services/pdf_service.dart';
import 'package:open_file/open_file.dart';

class RosterManagementScreen extends StatefulWidget {
  final AuthService authService;

  const RosterManagementScreen({
    Key? key,
    required this.authService,
  }) : super(key: key);

  @override
  State<RosterManagementScreen> createState() => _RosterManagementScreenState();
}

// Helper class untuk user dengan pattern data
class UserWithPattern {
  final User user;
  final RosterPattern? pattern;
  final List<int> calculatedShifts; // Shift IDs untuk setiap hari dalam bulan
  final int firstOffDay; // Hari pertama OFF (1-31, 999 jika tidak ada)
  final int offDayOfWeek; // Day of week untuk first OFF (1=Mon, 7=Sun)

  UserWithPattern({
    required this.user,
    this.pattern,
    required this.calculatedShifts,
    required this.firstOffDay,
    required this.offDayOfWeek,
  });
}

class _RosterManagementScreenState extends State<RosterManagementScreen> {
  final ShiftService _shiftService = ShiftService();
  final ShiftAssignmentService _assignmentService = ShiftAssignmentService();
  final UserService _userService = UserService();
  final RosterPatternService _patternService = RosterPatternService();
  final RosterAssignmentService _rosterAssignmentService =
      RosterAssignmentService();
  final PdfService _pdfService = PdfService();

  DateTime _selectedMonth = DateTime.now();
  List<Shift> _shifts = [];
  List<User> _users = [];
  Map<String, List<ShiftAssignment>> _assignments = {}; // key: "YYYY-MM-DD"
  Map<int, RosterPattern?> _userPatterns = {}; // key: userId, value: pattern
  List<UserWithPattern> _rosterData =
      []; // Calculated roster data dengan pattern
  bool _isLoading = true;
  String? _error;

  // View mode: true = Grid View, false = Calendar View
  bool _isGridView = true;

  // Speed dial FAB state
  bool _isFabExpanded = false;

  // Grid sort method: 'first' (by OFF day number) or 'last' (by day of week)
  String _gridSortMethod = 'first';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = widget.authService.accessToken;
      if (token == null) throw Exception('No authentication token');

      // Load shifts
      final shifts = await _shiftService.getShifts(token);

      // Load users
      final users = await _userService.getUsers();

      // Load assignments for current month using portal endpoint
      // Format: "YYYY-MM-DD" (any day in the month, will match whole month)
      final monthStr =
          '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}-01';

      print('📅 Fetching assignments for month: $monthStr');
      final assignments = await _assignmentService.getMonthAssignments(
        token,
        monthStr,
      );

      print('📦 Total assignments fetched: ${assignments.length}');

      // DEBUG: Log all Ilham (user_id=8) assignments BEFORE grouping
      final ilhamAssignments = assignments.where((a) => a.userId == 8).toList();
      print(
          '🔍 DEBUG Ilham: Found ${ilhamAssignments.length} assignments for user_id=8');
      for (var i = 0; i < ilhamAssignments.length && i < 5; i++) {
        final assign = ilhamAssignments[i];
        print(
            '  Ilham[$i]: ID=${assign.id}, Date=${assign.assignmentDate}, Shift=${assign.shiftId}');
      }

      // Group assignments by date
      final Map<String, List<ShiftAssignment>> assignmentsByDate = {};
      for (var assignment in assignments) {
        // Use simple string formatting without DateFormat to avoid timezone issues
        final year = assignment.assignmentDate.year.toString();
        final month =
            assignment.assignmentDate.month.toString().padLeft(2, '0');
        final day = assignment.assignmentDate.day.toString().padLeft(2, '0');
        final key = '$year-$month-$day';

        assignmentsByDate.putIfAbsent(key, () => []);
        assignmentsByDate[key]!.add(assignment);
      }

      print('📅 Assignments grouped by ${assignmentsByDate.length} dates');

      // DEBUG: Check if Ilham has assignment on Dec 1
      final dec1Key = '2025-12-01';
      if (assignmentsByDate.containsKey(dec1Key)) {
        final dec1Assignments = assignmentsByDate[dec1Key]!;
        final ilhamDec1 = dec1Assignments.where((a) => a.userId == 8).toList();
        print(
            '🚨 CRITICAL DEBUG: $dec1Key has ${dec1Assignments.length} total assignments');
        if (ilhamDec1.isNotEmpty) {
          print('   ⚠️ Ilham (user_id=8) HAS assignment on Dec 1:');
          for (var a in ilhamDec1) {
            print('      ID=${a.id}, Shift=${a.shiftId}');
          }
        } else {
          print('   ✓ Ilham (user_id=8) has NO assignment on Dec 1 (correct)');
        }
      }

      // Show first 5 dates for debugging
      int count = 0;
      assignmentsByDate.forEach((date, assigns) {
        if (count < 5) {
          print('  $date: ${assigns.length} assignments');
          for (var a in assigns.take(3)) {
            print('    - User ${a.userId}: Shift ${a.shiftId}');
          }
          count++;
        }
      });

      // Fetch roster assignments (user-pattern mapping for the month)
      final Map<int, RosterPattern?> userPatterns = {};
      try {
        print(
            '🔍 Requesting roster assignments for: ${_selectedMonth.year}/${_selectedMonth.month}');

        final rosterAssignments =
            await _rosterAssignmentService.getMonthAssignments(
          token,
          _selectedMonth.year,
          _selectedMonth.month,
        );

        print('📥 Received ${rosterAssignments.length} roster assignments');

        // Build userPatterns map from roster assignments
        // Pattern data is already included in the response!
        for (var rosterAssignment in rosterAssignments) {
          // Convert roster assignment pattern data to RosterPattern object
          // Backend sends 1D array [1,2,3,1,2,0,0], wrap it in 2D for RosterPattern
          final pattern = RosterPattern(
            id: rosterAssignment.patternId,
            name: rosterAssignment.patternName,
            description: null,
            personilCount: 1, // Not used in calculation
            patternData: [rosterAssignment.patternData], // Wrap 1D array in 2D
            isDefault: false,
            createdBy: null,
            createdAt: rosterAssignment.assignedAt,
            updatedAt: rosterAssignment.assignedAt,
            usageCount: 0,
            lastUsedAt: rosterAssignment.assignedAt,
          );

          userPatterns[rosterAssignment.userId] = pattern;

          print(
              '👤 User ${rosterAssignment.userName} (ID: ${rosterAssignment.userId}):');
          print('   Pattern: ${rosterAssignment.patternName}');
          print('   Data: ${rosterAssignment.patternData}');
        }

        print(
            '✅ Loaded ${rosterAssignments.length} roster assignments with patterns');
      } catch (e) {
        print('⚠️ Error loading roster assignments: $e');
        // Continue without roster assignments - will show only actual shifts
      }

      // Fill remaining users with null patterns
      for (var user in users) {
        userPatterns.putIfAbsent(user.id, () => null);
      }

      // Calculate roster data with pattern fallback
      final rosterData = _calculateRosterData(
        users: users,
        shifts: shifts,
        assignments: assignmentsByDate,
        userPatterns: userPatterns,
        selectedMonth: _selectedMonth,
      );

      setState(() {
        _shifts = shifts;
        _users = users;
        _assignments = assignmentsByDate;
        _userPatterns = userPatterns;
        _rosterData = rosterData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Calculate roster data with pattern fallback (sama seperti portal)
  List<UserWithPattern> _calculateRosterData({
    required List<User> users,
    required List<Shift> shifts,
    required Map<String, List<ShiftAssignment>> assignments,
    required Map<int, RosterPattern?> userPatterns,
    required DateTime selectedMonth,
  }) {
    final daysInMonth =
        DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;

    return users.map((user) {
      final pattern = userPatterns[user.id];
      print('\n🧑 Calculating roster for: ${user.name} (ID: ${user.id})');
      if (pattern != null) {
        print('  Pattern: ${pattern.name}');
        print('  Pattern Data: ${pattern.patternData[0]}');
      } else {
        print('  ⚠️ No pattern assigned');
      }

      // Calculate shifts for each day in month
      final calculatedShifts = List<int>.generate(daysInMonth, (dayIndex) {
        final day = dayIndex + 1;
        final date = DateTime(selectedMonth.year, selectedMonth.month, day);
        final year = date.year.toString();
        final month = date.month.toString().padLeft(2, '0');
        final dayStr = date.day.toString().padLeft(2, '0');
        final dateKey = '$year-$month-$dayStr';

        // Priority 1: Check actual assignment (from database)
        final dayAssignments = assignments[dateKey] ?? [];
        final actualAssignment = dayAssignments.firstWhere(
          (a) => a.userId == user.id,
          orElse: () => ShiftAssignment(
            id: -1,
            userId: user.id,
            shiftId: -1,
            assignmentDate: date,
            isReplacement: false,
          ),
        );

        if (actualAssignment.id != -1 && actualAssignment.shiftId != -1) {
          print(
              '  ✅ Day $day: Actual assignment found - Shift ${actualAssignment.shiftId} (Assignment ID: ${actualAssignment.id})');
          return actualAssignment.shiftId; // ✅ Use saved assignment
        }

        // Priority 2: Fallback to pattern (predicted schedule)
        if (pattern != null && pattern.patternData.isNotEmpty) {
          // PORTAL LOGIC: Pattern cycles every 7 days based on day-of-month
          // dayIndex = 0,1,2,...30 (for Dec: 0-30)
          // patternIndex = dayIndex % 7 (repeats every 7 days)
          // Dec 1 → dayIndex=0 → pattern[0]
          // Dec 8 → dayIndex=7 → pattern[0] (cycle repeats)
          final patternIndex = dayIndex % 7;

          if (patternIndex >= 0 &&
              patternIndex < pattern.patternData[0].length) {
            final shiftId = pattern.patternData[0][patternIndex];
            print(
                '  📅 Day $day (dayIndex=$dayIndex): pattern[$patternIndex] = Shift $shiftId');
            return shiftId; // ✅ Use pattern
          }
        }

        // Priority 3: Default to OFF (0)
        return 0; // ❌ OFF
      });

      // Find first OFF day and day of week
      final firstOffDay = calculatedShifts.indexOf(0) + 1;
      int offDayOfWeek = 0;

      if (firstOffDay > 0 && firstOffDay <= daysInMonth) {
        final offDate =
            DateTime(selectedMonth.year, selectedMonth.month, firstOffDay);
        offDayOfWeek = offDate.weekday;
        // Convert Sunday (7) to highest priority for "last" sorting
        if (offDayOfWeek == DateTime.sunday) offDayOfWeek = 7;
      }

      return UserWithPattern(
        user: user,
        pattern: pattern,
        calculatedShifts: calculatedShifts,
        firstOffDay: firstOffDay > 0 ? firstOffDay : 999,
        offDayOfWeek: offDayOfWeek,
      );
    }).toList();
  }

  Future<void> _showAssignmentDialog({DateTime? date}) async {
    final selectedDate = date ?? DateTime.now();
    User? selectedUser;
    Shift? selectedShift;
    bool isReplacement = false;
    User? replacedUser;
    final notesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
              'Assign Shift - ${DateFormat('dd MMM yyyy').format(selectedDate)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<User>(
                  decoration: const InputDecoration(
                    labelText: 'Pilih User',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedUser,
                  items: _users
                      .map((user) => DropdownMenuItem(
                            value: user,
                            child: Text('${user.name} (${user.phone})'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedUser = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Shift>(
                  decoration: const InputDecoration(
                    labelText: 'Pilih Shift',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedShift,
                  items: _shifts
                      .where((s) => s.isActive)
                      .map((shift) => DropdownMenuItem(
                            value: shift,
                            child: Text(
                              '${shift.name} (${shift.getFormattedStartTime()}-${shift.getFormattedEndTime()})',
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedShift = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Replacement'),
                  subtitle: const Text('User ini menggantikan user lain'),
                  value: isReplacement,
                  onChanged: (value) {
                    setDialogState(() {
                      isReplacement = value;
                      if (!value) replacedUser = null;
                    });
                  },
                ),
                if (isReplacement) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<User>(
                    decoration: const InputDecoration(
                      labelText: 'User yang Digantikan',
                      border: OutlineInputBorder(),
                    ),
                    value: replacedUser,
                    items: _users
                        .where((u) => u.id != selectedUser?.id)
                        .map((user) => DropdownMenuItem(
                              value: user,
                              child: Text('${user.name} (${user.phone})'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        replacedUser = value;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedUser == null || selectedShift == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pilih user dan shift')),
                  );
                  return;
                }

                if (isReplacement && replacedUser == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pilih user yang digantikan')),
                  );
                  return;
                }

                Navigator.pop(context);

                try {
                  final token = widget.authService.accessToken;
                  if (token == null) throw Exception('No token');

                  await _assignmentService.createAssignment(
                    token,
                    userId: selectedUser!.id,
                    shiftId: selectedShift!.id,
                    assignmentDate: selectedDate,
                    isReplacement: isReplacement,
                    replacedUserId: replacedUser?.id,
                    notes: notesController.text.isEmpty
                        ? null
                        : notesController.text,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Assignment berhasil dibuat')),
                  );

                  _loadData();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBulkAssignDialog() async {
    User? selectedUser;
    Shift? selectedShift;
    DateTimeRange? dateRange;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bulk Assign Shift'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<User>(
                  decoration: const InputDecoration(
                    labelText: 'Pilih User',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedUser,
                  items: _users
                      .map((user) => DropdownMenuItem(
                            value: user,
                            child: Text('${user.name} (${user.phone})'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedUser = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Shift>(
                  decoration: const InputDecoration(
                    labelText: 'Pilih Shift',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedShift,
                  items: _shifts
                      .where((s) => s.isActive)
                      .map((shift) => DropdownMenuItem(
                            value: shift,
                            child: Text(
                              '${shift.name} (${shift.getFormattedStartTime()}-${shift.getFormattedEndTime()})',
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedShift = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Rentang Tanggal'),
                  subtitle: Text(
                    dateRange != null
                        ? '${DateFormat('dd/MM/yy').format(dateRange!.start)} - ${DateFormat('dd/MM/yy').format(dateRange!.end)}'
                        : 'Belum dipilih',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: dateRange,
                    );
                    if (picked != null) {
                      setDialogState(() {
                        dateRange = picked;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedUser == null ||
                    selectedShift == null ||
                    dateRange == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lengkapi semua field')),
                  );
                  return;
                }

                Navigator.pop(context);

                try {
                  final token = widget.authService.accessToken;
                  if (token == null) throw Exception('No token');

                  // Generate assignments for date range
                  final assignments = <Map<String, dynamic>>[];
                  DateTime currentDate = dateRange!.start;
                  while (currentDate
                      .isBefore(dateRange!.end.add(const Duration(days: 1)))) {
                    assignments.add({
                      'user_id': selectedUser!.id,
                      'shift_id': selectedShift!.id,
                      'assignment_date':
                          DateFormat('yyyy-MM-dd').format(currentDate),
                    });
                    currentDate = currentDate.add(const Duration(days: 1));
                  }

                  final result = await _assignmentService.createBulkAssignments(
                    token,
                    assignments,
                  );

                  final created = result['data']['created'] as List;
                  final errors = result['data']['errors'] as List?;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Berhasil: ${created.length} assignment\n'
                        '${errors != null && errors.isNotEmpty ? "Gagal: ${errors.length}" : ""}',
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );

                  _loadData();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

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
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Expanded(
              child: _buildError(),
            )
          else ...[
            _buildMonthSelector(isDark),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: _isGridView ? _buildGridView() : _buildCalendar(),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: _buildSpeedDialFAB(isDark, primaryColor),
    );
  }

  // Speed Dial FAB with 2 options
  Widget _buildSpeedDialFAB(bool isDark, Color primaryColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Overlay when expanded
        if (_isFabExpanded)
          GestureDetector(
            onTap: () => setState(() => _isFabExpanded = false),
            child: Container(
              color: Colors.transparent,
            ),
          ),

        // Options (show when expanded)
        if (_isFabExpanded) ...[
          _buildFabOption(
            icon: Icons.auto_awesome,
            label: 'AUTO GENERATE',
            color: Colors.purple,
            onTap: () {
              setState(() => _isFabExpanded = false);
              _showAutoGenerateDialog();
            },
          ),
          const SizedBox(height: 12),
          _buildFabOption(
            icon: Icons.picture_as_pdf,
            label: 'EXPORT PDF',
            color: Colors.green,
            onTap: () {
              setState(() => _isFabExpanded = false);
              _exportToPdf();
            },
          ),
          const SizedBox(height: 12),
          _buildFabOption(
            icon: Icons.calendar_today,
            label: 'BULK ASSIGN',
            color: Colors.blue,
            onTap: () {
              setState(() => _isFabExpanded = false);
              _showBulkAssignDialog();
            },
          ),
          const SizedBox(height: 12),
          _buildFabOption(
            icon: Icons.delete_sweep,
            label: 'RESET ROSTER',
            color: Colors.red,
            onTap: () {
              setState(() => _isFabExpanded = false);
              _showResetRosterDialog();
            },
          ),
          const SizedBox(height: 16),
        ],

        // Main FAB
        FloatingActionButton(
          onPressed: () => setState(() => _isFabExpanded = !_isFabExpanded),
          backgroundColor: primaryColor,
          foregroundColor: isDark ? Colors.black : Colors.white,
          child: AnimatedRotation(
            turns: _isFabExpanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(_isFabExpanded ? Icons.close : Icons.add, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildFabOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton(
          mini: true,
          onPressed: onTap,
          backgroundColor: color,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ],
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
                  'Manajemen Roster',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
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
          const SizedBox(width: 8),
          // View toggle button
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isGridView ? Icons.calendar_month : Icons.grid_on,
                color: isDark ? AppColors.darkTextPrimary : Colors.white,
                size: 24,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() {
                  _isGridView = !_isGridView;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
            ),
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month - 1,
                );
              });
              _loadData();
            },
          ),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedMonth,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.light(
                        primary: AppColors.primary,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() {
                  _selectedMonth = DateTime(picked.year, picked.month);
                });
                _loadData();
              }
            },
            child: Row(
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
            ),
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month + 1,
                );
              });
              _loadData();
            },
          ),
        ],
      ),
    );
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
            onPressed: _loadData,
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDay.day;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: daysInMonth,
      itemBuilder: (context, index) {
        final day = index + 1;
        final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);

        // Use same manual formatting as in _loadData to avoid timezone issues
        final year = date.year.toString();
        final month = date.month.toString().padLeft(2, '0');
        final dayStr = date.day.toString().padLeft(2, '0');
        final dateKey = '$year-$month-$dayStr';

        final dayAssignments = _assignments[dateKey] ?? [];
        final isToday = DateTime.now().year == date.year &&
            DateTime.now().month == date.month &&
            DateTime.now().day == date.day;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isToday
                ? Border.all(
                    color: AppColors.primary,
                    width: 2,
                  )
                : isDark
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
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isToday
                    ? AppColors.primary
                    : dayAssignments.isEmpty
                        ? (isDark
                            ? AppColors.darkSurfaceVariant
                            : Colors.grey.shade200)
                        : AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$day',
                  style: TextStyle(
                    color: isToday
                        ? Colors.white
                        : dayAssignments.isEmpty
                            ? (isDark
                                ? AppColors.darkTextSecondary
                                : Colors.grey.shade600)
                            : AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            title: Text(
              DateFormat('EEEE, dd MMMM').format(date),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    dayAssignments.isEmpty
                        ? Icons.event_busy
                        : Icons.event_available,
                    size: 14,
                    color: dayAssignments.isEmpty
                        ? (isDark ? AppColors.darkTextTertiary : Colors.grey)
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dayAssignments.isEmpty
                        ? 'Belum ada assignment'
                        : '${dayAssignments.length} assignment',
                    style: TextStyle(
                      fontSize: 13,
                      color: dayAssignments.isEmpty
                          ? (isDark ? AppColors.darkTextTertiary : Colors.grey)
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Container(
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.add_circle_outline,
                  color: AppColors.primary,
                ),
                onPressed: () => _showAssignmentDialog(date: date),
              ),
            ),
            children: dayAssignments
                .map((assignment) => _buildAssignmentTile(assignment, isDark))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildAssignmentTile(ShiftAssignment assignment, bool isDark) {
    // Get color for the shift
    Color shiftColor = AppColors.primary;
    try {
      final shift = _shifts.firstWhere((s) => s.id == assignment.shiftId);
      shiftColor = shift.colorValue;
    } catch (e) {
      // Use default if shift not found
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.lightSurfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Avatar with shift color
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: shiftColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                assignment.userName?.substring(0, 1).toUpperCase() ?? 'U',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: shiftColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assignment.userName ?? 'Unknown',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: shiftColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${assignment.shiftName} (${assignment.getFormattedStartTime()}-${assignment.getFormattedEndTime()})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: shiftColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (assignment.isReplacement) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Replacement: ${assignment.replacedUserName ?? "N/A"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (assignment.notes != null &&
                    assignment.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '📝 ${assignment.notes}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Delete button
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
            onPressed: () => _deleteAssignment(assignment),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAssignment(ShiftAssignment assignment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text(
          'Yakin ingin menghapus assignment "${assignment.userName}" dari shift "${assignment.shiftCode ?? assignment.shiftName}"?',
        ),
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

        await _assignmentService.deleteAssignment(token, assignment.id);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment berhasil dihapus')),
        );

        _loadData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  // Grid View - Shows users in rows, dates in columns (like Excel)
  Widget _buildGridView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDay.day;

    // Filter only security users (role = 'security') from roster data
    var securityRosterData = _rosterData
        .where((userWithPattern) => userWithPattern.user.role == 'security')
        .toList();

    // Apply sorting based on selected method (sama seperti portal)
    if (_gridSortMethod == 'first') {
      // Sort by first OFF day NUMBER (1, 2, 3, ...)
      securityRosterData.sort((a, b) => a.firstOffDay.compareTo(b.firstOffDay));
    } else if (_gridSortMethod == 'last') {
      // Sort by day of WEEK descending (Sunday=7, Saturday=6, ..., Monday=1)
      // Higher day of week = closer to weekend = goes first
      securityRosterData
          .sort((a, b) => b.offDayOfWeek.compareTo(a.offDayOfWeek));
    }

    if (securityRosterData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Belum ada user security',
              style: TextStyle(
                color: isDark ? AppColors.darkTextSecondary : Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Legend/Info bar with sort selector
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: isDark
                ? Border.all(color: AppColors.borderDark, width: 1)
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.sort,
                  size: 18,
                  color:
                      isDark ? AppColors.darkTextSecondary : AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Urutan:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.lightSurfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _gridSortMethod,
                      isDense: true,
                      isExpanded: true,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                      dropdownColor: isDark ? AppColors.darkCard : Colors.white,
                      icon: Icon(
                        Icons.arrow_drop_down,
                        size: 20,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'first',
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 16, color: Colors.blue),
                              SizedBox(width: 6),
                              Text('First OFF Day'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'last',
                          child: Row(
                            children: [
                              Icon(Icons.weekend,
                                  size: 16, color: Colors.orange),
                              SizedBox(width: 6),
                              Text('Last OFF Day (Weekend)'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _gridSortMethod = value;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Grid Table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row (dates)
                    _buildGridHeader(daysInMonth, isDark),

                    // User rows
                    ...securityRosterData
                        .map((userWithPattern) => _buildGridUserRow(
                              userWithPattern,
                              daysInMonth,
                              isDark,
                            )),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridHeader(int daysInMonth, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.primary.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          // User name header (fixed column)
          Container(
            width: 120,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  width: 1,
                ),
              ),
            ),
            child: Text(
              'PERSONIL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? AppColors.darkTextPrimary : AppColors.primary,
              ),
            ),
          ),
          // Date columns
          ...List.generate(daysInMonth, (index) {
            final day = index + 1;
            final date =
                DateTime(_selectedMonth.year, _selectedMonth.month, day);
            final dayName = DateFormat('E').format(date).substring(0, 1);
            final isWeekend = date.weekday == DateTime.saturday ||
                date.weekday == DateTime.sunday;

            return Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isWeekend
                    ? (isDark
                        ? Colors.red.withOpacity(0.1)
                        : Colors.red.withOpacity(0.05))
                    : null,
                border: Border(
                  right: BorderSide(
                    color:
                        isDark ? AppColors.borderDark : AppColors.borderLight,
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isWeekend
                          ? Colors.red
                          : (isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary),
                    ),
                  ),
                  Text(
                    dayName,
                    style: TextStyle(
                      fontSize: 11,
                      color: isWeekend
                          ? Colors.red.shade300
                          : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGridUserRow(
      UserWithPattern userWithPattern, int daysInMonth, bool isDark) {
    final user = userWithPattern.user;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // User name (fixed column)
          Container(
            width: 120,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  width: 1,
                ),
              ),
            ),
            child: Text(
              user.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Date cells
          ...List.generate(daysInMonth, (index) {
            final day = index + 1;
            final date =
                DateTime(_selectedMonth.year, _selectedMonth.month, day);
            final year = date.year.toString();
            final month = date.month.toString().padLeft(2, '0');
            final dayStr = date.day.toString().padLeft(2, '0');
            final dateKey = '$year-$month-$dayStr';

            // Get calculated shift ID from pattern fallback
            final calculatedShiftId = userWithPattern.calculatedShifts[index];

            // Find actual assignment for edit/delete functionality
            final dayAssignments = _assignments[dateKey] ?? [];
            final assignment = dayAssignments.firstWhere(
              (a) => a.userId == user.id,
              orElse: () => ShiftAssignment(
                id: -1,
                userId: user.id,
                shiftId: -1,
                assignmentDate: date,
                isReplacement: false,
              ),
            );

            return _buildGridCell(
              user,
              date,
              dateKey,
              assignment,
              calculatedShiftId, // Pass calculated shift ID
              isDark,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGridCell(
    User user,
    DateTime date,
    String dateKey,
    ShiftAssignment assignment,
    int calculatedShiftId, // Shift ID from pattern fallback
    bool isDark,
  ) {
    final hasActualAssignment = assignment.id != -1;
    final isWeekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

    // Determine which shift to display:
    // 1. If has actual assignment, use assignment.shiftId
    // 2. Otherwise, use calculatedShiftId (from pattern or 0)
    final displayShiftId =
        hasActualAssignment ? assignment.shiftId : calculatedShiftId;

    // Find shift details
    Shift? shift;
    if (displayShiftId > 0) {
      try {
        shift = _shifts.firstWhere((s) => s.id == displayShiftId);
      } catch (e) {
        // Shift not found
      }
    }

    // Determine if this is OFF (0) or no shift found
    final isOff = displayShiftId == 0 || shift == null;

    return InkWell(
      onTap: () => _showQuickShiftSelector(user, date, dateKey, assignment),
      child: Container(
        width: 60,
        height: 50,
        decoration: BoxDecoration(
          color: isWeekend
              ? (isDark
                  ? Colors.red.withOpacity(0.05)
                  : Colors.red.withOpacity(0.02))
              : null,
          border: Border(
            right: BorderSide(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
              width: 0.5,
            ),
          ),
        ),
        child: Center(
          child: !isOff && shift != null
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: shift.colorValue.withOpacity(hasActualAssignment
                        ? 0.15
                        : 0.08), // Lighter if pattern
                    borderRadius: BorderRadius.circular(8),
                    border: hasActualAssignment
                        ? null
                        : Border.all(
                            color: shift.colorValue.withOpacity(0.3),
                            width: 1,
                            style: BorderStyle.solid,
                          ),
                  ),
                  child: Text(
                    shift.code ??
                        shift.name
                            .split(' ')
                            .last, // Use code (e.g., "1", "2", "3"), fallback to name
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: shift.colorValue,
                    ),
                  ),
                )
              : Icon(
                  Icons.event_busy_rounded, // Pertahankan icon untuk OFF
                  size: 24,
                  color: Colors.red.shade600,
                ),
        ),
      ),
    );
  }

  // Show shift detail information bottom sheet
  Future<void> _showQuickShiftSelector(
    User user,
    DateTime date,
    String dateKey,
    ShiftAssignment currentAssignment,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasAssignment = currentAssignment.id != -1;

    // Determine shift details
    Shift? shift;
    String shiftStatus = '';

    if (hasAssignment) {
      // Has actual assignment in database
      try {
        shift = _shifts.firstWhere((s) => s.id == currentAssignment.shiftId);
        shiftStatus = 'Assignment Aktual';
      } catch (e) {
        shiftStatus = 'Shift tidak ditemukan';
      }
    } else {
      // Check from pattern
      final userWithPattern = _rosterData.firstWhere(
        (u) => u.user.id == user.id,
        orElse: () => _rosterData.first,
      );

      final lastDay =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final daysInMonth = lastDay.day;
      final dayIndex = date.day - 1;

      if (dayIndex < userWithPattern.calculatedShifts.length) {
        final calculatedShiftId = userWithPattern.calculatedShifts[dayIndex];
        if (calculatedShiftId > 0) {
          try {
            shift = _shifts.firstWhere((s) => s.id == calculatedShiftId);
            shiftStatus = 'Dari Pattern';
          } catch (e) {
            shiftStatus = 'Pattern shift tidak ditemukan';
          }
        } else {
          shiftStatus = 'OFF (Libur)';
        }
      }
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with close button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.info_outline,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Detail Shift Assignment',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // User Info
            _buildInfoRow(
              Icons.person,
              'Personil',
              user.name,
              isDark,
            ),
            const SizedBox(height: 16),

            // Date Info
            _buildInfoRow(
              Icons.calendar_today,
              'Tanggal',
              DateFormat('EEEE, dd MMMM yyyy').format(date),
              isDark,
            ),
            const SizedBox(height: 16),

            // Shift Info
            if (shift != null) ...[
              _buildInfoRow(
                Icons.schedule,
                'Shift',
                '${shift.code ?? shift.name} - ${shift.name}',
                isDark,
              ),
              const SizedBox(height: 16),

              // Shift Time
              _buildInfoRow(
                Icons.access_time,
                'Jam Kerja',
                '${shift.getFormattedStartTime()} - ${shift.getFormattedEndTime()}',
                isDark,
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkTextSecondary.withOpacity(0.1)
                : AppColors.lightTextSecondary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper: Find first OFF day (no assignment) for a user in current month
  int _getFirstOffDay(User user) {
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDay.day;

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      final year = date.year.toString();
      final month = date.month.toString().padLeft(2, '0');
      final dayStr = date.day.toString().padLeft(2, '0');
      final dateKey = '$year-$month-$dayStr';

      final dayAssignments = _assignments[dateKey] ?? [];
      final hasAssignment = dayAssignments.any((a) => a.userId == user.id);

      if (!hasAssignment) {
        return day; // Found first OFF day
      }
    }

    return -1; // No OFF day found
  }

  // Reset Roster Dialog - Clear all assignments for selected month
  Future<void> _showResetRosterDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final monthName = DateFormat('MMMM yyyy').format(_selectedMonth);

    // Count assignments in current month
    final totalAssignments = _assignments.values.fold<int>(
      0,
      (sum, assignments) => sum + assignments.length,
    );

    if (totalAssignments == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada assignment untuk bulan ini'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Reset Roster?',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apakah Anda yakin ingin menghapus SEMUA shift assignments untuk bulan:',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    monthName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Total $totalAssignments assignments akan dihapus',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Tindakan ini tidak dapat dibatalkan!',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Batal',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Ya, Reset'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _resetRoster();
    }
  }

  Future<void> _resetRoster() async {
    try {
      setState(() => _isLoading = true);

      final token = widget.authService.accessToken;
      if (token == null) throw Exception('No token');

      // Get all assignment IDs for the current month
      final List<int> assignmentIds = [];
      _assignments.forEach((dateKey, assignments) {
        for (var assignment in assignments) {
          assignmentIds.add(assignment.id);
        }
      });

      // Delete all assignments
      int deletedCount = 0;
      for (var id in assignmentIds) {
        try {
          await _assignmentService.deleteAssignment(token, id);
          deletedCount++;
        } catch (e) {
          print('Failed to delete assignment $id: $e');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Roster berhasil direset!\n'
            'Dihapus: $deletedCount assignments',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );

      // Reload data
      await _loadData();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Auto Generate Dialog - Phase 2
  Future<void> _showAutoGenerateDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get security users only and sort alphabetically
    final securityUsers = _users.where((u) => u.role == 'security').toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (securityUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada user security')),
      );
      return;
    }

    // State variables
    List<User> selectedUsers = [];
    bool isLoadingPatterns = false;
    List<RosterPattern> availablePatterns = [];
    RosterPattern? selectedPattern;
    String? patternLoadError;

    // Load available patterns from API
    Future<void> loadPatterns(int personilCount) async {
      try {
        print('🔄 Loading patterns from API for $personilCount personil...');
        final token = widget.authService.accessToken;
        final patterns = await _patternService.getPatterns(
          token: token,
          personilCount: personilCount,
        );
        print('✅ Received ${patterns.length} patterns from API');
        availablePatterns = patterns;

        // Auto-select default pattern if available
        try {
          selectedPattern = patterns.firstWhere((p) => p.isDefault);
          print('✅ Auto-selected default pattern: ${selectedPattern?.name}');
        } catch (e) {
          selectedPattern = patterns.isNotEmpty ? patterns.first : null;
          print(
              '⚠️ No default pattern, selected first: ${selectedPattern?.name}');
        }
        patternLoadError = null;
      } catch (e) {
        print('❌ Error loading patterns: $e');
        patternLoadError = 'Gagal memuat pattern: $e';
        availablePatterns = [];
        selectedPattern = null;
      } finally {
        isLoadingPatterns = false;
      }
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Determine pattern based on selected users count
          final userCount = selectedUsers.length;

          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.purple,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Auto Generate Roster',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.purple.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.purple,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Generate roster otomatis untuk ${DateFormat('MMMM yyyy').format(_selectedMonth)} dengan pattern proven',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // User selection
                    Text(
                      'Pilih Personil (Urutan = Row Pattern):',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: securityUsers.length,
                        itemBuilder: (context, index) {
                          final user = securityUsers[index];
                          final isSelected = selectedUsers.contains(user);
                          final selectedIndex = selectedUsers.indexOf(user);

                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setDialogState(() {
                                final previousCount = selectedUsers.length;
                                if (value == true) {
                                  selectedUsers.add(user);
                                } else {
                                  selectedUsers.remove(user);
                                }
                                // Load patterns when count changes
                                final newCount = selectedUsers.length;
                                if (newCount > 0 && newCount != previousCount) {
                                  isLoadingPatterns = true;
                                  loadPatterns(newCount).then((_) {
                                    setDialogState(() {});
                                  });
                                } else if (newCount == 0) {
                                  availablePatterns = [];
                                  selectedPattern = null;
                                }
                              });
                            },
                            title: Row(
                              children: [
                                if (isSelected)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Row ${selectedIndex + 1}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    user.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.lightTextPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              user.phone,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                            activeColor: Colors.purple,
                            dense: true,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Batal',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: selectedUsers.isEmpty ||
                        selectedPattern == null ||
                        isLoadingPatterns
                    ? null
                    : () async {
                        Navigator.pop(context);

                        // Record pattern usage
                        try {
                          final token = widget.authService.accessToken;
                          await _patternService.recordUsage(selectedPattern!.id,
                              token: token);
                        } catch (e) {
                          print('Warning: Failed to record usage: $e');
                        }

                        // Generate roster
                        await _generateRoster(
                          selectedUsers,
                          selectedPattern!.patternData,
                        );
                      },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Generate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getShiftColor(int shiftNumber) {
    try {
      // Try to find shift by checking shift name patterns
      final shift = _shifts.firstWhere(
        (s) =>
            s.name.contains('$shiftNumber') ||
            (shiftNumber == 1 && s.name.toLowerCase().contains('pagi')) ||
            (shiftNumber == 2 && s.name.toLowerCase().contains('sore')) ||
            (shiftNumber == 3 && s.name.toLowerCase().contains('malam')),
      );
      return shift.colorValue;
    } catch (e) {
      // Fallback colors
      switch (shiftNumber) {
        case 1:
          return Colors.blue;
        case 2:
          return Colors.orange;
        case 3:
          return Colors.green;
        default:
          return Colors.grey;
      }
    }
  }

  // Pattern Library Based Generation (100% Match with Reference)
  Future<void> _generateRoster(
    List<User> selectedUsers,
    List<List<int>> patterns,
  ) async {
    try {
      setState(() => _isLoading = true);

      final token = widget.authService.accessToken;
      if (token == null) throw Exception('No token');

      // Calculate days in selected month
      final daysInMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;

      // Validate pattern count matches user count
      if (patterns.length < selectedUsers.length) {
        throw Exception(
            'Pattern library tidak cukup untuk ${selectedUsers.length} personil');
      }

      // Generate assignments using pattern library
      final List<Map<String, dynamic>> assignments = [];

      for (int userIndex = 0; userIndex < selectedUsers.length; userIndex++) {
        final user = selectedUsers[userIndex];

        // Get pattern for this user (row-based, not rotation)
        final pattern = patterns[userIndex];
        final patternLength = pattern.length; // Should be 7

        for (int day = 1; day <= daysInMonth; day++) {
          // Calculate position in pattern (simple cyclic)
          final patternIndex = (day - 1) % patternLength;
          final shiftNumber = pattern[patternIndex];

          // Skip if it's OFF day (0)
          if (shiftNumber == 0) continue;

          // Find shift ID by shift number
          final shift = _findShiftByNumber(shiftNumber);
          if (shift == null) {
            throw Exception(
                'Shift $shiftNumber tidak ditemukan. Pastikan shift sudah dibuat.');
          }

          final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);

          assignments.add({
            'user_id': user.id,
            'shift_id': shift.id,
            'assignment_date': DateFormat('yyyy-MM-dd').format(date),
          });
        }
      }

      // Call bulk create API
      final result = await _assignmentService.createBulkAssignments(
        token,
        assignments,
      );

      final created = result['data']['created'] as List;
      final errors = result['data']['errors'] as List?;

      // Show result
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Roster generated with proven pattern!\n'
            'Berhasil: ${created.length} assignments\n'
            '${errors != null && errors.isNotEmpty ? "Gagal/Duplicate: ${errors.length}" : ""}',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );

      // Reload data
      await _loadData();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Shift? _findShiftByNumber(int shiftNumber) {
    try {
      // Match ONLY by time range (paling reliable)
      // Pattern reference:
      // 1 = Shift Pagi (start: 06:00-09:00)
      // 2 = Shift Siang (start: 14:00-17:00)
      // 3 = Shift Malam (start: 22:00-23:59)

      if (_shifts.isEmpty) return null;

      if (shiftNumber == 1) {
        // Shift pagi: start time antara 06:00-09:00
        final shift = _shifts.firstWhere(
          (s) {
            final hour = int.tryParse(s.startTime.split(':')[0]) ?? 0;
            return hour >= 6 && hour <= 9;
          },
          orElse: () => _shifts.first, // fallback ke shift pertama
        );
        return shift;
      } else if (shiftNumber == 2) {
        // Shift siang: start time antara 14:00-17:00
        final shift = _shifts.firstWhere(
          (s) {
            final hour = int.tryParse(s.startTime.split(':')[0]) ?? 0;
            return hour >= 14 && hour <= 17;
          },
          orElse: () => _shifts.length > 1 ? _shifts[1] : _shifts.first,
        );
        return shift;
      } else if (shiftNumber == 3) {
        // Shift malam: start time antara 22:00-23:59
        final shift = _shifts.firstWhere(
          (s) {
            final hour = int.tryParse(s.startTime.split(':')[0]) ?? 0;
            return hour >= 22;
          },
          orElse: () => _shifts.length > 2 ? _shifts[2] : _shifts.last,
        );
        return shift;
      }

      return null;
    } catch (e) {
      print('Error finding shift $shiftNumber: $e');
      return null;
    }
  }

  /// Export roster to PDF
  Future<void> _exportToPdf() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Validate data
    if (_rosterData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada data roster untuk diekspor'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Generating PDF...',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final token = widget.authService.accessToken;
      if (token == null) throw Exception('No token');

      // Prepare data for PDF (same format as portal)
      final monthName = DateFormat('MMMM yyyy').format(_selectedMonth);
      final lastDay =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final daysInMonth = lastDay.day;

      // Generate day names (S, M, T, W, T, F, S)
      final dayNames = List.generate(daysInMonth, (index) {
        final date =
            DateTime(_selectedMonth.year, _selectedMonth.month, index + 1);
        return DateFormat('E').format(date).substring(0, 1).toUpperCase();
      });

      // Prepare users data
      final usersData = _rosterData.map((userWithPattern) {
        final user = userWithPattern.user;
        final shifts = userWithPattern.calculatedShifts;

        return {
          'name': user.name,
          'shifts': shifts,
        };
      }).toList();

      print('📄 Exporting PDF:');
      print('   Month: $monthName');
      print('   Days: $daysInMonth');
      print('   Users: ${usersData.length}');

      // Call PDF service
      final pdfBytes = await _pdfService.exportRosterPdf(
        token: token,
        month: monthName,
        daysInMonth: daysInMonth,
        dayNames: dayNames,
        users: usersData,
      );

      // Close loading dialog
      Navigator.pop(context);

      // Show success dialog with options
      final fileName = 'Roster-${monthName.replaceAll(' ', '-')}.pdf';

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'PDF Berhasil Dibuat!',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File: $fileName',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Size: ${(pdfBytes.length / 1024).toStringAsFixed(1)} KB',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await _pdfService.sharePdf(
                    pdfBytes: pdfBytes,
                    fileName: fileName,
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error sharing: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.share),
              label: const Text('Share'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                // Simpan context sebelum operasi async
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);

                try {
                  // Save file BEFORE closing dialog
                  final filePath = await _pdfService.savePdfToDownloads(
                    pdfBytes: pdfBytes,
                    fileName: fileName,
                  );

                  // Close dialog
                  navigator.pop();

                  // Show success snackbar with OPEN button
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: const Text('✓ PDF saved to Downloads'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 5),
                      action: SnackBarAction(
                        label: 'OPEN',
                        textColor: Colors.white,
                        onPressed: () {
                          OpenFile.open(filePath);
                        },
                      ),
                    ),
                  );
                } catch (e) {
                  // Close dialog first if error
                  navigator.pop();

                  // Show error snackbar
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Error saving: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('Save to Downloads'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
