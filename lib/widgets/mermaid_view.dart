import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders a Mermaid diagram.
/// - Web platform  → mermaid.ink (already in a browser, no nested WebView)
/// - Android / iOS → locally via bundled mermaid.min.js (no network needed)
class MermaidView extends StatelessWidget {
  final String code;
  final bool isDark;

  const MermaidView({super.key, required this.code, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _MermaidInkImage(code: code, isDark: isDark);
    }
    return _MermaidNativeWebView(code: code, isDark: isDark);
  }
}

// ---------------------------------------------------------------------------
// Web fallback: mermaid.ink image
// ---------------------------------------------------------------------------

class _MermaidInkImage extends StatelessWidget {
  final String code;
  final bool isDark;

  const _MermaidInkImage({required this.code, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final src = isDark ? '%%{init: {"theme":"dark"}}%%\n$code' : code;
    final url = 'https://mermaid.ink/img/${base64Url.encode(utf8.encode(src))}';
    final textColor = isDark
        ? const Color(0xFFABB2BF)
        : const Color(0xFF383A42);

    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, _, __) => Padding(
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: textColor,
          ),
        ),
      ),
    );
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
