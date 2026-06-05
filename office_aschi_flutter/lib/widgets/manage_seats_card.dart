import 'package:flutter/material.dart';
import '../models/models.dart';
import 'section_card.dart';

/// Reusable manage seats card showing existing seats as chips with delete,
/// and a text field to add new seats.
class ManageSeatsCard extends StatelessWidget {
  final List<SeatResponse> seats;
  final TextEditingController seatLabelController;
  final ValueChanged<SeatResponse> onDeleteSeat;
  final VoidCallback onAddSeat;

  const ManageSeatsCard({
    super.key,
    required this.seats,
    required this.seatLabelController,
    required this.onDeleteSeat,
    required this.onAddSeat,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SectionCard(
      title: 'Seats',
      children: [
        if (seats.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: seats
                .map(
                  (s) => InputChip(
                    label: Text(s.label),
                    labelStyle: TextStyle(color: cs.onSurface),
                    onDeleted: () => onDeleteSeat(s),
                    deleteIconColor: cs.onSurfaceVariant,
                    side: BorderSide(color: cs.outline),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: seatLabelController,
          decoration: InputDecoration(
            hintText: 'e.g. Desk A1',
            labelText: 'New seat label',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: onAddSeat,
              tooltip: 'Add seat',
            ),
          ),
          onSubmitted: (_) => onAddSeat(),
        ),
      ],
    );
  }
}
