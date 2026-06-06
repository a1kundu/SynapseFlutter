import 'package:flutter/material.dart';
import 'section_card.dart';

/// Reusable danger zone card for destructive actions like team deletion.
class DangerZoneCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData icon;

  const DangerZoneCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.actionLabel = 'Delete',
    required this.onAction,
    this.icon = Icons.delete_forever,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SectionCard(
      cardColor: cs.errorContainer,
      contentPadding: EdgeInsets.zero,
      children: [
        ListTile(
          leading: Icon(icon, color: cs.onErrorContainer),
          title: Text(title, style: TextStyle(color: cs.onErrorContainer)),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: cs.onErrorContainer.withValues(alpha: 0.8)),
          ),
          trailing: TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: cs.onErrorContainer),
            child: Text(actionLabel),
          ),
        ),
      ],
    );
  }
}
