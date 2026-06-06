import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/models.dart';

/// Reusable availability stats chips showing booked, available, waitlisted,
/// and total seat counts.
class AvailabilityStats extends StatelessWidget {
  final AvailabilityResponse? availability;

  const AvailabilityStats({super.key, this.availability});

  @override
  Widget build(BuildContext context) {
    final a = availability;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Wrap(
      spacing: 8,
      children: [
        Chip(
          label: Text('${a?.bookedCount ?? 0} booked'),
          backgroundColor: cs.primaryContainer,
          labelStyle: TextStyle(color: cs.onPrimaryContainer),
          side: BorderSide.none,
        ),
        Chip(
          label: Text('${a?.availableCount ?? 0} available'),
          backgroundColor: AppColors.greenContainer(isDark),
          labelStyle: TextStyle(color: AppColors.greenText(isDark)),
          side: BorderSide.none,
        ),
        if ((a?.waitlistedCount ?? 0) > 0)
          Chip(
            label: Text('${a!.waitlistedCount} waitlisted'),
            backgroundColor: cs.tertiaryContainer,
            labelStyle: TextStyle(color: cs.onTertiaryContainer),
            side: BorderSide.none,
          ),
        Chip(
          label: Text('${a?.totalSeats ?? 0} total'),
          backgroundColor: cs.surfaceContainerHighest,
          labelStyle: TextStyle(color: cs.onSurfaceVariant),
          side: BorderSide.none,
        ),
      ],
    );
  }
}
