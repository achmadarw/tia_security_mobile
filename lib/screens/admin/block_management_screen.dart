import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/block_service.dart';
import '../../models/block.dart';
import 'block_form_screen.dart';

class BlockManagementScreen extends StatefulWidget {
  final AuthService authService;

  const BlockManagementScreen({super.key, required this.authService});

  @override
  State<BlockManagementScreen> createState() => _BlockManagementScreenState();
}

class _BlockManagementScreenState extends State<BlockManagementScreen> {
  final BlockService _blockService = BlockService();
  List<Block> _blocks = [];
  List<Block> _filteredBlocks = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _filterStatus = 'all'; // 'all', 'active', 'inactive'

  @override
  void initState() {
    super.initState();
    _loadBlocks();
  }

  Future<void> _loadBlocks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final blocks = await _blockService.getBlocks();
      setState(() {
        _blocks = blocks;
        _filterBlocks();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      print('[BlockManagement] Error loading blocks: $e');
    }
  }

  void _filterBlocks() {
    List<Block> filtered = _blocks;

    // Apply status filter
    if (_filterStatus != 'all') {
      filtered = filtered
          .where((block) => block.status.toLowerCase() == _filterStatus)
          .toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((block) {
        return block.name.toLowerCase().contains(query) ||
            (block.description?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    setState(() {
      _filteredBlocks = filtered;
    });
  }

  Future<void> _deleteBlock(Block block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Blok?'),
        content: Text(
          'Apakah Anda yakin ingin menghapus blok "${block.name}"?\n\nTindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('BATAL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );

    if (confirmed == true && block.id != null) {
      try {
        await _blockService.deleteBlock(block.id!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blok "${block.name}" berhasil dihapus'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadBlocks();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus blok: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleBlockActive(Block block) async {
    if (block.id == null) return;

    try {
      await _blockService.toggleBlockStatus(block);
      final newStatus = block.isActive ? 'nonaktif' : 'aktif';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Blok "${block.name}" berhasil di$newStatus kan'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadBlocks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengubah status: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final activeCount = _blocks.where((b) => b.isActive).length;
    final inactiveCount = _blocks.where((b) => !b.isActive).length;

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
                    : _buildBlocksList(isDark),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BlockFormScreen(
                authService: widget.authService,
              ),
            ),
          );

          if (result == true) {
            _loadBlocks();
          }
        },
        icon: const Icon(Icons.add, size: 24),
        label: const Text(
          'TAMBAH BLOK',
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
                  'Manajemen Blok',
                  style: TextStyle(
                    color: isDark ? AppColors.darkTextPrimary : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_filteredBlocks.length} dari ${_blocks.length} blok',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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
              Icons.location_city,
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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'Aktif',
            activeCount,
            Icons.check_circle,
            isDark ? AppColors.successDark : AppColors.success,
            isDark,
          ),
          Container(
            width: 1,
            height: 40,
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
          _buildStatItem(
            'Nonaktif',
            inactiveCount,
            Icons.cancel,
            isDark ? AppColors.errorDark : AppColors.error,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, int count, IconData icon, Color color, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchAndFilter(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Search bar
          Container(
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
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _filterBlocks();
                });
              },
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'Cari nama blok...',
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
                            _filterBlocks();
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
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Semua', 'all', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Aktif', 'active', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Nonaktif', 'inactive', isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final isSelected = _filterStatus == value;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? (isDark ? Colors.black : Colors.white)
              : (isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary),
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = value;
          _filterBlocks();
        });
      },
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      selectedColor: primaryColor,
      checkmarkColor: isDark ? Colors.black : Colors.white,
      side: BorderSide(
        color: isSelected
            ? primaryColor
            : (isDark ? AppColors.borderDark : AppColors.borderLight),
        width: isSelected ? 1.5 : 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      elevation: isSelected ? 2 : 0,
      shadowColor: primaryColor.withOpacity(0.3),
    );
  }

  Widget _buildBlocksList(bool isDark) {
    if (_filteredBlocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 80,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _filterStatus != 'all'
                  ? 'Tidak ada blok yang cocok'
                  : 'Belum ada blok',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _filterStatus != 'all'
                  ? 'Coba ubah filter atau pencarian'
                  : 'Tambahkan blok pertama Anda',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBlocks,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredBlocks.length,
        itemBuilder: (context, index) {
          final block = _filteredBlocks[index];
          return _buildBlockCard(block, isDark);
        },
      ),
    );
  }

  Widget _buildBlockCard(Block block, bool isDark) {
    final statusColor = block.isActive
        ? (isDark ? AppColors.successDark : AppColors.success)
        : (isDark ? AppColors.errorDark : AppColors.error);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Color indicator bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: statusColor,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Block name and status
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            block.name,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                block.isActive
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                block.isActive ? 'Aktif' : 'Nonaktif',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Coordinates
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            block.coordinatesText,
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Description
                    if (block.description != null &&
                        block.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        block.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Menu button
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BlockFormScreen(
                        authService: widget.authService,
                        block: block,
                      ),
                    ),
                  );

                  if (result == true) {
                    _loadBlocks();
                  }
                } else if (value == 'delete') {
                  _deleteBlock(block);
                } else if (value == 'toggle') {
                  _toggleBlockActive(block);
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
                        block.isActive
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(block.isActive ? 'Nonaktifkan' : 'Aktifkan'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Hapus', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color:
                isDark ? AppColors.darkPrimary : Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Memuat blok...',
            style: TextStyle(
              fontSize: 16,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: isDark ? AppColors.errorDark : AppColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Gagal memuat data',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error ?? 'Terjadi kesalahan',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadBlocks,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}
