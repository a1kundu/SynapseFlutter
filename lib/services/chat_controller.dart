import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/chat_models.dart';
import '../models/chat_session.dart';
import '../models/llm_models.dart';
import '../models/mcp_models.dart';
import '../settings/settings_repository.dart';
import 'chat_storage.dart';
import 'llm_api_client.dart';
import 'mcp_client.dart';

/// Chat controller managing sessions, messages, model selection, MCP tools,
/// tool selection, and streaming.
class ChatController extends ChangeNotifier {
  final LlmApiClient _apiClient = LlmApiClient();
  final McpClient _mcpClient = McpClient();
  final ChatStorage _storage = ChatStorage.instance;

  int _messageCounter = 0;

  // ── Session management ────────────────────────────────────────────────

  List<ChatSession> sessions = [];
  ChatSession? activeSession;

  // ── Current session state ─────────────────────────────────────────────

  final List<ChatMessage> messages = [];
  LlmModel? selectedModel;
  final List<LlmModel> availableModels = [];
  bool isLoadingModels = false;
  String? modelFetchError;

  final List<ChatAttachment> pendingAttachments = [];
  bool isGenerating = false;
  String inputText = '';

  // ── MCP tools ─────────────────────────────────────────────────────────

  final List<McpServerTool> mcpTools = [];
  bool isLoadingMcpTools = false;
  String? mcpError;

  // ── System tools (built-in, handled locally) ─────────────────────────

  static const String _systemToolServerName = 'Synapse';

  static final List<McpServerTool> systemTools = [
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'current_date_time',
        description:
            'Returns the current local date and time in a human-readable format.',
        inputSchema: {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      ),
      isSystemTool: true,
    ),
  ];

  /// All tools: system + MCP.
  List<McpServerTool> get allTools => [...systemTools, ...mcpTools];

  /// Which tools are enabled for LLM context.
  /// If empty and no explicit selection made, all tools are active.
  Set<String> enabledToolNames = {};
  bool _hasExplicitToolSelection = false;

  /// Tools that are currently active (enabled and available).
  List<McpServerTool> get activeTools {
    if (!_hasExplicitToolSelection) {
      return allTools;
    }
    return allTools
        .where((t) => enabledToolNames.contains(t.tool.name))
        .toList();
  }

  ChatController() {
    _loadSessions();
    refreshModels();
    refreshMcpTools();
  }

  // ── Session management methods ────────────────────────────────────────

  void _loadSessions() {
    sessions = _storage.getSessions();
    final activeId = _storage.activeSessionId;
    if (activeId != null) {
      activeSession = sessions.where((s) => s.id == activeId).firstOrNull;
    }
    if (activeSession != null) {
      messages.clear();
      messages.addAll(_storage.getMessages(activeSession!.id));
      _messageCounter = messages.isEmpty
          ? 0
          : messages.map((m) => m.timestamp).reduce((a, b) => a > b ? a : b);
    }
    // Load tool selection
    final settings = SettingsRepository.instance;
    _hasExplicitToolSelection = settings.hasToolSelection;
    enabledToolNames = settings.enabledMcpToolNames;
  }

  void createNewChat() {
    _saveCurrentSession();

    final session = ChatSession(
      id: ChatSession.generateId(),
      name: 'New Chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    sessions.insert(0, session);
    activeSession = session;
    messages.clear();
    _messageCounter = 0;
    pendingAttachments.clear();
    inputText = '';

    _storage.saveSessions(sessions);
    _storage.activeSessionId = session.id;
    notifyListeners();
  }

  void switchToSession(String sessionId) {
    if (activeSession?.id == sessionId) return;
    _saveCurrentSession();

    activeSession = sessions.where((s) => s.id == sessionId).firstOrNull;
    if (activeSession != null) {
      messages.clear();
      messages.addAll(_storage.getMessages(activeSession!.id));
      _messageCounter = messages.isEmpty
          ? 0
          : messages.map((m) => m.timestamp).reduce((a, b) => a > b ? a : b);
      _storage.activeSessionId = sessionId;
    }
    pendingAttachments.clear();
    inputText = '';
    notifyListeners();
  }

  void renameSession(String sessionId, String name) {
    final session = sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session != null) {
      session.name = name.trim().isEmpty ? 'Untitled' : name.trim();
      _storage.saveSessions(sessions);
      notifyListeners();
    }
  }

  void deleteSession(String sessionId) {
    _storage.deleteSessionData(sessionId);
    sessions.removeWhere((s) => s.id == sessionId);

    if (activeSession?.id == sessionId) {
      if (sessions.isNotEmpty) {
        switchToSession(sessions.first.id);
      } else {
        activeSession = null;
        messages.clear();
        _messageCounter = 0;
        _storage.activeSessionId = null;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  void forkChatAtMessage(String messageId) {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;

    _saveCurrentSession();

    final forkedMessages = messages
        .sublist(0, idx + 1)
        .map(
          (m) => ChatMessage(
            id: ChatMessage.generateId(),
            role: m.role,
            content: m.content,
            timestamp: m.timestamp,
            attachments: m.attachments,
            model: m.model,
          ),
        )
        .toList();

    final session = ChatSession(
      id: ChatSession.generateId(),
      name: 'Fork: ${activeSession?.name ?? "Chat"}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    sessions.insert(0, session);
    _storage.saveSessions(sessions);
    _storage.saveMessages(session.id, forkedMessages);

    activeSession = session;
    messages.clear();
    messages.addAll(forkedMessages);
    _messageCounter = forkedMessages.isEmpty
        ? 0
        : forkedMessages
              .map((m) => m.timestamp)
              .reduce((a, b) => a > b ? a : b);
    _storage.activeSessionId = session.id;
    notifyListeners();
  }

  void editUserMessage(String messageId, String newContent) {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0 || messages[idx].role != MessageRole.user) return;
    if (isGenerating) return;

    // Remove all messages after the edited one
    messages.removeRange(idx + 1, messages.length);
    messages[idx].content = newContent;

    _saveCurrentSession();
    notifyListeners();

    // Re-generate the response
    _generateResponse();
  }

  /// Export the current chat as a JSON map.
  Map<String, dynamic> exportChatToJson() {
    return {
      'session': {
        'id': activeSession?.id,
        'name': activeSession?.name ?? 'Untitled',
        'createdAt': activeSession?.createdAt.toIso8601String(),
        'exportedAt': DateTime.now().toIso8601String(),
      },
      'messages': messages
          .map(
            (m) => {
              'role': m.role.name,
              'content': m.content,
              'model': m.model?.displayName,
              'attachments': m.attachments
                  .map(
                    (a) => {
                      'fileName': a.fileName,
                      'mimeType': a.mimeType,
                      'size': a.displaySize,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };
  }

  void _saveCurrentSession() {
    if (activeSession != null && messages.isNotEmpty) {
      activeSession!.updatedAt = DateTime.now();
      _storage.saveMessages(activeSession!.id, messages);
      _storage.saveSessions(sessions);
    }
  }

  // ── Tool selection ────────────────────────────────────────────────────

  void toggleTool(String toolName) {
    _hasExplicitToolSelection = true;
    if (enabledToolNames.contains(toolName)) {
      enabledToolNames.remove(toolName);
    } else {
      enabledToolNames.add(toolName);
    }
    _persistToolSelection();
    notifyListeners();
  }

  void enableAllTools() {
    _hasExplicitToolSelection = true;
    enabledToolNames = allTools.map((t) => t.tool.name).toSet();
    _persistToolSelection();
    notifyListeners();
  }

  void disableAllTools() {
    _hasExplicitToolSelection = true;
    enabledToolNames.clear();
    _persistToolSelection();
    notifyListeners();
  }

  void _persistToolSelection() {
    SettingsRepository.instance.enabledMcpToolNames = enabledToolNames;
  }

  // ── Model / input ─────────────────────────────────────────────────────

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
        final restored = lastId.isNotEmpty
            ? models.where((m) => m.id == lastId).firstOrNull
            : null;
        if (selectedModel == null ||
            models.every((m) => m.id != selectedModel?.id)) {
          selectedModel = restored ?? models.first;
        }
      }
      modelFetchError = null;
    } catch (e) {
      final msg = e.toString();
      modelFetchError = msg.startsWith('Exception: ') ? msg.substring(11) : msg;
    }

    isLoadingModels = false;
    notifyListeners();
  }

  // ── Attachments ───────────────────────────────────────────────────────

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

  // ── MCP Tools ─────────────────────────────────────────────────────────

  /// Refresh MCP tools from all configured servers.
  Future<void> refreshMcpTools() async {
    final servers = SettingsRepository.instance.mcpServers
        .where((s) => s.enabled)
        .toList();
    if (servers.isEmpty) {
      mcpTools.clear();
      mcpError = null;
      notifyListeners();
      return;
    }

    isLoadingMcpTools = true;
    mcpError = null;
    notifyListeners();

    final discoveredTools = <McpServerTool>[];
    final errors = <String>[];

    for (final server in servers) {
      try {
        final tools = await _mcpClient.discoverTools(server);
        for (final tool in tools) {
          discoveredTools.add(
            McpServerTool(
              serverName: server.name,
              serverConfig: server,
              tool: tool,
            ),
          );
        }
      } catch (e) {
        errors.add('${server.name}: $e');
      }
    }

    mcpTools
      ..clear()
      ..addAll(discoveredTools);
    mcpError = errors.isNotEmpty ? errors.join('; ') : null;
    isLoadingMcpTools = false;

    // Auto-enable newly discovered tools if no explicit selection was made
    if (!_hasExplicitToolSelection) {
      enabledToolNames = allTools.map((t) => t.tool.name).toSet();
    } else {
      // Add any new tools that weren't previously known
      for (final tool in allTools) {
        if (!enabledToolNames.contains(tool.tool.name)) {
          // New tool; keep it disabled since user has made explicit selection
        }
      }
    }

    notifyListeners();
  }

  // ── Send message ──────────────────────────────────────────────────────

  /// Send a user message and get an LLM response.
  void sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && pendingAttachments.isEmpty) return;

    // Ensure we have an active session
    if (activeSession == null) {
      final session = ChatSession(
        id: ChatSession.generateId(),
        name: ChatSession.generateName(
          trimmed.isNotEmpty ? trimmed : 'File conversation',
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      sessions.insert(0, session);
      activeSession = session;
      _storage.saveSessions(sessions);
      _storage.activeSessionId = session.id;
    } else if (messages.isEmpty && trimmed.isNotEmpty) {
      // Auto-name session from first message
      activeSession!.name = ChatSession.generateName(trimmed);
      _storage.saveSessions(sessions);
    }

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

    // Save after adding user message
    _saveCurrentSession();

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

    final discoveredTools = <McpServerTool>[];
    final errors = <String>[];
    for (final server in servers) {
      try {
        final tools = await _mcpClient.discoverTools(server);
        for (final tool in tools) {
          discoveredTools.add(
            McpServerTool(
              serverName: server.name,
              serverConfig: server,
              tool: tool,
            ),
          );
        }
      } catch (e) {
        errors.add('${server.name}: $e');
      }
    }

    mcpTools
      ..clear()
      ..addAll(discoveredTools);
    mcpError = errors.isNotEmpty ? errors.join('; ') : null;
    isLoadingMcpTools = false;
    notifyListeners();
  }

  void _generateResponse() {
    final settings = SettingsRepository.instance;

    if (!settings.isLlmConfigured) {
      messages.add(
        ChatMessage(
          id: ChatMessage.generateId(),
          role: MessageRole.assistant,
          content:
              'API key not configured. Go to Settings to set your API key.',
          timestamp: ++_messageCounter,
          model: selectedModel,
        ),
      );
      notifyListeners();
      return;
    }

    isGenerating = true;
    final currentModel = selectedModel;
    final assistantId = ChatMessage.generateId();
    messages.add(
      ChatMessage(
        id: assistantId,
        role: MessageRole.assistant,
        content: '',
        timestamp: ++_messageCounter,
        model: currentModel,
        isStreaming: true,
      ),
    );
    notifyListeners();

    _doGenerate(assistantId, currentModel);
  }

  Future<void> _doGenerate(String assistantId, LlmModel? currentModel) async {
    try {
      if (currentModel == null) {
        _updateMessage(
          assistantId,
          content: 'No model selected. Fetch models first.',
          streaming: false,
        );
        isGenerating = false;
        notifyListeners();
        return;
      }

      final tools = activeTools;
      final hasTools = tools.isNotEmpty;
      final modelSupportsTools = currentModel.supportsTools;

      // Only describe tools in the system prompt when the model does NOT
      // support native function calling.  When function calling IS supported
      // the tools are sent via the API `tools` parameter and describing them
      // again in the prompt causes many models to output raw JSON instead of
      // using the proper tool-call mechanism.
      final conversationHistory = _buildConversationHistory(
        assistantId,
        modelSupportsTools ? const [] : tools,
      );

      final openAiTools = (hasTools && modelSupportsTools)
          ? tools
                .map(
                  (st) => OpenAiTool(
                    function: OpenAiFunction(
                      name: st.tool.name,
                      description: st.tool.description ?? '',
                      parameters: st.tool.inputSchema,
                    ),
                  ),
                )
                .toList()
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
          content: current.isEmpty ? 'Error: $e' : current,
        );
      }
    } finally {
      final idx = messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        messages[idx] = messages[idx].copyWith(isStreaming: false);
      }
      isGenerating = false;
      _saveCurrentSession();
      notifyListeners();
    }
  }

  List<ChatRequestMessage> _buildConversationHistory(
    String excludeId,
    List<McpServerTool> tools,
  ) {
    final history = <ChatRequestMessage>[];
    final settings = SettingsRepository.instance;

    // Build system prompt
    final systemParts = <String>[];
    systemParts.add(
      'You are Synapse, a helpful AI assistant.',
    );

    // User-defined system prompt
    final userSystemPrompt = settings.systemPrompt;
    if (userSystemPrompt.isNotEmpty) {
      systemParts.add(userSystemPrompt);
    }

    if (tools.isNotEmpty) {
      final toolDescriptions = tools
          .map((st) {
            final schema = st.tool.inputSchema != null
                ? jsonEncode(st.tool.inputSchema)
                : '{}';
            return '- **${st.tool.name}** (server: ${st.serverName}): '
                '${st.tool.description ?? "No description"}\n'
                '  Input schema: $schema';
          })
          .join('\n\n');

      systemParts.add(
        'You have access to the following tools via MCP (Model Context Protocol) servers. '
        'Use them when appropriate to help the user.\n\n'
        'Available tools:\n$toolDescriptions\n\n'
        'When you need to use a tool, the system will automatically invoke it for you via function calling.',
      );
    }

    history.add(
      ChatRequestMessage(role: 'system', content: systemParts.join('\n\n')),
    );

    // Add messages with file attachment context
    history.addAll(
      messages.where((m) => m.id != excludeId).map((m) {
        final content = _buildMessageContent(m);
        return ChatRequestMessage(
          role: m.role == MessageRole.user ? 'user' : 'assistant',
          content: content,
        );
      }),
    );

    return history;
  }

  /// Build message content including file attachment data.
  String _buildMessageContent(ChatMessage message) {
    final parts = <String>[];

    if (message.content.isNotEmpty) {
      parts.add(message.content);
    }

    for (final attachment in message.attachments) {
      if (attachment.bytes != null && attachment.isTextBased) {
        try {
          final content = utf8.decode(attachment.bytes!, allowMalformed: true);
          parts.add(
            '\n\n--- Attached file: ${attachment.fileName} ---\n$content\n--- End of ${attachment.fileName} ---',
          );
        } catch (_) {
          parts.add(
            '\n[Attached file: ${attachment.fileName} (${attachment.mimeType}, ${attachment.displaySize}) - could not read content]',
          );
        }
      } else if (attachment.bytes != null) {
        parts.add(
          '\n[Attached file: ${attachment.fileName} (${attachment.mimeType}, ${attachment.displaySize})]',
        );
      } else {
        parts.add(
          '\n[Previously attached file: ${attachment.fileName} (${attachment.mimeType}, ${attachment.displaySize})]',
        );
      }
    }

    return parts.join();
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
          if (toolCalls.isNotEmpty &&
              toolCalls.any((tc) => tc.function.name.isNotEmpty)) {
            toolCallHandled = true;
            await _handleToolCalls(
              assistantId,
              model,
              conversationHistory,
              toolCalls,
              mcpToolsList,
            );
          } else if (builder.isEmpty) {
            _updateMessage(
              assistantId,
              content: 'No response received from the model. Please try again.',
            );
          }
        case ErrorEvent():
          _updateMessage(
            assistantId,
            content: 'Error: ${event.message}',
            streaming: false,
          );
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
    final toolNames = toolCalls
        .map((tc) => tc.function.name)
        .where((n) => n.isNotEmpty)
        .toList();
    _updateMessage(
      assistantId,
      content: 'Calling tools: ${toolNames.join(", ")}...',
      streaming: true,
    );

    final toolResults = <String>[];
    for (final call in toolCalls) {
      final toolName = call.function.name;
      final serverTool = tools
          .where((t) => t.tool.name == toolName)
          .firstOrNull;

      String resultContent;
      if (serverTool != null && serverTool.isSystemTool) {
        resultContent = _executeSystemTool(toolName);
      } else if (serverTool != null) {
        try {
          Map<String, dynamic> args;
          try {
            args = jsonDecode(call.function.arguments) as Map<String, dynamic>;
          } catch (_) {
            args = {};
          }
          resultContent = await _mcpClient.callTool(
            serverTool.serverConfig!,
            toolName,
            args,
          );
        } catch (e) {
          resultContent = 'Error executing tool: $e';
        }
      } else {
        resultContent = "Error: Tool '$toolName' not found";
      }
      toolResults.add('Tool `$toolName` returned:\n$resultContent');
    }

    final extendedHistory = originalHistory.toList();
    extendedHistory.add(
      ChatRequestMessage(
        role: 'user',
        content:
            '[Tool Results]\n\n${toolResults.join("\n\n---\n\n")}\n\nPlease use these tool results to answer my original question.',
      ),
    );

    // Stream final response without tools to prevent infinite loop
    await _streamWithToolCalling(assistantId, model, extendedHistory, null, []);
  }

  /// Execute a built-in system tool and return its result.
  String _executeSystemTool(String toolName) {
    switch (toolName) {
      case 'current_date_time':
        final now = DateTime.now();
        final dateTime =
            '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}, ${now.year} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        return dateTime;
      default:
        return "Error: Unknown system tool '$toolName'";
    }
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
    if (activeSession != null) {
      _storage.saveMessages(activeSession!.id, []);
    }
    notifyListeners();
  }

  String _weekday(int wd) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[wd - 1];
  }

  String _month(int m) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[m - 1];
  }
}
