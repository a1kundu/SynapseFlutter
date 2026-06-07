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

  // Background colours matching the code-block container in chat_screen.dart.
  // An opaque background is required on Android — transparent WebViews are
  // unreliable and often render as blank.
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
            // addPostFrameCallback avoids calling setState before the first
            // frame is committed, which would trigger _owner != null crash.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _height = h + 24;
                  _loaded = true;
                });
              }
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            // Defer until after the current frame so the RenderObject
            // is guaranteed to be attached before any setState fires.
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
      setState(() => _loaded = false);
      // Re-apply background colour if theme changed.
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
    // Set background first so there's no flash of wrong colour.
    _controller.runJavaScript(
      'setBackground("$bg"); renderDiagram($encoded, "$theme");',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use a plain SizedBox — AnimatedContainer animates through intermediate
    // heights including zero, which causes WebViewWidget layout errors.
    // StackFit.loose (default) is used so WebViewWidget gets bounded
    // constraints even at the initial height.
    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
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
