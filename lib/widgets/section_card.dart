import 'package:flutter/material.dart';

/// Common card shell used by section-style cards across the app.
///
/// Provides the shared structure: outer padding → [Card] → inner padding →
/// a column with an optional section header and arbitrary [children].
class SectionCard extends StatelessWidget {
  /// Section title displayed at the top of the card (e.g. "Seats", "Members").
  final String? title;

  /// Override the default title style (labelLarge + onSurfaceVariant).
  final TextStyle? titleStyle;

  /// Widgets rendered below the title inside the card.
  final List<Widget> children;

  /// Padding applied inside the card. Defaults to 16 on all sides.
  final EdgeInsetsGeometry contentPadding;

  /// Padding around the card. Defaults to horizontal 16.
  final EdgeInsetsGeometry outerPadding;

  /// Optional card background colour.
  final Color? cardColor;

  /// Optional card shape override.
  final ShapeBorder? shape;

  const SectionCard({
    super.key,
    this.title,
    this.titleStyle,
    required this.children,
    this.contentPadding = const EdgeInsets.all(16),
    this.outerPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.cardColor,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zeroPadding = contentPadding == EdgeInsets.zero;

    final effectiveTitleStyle =
        titleStyle ??
        Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant);

    return Padding(
      padding: outerPadding,
      child: Card(
        color: cardColor,
        shape: shape,
        child: Padding(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: zeroPadding
                      ? const EdgeInsets.fromLTRB(16, 16, 16, 4)
                      : EdgeInsets.zero,
                  child: Text(title!, style: effectiveTitleStyle),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
