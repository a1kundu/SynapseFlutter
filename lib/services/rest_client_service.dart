import 'dart:convert';

import 'package:http/http.dart' as http;

/// Supported HTTP methods.
const _supportedMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

/// Maximum response body size to return (20KB).
const _maxResponseSize = 20000;

/// REST client service for making arbitrary HTTP requests.
class RestClientService {
  static const _userAgent = 'Synapse/1.0 (AI Assistant REST Client)';

  /// Execute an HTTP request and return a formatted result.
  static Future<String> request({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
    int? timeoutSeconds,
  }) async {
    // Validate method.
    final upperMethod = method.toUpperCase();
    if (!_supportedMethods.contains(upperMethod)) {
      return 'Error: Unsupported HTTP method "$method". '
          'Supported: ${_supportedMethods.join(", ")}';
    }

    // Validate URL.
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return 'Error: Invalid URL. Must start with http:// or https://';
    }

    // Build headers.
    final requestHeaders = <String, String>{
      'User-Agent': _userAgent,
      ...?headers,
    };

    // Determine timeout.
    final timeout = Duration(seconds: (timeoutSeconds ?? 30).clamp(1, 60));

    try {
      final http.Response response;

      switch (upperMethod) {
        case 'GET':
          response = await http.get(uri, headers: requestHeaders).timeout(timeout);
        case 'POST':
          response = await http.post(uri, headers: requestHeaders, body: body).timeout(timeout);
        case 'PUT':
          response = await http.put(uri, headers: requestHeaders, body: body).timeout(timeout);
        case 'PATCH':
          response = await http.patch(uri, headers: requestHeaders, body: body).timeout(timeout);
        case 'DELETE':
          response = await http.delete(uri, headers: requestHeaders, body: body).timeout(timeout);
        case 'HEAD':
          response = await http.head(uri, headers: requestHeaders).timeout(timeout);
        case 'OPTIONS':
          // http package doesn't have a dedicated options method.
          final request = http.Request('OPTIONS', uri);
          request.headers.addAll(requestHeaders);
          if (body != null) request.body = body;
          final streamed = await http.Client().send(request).timeout(timeout);
          response = await http.Response.fromStream(streamed);
        default:
          return 'Error: Unsupported method "$upperMethod".';
      }

      return _formatResponse(response, upperMethod);
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        return 'Error: Request timed out after ${timeout.inSeconds}s.';
      }
      if (e.toString().contains('SocketException') ||
          e.toString().contains('HandshakeException')) {
        return 'Error: Connection failed — could not reach $url';
      }
      return 'Error: Request failed — $e';
    }
  }

  /// Format the HTTP response for the LLM.
  static String _formatResponse(http.Response response, String method) {
    final buffer = StringBuffer();

    // Status line.
    buffer.writeln('HTTP ${response.statusCode} ${_httpReason(response.statusCode)}');
    buffer.writeln();

    // Response headers (selected important ones).
    final headersToShow = <String, String>{};
    for (final key in response.headers.keys) {
      final lower = key.toLowerCase();
      if (lower == 'content-type' ||
          lower == 'content-length' ||
          lower == 'location' ||
          lower == 'set-cookie' ||
          lower == 'www-authenticate' ||
          lower == 'x-ratelimit-remaining' ||
          lower == 'x-ratelimit-limit' ||
          lower == 'retry-after' ||
          lower == 'allow' ||
          lower == 'access-control-allow-origin' ||
          lower == 'etag' ||
          lower == 'last-modified') {
        headersToShow[key] = response.headers[key]!;
      }
    }

    if (headersToShow.isNotEmpty) {
      buffer.writeln('Headers:');
      for (final entry in headersToShow.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
      buffer.writeln();
    }

    // Body (skip for HEAD).
    if (method == 'HEAD') {
      buffer.writeln('(HEAD request — no body)');
      return buffer.toString().trim();
    }

    final body = response.body;
    if (body.isEmpty) {
      buffer.writeln('(empty response body)');
      return buffer.toString().trim();
    }

    // Try to pretty-print JSON.
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('json')) {
      try {
        final decoded = jsonDecode(body);
        final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
        if (pretty.length > _maxResponseSize) {
          buffer.writeln('Body (JSON, truncated):');
          buffer.writeln(pretty.substring(0, _maxResponseSize));
          buffer.writeln('\n[response truncated at $_maxResponseSize chars]');
        } else {
          buffer.writeln('Body (JSON):');
          buffer.writeln(pretty);
        }
        return buffer.toString().trim();
      } catch (_) {
        // Not valid JSON despite content-type; fall through.
      }
    }

    // Plain text / other.
    if (body.length > _maxResponseSize) {
      buffer.writeln('Body:');
      buffer.writeln(body.substring(0, _maxResponseSize));
      buffer.writeln('\n[response truncated at $_maxResponseSize chars]');
    } else {
      buffer.writeln('Body:');
      buffer.writeln(body);
    }

    return buffer.toString().trim();
  }

  /// Get a human-readable HTTP status reason.
  static String _httpReason(int code) {
    switch (code) {
      case 200: return 'OK';
      case 201: return 'Created';
      case 202: return 'Accepted';
      case 204: return 'No Content';
      case 301: return 'Moved Permanently';
      case 302: return 'Found';
      case 304: return 'Not Modified';
      case 400: return 'Bad Request';
      case 401: return 'Unauthorized';
      case 403: return 'Forbidden';
      case 404: return 'Not Found';
      case 405: return 'Method Not Allowed';
      case 408: return 'Request Timeout';
      case 409: return 'Conflict';
      case 413: return 'Payload Too Large';
      case 415: return 'Unsupported Media Type';
      case 422: return 'Unprocessable Entity';
      case 429: return 'Too Many Requests';
      case 500: return 'Internal Server Error';
      case 502: return 'Bad Gateway';
      case 503: return 'Service Unavailable';
      case 504: return 'Gateway Timeout';
      default: return '';
    }
  }
}
