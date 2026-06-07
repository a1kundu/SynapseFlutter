import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Conditional import: on web the real JS-interop renderer is used;
// on native platforms the stub is imported (never actually called).
import '_mermaid_web_renderer.dart'
    if (dart.library.js_interop) '_mermaid_web_renderer_web.dart';

/// Renders a Mermaid diagram.
/// - Web        → dart:js_interop calls bundled mermaid.js → SVG via HtmlElementView
/// - Android/iOS → WebView loads local index.html with bundled mermaid.js
class MermaidView extends StatelessWidget {
  final String code;
  final bool isDark;

  const MermaidView({super.key, required this.code, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return MermaidWebRenderer(code: code, isDark: isDark);
    }
    return _MermaidNativeWebView(code: code, isDark: isDark);
  }
}

// ---------------------------------------------------------------------------
// Native renderer: WebView + bundled mermaid.min.js
// ---------------------------------------------------------------------------

class _MermaidNativeWebView extends StatefulWidget {
  final String code;
  final bool isDark;

  const _MermaidNativeWebView({required this.code, required this.isDark});

  @override
  State<_MermaidNativeWebView> createState() => _MermaidNativeWebViewState();
}

class _MermaidNativeWebViewState extends State<_MermaidNativeWebView> {
  late final WebViewController _controller;
  double _height = 220;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setBackgroundColor(Colors.transparent)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'HeightChannel',
        onMessageReceived: (msg) {
          final h = double.tryParse(msg.message);
          if (h != null && h > 16 && mounted) {
            setState(() {
              _height = h + 24;
              _loaded = true;
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _injectDiagram()),
      )
      ..loadFlutterAsset('assets/mermaid/index.html');
  }

  @override
  void didUpdateWidget(_MermaidNativeWebView old) {
    super.didUpdateWidget(old);
    if (old.isDark != widget.isDark || old.code != widget.code) {
      setState(() => _loaded = false);
      _injectDiagram();
    }
  }

  void _injectDiagram() {
    final theme = widget.isDark ? 'dark' : 'default';
    final encoded = jsonEncode(widget.code);
    _controller.runJavaScript('renderDiagram($encoded, "$theme");');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: _height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller),
          if (!_loaded)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}
