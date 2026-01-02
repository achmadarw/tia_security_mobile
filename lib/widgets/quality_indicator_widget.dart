import 'package:flutter/material.dart';

/// Quality Indicator Widget
///
/// Shows real-time image quality score with color-coded feedback
/// and user guidance messages.
///
/// Usage:
/// ```dart
/// QualityIndicatorWidget(
///   qualityScore: 85.5,
///   checks: {
///     'brightness': true,
///     'blur': true,
///     'contrast': true,
///     'pose': false,
///   },
/// )
/// ```
class QualityIndicatorWidget extends StatelessWidget {
  final double qualityScore; // 0-100
  final Map<String, bool>? checks;
  final bool showDetails;

  const QualityIndicatorWidget({
    Key? key,
    required this.qualityScore,
    this.checks,
    this.showDetails = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = _getColorForScore(qualityScore);
    final statusText = _getStatusText(qualityScore);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score and status
          Row(
            children: [
              Icon(
                _getIconForScore(qualityScore),
                color: color,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      'Kualitas: ${qualityScore.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              // Progress circle
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: qualityScore / 100,
                      strokeWidth: 6,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                    Text(
                      '${qualityScore.toInt()}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Details (if enabled)
          if (showDetails && checks != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _buildChecksList(checks!),
          ],

          // Guidance message
          if (qualityScore < 70) ...[
            const SizedBox(height: 12),
            _buildGuidanceMessage(checks),
          ],
        ],
      ),
    );
  }

  Widget _buildChecksList(Map<String, bool> checks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: checks.entries.map((entry) {
        final checkName = _getCheckDisplayName(entry.key);
        final isPassed = entry.value;
        final icon = isPassed ? Icons.check_circle : Icons.cancel;
        final color = isPassed ? Colors.green : Colors.red;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                checkName,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGuidanceMessage(Map<String, bool>? checks) {
    String message = 'Tingkatkan kualitas foto:';

    if (checks != null) {
      final failedChecks =
          checks.entries.where((e) => !e.value).map((e) => e.key).toList();

      if (failedChecks.contains('brightness')) {
        message = '💡 Coba di tempat yang lebih terang';
      } else if (failedChecks.contains('blur')) {
        message = '📸 Pegang kamera dengan stabil';
      } else if (failedChecks.contains('contrast')) {
        message = '🎨 Gunakan latar belakang yang berbeda';
      } else if (failedChecks.contains('pose')) {
        message = '👤 Hadap langsung ke kamera';
      } else if (failedChecks.contains('size')) {
        message = '📏 Dekatkan kamera ke wajah';
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForScore(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  IconData _getIconForScore(double score) {
    if (score >= 80) return Icons.check_circle;
    if (score >= 60) return Icons.warning;
    return Icons.error;
  }

  String _getStatusText(double score) {
    if (score >= 80) return 'Kualitas Baik';
    if (score >= 60) return 'Kualitas Cukup';
    return 'Kualitas Kurang';
  }

  String _getCheckDisplayName(String checkKey) {
    switch (checkKey) {
      case 'brightness':
        return 'Pencahayaan';
      case 'blur':
        return 'Ketajaman';
      case 'contrast':
        return 'Kontras';
      case 'pose':
        return 'Posisi Wajah';
      case 'size':
        return 'Ukuran Wajah';
      default:
        return checkKey;
    }
  }
}

/// Simple Quality Badge Widget
///
/// Compact version for showing quality score only
class QualityBadge extends StatelessWidget {
  final double qualityScore;
  final bool showLabel;

  const QualityBadge({
    Key? key,
    required this.qualityScore,
    this.showLabel = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = _getColorForScore(qualityScore);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIconForScore(qualityScore),
            color: Colors.white,
            size: 16,
          ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              '${qualityScore.toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getColorForScore(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  IconData _getIconForScore(double score) {
    if (score >= 80) return Icons.check_circle;
    if (score >= 60) return Icons.warning;
    return Icons.error;
  }
}

/// Real-time Quality Indicator (for camera preview)
///
/// Shows live quality feedback during camera capture
class RealtimeQualityIndicator extends StatelessWidget {
  final double qualityScore;
  final bool isProcessing;

  const RealtimeQualityIndicator({
    Key? key,
    required this.qualityScore,
    this.isProcessing = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Memproses...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final color = _getColorForScore(qualityScore);
    final icon = _getIconForScore(qualityScore);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            '${qualityScore.toInt()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForScore(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  IconData _getIconForScore(double score) {
    if (score >= 80) return Icons.check_circle;
    if (score >= 60) return Icons.warning;
    return Icons.error;
  }
}
