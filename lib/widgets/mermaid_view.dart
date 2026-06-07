import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// Shared cache: the 3.3 MB mermaid.js is read from disk once per app session.
// rootBundle itself also caches, but this avoids even the Future overhead.
String? _mermaidJsCache;

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
              if (mounted) setState(() => _height = h + 16);
            });
          }
        },
      );
    _loadPage();
  }

  @override
  void didUpdateWidget(_MermaidNativeWebView old) {
    super.didUpdateWidget(old);
    if (old.isDark != widget.isDark || old.code != widget.code) {
      if (old.isDark != widget.isDark) {
        _controller.setBackgroundColor(_bgColor);
      }
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    // Inline mermaid.js directly into the HTML so there are no relative-path
    // URL resolution issues on Android (loadFlutterAsset + <script src> is
    // unreliable — mermaid.min.js silently fails to load, leaving window.mermaid
    // undefined and the diagram blank). rootBundle caches after first read.
    _mermaidJsCache ??= await rootBundle.loadString(
      'assets/mermaid/mermaid.min.js',
    );
    if (!mounted) return;

    final bg = widget.isDark ? '#282C34' : '#F5F5F5';
    final theme = widget.isDark ? 'dark' : 'default';
    // jsonEncode produces a valid JS string literal (escapes \n, ", etc.)
    final src = jsonEncode(widget.code);

    final html =
        '<!DOCTYPE html>'
        '<html><head>'
        '<meta charset="UTF-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">'
        '<style>'
        'html,body{margin:0;padding:0;background:$bg;}'
        '#wrap{padding:8px;overflow-x:auto;}'
        '#wrap svg{display:block;}'
        '</style>'
        '<script>${_mermaidJsCache!}</script>'
        '</head><body>'
        '<div id="wrap"></div>'
        '<script>'
        '(function(){'
        'mermaid.initialize({'
        'startOnLoad:false,'
        'theme:"$theme",'
        'securityLevel:"loose",'
        'flowchart:{useMaxWidth:true},'
        'sequence:{useMaxWidth:true}'
        '});'
        'var wrap=document.getElementById("wrap");'
        'var el=document.createElement("div");'
        'el.id="mermaid-diagram";'
        'el.textContent=$src;'
        'wrap.appendChild(el);'
        'mermaid.run({nodes:[el]})'
        '.then(report)'
        '.catch(function(e){wrap.innerHTML="<pre style=\'color:#e06c75;padding:8px\'>"+(e.message||String(e))+"</pre>";report();});'
        'function report(){'
        'requestAnimationFrame(function(){'
        'requestAnimationFrame(function(){'
        'var h=Math.ceil(document.documentElement.scrollHeight);'
        'if(window.HeightChannel&&h>0)HeightChannel.postMessage(String(h));'
        '});});}'
        '})();'
        '</script>'
        '</body></html>';

    _controller.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: WebViewWidget(controller: _controller),
    );
  }
}
