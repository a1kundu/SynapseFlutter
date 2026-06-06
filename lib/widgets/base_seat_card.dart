import 'package:flutter/material.dart';
import 'seat_card_theme.dart';

/// Shared card shell used by all seat card variants.
///
/// Renders a [Card] with background color, border, border radius, and padding
/// derived from the resolved [SeatCardThemeData]. The theme is obtained by
/// merging (in order of priority):
///
///   1. Defaults resolved from the current [ColorScheme] / [AppColors]
///   2. Ancestor [SeatCardTheme] (if any)
///   3. Per-card [themeOverride] (if provided)
///
/// The [builder] callback receives the [ResolvedSeatCardTheme] so that child
/// widgets (labels, avatars, badges, buttons) can read their styles from the
/// same theme definition rather than hardcoding them.
///
/// ```dart
/// BaseSeatCard(
///   isEngaged: seat.isEngaged,
///   builder: (context, theme) {
///     return Text(seat.label, style: theme.labelStyle);
///   },
/// )
/// ```
class BaseSeatCard extends StatelessWidget {
  const BaseSeatCard({
    super.key,
    required this.isEngaged,
    this.themeOverride,
    required this.builder,
  });

  /// Whether the seat is currently engaged / booked.
  final bool isEngaged;

  /// Optional per-card overrides merged on top of the inherited theme.
  final SeatCardThemeData? themeOverride;

  /// Builder that provides the fully resolved theme to child widgets.
  final Widget Function(BuildContext context, ResolvedSeatCardTheme theme)
      builder;

  @override
  Widget build(BuildContext context) {
    final inherited = SeatCardTheme.of(context);
    final effective = inherited.merge(themeOverride);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolved = effective.resolve(cs, isDark);

    return Card(
      color: resolved.backgroundColor(isEngaged),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(resolved.borderRadius),
        side: BorderSide(
          color: resolved.borderColor(isEngaged),
          width: resolved.borderWidth,
        ),
      ),
      child: Padding(
        padding: resolved.padding,
        child: builder(context, resolved),
      ),
    );
  }
}
