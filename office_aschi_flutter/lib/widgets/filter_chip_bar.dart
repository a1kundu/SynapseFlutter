import 'package:flutter/material.dart';

/// Reusable filter chip bar used in seat search and similar filter UIs.
class FilterChipBar<T> extends StatelessWidget {
  final List<FilterChipItem<T>> items;
  final T activeFilter;
  final ValueChanged<T> onSelected;

  const FilterChipBar({
    super.key,
    required this.items,
    required this.activeFilter,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: items
          .expand((item) => [
                FilterChip(
                  label: Text(
                    item.label,
                    style: TextStyle(
                      color: activeFilter == item.value
                          ? cs.onPrimary
                          : cs.onSurface,
                    ),
                  ),
                  selected: activeFilter == item.value,
                  onSelected: (_) => onSelected(item.value),
                  selectedColor: cs.primary,
                  checkmarkColor: cs.onPrimary,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
                const SizedBox(width: 8),
              ])
          .toList()
        ..removeLast(), // remove trailing SizedBox
    );
  }
}

/// Data class for filter chip items.
class FilterChipItem<T> {
  final String label;
  final T value;

  const FilterChipItem({required this.label, required this.value});
}
