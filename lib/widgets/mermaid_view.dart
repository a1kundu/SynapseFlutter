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
  // Start at a generous height so the WebView has room to render Mermaid
  // at its natural size before HeightChannel reports back.
  double _height = 400;

  static const _darkBg = Color(0xFF282C34);
  static const _lightBg = Color(0xFFF5F5F5);

  Color get _bgColor => widget.isDark ? _darkBg : _lightBg;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setBackgroundColor(_bgColor)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'HeightChannel',
        onMessageReceived: (msg) {
          final h = double.tryParse(msg.message);
          if (h != null && h > 16) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _height = h + 24);
              }
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _injectDiagram();
            });
          },
        ),
      )
      ..loadFlutterAsset('assets/mermaid/index.html');
  }

  @override
  void didUpdateWidget(_MermaidNativeWebView old) {
    super.didUpdateWidget(old);
    if (old.isDark != widget.isDark || old.code != widget.code) {
      if (old.isDark != widget.isDark) {
        _controller.setBackgroundColor(_bgColor);
      }
      _injectDiagram();
    }
  }

  void _injectDiagram() {
    final bg = widget.isDark ? '#282C34' : '#F5F5F5';
    final theme = widget.isDark ? 'dark' : 'default';
    final encoded = jsonEncode(widget.code);
    _controller.runJavaScript(
      'setBackground("$bg"); renderDiagram($encoded, "$theme");',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: WebViewWidget(controller: _controller),
    );
  }
}
