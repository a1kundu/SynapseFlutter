// Stub for non-web platforms. The real implementation is in
// _mermaid_web_renderer_web.dart and is selected via conditional import.
import 'package:flutter/material.dart';

class MermaidWebRenderer extends StatelessWidget {
  final String code;
  final bool isDark;

  const MermaidWebRenderer({
    super.key,
    required this.code,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
