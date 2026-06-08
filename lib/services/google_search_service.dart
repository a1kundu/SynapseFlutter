import 'package:http/http.dart' as http;

/// A single Google search result.
class GoogleSearchResult {
  final String title;
  final String url;
  final String snippet;

  const GoogleSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  String toDisplayString(int index) {
    return '$index. $title\n   $url\n   $snippet';
  }
}

/// Google Search service via HTML scraping of google.com/search.
///
/// Uses a mobile User-Agent and standard GET request.
/// Designed for low-volume, personal use on an Android device.
class GoogleSearchService {
  static const _searchUrl = 'https://www.google.com/search';

  /// Mobile Chrome User-Agent for natural-looking requests.
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Mobile Safari/537.36';

  static const _timeout = Duration(seconds: 12);

  /// Search Google and return formatted top results.
  static Future<String> search(
    String query, {
    int maxResults = 5,
    String language = 'en',
  }) async {
    if (query.trim().isEmpty) {
      return 'Error: No search query provided.';
    }
    maxResults = maxResults.clamp(1, 10);

    try {
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        'q': query,
        'num': '${maxResults + 5}', // request extra to account for filtering
        'hl': language,
        'pws': '0', // disable personalization
        'udm': '14', // web results filter (cleaner HTML)
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': '$language,en;q=0.5',
          'Accept-Encoding': 'identity', // no gzip to simplify parsing
          'DNT': '1',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
        },
      ).timeout(_timeout);

      if (response.statusCode == 429) {
        return 'Error: Google rate-limited the request (HTTP 429). Try again later.';
      }
      if (response.statusCode != 200) {
        return 'Error: Google returned HTTP ${response.statusCode}.';
      }

      // Check for CAPTCHA / consent page
      final body = response.body;
      if (body.contains('detected unusual traffic') ||
          body.contains('/sorry/') ||
          body.contains('captcha')) {
        return 'Error: Google is requesting a CAPTCHA. '
            'Try again later or reduce search frequency.';
      }

      final results = _parseResults(body, maxResults);
      if (results.isEmpty) {
        return 'No results found for: $query';
      }

      final buffer = StringBuffer();
      buffer.writeln('Google search results for: $query\n');
      for (int i = 0; i < results.length; i++) {
        buffer.writeln(results[i].toDisplayString(i + 1));
        if (i < results.length - 1) buffer.writeln();
      }
      return buffer.toString().trim();
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        return 'Error: Google search timed out after ${_timeout.inSeconds}s.';
      }
      return 'Error: Google search failed — $e';
    }
  }

  // ── HTML parsing ──────────────────────────────────────────────────────

  /// Parse Google search result HTML.
  ///
  /// Strategy (ordered by reliability):
  ///  1. Find `<div class="g">` blocks (stable for years).
  ///  2. Within each block, find `<a href="..."><h3>Title</h3></a>`.
  ///  3. Extract snippet from nearby text spans/divs.
  ///  4. Fallback: find any `<a>` containing `<h3>` if no `.g` blocks.
  static List<GoogleSearchResult> _parseResults(String html, int maxResults) {
    final results = <GoogleSearchResult>[];

    // ── Strategy 1: <div class="g"> blocks ──────────────────────────────
    final gBlockPattern = RegExp(
      r'<div\s+class="[^"]*\bg\b[^"]*"[^>]*>(.*?)(?=<div\s+class="[^"]*\bg\b[^"]*"|<footer|$)',
      dotAll: true,
    );

    for (final block in gBlockPattern.allMatches(html)) {
      if (results.length >= maxResults) break;
      final result = _extractFromBlock(block.group(1) ?? '');
      if (result != null) results.add(result);
    }

    // ── Strategy 2: fallback – any <a> with <h3> inside ─────────────────
    if (results.isEmpty) {
      final anchorH3Pattern = RegExp(
        r'<a\s[^>]*href="([^"]*)"[^>]*>(?:(?!</a>).)*<h3[^>]*>(.*?)</h3>',
        dotAll: true,
      );

      for (final match in anchorH3Pattern.allMatches(html)) {
        if (results.length >= maxResults) break;

        final rawHref = match.group(1) ?? '';
        final rawTitle = _stripTags(match.group(2) ?? '').trim();
        final url = _resolveUrl(rawHref);

        if (rawTitle.isEmpty || url.isEmpty) continue;
        if (_isGoogleInternal(url)) continue;

        // Try to find a snippet near this match
        final snippet = _findSnippetNear(html, match.end);

        results.add(GoogleSearchResult(
          title: _decodeEntities(rawTitle),
          url: url,
          snippet: _decodeEntities(snippet),
        ));
      }
    }

    return results;
  }

  /// Extract a search result from a single `<div class="g">` block.
  static GoogleSearchResult? _extractFromBlock(String blockHtml) {
    // Find the anchor with an h3 title
    final anchorPattern = RegExp(
      r'<a\s[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    String? url;
    String? title;

    for (final anchor in anchorPattern.allMatches(blockHtml)) {
      final href = anchor.group(1) ?? '';
      final inner = anchor.group(2) ?? '';

      // We want the anchor that contains <h3>
      final h3Match = RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true)
          .firstMatch(inner);
      if (h3Match != null) {
        title = _stripTags(h3Match.group(1) ?? '').trim();
        url = _resolveUrl(href);
        break;
      }
    }

    if (title == null || title.isEmpty || url == null || url.isEmpty) {
      return null;
    }
    if (_isGoogleInternal(url)) return null;

    // Extract snippet: look for text in spans/divs after the title link,
    // but before any nested <div class="g"> or action elements.
    final snippet = _extractSnippet(blockHtml);

    return GoogleSearchResult(
      title: _decodeEntities(title),
      url: url,
      snippet: _decodeEntities(snippet),
    );
  }

  /// Extract snippet text from a result block.
  ///
  /// Tries multiple patterns since Google's snippet markup varies:
  ///  - `<span class="...">` containing the snippet
  ///  - `data-sncf` attribute divs
  ///  - Generic: longest text span that isn't the title or URL
  static String _extractSnippet(String blockHtml) {
    // Pattern 1: spans with "st" class or data-sncf containers (legacy)
    final stMatch = RegExp(
      r'class="[^"]*\bst\b[^"]*"[^>]*>(.*?)</span>',
      dotAll: true,
    ).firstMatch(blockHtml);
    if (stMatch != null) {
      final text = _stripTags(stMatch.group(1) ?? '').trim();
      if (text.length > 20) return text;
    }

    // Pattern 2: VwiC3b class (common in modern Google results)
    final vwicMatch = RegExp(
      r'class="[^"]*VwiC3b[^"]*"[^>]*>(.*?)</(?:span|div)>',
      dotAll: true,
    ).firstMatch(blockHtml);
    if (vwicMatch != null) {
      final text = _stripTags(vwicMatch.group(1) ?? '').trim();
      if (text.length > 20) return text;
    }

    // Pattern 3: Look for data-sncf attribute
    final sncfMatch = RegExp(
      r'data-sncf[^>]*>(.*?)</(?:span|div)>',
      dotAll: true,
    ).firstMatch(blockHtml);
    if (sncfMatch != null) {
      final text = _stripTags(sncfMatch.group(1) ?? '').trim();
      if (text.length > 20) return text;
    }

    // Pattern 4: Find the longest readable text span in the block
    // (heuristic: after stripping the title/URL area, the snippet
    //  is usually the longest remaining text blob)
    final allSpans = RegExp(
      r'<(?:span|div|em)[^>]*>(.*?)</(?:span|div|em)>',
      dotAll: true,
    ).allMatches(blockHtml);

    String best = '';
    for (final span in allSpans) {
      final text = _stripTags(span.group(1) ?? '').trim();
      // Ignore very short fragments, URLs, and dates
      if (text.length > best.length &&
          text.length > 30 &&
          !text.startsWith('http') &&
          !RegExp(r'^\w+\.\w+').hasMatch(text)) {
        best = text;
      }
    }

    return best;
  }

  /// Try to find snippet text near a given position in the HTML.
  static String _findSnippetNear(String html, int position) {
    // Take a window of ~2000 chars after the match
    final window = html.substring(
      position,
      (position + 2000).clamp(0, html.length),
    );

    // Look for text-heavy spans
    final spanPattern = RegExp(
      r'<(?:span|div)[^>]*>(.*?)</(?:span|div)>',
      dotAll: true,
    );

    for (final match in spanPattern.allMatches(window)) {
      final text = _stripTags(match.group(1) ?? '').trim();
      if (text.length > 40 &&
          !text.startsWith('http') &&
          !text.contains('<')) {
        return text;
      }
    }
    return '';
  }

  /// Resolve a URL from Google's href format.
  ///
  /// Google uses several formats:
  ///  - `/url?q=https://actual-url.com&sa=...` (redirect wrapper)
  ///  - Direct `https://actual-url.com`
  ///  - Protocol-relative `//url`
  static String _resolveUrl(String href) {
    // Google's redirect wrapper
    final qMatch = RegExp(r'[?&]q=([^&]+)').firstMatch(href);
    if (qMatch != null) {
      try {
        return Uri.decodeComponent(qMatch.group(1)!);
      } catch (_) {
        return '';
      }
    }

    // Direct URL
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }

    // Protocol-relative
    if (href.startsWith('//')) {
      return 'https:$href';
    }

    return '';
  }

  /// Check if a URL is Google-internal (not a real search result).
  static bool _isGoogleInternal(String url) {
    final lower = url.toLowerCase();
    return lower.contains('google.com/search') ||
        lower.contains('google.com/url') ||
        lower.contains('accounts.google') ||
        lower.contains('support.google') ||
        lower.contains('policies.google') ||
        lower.contains('maps.google') ||
        lower.startsWith('/');
  }

  /// Strip all HTML tags from a string.
  static String _stripTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Decode common HTML entities.
  static String _decodeEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '...')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
          final code = int.tryParse(match.group(1) ?? '');
          if (code != null && code > 0 && code < 0x10FFFF) {
            return String.fromCharCode(code);
          }
          return match.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
          final code = int.tryParse(match.group(1) ?? '', radix: 16);
          if (code != null && code > 0 && code < 0x10FFFF) {
            return String.fromCharCode(code);
          }
          return match.group(0)!;
        })
        .trim();
  }
}
