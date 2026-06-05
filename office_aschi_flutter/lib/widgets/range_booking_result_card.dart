import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

/// Card showing the results of a range booking operation.
///
/// Displays summary chips (confirmed, waitlisted, failed counts) and a
/// per-date result list with color-coded status indicators.
class RangeBookingResultCard extends StatelessWidget {
  final RangeBookingResponse result;
  final VoidCallback onDismiss;

  const RangeBookingResultCard({
    super.key,
    required this.result,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with title and dismiss button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Range Booking: ${result.seatLabel}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDismiss,
                  tooltip: 'Dismiss',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Summary chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryChip(
                  label: '${result.confirmedCount} Confirmed',
                  color: Colors.green,
                  isDark: isDark,
                ),
                if (result.waitlistedCount > 0)
                  _SummaryChip(
                    label: '${result.waitlistedCount} Waitlisted',
                    color: Colors.orange,
                    isDark: isDark,
                  ),
                if (result.failedCount > 0)
                  _SummaryChip(
                    label: '${result.failedCount} Skipped',
                    color: Colors.red,
                    isDark: isDark,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Per-date results
            ...result.results.map((r) => _ResultRow(result: r, cs: cs)),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;

  const _SummaryChip({
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final RangeBookingResult result;
  final ColorScheme cs;

  const _ResultRow({required this.result, required this.cs});

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.success;
    final bgColor = isSuccess
        ? Colors.green.withValues(alpha: 0.06)
        : Colors.grey.withValues(alpha: 0.06);

    Color statusColor;
    if (result.status == 'Confirmed') {
      statusColor = Colors.green;
    } else if (result.status == 'Waitlisted') {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.grey;
    }

    // Format date nicely
    String displayDate;
    try {
      final dt = DateTime.parse(result.date);
      displayDate = DateFormat('EEE, MMM d').format(dt);
    } catch (_) {
      displayDate = result.date;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              displayDate,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              result.status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          if (result.error != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.error!,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
