import 'package:http/http.dart' as http;

/// A single search result.
class SearchResult {
  final String title;
  final String url;
  final String snippet;

  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  String toDisplayString(int index) {
    return '$index. $title\n   $url\n   $snippet';
  }
}

/// Web search service using DuckDuckGo (no API key required).
class WebSearchService {
  static const _searchUrl = 'https://html.duckduckgo.com/html/';
  static const _userAgent = 'Synapse/1.0 (AI Assistant)';
  static const _timeout = Duration(seconds: 10);

  /// Search DuckDuckGo and return formatted top results.
  static Future<String> search(String query, {int maxResults = 5}) async {
    if (query.trim().isEmpty) {
      return 'Error: No search query provided.';
    }
    maxResults = maxResults.clamp(1, 10);

    try {
      final response = await http.post(
        Uri.parse(_searchUrl),
        headers: {
          'User-Agent': _userAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'q=${Uri.encodeComponent(query)}&b=',
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        return 'Error: Search returned HTTP ${response.statusCode}.';
      }

      final results = _parseSearchResults(response.body, maxResults);
      if (results.isEmpty) {
        return 'No results found for: $query';
      }

      final buffer = StringBuffer();
      buffer.writeln('Search results for: $query\n');
      for (int i = 0; i < results.length; i++) {
        buffer.writeln(results[i].toDisplayString(i + 1));
        if (i < results.length - 1) buffer.writeln();
      }
      return buffer.toString().trim();
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        return 'Error: Search request timed out after ${_timeout.inSeconds}s.';
      }
      return 'Error: Search failed — $e';
    }
  }

  // ── DuckDuckGo HTML parsing ───────────────────────────────────────────

  static List<SearchResult> _parseSearchResults(String html, int maxResults) {
    final results = <SearchResult>[];

    // Match result blocks.
    final resultBlockPattern = RegExp(
      r'class="result results_links[^"]*"(.*?)(?=class="result results_links|$)',
      dotAll: true,
    );

    final blocks = resultBlockPattern.allMatches(html);

    for (final block in blocks) {
      if (results.length >= maxResults) break;

      final blockHtml = block.group(1) ?? '';

      // Extract title and href from result__a.
      final titleMatch = RegExp(
        r'class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
        dotAll: true,
      ).firstMatch(blockHtml);

      if (titleMatch == null) continue;

      final rawHref = titleMatch.group(1) ?? '';
      final rawTitle = _stripTags(titleMatch.group(2) ?? '').trim();

      if (rawTitle.isEmpty) continue;

      // Decode the actual URL from DuckDuckGo's redirect.
      final actualUrl = _extractDdgUrl(rawHref);
      if (actualUrl.isEmpty) continue;

      // Extract snippet.
      final snippetMatch = RegExp(
        r'class="result__snippet"[^>]*>(.*?)</(?:a|span)>',
        dotAll: true,
      ).firstMatch(blockHtml);
      final rawSnippet = _stripTags(snippetMatch?.group(1) ?? '').trim();

      results.add(SearchResult(
        title: _decodeHtmlEntities(rawTitle),
        url: actualUrl,
        snippet: _decodeHtmlEntities(rawSnippet),
      ));
    }

    return results;
  }

  /// Extract the real URL from DuckDuckGo's redirect href.
  /// Format: //duckduckgo.com/l/?uddg=https%3A%2F%2F...&rut=...
  static String _extractDdgUrl(String href) {
    final uddgMatch = RegExp(r'uddg=([^&]+)').firstMatch(href);
    if (uddgMatch != null) {
      try {
        return Uri.decodeComponent(uddgMatch.group(1)!);
      } catch (_) {
        return '';
      }
    }
    if (href.startsWith('http')) return href;
    if (href.startsWith('//')) return 'https:$href';
    return '';
  }

  /// Strip all HTML tags from a string.
  static String _stripTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// Decode common HTML entities.
  static String _decodeHtmlEntities(String text) {
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
        });
  }
}
