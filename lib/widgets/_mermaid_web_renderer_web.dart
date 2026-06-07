// Web-specific Mermaid renderer.
// Uses dart:js_interop to call mermaid.js (loaded in index.html) directly —
// no network, no iframe, no mermaid.ink. The rendered SVG is displayed via
// HtmlElementView so it is a real DOM node inside the Flutter web page.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
// dart:html is deprecated in favour of package:web but is still the easiest
// way to create typed HTMLElement objects for HtmlElementView factories.
// ignore: deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// JS interop declarations for mermaid (global loaded from index.html)
// ---------------------------------------------------------------------------

@JS('mermaid.initialize')
external void _mermaidInit(JSObject config);

@JS('mermaid.render')
external JSPromise<JSObject> _mermaidRender(String id, String code);

extension _MermaidResult on JSObject {
  external String get svg;
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

int _viewCounter = 0;

class MermaidWebRenderer extends StatefulWidget {
  final String code;
  final bool isDark;

  const MermaidWebRenderer({
    super.key,
    required this.code,
    required this.isDark,
  });

  @override
  State<MermaidWebRenderer> createState() => _MermaidWebRendererState();
}

class _MermaidWebRendererState extends State<MermaidWebRenderer> {
  String? _viewType;
  bool _error = false;
  double _height = 200;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(MermaidWebRenderer old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.isDark != widget.isDark) {
      setState(() {
        _viewType = null;
        _error = false;
      });
      _render();
    }
  }

  Future<void> _render() async {
    try {
      final theme = widget.isDark ? 'dark' : 'default';

      _mermaidInit(
        {
              'startOnLoad': false,
              'theme': theme,
              'securityLevel': 'loose',
              'flowchart': {'useMaxWidth': true},
              'sequence': {'useMaxWidth': true},
            }.jsify()!
            as JSObject,
      );

      final renderId = 'mermaid-${_viewCounter++}';
      final result = await _mermaidRender(renderId, widget.code).toDart;
      final svg = result.svg;

      // Parse the intrinsic height from the SVG viewBox attribute.
      // viewBox="minX minY width height"
      double h = 200;
      final vb = RegExp(
        'viewBox=["\']\\s*[\\d.]+\\s+[\\d.]+\\s+[\\d.]+\\s+([\\d.]+)',
      ).firstMatch(svg);
      if (vb != null) {
        h = double.tryParse(vb.group(1)!) ?? h;
      } else {
        // Fall back to explicit height attribute
        final ha = RegExp(r'<svg[^>]+\sheight="([\d.]+)"').firstMatch(svg);
        if (ha != null) h = double.tryParse(ha.group(1)!) ?? h;
      }

      // Each render needs a unique viewType string because
      // registerViewFactory is write-once per type.
      final viewType = 'mermaid-view-${_viewCounter++}';
      final svgContent = svg;

      ui_web.platformViewRegistry.registerViewFactory(viewType, (_) {
        final div = html.DivElement()
          ..style.width = '100%'
          ..style.overflowX = 'auto'
          ..style.overflowY = 'hidden'
          ..style.background = 'transparent'
          ..setInnerHtml(
            svgContent,
            // The SVG is Mermaid-generated — safe to trust.
            // ignore: deprecated_member_use
            treeSanitizer: html.NodeTreeSanitizer.trusted,
          );

        // Make SVG responsive
        final svgEl = div.querySelector('svg');
        if (svgEl != null) {
          svgEl.style.maxWidth = '100%';
          svgEl.style.height = 'auto';
        }
        return div;
      });

      if (mounted) {
        setState(() {
          _viewType = viewType;
          _height = h + 16;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark
        ? const Color(0xFFABB2BF)
        : const Color(0xFF383A42);

    if (_error) {
      // Graceful fallback: show raw source
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          widget.code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: textColor,
          ),
        ),
      );
    }

    if (_viewType == null) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return SizedBox(
      height: _height,
      child: HtmlElementView(viewType: _viewType!),
    );
  }
}
