import 'package:flutter/material.dart';
import '../models/models.dart';
import 'base_seat_card.dart';
import 'seat_card_theme.dart';

/// Seat card used in the **team detail bookings** tab.
///
/// Shows a seat's label, booking status, and either the booked person's
/// info or a "Book" button for available seats.
///
/// All visual properties (background, border, avatar, button, label) are
/// read from the [ResolvedSeatCardTheme] provided by [BaseSeatCard].
/// Override them per-card via [themeOverride] or for an entire subtree
/// via an ancestor [SeatCardTheme].
class SeatBookingCard extends StatelessWidget {
  final SeatView seat;
  final VoidCallback? onBook;
  final VoidCallback? onCancel;
  final SeatCardThemeData? themeOverride;

  const SeatBookingCard({
    super.key,
    required this.seat,
    this.onBook,
    this.onCancel,
    this.themeOverride,
  });

  @override
  Widget build(BuildContext context) {
    final isBooked = seat.status == 'booked';

    return BaseSeatCard(
      isEngaged: isBooked,
      themeOverride: themeOverride,
      builder: (context, theme) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Header row: label + optional cancel button --
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(seat.label, style: theme.labelStyle),
                ),
                if (isBooked && onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onCancel,
                    tooltip: 'Cancel booking',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            // -- Body: person info or book button --
            if (isBooked)
              Row(
                children: [
                  CircleAvatar(
                    radius: theme.avatarRadius,
                    backgroundColor: theme.avatarBackgroundColor,
                    child: Text(
                      seat.personName.isNotEmpty
                          ? seat.personName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: theme.avatarForegroundColor,
                        fontSize: theme.avatarRadius - 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      seat.personName,
                      style: theme.personNameStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onBook,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.buttonBackgroundColor,
                    foregroundColor: theme.buttonForegroundColor,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 4),
                      Text('Book'),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Seat card used in the **cross-team seat search** screen.
///
/// Shows seat label, team name, engaged/vacant status badge, and the
/// engaged person's info. All visual tokens come from the resolved theme.
class SeatOverviewCard extends StatelessWidget {
  final SeatOverviewResponse seat;
  final SeatCardThemeData? themeOverride;

  const SeatOverviewCard({
    super.key,
    required this.seat,
    this.themeOverride,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BaseSeatCard(
      isEngaged: seat.isEngaged,
      themeOverride: themeOverride,
      builder: (context, theme) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Header row: label + status badge --
            Row(
              children: [
                Expanded(
                  child: Text(
                    seat.label,
                    style: theme.labelStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.badgeColor(seat.isEngaged),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    seat.isEngaged ? 'Engaged' : 'Vacant',
                    style: theme.badgeTextStyle.copyWith(
                      color: theme.badgeTextColor(seat.isEngaged),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // -- Team name --
            Text(
              seat.teamName,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            // -- Engaged person info --
            if (seat.isEngaged && seat.engagedBy != null)
              Row(
                children: [
                  CircleAvatar(
                    radius: theme.avatarRadius,
                    backgroundColor: theme.avatarBackgroundColor,
                    child: Text(
                      seat.engagedBy!.reporteeName[0].toUpperCase(),
                      style: TextStyle(
                        color: theme.avatarForegroundColor,
                        fontSize: theme.avatarRadius - 1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      seat.engagedBy!.reporteeName,
                      style: theme.personNameStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
