import 'package:flutter/material.dart';

/// Reusable icon box used in settings list tiles.
class IconBox extends StatelessWidget {
  final IconData icon;
  final ColorScheme? colorScheme;

  const IconBox({super.key, required this.icon, this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: cs.onPrimary, size: 22),
    );
  }
}
