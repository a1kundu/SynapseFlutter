/// MCP transport type.
enum McpTransportType { sse, httpStreamable }

/// Configuration for an MCP server (persisted in settings).
class McpServerConfig {
  final String name;
  final String url;
  final McpTransportType type;
  final bool enabled;

  const McpServerConfig({
    required this.name,
    required this.url,
    required this.type,
    this.enabled = true,
  });

  McpServerConfig copyWith({bool? enabled}) => McpServerConfig(
    name: name,
    url: url,
    type: type,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'type': type.name,
    'enabled': enabled,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      name: json['name'] as String,
      url: json['url'] as String,
      type: McpTransportType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => McpTransportType.httpStreamable,
      ),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    );
  }
}

/// An MCP tool discovered from a server.
class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;

  const McpTool({required this.name, this.description, this.inputSchema});
}

/// Resolved tool with server info (for UI + system prompt).
class McpServerTool {
  final String serverName;
  final McpServerConfig serverConfig;
  final McpTool tool;

  const McpServerTool({
    required this.serverName,
    required this.serverConfig,
    required this.tool,
  });
}
