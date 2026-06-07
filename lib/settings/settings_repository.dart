import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/llm_models.dart';
import '../models/mcp_models.dart';

/// Central settings repository (singleton).
class SettingsRepository extends ChangeNotifier {
  static SettingsRepository? _instance;
  static SettingsRepository get instance =>
      _instance ??= SettingsRepository._();

  SettingsRepository._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── LLM Provider ──────────────────────────────────────────────────────

  LlmProvider get llmProvider {
    final name = _prefs?.getString('llm_provider');
    if (name == null) return LlmProvider.githubModels;
    return LlmProvider.values.firstWhere(
      (p) => p.name == name,
      orElse: () => LlmProvider.githubModels,
    );
  }

  set llmProvider(LlmProvider value) {
    _prefs?.setString('llm_provider', value.name);
    notifyListeners();
  }

  String get llmApiKey => _prefs?.getString('llm_api_key') ?? '';

  set llmApiKey(String value) {
    _prefs?.setString('llm_api_key', value);
    notifyListeners();
  }

  String get llmServerUrl => _prefs?.getString('llm_server_url') ?? '';

  set llmServerUrl(String value) {
    _prefs?.setString('llm_server_url', value);
    notifyListeners();
  }

  /// Resolved base URL (custom or provider default).
  String get resolvedBaseUrl {
    final custom = llmServerUrl;
    return custom.isNotEmpty ? custom : llmProvider.defaultBaseUrl;
  }

  bool get isLlmConfigured => llmApiKey.isNotEmpty;

  // ── Last Selected Model ───────────────────────────────────────────────

  String get lastSelectedModelId =>
      _prefs?.getString('last_selected_model_id') ?? '';

  set lastSelectedModelId(String value) {
    _prefs?.setString('last_selected_model_id', value);
  }

  // ── System Prompt ─────────────────────────────────────────────────────

  /// User-defined system prompt (appended after the base system prompt).
  String get systemPrompt => _prefs?.getString('system_prompt') ?? '';

  set systemPrompt(String value) {
    _prefs?.setString('system_prompt', value);
    notifyListeners();
  }

  // ── MCP Servers ───────────────────────────────────────────────────────

  List<McpServerConfig> get mcpServers {
    final json = _prefs?.getString('mcp_servers_json');
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => McpServerConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _saveMcpServers(List<McpServerConfig> servers) {
    final json = jsonEncode(servers.map((s) => s.toJson()).toList());
    _prefs?.setString('mcp_servers_json', json);
    notifyListeners();
  }

  void addMcpServer(McpServerConfig server) {
    final servers = mcpServers.toList();
    servers.add(server);
    _saveMcpServers(servers);
  }

  void removeMcpServer(String name) {
    final servers = mcpServers.where((s) => s.name != name).toList();
    _saveMcpServers(servers);
  }

  void toggleMcpServer(String name, {required bool enabled}) {
    final servers = mcpServers
        .map((s) => s.name == name ? s.copyWith(enabled: enabled) : s)
        .toList();
    _saveMcpServers(servers);
  }

  // ── Enabled MCP Tool Names ────────────────────────────────────────────

  /// Set of tool names enabled for LLM context. Empty = all enabled.
  Set<String> get enabledMcpToolNames {
    final json = _prefs?.getString('enabled_mcp_tools');
    if (json == null || json.isEmpty) return {};
    try {
      return (jsonDecode(json) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  set enabledMcpToolNames(Set<String> names) {
    _prefs?.setString('enabled_mcp_tools', jsonEncode(names.toList()));
  }

  /// Whether tool selection has been explicitly set (vs default all-enabled).
  bool get hasToolSelection =>
      _prefs?.getString('enabled_mcp_tools')?.isNotEmpty == true;

  // ── Theme ─────────────────────────────────────────────────────────────

  // Theme mode is managed by the existing app_theme.dart

  // ── Auto Update ───────────────────────────────────────────────────────

  bool get autoUpdateCheckEnabled =>
      _prefs?.getBool('auto_update_check') ?? true;

  set autoUpdateCheckEnabled(bool value) {
    _prefs?.setBool('auto_update_check', value);
    notifyListeners();
  }
}
