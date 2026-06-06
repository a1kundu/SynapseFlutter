import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Reusable date navigator with left/right arrows, day display, and
/// optional "Today" button. Used in bookings tab and seat search.
class DateNavigator extends StatelessWidget {
  final DateTime selectedDate;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback? onToday;
  final ValueChanged<DateTime> onDatePicked;

  const DateNavigator({
    super.key,
    required this.selectedDate,
    required this.onPreviousDay,
    required this.onNextDay,
    this.onToday,
    required this.onDatePicked,
  });

  bool get _isToday =>
      DateFormat('yyyy-MM-dd').format(selectedDate) ==
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -300) {
          onNextDay();
        } else if (details.primaryVelocity! > 300) {
          onPreviousDay();
        }
      },
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPreviousDay,
                icon: Icon(Icons.chevron_left, size: 32, color: cs.onSurface),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      onDatePicked(picked);
                    }
                  },
                  child: Column(
                    children: [
                      Text(
                        '${selectedDate.day}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${DateFormat('MMMM').format(selectedDate)} ${selectedDate.year}',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE').format(selectedDate),
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: onNextDay,
                icon: Icon(Icons.chevron_right, size: 32, color: cs.onSurface),
              ),
            ],
          ),
          if (!_isToday && onToday != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: onToday,
                icon: const Icon(Icons.today, size: 18),
                label: const Text('Today'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact date selector row (used in seat search screen).
class DateSelectorRow extends StatelessWidget {
  final DateTime selectedDate;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback onTap;

  const DateSelectorRow({
    super.key,
    required this.selectedDate,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPreviousDay,
        ),
        GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Text(
                DateFormat('d').format(selectedDate),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                DateFormat('MMM yyyy').format(selectedDate),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                DateFormat('EEEE').format(selectedDate),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNextDay),
      ],
    );
  }
}
