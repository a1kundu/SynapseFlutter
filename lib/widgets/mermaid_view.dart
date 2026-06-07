import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
  double _height = 300;
  bool _pageLoaded = false;

  static const _darkBg = Color(0xFF282C34);
  static const _lightBg = Color(0xFFF5F5F5);

  Color get _bgColor => widget.isDark ? _darkBg : _lightBg;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setBackgroundColor(_bgColor)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..addJavaScriptChannel(
        'HeightChannel',
        onMessageReceived: (msg) {
          final h = double.tryParse(msg.message);
          if (h != null && h > 16) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _height = h + 16);
              }
            });
          }
        },
      )
      ..addJavaScriptChannel(
        'ReadyChannel',
        onMessageReceived: (msg) {
          // mermaid.js is parsed and ready — if the page already finished
          // loading and we haven't rendered yet, inject now.
          // (The JS side also handles pending renders, but this is a safety net.)
          if (_pageLoaded && mounted) {
            _injectDiagram();
          }
        },
      )
      ..addJavaScriptChannel(
        'ErrorChannel',
        onMessageReceived: (msg) {
          debugPrint('[MermaidView] JS error: ${msg.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _pageLoaded = true;
            // Defer one frame so the RenderObject is attached before setState.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _injectDiagram();
            });
          },
        ),
      )
      // loadFlutterAsset sets up WebViewAssetLoader on Android so relative
      // <script src="mermaid.min.js"> resolves correctly from the same dir.
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
    // renderDiagram() in index.html now queues the render if mermaid isn't
    // ready yet, so it's safe to call this early.
    _controller.runJavaScript(
      'setBackground("$bg"); renderDiagram($encoded, "$theme");',
    );
  }

  @override
  void dispose() {
    // WebViewController doesn't have a dispose() method in webview_flutter 4.x,
    // but clearing the page helps release resources.
    _controller.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use screen width as a bounded constraint so the WebView can render
    // inside a horizontal SingleChildScrollView (which gives unbounded width).
    // The HTML has useMaxWidth: true so the diagram fits within this width.
    final screenWidth = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: screenWidth,
      height: _height,
      child: WebViewWidget(
        controller: _controller,
        gestureRecognizers: {
          Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
          Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
        },
      ),
    );
  }
}
