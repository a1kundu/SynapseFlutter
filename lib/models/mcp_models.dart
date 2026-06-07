/// MCP transport type.
enum McpTransportType { sse, httpStreamable }

/// Authentication type for MCP servers.
enum McpAuthType { none, bearer, customHeader }

/// Configuration for an MCP server (persisted in settings).
class McpServerConfig {
  final String name;
  final String url;
  final McpTransportType type;
  final bool enabled;
  final McpAuthType authType;

  /// Bearer token (used when authType == bearer).
  final String? authToken;

  /// Custom header name (used when authType == customHeader).
  final String? authHeaderName;

  /// Custom header value (used when authType == customHeader).
  final String? authHeaderValue;

  const McpServerConfig({
    required this.name,
    required this.url,
    required this.type,
    this.enabled = true,
    this.authType = McpAuthType.none,
    this.authToken,
    this.authHeaderName,
    this.authHeaderValue,
  });

  McpServerConfig copyWith({
    bool? enabled,
    McpAuthType? authType,
    String? authToken,
    String? authHeaderName,
    String? authHeaderValue,
  }) => McpServerConfig(
    name: name,
    url: url,
    type: type,
    enabled: enabled ?? this.enabled,
    authType: authType ?? this.authType,
    authToken: authToken ?? this.authToken,
    authHeaderName: authHeaderName ?? this.authHeaderName,
    authHeaderValue: authHeaderValue ?? this.authHeaderValue,
  );

  /// Returns the auth headers to include in requests, or empty map if none.
  Map<String, String> get authHeaders {
    switch (authType) {
      case McpAuthType.bearer:
        if (authToken != null && authToken!.isNotEmpty) {
          return {'Authorization': 'Bearer $authToken'};
        }
        return {};
      case McpAuthType.customHeader:
        if (authHeaderName != null &&
            authHeaderName!.isNotEmpty &&
            authHeaderValue != null &&
            authHeaderValue!.isNotEmpty) {
          return {authHeaderName!: authHeaderValue!};
        }
        return {};
      case McpAuthType.none:
        return {};
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'type': type.name,
    'enabled': enabled,
    'authType': authType.name,
    if (authToken != null) 'authToken': authToken,
    if (authHeaderName != null) 'authHeaderName': authHeaderName,
    if (authHeaderValue != null) 'authHeaderValue': authHeaderValue,
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
      authType: McpAuthType.values.firstWhere(
        (t) => t.name == json['authType'],
        orElse: () => McpAuthType.none,
      ),
      authToken: json['authToken'] as String?,
      authHeaderName: json['authHeaderName'] as String?,
      authHeaderValue: json['authHeaderValue'] as String?,
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
  final McpServerConfig? serverConfig;
  final McpTool tool;

  /// True for built-in tools handled locally (not via MCP).
  final bool isSystemTool;

  const McpServerTool({
    required this.serverName,
    this.serverConfig,
    required this.tool,
    this.isSystemTool = false,
  });
}
