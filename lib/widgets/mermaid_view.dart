import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders a Mermaid diagram locally using a bundled mermaid.min.js asset.
/// The WebView self-reports its rendered height via a JS channel so the widget
/// sizes itself correctly inside a scrolling list.
class MermaidWebView extends StatefulWidget {
  final String code;
  final bool isDark;

  const MermaidWebView({super.key, required this.code, required this.isDark});

  @override
  State<MermaidWebView> createState() => _MermaidWebViewState();
}

class _MermaidWebViewState extends State<MermaidWebView> {
  late final WebViewController _controller;
  double _height = 200; // initial placeholder height
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
          if (h != null && h > 0 && mounted) {
            setState(() {
              _height = h + 16; // a little padding
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
  void didUpdateWidget(MermaidWebView old) {
    super.didUpdateWidget(old);
    // Re-inject if theme or diagram source changed
    if (old.isDark != widget.isDark || old.code != widget.code) {
      _injectDiagram();
    }
  }

  void _injectDiagram() {
    final theme = widget.isDark ? 'dark' : 'default';
    final encodedSource = jsonEncode(widget.code);
    _controller.runJavaScript('renderDiagram($encodedSource, "$theme");');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Stack(
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
