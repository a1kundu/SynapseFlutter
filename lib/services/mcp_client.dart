import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/mcp_models.dart';

class McpClient {
  int _requestId = 0;
  int _nextId() => ++_requestId;

  /// Discover tools from an MCP server.
  Future<List<McpTool>> discoverTools(McpServerConfig server) async {
    try {
      final postUrl = switch (server.type) {
        McpTransportType.httpStreamable => server.url,
        McpTransportType.sse => await _discoverSsePostEndpoint(server.url),
      };

      // 1. Initialize
      await _sendJsonRpc(postUrl, 'initialize', {
        'protocolVersion': '2025-03-26',
        'capabilities': {},
        'clientInfo': {'name': 'Synapse', 'version': '1.0.0'},
      });

      // 2. Notify initialized
      await _sendNotification(postUrl, 'notifications/initialized');

      // 3. List tools
      final toolsResult = await _sendJsonRpc(postUrl, 'tools/list', {});
      final tools = (toolsResult['tools'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return tools.map((t) => McpTool(
        name: t['name'] as String,
        description: t['description'] as String?,
        inputSchema: t['inputSchema'] as Map<String, dynamic>?,
      )).toList();
    } catch (e) {
      throw Exception('Failed to discover tools from ${server.name}: $e');
    }
  }

  /// Call a tool on an MCP server.
  Future<String> callTool(
    McpServerConfig server,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final postUrl = switch (server.type) {
        McpTransportType.httpStreamable => server.url,
        McpTransportType.sse => await _discoverSsePostEndpoint(server.url),
      };

      // Re-initialize before tool call (MCP requires it)
      await _sendJsonRpc(postUrl, 'initialize', {
        'protocolVersion': '2025-03-26',
        'capabilities': {},
        'clientInfo': {'name': 'Synapse', 'version': '1.0.0'},
      });
      await _sendNotification(postUrl, 'notifications/initialized');

      final result = await _sendJsonRpc(postUrl, 'tools/call', {
        'name': toolName,
        'arguments': arguments,
      });

      final isError = result['isError'] as bool? ?? false;
      final content = (result['content'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final text = content.map((c) => c['text'] as String? ?? '').join('\n');

      if (isError) throw Exception(text);
      return text;
    } catch (e) {
      throw Exception('Tool call failed: $e');
    }
  }

  Future<String> _discoverSsePostEndpoint(String sseUrl) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(sseUrl));
      request.headers['Accept'] = 'text/event-stream';
      final response = await client.send(request);

      await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('event:') && chunk.contains('endpoint')) {
          continue; // next line is the data
        }
        if (chunk.startsWith('data:')) {
          final endpoint = chunk.substring(5).trim();
          if (endpoint.isNotEmpty && endpoint != '[DONE]') {
            // Resolve relative URL
            final baseUri = Uri.parse(sseUrl);
            final endpointUri = Uri.parse(endpoint);
            if (endpointUri.hasScheme) return endpoint;
            return baseUri.resolve(endpoint).toString();
          }
        }
      }
      throw Exception('No endpoint event received from SSE');
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _sendJsonRpc(
    String url,
    String method,
    Map<String, dynamic>? params,
  ) async {
    final id = _nextId();
    final request = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
    };
    if (params != null) request['params'] = params;

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      },
      body: jsonEncode(request),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final body = response.body;

    // Response might be SSE-wrapped or direct JSON
    String jsonBody;
    if (body.trimLeft().startsWith('{')) {
      jsonBody = body;
    } else {
      // Parse SSE-wrapped response
      final dataLine = body
          .split('\n')
          .where((l) => l.trim().startsWith('data:'))
          .map((l) => l.trim().substring(5).trim())
          .firstWhere((l) => l.isNotEmpty && l != '[DONE]', orElse: () => '');
      if (dataLine.isEmpty) throw Exception('Empty response');
      jsonBody = dataLine;
    }

    final rpcResponse = jsonDecode(jsonBody) as Map<String, dynamic>;
    if (rpcResponse['error'] != null) {
      final error = rpcResponse['error'] as Map<String, dynamic>;
      throw Exception('MCP error: ${error['message']}');
    }
    return (rpcResponse['result'] as Map<String, dynamic>?) ?? {};
  }

  Future<void> _sendNotification(String url, String method) async {
    final request = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
    };
    await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      },
      body: jsonEncode(request),
    );
  }
}
