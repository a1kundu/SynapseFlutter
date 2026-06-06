import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/chat_models.dart';
import '../models/llm_models.dart';
import '../models/mcp_models.dart';
import '../settings/settings_repository.dart';
import 'llm_api_client.dart';
import 'mcp_client.dart';

/// Chat controller managing messages, model selection, MCP tools, and streaming.
/// Equivalent to SynapseKT's ChatViewModel.
class ChatController extends ChangeNotifier {
  final LlmApiClient _apiClient = LlmApiClient();
  final McpClient _mcpClient = McpClient();

  int _messageCounter = 0;

  final List<ChatMessage> messages = [];
  LlmModel? selectedModel;
  final List<LlmModel> availableModels = [];
  bool isLoadingModels = false;
  String? modelFetchError;

  final List<ChatAttachment> pendingAttachments = [];
  bool isGenerating = false;
  String inputText = '';

  // MCP tools
  final List<McpServerTool> mcpTools = [];
  bool isLoadingMcpTools = false;
  String? mcpError;

  ChatController() {
    refreshModels();
    refreshMcpTools();
  }

  void onInputTextChange(String text) {
    inputText = text;
    notifyListeners();
  }

  void selectModel(LlmModel model) {
    selectedModel = model;
    SettingsRepository.instance.lastSelectedModelId = model.id;
    notifyListeners();
  }

  /// Fetch models from the configured provider.
  Future<void> refreshModels() async {
    final settings = SettingsRepository.instance;
    if (!settings.isLlmConfigured) return;

    isLoadingModels = true;
    modelFetchError = null;
    notifyListeners();

    try {
      final models = await _apiClient.fetchModels();
      if (models.isNotEmpty) {
        availableModels
          ..clear()
          ..addAll(models);
        final lastId = settings.lastSelectedModelId;
        final restored =
            lastId.isNotEmpty ? models.where((m) => m.id == lastId).firstOrNull : null;
        if (selectedModel == null || models.every((m) => m.id != selectedModel?.id)) {
          selectedModel = restored ?? models.first;
        }
      }
      modelFetchError = null;
    } catch (e) {
      modelFetchError = e.toString();
    }

    isLoadingModels = false;
    notifyListeners();
  }

  void addAttachment(ChatAttachment attachment) {
    pendingAttachments.add(attachment);
    notifyListeners();
  }

  void removeAttachment(int index) {
    if (index >= 0 && index < pendingAttachments.length) {
      pendingAttachments.removeAt(index);
      notifyListeners();
    }
  }

  void clearAttachments() {
    pendingAttachments.clear();
    notifyListeners();
  }

  /// Refresh MCP tools from all configured servers.
  Future<void> refreshMcpTools() async {
    final servers = SettingsRepository.instance.mcpServers;
    if (servers.isEmpty) {
      mcpTools.clear();
      mcpError = null;
      notifyListeners();
      return;
    }

    isLoadingMcpTools = true;
    mcpError = null;
    notifyListeners();

    final allTools = <McpServerTool>[];
    final errors = <String>[];

    for (final server in servers) {
      try {
        final tools = await _mcpClient.discoverTools(server);
        for (final tool in tools) {
          allTools.add(McpServerTool(
            serverName: server.name,
            serverConfig: server,
            tool: tool,
          ));
        }
      } catch (e) {
        errors.add('${server.name}: $e');
      }
    }

    mcpTools
      ..clear()
      ..addAll(allTools);
    mcpError = errors.isNotEmpty ? errors.join('; ') : null;
    isLoadingMcpTools = false;
    notifyListeners();
  }

  /// Send a user message and get an LLM response.
  void sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && pendingAttachments.isEmpty) return;

    final userMessage = ChatMessage(
      id: ChatMessage.generateId(),
      role: MessageRole.user,
      content: trimmed,
      timestamp: ++_messageCounter,
      attachments: List.from(pendingAttachments),
    );
    messages.add(userMessage);
    pendingAttachments.clear();
    inputText = '';
    notifyListeners();

    // Check if MCP servers changed
    final servers = SettingsRepository.instance.mcpServers;
    final distinctServers = mcpTools.map((t) => t.serverName).toSet();
    if (servers.length != distinctServers.length ||
        servers.any((s) => !distinctServers.contains(s.name))) {
      _refreshMcpToolsSyncThenGenerate();
      return;
    }

    _generateResponse();
  }

  Future<void> _refreshMcpToolsSyncThenGenerate() async {
    await _refreshMcpToolsSync();
    _generateResponse();
  }

  Future<void> _refreshMcpToolsSync() async {
    final servers = SettingsRepository.instance.mcpServers;
    if (servers.isEmpty) {
      mcpTools.clear();
      mcpError = null;
      return;
    }

    isLoadingMcpTools = true;
    mcpError = null;
    notifyListeners();

    final allTools = <McpServerTool>[];
    final errors = <String>[];
    for (final server in servers) {
      try {
        final tools = await _mcpClient.discoverTools(server);
        for (final tool in tools) {
          allTools.add(McpServerTool(
            serverName: server.name,
            serverConfig: server,
            tool: tool,
          ));
        }
      } catch (e) {
        errors.add('${server.name}: $e');
      }
    }

    mcpTools
      ..clear()
      ..addAll(allTools);
    mcpError = errors.isNotEmpty ? errors.join('; ') : null;
    isLoadingMcpTools = false;
    notifyListeners();
  }

  void _generateResponse() {
    final settings = SettingsRepository.instance;

    if (!settings.isLlmConfigured) {
      messages.add(ChatMessage(
        id: ChatMessage.generateId(),
        role: MessageRole.assistant,
        content: '\u26a0\ufe0f API key not configured. Go to Settings \u2192 LLM Provider to set your API key.',
        timestamp: ++_messageCounter,
        model: selectedModel,
      ));
      notifyListeners();
      return;
    }

    isGenerating = true;
    final currentModel = selectedModel;
    final assistantId = ChatMessage.generateId();
    messages.add(ChatMessage(
      id: assistantId,
      role: MessageRole.assistant,
      content: '',
      timestamp: ++_messageCounter,
      model: currentModel,
      isStreaming: true,
    ));
    notifyListeners();

    _doGenerate(assistantId, currentModel);
  }

  Future<void> _doGenerate(String assistantId, LlmModel? currentModel) async {
    try {
      if (currentModel == null) {
        _updateMessage(assistantId, content: '\u26a0\ufe0f No model selected. Fetch models first.', streaming: false);
        isGenerating = false;
        notifyListeners();
        return;
      }

      final tools = mcpTools.toList();
      final hasTools = tools.isNotEmpty;
      final conversationHistory = _buildConversationHistory(assistantId, tools);

      final modelSupportsTools = currentModel.supportsTools;
      final openAiTools = (hasTools && modelSupportsTools)
          ? tools.map((st) => OpenAiTool(
              function: OpenAiFunction(
                name: st.tool.name,
                description: st.tool.description ?? '',
                parameters: st.tool.inputSchema,
              ),
            )).toList()
          : null;

      await _streamWithToolCalling(
        assistantId,
        currentModel,
        conversationHistory,
        openAiTools,
        modelSupportsTools ? tools : [],
      );
    } catch (e) {
      final idx = messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        final current = messages[idx].content;
        messages[idx] = messages[idx].copyWith(
          content: current.isEmpty ? '\u26a0\ufe0f Error: $e' : current,
        );
      }
    } finally {
      final idx = messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        messages[idx] = messages[idx].copyWith(isStreaming: false);
      }
      isGenerating = false;
      notifyListeners();
    }
  }

  List<ChatRequestMessage> _buildConversationHistory(
    String excludeId,
    List<McpServerTool> tools,
  ) {
    final history = <ChatRequestMessage>[];
    final now = DateTime.now();
    final dateTime = '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}, ${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final systemParts = <String>[];
    systemParts.add('You are Synapse, a helpful AI assistant.\nCurrent date and time: $dateTime');

    if (tools.isNotEmpty) {
      final toolDescriptions = tools.map((st) {
        final schema = st.tool.inputSchema != null ? jsonEncode(st.tool.inputSchema) : '{}';
        return '- **${st.tool.name}** (server: ${st.serverName}): '
            '${st.tool.description ?? "No description"}\n'
            '  Input schema: $schema';
      }).join('\n\n');

      systemParts.add(
        'You have access to the following tools via MCP (Model Context Protocol) servers. '
        'Use them when appropriate to help the user.\n\n'
        'Available tools:\n$toolDescriptions\n\n'
        'When you need to use a tool, the system will automatically invoke it for you via function calling.'
      );
    }

    history.add(ChatRequestMessage(
      role: 'system',
      content: systemParts.join('\n\n'),
    ));

    history.addAll(
      messages
          .where((m) => m.id != excludeId)
          .map((m) => ChatRequestMessage(
                role: m.role == MessageRole.user ? 'user' : 'assistant',
                content: m.content,
              )),
    );

    return history;
  }

  Future<void> _streamWithToolCalling(
    String assistantId,
    LlmModel model,
    List<ChatRequestMessage> conversationHistory,
    List<OpenAiTool>? openAiTools,
    List<McpServerTool> mcpToolsList,
  ) async {
    final eventStream = _apiClient.streamWithTools(
      model: model,
      conversationHistory: conversationHistory,
      tools: openAiTools,
    );

    final builder = StringBuffer();
    var toolCallHandled = false;

    await for (final event in eventStream) {
      switch (event) {
        case TokenEvent():
          builder.write(event.text);
          _updateMessage(assistantId, content: builder.toString());
        case DoneEvent():
          if (toolCallHandled) continue;
          final toolCalls = event.toolCalls;
          if (toolCalls.isNotEmpty && toolCalls.any((tc) => tc.function.name.isNotEmpty)) {
            toolCallHandled = true;
            await _handleToolCalls(assistantId, model, conversationHistory, toolCalls, mcpToolsList);
          } else if (builder.isEmpty) {
            _updateMessage(assistantId, content: 'No response received from the model. Please try again.');
          }
        case ErrorEvent():
          _updateMessage(assistantId, content: '\u26a0\ufe0f Error: ${event.message}', streaming: false);
      }
    }
  }

  Future<void> _handleToolCalls(
    String assistantId,
    LlmModel model,
    List<ChatRequestMessage> originalHistory,
    List<ToolCallInfo> toolCalls,
    List<McpServerTool> tools,
  ) async {
    final toolNames = toolCalls.map((tc) => tc.function.name).where((n) => n.isNotEmpty).toList();
    _updateMessage(assistantId, content: '\ud83d\udd27 Calling tools: ${toolNames.join(", ")}...', streaming: true);

    final toolResults = <String>[];
    for (final call in toolCalls) {
      final toolName = call.function.name;
      final serverTool = tools.where((t) => t.tool.name == toolName).firstOrNull;

      String resultContent;
      if (serverTool != null) {
        try {
          Map<String, dynamic> args;
          try {
            args = jsonDecode(call.function.arguments) as Map<String, dynamic>;
          } catch (_) {
            args = {};
          }
          resultContent = await _mcpClient.callTool(serverTool.serverConfig, toolName, args);
        } catch (e) {
          resultContent = 'Error executing tool: $e';
        }
      } else {
        resultContent = "Error: Tool '$toolName' not found";
      }
      toolResults.add('Tool `$toolName` returned:\n$resultContent');
    }

    final extendedHistory = originalHistory.toList();
    extendedHistory.add(ChatRequestMessage(
      role: 'user',
      content: '[Tool Results]\n\n${toolResults.join("\n\n---\n\n")}\n\nPlease use these tool results to answer my original question.',
    ));

    // Stream final response without tools to prevent infinite loop
    await _streamWithToolCalling(assistantId, model, extendedHistory, null, []);
  }

  void _updateMessage(String id, {String? content, bool? streaming}) {
    final idx = messages.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      if (content != null) messages[idx].content = content;
      if (streaming != null) messages[idx].isStreaming = streaming;
      notifyListeners();
    }
  }

  void clearConversation() {
    messages.clear();
    pendingAttachments.clear();
    inputText = '';
    notifyListeners();
  }

  String _weekday(int wd) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[wd - 1];
  }

  String _month(int m) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    return months[m - 1];
  }
}
