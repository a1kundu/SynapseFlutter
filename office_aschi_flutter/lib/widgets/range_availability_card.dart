import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_service.dart';

/// Card showing range availability using Material 3 design patterns.
///
/// Displays days grouped by month with circular occupancy indicators,
/// using M3 color tokens for status. Tapping a day cell calls
/// [onJumpToDate] to navigate to single-day view.
class RangeAvailabilityCard extends StatelessWidget {
  final RangeAvailabilityResponse? rangeAvailability;
  final bool loading;
  final DateTime rangeFrom;
  final DateTime rangeTo;
  final DateTime selectedDate;
  final void Function(DateTime from, DateTime to) onRangeChanged;
  final ValueChanged<String> onJumpToDate;

  const RangeAvailabilityCard({
    super.key,
    required this.rangeAvailability,
    required this.loading,
    required this.rangeFrom,
    required this.rangeTo,
    required this.selectedDate,
    required this.onRangeChanged,
    required this.onJumpToDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(Icons.date_range, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Range Availability',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Date range picker chip
            Center(
              child: _DateRangeChip(
                rangeFrom: rangeFrom,
                rangeTo: rangeTo,
                onTap: () => _pickRange(context),
              ),
            ),
            const SizedBox(height: 16),
            // Content
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rangeAvailability != null)
              _DayGrid(
                days: rangeAvailability!.days,
                selectedDate: selectedDate,
                onJumpToDate: onJumpToDate,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: rangeFrom, end: rangeTo),
    );
    if (range != null) {
      final days = range.end.difference(range.start).inDays + 1;
      if (days > 90) {
        if (context.mounted) {
          showRootSnackBar(
            const SnackBar(content: Text('Date range cannot exceed 90 days')),
          );
        }
        return;
      }
      onRangeChanged(range.start, range.end);
    }
  }
}

// ---------------------------------------------------------------------------
// Date range selector chip
// ---------------------------------------------------------------------------

class _DateRangeChip extends StatelessWidget {
  final DateTime rangeFrom;
  final DateTime rangeTo;
  final VoidCallback onTap;

  const _DateRangeChip({
    required this.rangeFrom,
    required this.rangeTo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final days = rangeTo.difference(rangeFrom).inDays + 1;

    // Use input-field styling for proper light/dark contrast.
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                '${DateFormat('MMM d').format(rangeFrom)} – '
                '${DateFormat('MMM d, y').format(rangeTo)}',
                style: tt.bodyMedium,
              ),
              const SizedBox(width: 8),
              Text(
                '($days days)',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day grid with month group headers
// ---------------------------------------------------------------------------

class _DayGrid extends StatelessWidget {
  final List<DateAvailabilitySummary> days;
  final DateTime selectedDate;
  final ValueChanged<String> onJumpToDate;

  const _DayGrid({
    required this.days,
    required this.selectedDate,
    required this.onJumpToDate,
  });

  @override
  Widget build(BuildContext context) {
    // Group days by month
    final groups = <String, List<DateAvailabilitySummary>>{};
    for (final day in days) {
      final dt = DateTime.parse(day.date);
      final key = DateFormat('MMMM y').format(dt);
      groups.putIfAbsent(key, () => []).add(day);
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend row
        _Legend(cs: cs, isDark: isDark),
        const SizedBox(height: 12),
        // Month groups
        for (final entry in groups.entries) ...[
          // Month label
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              entry.key,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: cs.primary),
            ),
          ),
          // Day chips in a wrap
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: entry.value.map((day) {
              return _DayChip(
                day: day,
                isDark: isDark,
                cs: cs,
                isSelected: _isSameDay(DateTime.parse(day.date), selectedDate),
                onTap: () => onJumpToDate(day.date),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Legend
// ---------------------------------------------------------------------------

class _Legend extends StatelessWidget {
  final ColorScheme cs;
  final bool isDark;

  const _Legend({required this.cs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendDot(
          color: AppColors.greenBorder(isDark),
          label: 'Available',
          cs: cs,
        ),
        const SizedBox(width: 16),
        _LegendDot(color: cs.error, label: 'Full', cs: cs),
        const SizedBox(width: 16),
        _LegendDot(
          color: cs.onSurface.withValues(alpha: 0.25),
          label: 'Weekend',
          cs: cs,
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final ColorScheme cs;

  const _LegendDot({
    required this.color,
    required this.label,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Individual day chip with circular occupancy indicator
// ---------------------------------------------------------------------------

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DayChip extends StatelessWidget {
  final DateAvailabilitySummary day;
  final bool isDark;
  final ColorScheme cs;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayChip({
    required this.day,
    required this.isDark,
    required this.cs,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.parse(day.date);
    final isWeekend =
        dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
    final isFull = day.availableCount == 0 && day.totalSeats > 0;
    final hasAvailability = day.availableCount > 0;
    final fillPct = day.totalSeats > 0
        ? (day.bookedCount / day.totalSeats)
        : 0.0;

    // M3-native color mapping
    Color ringColor;
    Color bgColor;
    if (isFull) {
      ringColor = cs.error;
      bgColor = cs.errorContainer.withValues(alpha: isDark ? 0.3 : 0.5);
    } else if (hasAvailability) {
      ringColor = AppColors.greenBorder(isDark);
      bgColor = AppColors.greenContainer(
        isDark,
      ).withValues(alpha: isDark ? 0.3 : 0.5);
    } else {
      ringColor = cs.outlineVariant;
      bgColor = cs.surfaceContainerHighest;
    }

    final dayLabel = DateFormat('E').format(dt);

    return Tooltip(
      message: '${day.bookedCount} booked, ${day.availableCount} available',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Opacity(
            opacity: isWeekend ? 0.45 : 1.0,
            child: Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? cs.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day of week abbreviation
                  Text(
                    dayLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Circular occupancy ring with day number
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: fillPct,
                          strokeWidth: 3,
                          backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(ringColor),
                        ),
                        Text(
                          '${dt.day}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Available / total
                  Text(
                    '${day.availableCount}/${day.totalSeats}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
