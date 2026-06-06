import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'section_card.dart';

const _boldTitle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16);

/// Builds the outlined card shape using the current [ColorScheme].
ShapeBorder _outlinedShapeWith(ColorScheme cs) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  side: BorderSide(color: cs.outlineVariant, width: 0.5),
);

/// Reusable waitlist card showing queued booking requests.
///
/// Replicates the Angular "waitlist-info" card: numbered entries with
/// avatar, name, desired seat, waitlisted-since timestamp, and a cancel
/// button per entry.
class WaitlistCard extends StatelessWidget {
  final List<WaitlistInfo> waitlist;
  final void Function(WaitlistInfo entry)? onCancel;

  const WaitlistCard({super.key, required this.waitlist, this.onCancel});

  String _formatSince(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('MMM d, h:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SectionCard(
      title: 'Waitlist',
      titleStyle: _boldTitle,
      outerPadding: EdgeInsets.zero,
      shape: _outlinedShapeWith(cs),
      children: [
        const SizedBox(height: 8),
        ...waitlist.asMap().entries.map((entry) {
          final i = entry.key;
          final w = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                // Orange avatar matching Angular's bgColor="orange"
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.orange.shade100,
                  child: Text(
                    w.reporteeName.isNotEmpty
                        ? w.reporteeName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Name + desired seat + since
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${i + 1} — ${w.reporteeName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Waiting for ${w.desiredSeatLabel} · since ${_formatSince(w.waitlistedSince)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Cancel button
                if (onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => onCancel!(w),
                    tooltip: 'Cancel waitlist entry',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Card shown when all seats are booked (availableCount == 0 && totalSeats > 0).
///
/// Replicates the Angular "waitlist-section": lists all booked seats with
/// the person currently holding them and a "Wait for it" button to join the
/// waitlist for that seat.
class AllSeatsBookedCard extends StatelessWidget {
  final List<BookingResponse> bookedSeats;
  final void Function(int seatId, String seatLabel) onWaitlist;

  const AllSeatsBookedCard({
    super.key,
    required this.bookedSeats,
    required this.onWaitlist,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SectionCard(
      title: 'All Seats Booked',
      titleStyle: _boldTitle,
      outerPadding: EdgeInsets.zero,
      shape: _outlinedShapeWith(cs),
      children: [
        const SizedBox(height: 4),
        Text(
          'Every seat is taken for this date. You can join the waitlist for any seat below.',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 700
                ? 3
                : constraints.maxWidth > 450
                ? 2
                : 1;
            if (crossAxisCount > 1) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                ),
                itemCount: bookedSeats.length,
                itemBuilder: (context, index) =>
                    _buildBookedSeatTile(bookedSeats[index], cs, isDark),
              );
            }
            return Column(
              children: bookedSeats
                  .map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildBookedSeatTile(b, cs, isDark),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBookedSeatTile(BookingResponse b, ColorScheme cs, bool isDark) {
    return Card(
      color: isDark
          ? cs.primaryContainer.withValues(alpha: 0.4)
          : cs.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.primary, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              b.seatLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.teal,
                  child: Text(
                    b.reporteeName.isNotEmpty
                        ? b.reporteeName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    b.reporteeName,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onWaitlist(b.seatId, b.seatLabel),
                icon: const Icon(Icons.schedule, size: 16),
                label: const Text('Wait for it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
