import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// Result of a web crawl operation.
class CrawlResult {
  final String url;
  final String title;
  final String content;
  final int statusCode;
  final String? error;

  CrawlResult({
    required this.url,
    this.title = '',
    this.content = '',
    this.statusCode = 0,
    this.error,
  });

  bool get isSuccess => error == null && statusCode >= 200 && statusCode < 400;

  @override
  String toString() {
    if (error != null) return 'Error crawling $url: $error';
    final buf = StringBuffer();
    if (title.isNotEmpty) buf.writeln('Title: $title\n');
    buf.write(content);
    return buf.toString();
  }
}

/// Fetches web pages and extracts readable text content.
class WebCrawler {
  static const _maxContentLength = 50 * 1024; // 50 KB text cap
  static const _timeout = Duration(seconds: 15);
  static const _maxRedirects = 5;
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  /// Crawl a URL and return extracted text content.
  static Future<CrawlResult> crawl(
    String url, {
    bool includeLinks = false,
  }) async {
    // Validate and normalize URL.
    Uri uri;
    try {
      uri = Uri.parse(url);
      if (!uri.hasScheme) uri = Uri.parse('https://$url');
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return CrawlResult(
          url: url,
          error: 'Only HTTP and HTTPS URLs are supported.',
        );
      }
    } catch (e) {
      return CrawlResult(url: url, error: 'Invalid URL: $e');
    }

    // Fetch with redirect following.
    http.Response response;
    try {
      response = await _fetchWithRedirects(uri);
    } catch (e) {
      return CrawlResult(url: url, error: 'Request failed: $e');
    }

    if (response.statusCode >= 400) {
      return CrawlResult(
        url: uri.toString(),
        statusCode: response.statusCode,
        error: 'HTTP ${response.statusCode}',
      );
    }

    // Determine content type.
    final contentType =
        response.headers['content-type']?.toLowerCase() ?? 'text/html';

    // If plain text or JSON, return directly.
    if (contentType.contains('application/json')) {
      final text = _truncate(response.body);
      return CrawlResult(
        url: uri.toString(),
        statusCode: response.statusCode,
        title: 'JSON Response',
        content: text,
      );
    }
    if (contentType.contains('text/plain')) {
      final text = _truncate(response.body);
      return CrawlResult(
        url: uri.toString(),
        statusCode: response.statusCode,
        content: text,
      );
    }

    // Parse HTML.
    final document = html_parser.parse(response.body);

    // Extract title.
    final title = document.querySelector('title')?.text.trim() ?? '';

    // Remove non-content elements.
    _removeElements(document, [
      'script',
      'style',
      'noscript',
      'iframe',
      'svg',
      'canvas',
      'nav',
      'footer',
      'header',
      'aside',
      'form',
      'button',
      'input',
      'select',
      'textarea',
      'menu',
      'menuitem',
    ]);

    // Remove elements by common non-content class/id patterns.
    _removeBySelector(document, [
      '[class*="cookie"]',
      '[class*="banner"]',
      '[class*="popup"]',
      '[class*="modal"]',
      '[class*="sidebar"]',
      '[class*="advertisement"]',
      '[class*="ad-"]',
      '[id*="cookie"]',
      '[id*="banner"]',
      '[id*="popup"]',
      '[id*="modal"]',
      '[id*="sidebar"]',
      '[id*="advertisement"]',
    ]);

    // Try to find main content area first.
    String text;
    final mainContent = document.querySelector('main') ??
        document.querySelector('article') ??
        document.querySelector('[role="main"]') ??
        document.querySelector('.content') ??
        document.querySelector('#content');

    if (mainContent != null) {
      text = _extractText(mainContent, includeLinks: includeLinks);
    } else {
      final body = document.body;
      text = body != null
          ? _extractText(body, includeLinks: includeLinks)
          : document.documentElement != null
              ? _extractText(document.documentElement!,
                  includeLinks: includeLinks)
              : '';
    }

    // Clean up whitespace.
    text = _cleanWhitespace(text);
    text = _truncate(text);

    return CrawlResult(
      url: uri.toString(),
      statusCode: response.statusCode,
      title: title,
      content: text,
    );
  }

  /// Follow redirects manually to handle cross-scheme redirects.
  static Future<http.Response> _fetchWithRedirects(Uri uri) async {
    var currentUri = uri;
    for (var i = 0; i < _maxRedirects; i++) {
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..headers['User-Agent'] = _userAgent
        ..headers['Accept'] =
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        ..headers['Accept-Language'] = 'en-US,en;q=0.9';

      final streamed =
          await http.Client().send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location == null) return response;
        currentUri = currentUri.resolve(location);
        continue;
      }
      return response;
    }
    throw Exception('Too many redirects');
  }

  /// Remove all elements matching the given tag names.
  static void _removeElements(dom.Document doc, List<String> tags) {
    for (final tag in tags) {
      doc.querySelectorAll(tag).forEach((e) => e.remove());
    }
  }

  /// Remove elements matching CSS selectors.
  static void _removeBySelector(dom.Document doc, List<String> selectors) {
    for (final selector in selectors) {
      try {
        doc.querySelectorAll(selector).forEach((e) => e.remove());
      } catch (_) {
        // Skip invalid selectors silently.
      }
    }
  }

  /// Extract readable text from an element, preserving structure.
  static String _extractText(
    dom.Element element, {
    bool includeLinks = false,
  }) {
    final buffer = StringBuffer();
    _walkNode(element, buffer, includeLinks: includeLinks);
    return buffer.toString();
  }

  /// Recursively walk DOM nodes and extract text.
  static void _walkNode(
    dom.Node node,
    StringBuffer buffer, {
    bool includeLinks = false,
  }) {
    if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }

    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase() ?? '';

      // Block-level elements get newlines.
      const blockTags = {
        'p', 'div', 'section', 'article', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'li', 'tr', 'blockquote', 'pre', 'figcaption', 'dt', 'dd',
      };

      if (blockTags.contains(tag)) buffer.write('\n');

      // Headings get markdown-style prefix.
      if (tag.startsWith('h') && tag.length == 2) {
        final level = int.tryParse(tag[1]) ?? 0;
        if (level >= 1 && level <= 6) {
          buffer.write('${'#' * level} ');
        }
      }

      // List items get bullet.
      if (tag == 'li') buffer.write('- ');

      // Links: optionally include href.
      if (tag == 'a' && includeLinks) {
        final href = node.attributes['href'] ?? '';
        if (href.isNotEmpty && !href.startsWith('#') && !href.startsWith('javascript:')) {
          // Process children first, then append link.
          for (final child in node.nodes) {
            _walkNode(child, buffer, includeLinks: includeLinks);
          }
          buffer.write(' [$href]');
          return;
        }
      }

      // BR becomes newline.
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }

      // HR becomes divider.
      if (tag == 'hr') {
        buffer.write('\n---\n');
        return;
      }

      for (final child in node.nodes) {
        _walkNode(child, buffer, includeLinks: includeLinks);
      }

      if (blockTags.contains(tag)) buffer.write('\n');
    }
  }

  /// Collapse multiple whitespace/newlines into readable text.
  static String _cleanWhitespace(String text) {
    // Collapse multiple blank lines into max 2 newlines.
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // Collapse multiple spaces/tabs into single space (preserve newlines).
    text = text.replaceAll(RegExp(r'[^\S\n]+'), ' ');
    // Trim lines.
    text = text
        .split('\n')
        .map((line) => line.trim())
        .join('\n');
    // Remove leading/trailing whitespace.
    return text.trim();
  }

  /// Truncate to max content length.
  static String _truncate(String text) {
    if (text.length <= _maxContentLength) return text;
    return '${text.substring(0, _maxContentLength)}\n\n[Content truncated at ${_maxContentLength ~/ 1024}KB]';
  }
}
