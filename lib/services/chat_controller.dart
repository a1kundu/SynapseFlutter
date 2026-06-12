import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../agents/agents.dart';
import '../models/chat_models.dart';
import '../models/chat_session.dart';
import '../models/llm_models.dart';
import '../models/mcp_models.dart';
import '../settings/settings_repository.dart';
import 'chat_storage.dart';
import 'llm_api_client.dart';
import 'lua_executor.dart';
import 'mcp_client.dart';
import 'notification_service.dart';
import 'rest_client_service.dart';
import 'memory_service.dart';
import 'ssh_service.dart';
import 'web_search_service.dart';
import 'web_crawler.dart';

/// Chat controller managing sessions, messages, model selection, MCP tools,
/// tool selection, and streaming.
class ChatController extends ChangeNotifier {
  final LlmApiClient _apiClient = LlmApiClient();
  final McpClient _mcpClient = McpClient();
  final ChatStorage _storage = ChatStorage.instance;
  final LuaExecutor _luaExecutor = LuaExecutor();

  // ── Multi-agent orchestration ───────────────────────────────────────
  final AgentExecutor _agentExecutor = AgentExecutor();
  final AgentRegistry _agentRegistry = AgentRegistry();

  /// Notifier for live sub-agent activity. The UI listens to this to
  /// show/hide the sub-agent dialog. null = no sub-agent running.
  final SubAgentActivityNotifier subAgentActivity = SubAgentActivityNotifier();

  /// Completed sub-agent activities, keyed by tool call ID.
  /// Allows the UI to re-open the dialog for past sub-agent runs.
  final Map<String, SubAgentActivity> completedSubAgentActivities = {};

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
  bool _cancelled = false;
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
        inputSchema: {'type': 'object', 'properties': {}, 'required': []},
      ),
      isSystemTool: true,
    ),
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'run_lua',
        description:
            'Execute a Lua 5.3 script in a sandboxed environment. '
            'Available: base (print, type, tostring, tonumber, pairs, ipairs, '
            'select, pcall, xpcall, error, assert, rawget, rawset, rawlen, rawequal, '
            'unpack, setmetatable, getmetatable), math, string, table, coroutine. '
            'NOT available: os, io, file, require, dofile, loadfile, debug, package. '
            'Use print() to produce output. The script runs with a 10 second timeout. '
            'Set persistent=true to keep variables/functions across calls in the same conversation.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'script': {
              'type': 'string',
              'description': 'The Lua script to execute.',
            },
            'persistent': {
              'type': 'boolean',
              'description':
                  'If true, Lua state persists across calls so variables '
                  'and functions defined earlier remain available. '
                  'Defaults to false (fresh VM each call).',
            },
          },
          'required': ['script'],
        },
      ),
      isSystemTool: true,
    ),
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'notify_user',
        description:
            'Send a system notification to the user\'s device. '
            'Use this to alert, remind, or inform the user with a notification '
            'that appears in the system notification shade even if the app is in background. '
            'Supports vibration, sound, silent mode, priority levels, and expandable text.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'The notification title (required).',
            },
            'body': {
              'type': 'string',
              'description': 'Short notification body text.',
            },
            'big_text': {
              'type': 'string',
              'description':
                  'Expandable long text shown when the notification is expanded. '
                  'Use for detailed content that doesn\'t fit in the body.',
            },
            'sub_text': {
              'type': 'string',
              'description': 'Small text shown below the notification content.',
            },
            'ticker': {
              'type': 'string',
              'description':
                  'Ticker text announced by accessibility services when the notification arrives.',
            },
            'vibrate': {
              'type': 'boolean',
              'description':
                  'Enable vibration when the notification is delivered. Defaults to true.',
            },
            'play_sound': {
              'type': 'boolean',
              'description':
                  'Play the default notification sound. Defaults to true.',
            },
            'silent': {
              'type': 'boolean',
              'description':
                  'If true, the notification is delivered silently — no sound, '
                  'no vibration, no heads-up popup. Defaults to false.',
            },
            'priority': {
              'type': 'string',
              'enum': ['min', 'low', 'default', 'high', 'max'],
              'description':
                  'Notification priority. "high"/"max" may show as heads-up. '
                  'Defaults to "default".',
            },
            'timeout_after_ms': {
              'type': 'integer',
              'description':
                  'Auto-dismiss the notification after this many milliseconds. '
                  'If not set, the notification persists until the user dismisses it.',
            },
          },
          'required': ['title'],
        },
      ),
      isSystemTool: true,
    ),
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'web_crawl',
        description:
            'Fetch and extract readable text content from a web page URL. '
            'Returns the page title and main text content with HTML stripped. '
            'Use this to read articles, documentation, blog posts, or any web page. '
            'Supports HTTP/HTTPS. Content is capped at 50KB of text.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description':
                  'The URL to crawl (e.g. "https://example.com/page"). '
                  'HTTP URLs are supported but HTTPS is preferred.',
            },
            'include_links': {
              'type': 'boolean',
              'description':
                  'If true, hyperlink URLs are included inline after link text '
                  'in [url] format. Defaults to false.',
            },
          },
          'required': ['url'],
        },
      ),
      isSystemTool: true,
    ),
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'web_search',
        description:
            'Search the web using DuckDuckGo. Returns titles, URLs, and '
            'snippets for the top results. Use this to find information, '
            'current events, documentation, code examples, news, etc. '
            'Combine with web_crawl to read specific results in full.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The search query.',
            },
            'max_results': {
              'type': 'integer',
              'description':
                  'Maximum number of results to return (1-10). Defaults to 5.',
            },
          },
          'required': ['query'],
        },
      ),
      isSystemTool: true,
    ),
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'rest_request',
        description:
            'Make an HTTP request to any REST API endpoint. '
            'Supports GET, POST, PUT, PATCH, DELETE, HEAD, and OPTIONS methods. '
            'Returns the status code, relevant headers, and response body. '
            'JSON responses are automatically pretty-printed. '
            'Use this to call APIs, test endpoints, fetch data, or interact with web services.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'method': {
              'type': 'string',
              'enum': ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'],
              'description': 'The HTTP method. Defaults to GET.',
            },
            'url': {
              'type': 'string',
              'description':
                  'The full URL to request (e.g. "https://api.example.com/users").',
            },
            'headers': {
              'type': 'object',
              'description':
                  'Optional HTTP headers as key-value pairs. '
                  'Example: {"Authorization": "Bearer token123", "Content-Type": "application/json"}',
            },
            'body': {
              'type': 'string',
              'description':
                  'Request body (for POST, PUT, PATCH). '
                  'For JSON APIs, provide a JSON string and set Content-Type header to application/json.',
            },
            'timeout_seconds': {
              'type': 'integer',
              'description':
                  'Request timeout in seconds (1-60). Defaults to 30.',
            },
          },
          'required': ['url'],
        },
      ),
      isSystemTool: true,
    ),
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'ssh_execute',
        description:
            'Execute a command on a remote server via SSH. '
            'Supports password and private-key authentication. '
            'Returns the exit code, stdout, and stderr of the command. '
            'Use this to manage servers, run diagnostics, deploy code, '
            'check logs, or perform any remote administration task.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'host': {
              'type': 'string',
              'description':
                  'The SSH server hostname or IP address (e.g. "192.168.1.10" or "myserver.example.com").',
            },
            'port': {
              'type': 'integer',
              'description': 'The SSH port. Defaults to 22.',
            },
            'username': {
              'type': 'string',
              'description': 'The SSH username to authenticate as.',
            },
            'password': {
              'type': 'string',
              'description':
                  'The password for password-based authentication. '
                  'Either "password" or "private_key" must be provided.',
            },
            'private_key': {
              'type': 'string',
              'description':
                  'The PEM-encoded private key for key-based authentication. '
                  'Either "password" or "private_key" must be provided.',
            },
            'passphrase': {
              'type': 'string',
              'description':
                  'The passphrase to decrypt the private key, if it is encrypted.',
            },
            'command': {
              'type': 'string',
              'description': 'The shell command to execute on the remote server.',
            },
            'timeout_seconds': {
              'type': 'integer',
              'description':
                  'Connection and execution timeout in seconds (1-120). Defaults to 30.',
            },
          },
          'required': ['host', 'username', 'command'],
        },
      ),
      isSystemTool: true,
    ),
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'memory_manage',
        description:
            'Persistent memory store that survives across chat sessions. '
            'Use this to save, recall, search, list, or delete information '
            'the user wants remembered (preferences, facts, notes, context). '
            'Memories are stored as key-value pairs with optional tags.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['save', 'recall', 'search', 'list', 'delete'],
              'description':
                  'The action to perform:\n'
                  '- save: Store or update a memory.\n'
                  '- recall: Retrieve a memory by exact key.\n'
                  '- search: Find memories by substring match in key, content, or tags.\n'
                  '- list: List all memories (optionally filtered by tag).\n'
                  '- delete: Remove a memory by key.',
            },
            'key': {
              'type': 'string',
              'description':
                  'The unique key for the memory. Required for save, recall, and delete. '
                  'Use short, descriptive, snake_case keys (e.g. "user_name", "project_stack").',
            },
            'content': {
              'type': 'string',
              'description':
                  'The content to store. Required for save.',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Optional tags for categorisation (e.g. ["preference", "work"]). '
                  'Used with save. When listing, pass a single tag to filter.',
            },
            'query': {
              'type': 'string',
              'description':
                  'Search query string. Required for the search action.',
            },
          },
          'required': ['action'],
        },
      ),
      isSystemTool: true,
    ),
    McpServerTool(
      serverName: _systemToolServerName,
      tool: McpTool(
        name: 'delegate_to_agent',
        description:
            'Delegate a task to a specialized sub-agent. Each sub-agent has '
            'its own expertise and tools. Use this when a task is best handled '
            'by a specialist rather than doing everything yourself.\n\n'
            'Available agents:\n'
            '- **researcher**: Web research specialist -- can search the internet, '
            'read web pages, and call REST APIs to gather information.\n'
            '- **coder**: Code execution specialist -- can write and run Lua scripts '
            'for computation, data processing, and problem solving.\n'
            '- **summarizer**: Text analysis specialist -- distills information into '
            'clear, concise summaries (no tools, pure reasoning).\n\n'
            'The sub-agent will execute independently and return its result to you. '
            'You can then use that result to continue your response.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'agent': {
              'type': 'string',
              'enum': ['researcher', 'coder', 'summarizer'],
              'description': 'The sub-agent to delegate the task to.',
            },
            'task': {
              'type': 'string',
              'description':
                  'A clear, detailed description of the task for the sub-agent. '
                  'Include all necessary context the sub-agent needs to complete the task.',
            },
            'context': {
              'type': 'string',
              'description':
                  'Optional additional context or data to pass to the sub-agent '
                  '(e.g. text to summarize, prior research results, etc.).',
            },
          },
          'required': ['agent', 'task'],
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
    // Register built-in sub-agents
    _agentRegistry.register(ResearcherAgent());
    _agentRegistry.register(CoderAgent());
    _agentRegistry.register(SummarizerAgent());

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
    if (isGenerating) cancelGeneration();
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
    if (isGenerating) cancelGeneration();
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
    _luaExecutor.resetState();
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
      _luaExecutor.resetState();
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

  void retryFromMessage(String messageId) {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0 || messages[idx].role != MessageRole.user) return;
    if (isGenerating) return;

    // Remove all messages after the user message
    messages.removeRange(idx + 1, messages.length);

    _saveCurrentSession();
    notifyListeners();

    // Re-generate the response with the same message
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

  /// Export a specific session (by ID) as a JSON map.
  Map<String, dynamic> exportSessionToJson(String sessionId) {
    final session = sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) return {};

    // Use current messages if it's the active session, otherwise load from storage
    final msgs = (activeSession?.id == sessionId)
        ? messages
        : _storage.getMessages(sessionId);

    return {
      'session': {
        'id': session.id,
        'name': session.name,
        'createdAt': session.createdAt.toIso8601String(),
        'exportedAt': DateTime.now().toIso8601String(),
      },
      'messages': msgs
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

    // Check if MCP servers changed (only consider enabled servers)
    final servers = SettingsRepository.instance.mcpServers
        .where((s) => s.enabled)
        .toList();
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
    final servers = SettingsRepository.instance.mcpServers
        .where((s) => s.enabled)
        .toList();
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
    _cancelled = false;
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
      _cancelled = false;
      _saveCurrentSession();
      notifyListeners();
    }
  }

  /// Cancel the ongoing LLM generation.
  void cancelGeneration() {
    if (!isGenerating) return;
    _cancelled = true;
    _apiClient.abortStream();
    notifyListeners();
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
      'You are Synapse, a helpful AI assistant.\n\n'
      'Response formatting:\n'
      'Your responses are rendered as rich markdown in the UI. The following features are fully supported:\n'
      '- **Text styling:** bold, italic, ~~strikethrough~~, headings (h1-h6), blockquotes, horizontal rules.\n'
      '- **Lists:** bullet lists, numbered lists, and task lists (- [ ] / - [x]).\n'
      '- **Tables:** GitHub-flavored pipe tables with styled headers and borders.\n'
      '- **Code:** fenced code blocks with syntax highlighting for 190+ languages '
      '(always specify the language, e.g. ```dart). Inline code with backticks for '
      'short references to symbols, file names, or commands.\n'
      '- **Math/LaTeX:** block math with \$\$...\$\$ or \\\\[...\\\\], '
      'inline math with \$...\$ or \\\\(...\\\\).\n'
      '- **Links:** [text](url) -- clickable, opens in external browser.\n'
      '- **Images:** ![alt](url) -- rendered inline.\n\n'
      'Use these capabilities when they improve clarity. '
      'Keep responses concise and well-structured; prefer bullet points or numbered lists over long paragraphs.',
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

  /// Maximum number of tool-calling rounds before forcing a final text response.
  static const int _maxToolRounds = 100;

  Future<void> _streamWithToolCalling(
    String assistantId,
    LlmModel model,
    List<ChatRequestMessage> conversationHistory,
    List<OpenAiTool>? openAiTools,
    List<McpServerTool> mcpToolsList, {
    int currentRound = 0,
  }) async {
    // Only send tools to the API if we haven't exceeded the max rounds.
    final toolsForRequest = currentRound < _maxToolRounds ? openAiTools : null;

    final eventStream = _apiClient.streamWithTools(
      model: model,
      conversationHistory: conversationHistory,
      tools: toolsForRequest,
    );

    final builder = StringBuffer();
    var toolCallHandled = false;

    await for (final event in eventStream) {
      if (_cancelled) break;
      switch (event) {
        case TokenEvent():
          builder.write(event.text);
          _updateMessage(assistantId, content: builder.toString());
        case DoneEvent():
          if (toolCallHandled) continue;
          final toolCalls = event.toolCalls;
          if (toolCalls.isNotEmpty &&
              toolCalls.any((tc) => tc.function.name.isNotEmpty) &&
              currentRound < _maxToolRounds) {
            toolCallHandled = true;
            await _handleToolCalls(
              assistantId,
              model,
              conversationHistory,
              toolCalls,
              mcpToolsList,
              openAiTools,
              currentRound: currentRound + 1,
              thinkingText: builder.toString(),
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

    // Mark any still-running tool calls as cancelled when the user cancels.
    if (_cancelled) {
      _markRunningToolCallsAsCancelled(assistantId);
    }
  }

  Future<void> _handleToolCalls(
    String assistantId,
    LlmModel model,
    List<ChatRequestMessage> originalHistory,
    List<ToolCallInfo> toolCalls,
    List<McpServerTool> tools,
    List<OpenAiTool>? openAiTools, {
    int currentRound = 1,
    String thinkingText = '',
  }) async {
    // Create ToolCallEntry list for UI display.
    // Set round on every entry; thinkingText only on the first entry.
    final filteredCalls =
        toolCalls.where((tc) => tc.function.name.isNotEmpty).toList();
    final newToolCallEntries = <ToolCallEntry>[];
    for (int i = 0; i < filteredCalls.length; i++) {
      final tc = filteredCalls[i];
      newToolCallEntries.add(ToolCallEntry(
        id: tc.id,
        toolName: tc.function.name,
        arguments: tc.function.arguments,
        status: ToolCallStatus.running,
        round: currentRound,
        thinkingText: i == 0 ? thinkingText.trim() : '',
      ));
    }

    // Preserve tool call entries from previous rounds so they remain visible
    // in the UI, and append the new round's entries.
    final msgIdx = messages.indexWhere((m) => m.id == assistantId);
    final existingToolCalls = msgIdx >= 0
        ? List<ToolCallEntry>.from(messages[msgIdx].toolCalls)
        : <ToolCallEntry>[];
    final allToolCallEntries = [...existingToolCalls, ...newToolCallEntries];

    // Update the assistant message with tool call entries (visible in UI).
    // Clear intermediate content -- it is now preserved in thinkingText on the
    // first tool call entry of this round, so keeping it in message.content
    // would cause it to render twice during streaming.
    _updateMessage(
      assistantId,
      content: '',
      toolCalls: List<ToolCallEntry>.from(allToolCallEntries),
    );

    // Execute each tool call and update entries progressively
    for (int i = 0; i < toolCalls.length; i++) {
      if (_cancelled) break;

      final call = toolCalls[i];
      final toolName = call.function.name;
      if (toolName.isEmpty) continue;

      final serverTool = tools
          .where((t) => t.tool.name == toolName)
          .firstOrNull;

      String resultContent;
      Map<String, dynamic> args;
      try {
        args = jsonDecode(call.function.arguments) as Map<String, dynamic>;
      } catch (_) {
        args = {};
      }

      if (serverTool != null && serverTool.isSystemTool) {
        resultContent = await _executeSystemTool(toolName, args,
            toolCallId: call.id);
      } else if (serverTool != null) {
        try {
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

      // Update the entry with result, preserving round and thinkingText.
      final entryIdx = allToolCallEntries.indexWhere((e) => e.id == call.id);
      if (entryIdx >= 0) {
        allToolCallEntries[entryIdx].result = resultContent;
        allToolCallEntries[entryIdx].status = resultContent.startsWith('Error')
            ? ToolCallStatus.error
            : ToolCallStatus.completed;
        // Create a new list with new entry objects so the UI properly detects changes.
        _updateMessage(
          assistantId,
          toolCalls: [
            for (final e in allToolCallEntries)
              ToolCallEntry(
                id: e.id,
                toolName: e.toolName,
                arguments: e.arguments,
                result: e.result,
                status: e.status,
                round: e.round,
                thinkingText: e.thinkingText,
              ),
          ],
        );
      }
    }

    // If cancelled mid-execution, mark remaining running entries and stop.
    if (_cancelled) {
      _markRunningToolCallsAsCancelled(assistantId);
      return;
    }

    // Build proper OpenAI-compatible conversation history:
    // 1. Original history
    // 2. Assistant message with tool_calls (role: assistant)
    // 3. Tool result messages (role: tool, one per tool call)
    final extendedHistory = originalHistory.toList();

    // Add assistant message that contains the tool_calls
    extendedHistory.add(
      ChatRequestMessage(
        role: 'assistant',
        toolCalls: toolCalls.where((tc) => tc.function.name.isNotEmpty).toList(),
      ),
    );

    // Add tool result messages (role: tool with tool_call_id)
    for (final entry in newToolCallEntries) {
      extendedHistory.add(
        ChatRequestMessage(
          role: 'tool',
          content: entry.result,
          toolCallId: entry.id,
        ),
      );
    }

    // Continue streaming -- pass tools forward so the model can make
    // additional tool calls if needed (up to _maxToolRounds).
    await _streamWithToolCalling(
      assistantId,
      model,
      extendedHistory,
      openAiTools,
      tools,
      currentRound: currentRound,
    );
  }

  /// Execute a built-in system tool and return its result.
  Future<String> _executeSystemTool(
    String toolName,
    Map<String, dynamic> args, {
    String? toolCallId,
  }) async {
    switch (toolName) {
      case 'current_date_time':
        final now = DateTime.now();
        final dateTime =
            '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}, ${now.year} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        return dateTime;
      case 'run_lua':
        final script = args['script'] as String? ?? '';
        if (script.trim().isEmpty) {
          return 'Error: No script provided.';
        }
        final persistent = args['persistent'] as bool? ?? false;
        final result = await _luaExecutor.execute(
          script,
          persistent: persistent,
        );
        return result.toToolOutput();
      case 'notify_user':
        final title = args['title'] as String? ?? '';
        if (title.trim().isEmpty) {
          return 'Error: Notification title is required.';
        }
        return await NotificationService.instance.notify(
          title: title,
          body: args['body'] as String?,
          bigText: args['big_text'] as String?,
          subText: args['sub_text'] as String?,
          ticker: args['ticker'] as String?,
          vibrate: args['vibrate'] as bool? ?? true,
          playSound: args['play_sound'] as bool? ?? true,
          silent: args['silent'] as bool? ?? false,
          priority: args['priority'] as String? ?? 'default',
          timeoutAfterMs: args['timeout_after_ms'] as int?,
        );
      case 'web_crawl':
        final url = args['url'] as String? ?? '';
        if (url.trim().isEmpty) {
          return 'Error: URL is required.';
        }
        final includeLinks = args['include_links'] as bool? ?? false;
        final result = await WebCrawler.crawl(url, includeLinks: includeLinks);
        if (!result.isSuccess) {
          return 'Error: ${result.error}';
        }
        return result.toString();
      case 'web_search':
        final query = args['query'] as String? ?? '';
        if (query.trim().isEmpty) {
          return 'Error: Search query is required.';
        }
        final maxResults = (args['max_results'] as int?) ?? 5;
        return await WebSearchService.search(query, maxResults: maxResults);
      case 'rest_request':
        final url = args['url'] as String? ?? '';
        if (url.trim().isEmpty) {
          return 'Error: URL is required.';
        }
        final method = (args['method'] as String?) ?? 'GET';
        final headersRaw = args['headers'];
        Map<String, String>? headers;
        if (headersRaw is Map) {
          headers = headersRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
        final body = args['body'] as String?;
        final timeoutSeconds = args['timeout_seconds'] as int?;
        return await RestClientService.request(
          method: method,
          url: url,
          headers: headers,
          body: body,
          timeoutSeconds: timeoutSeconds,
        );
      case 'ssh_execute':
        final sshHost = args['host'] as String? ?? '';
        if (sshHost.trim().isEmpty) {
          return 'Error: SSH host is required.';
        }
        final sshUsername = args['username'] as String? ?? '';
        if (sshUsername.trim().isEmpty) {
          return 'Error: SSH username is required.';
        }
        final sshCommand = args['command'] as String? ?? '';
        if (sshCommand.trim().isEmpty) {
          return 'Error: SSH command is required.';
        }
        return await SshService.execute(
          host: sshHost,
          port: (args['port'] as int?) ?? 22,
          username: sshUsername,
          password: args['password'] as String?,
          privateKey: args['private_key'] as String?,
          passphrase: args['passphrase'] as String?,
          command: sshCommand,
          timeoutSeconds: (args['timeout_seconds'] as int?) ?? 30,
        );
      case 'memory_manage':
        return _executeMemoryManage(args);
      case 'delegate_to_agent':
        return await _executeDelegateToAgent(args, toolCallId: toolCallId);
      default:
        return "Error: Unknown system tool '$toolName'";
    }
  }

  /// Execute the memory_manage system tool.
  String _executeMemoryManage(Map<String, dynamic> args) {
    final action = args['action'] as String? ?? '';
    final memory = MemoryService.instance;

    switch (action) {
      case 'save':
        final key = args['key'] as String? ?? '';
        if (key.trim().isEmpty) return 'Error: "key" is required for save.';
        final content = args['content'] as String? ?? '';
        if (content.trim().isEmpty) {
          return 'Error: "content" is required for save.';
        }
        final tags = (args['tags'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        return memory.save(key: key, content: content, tags: tags);
      case 'recall':
        final key = args['key'] as String? ?? '';
        if (key.trim().isEmpty) return 'Error: "key" is required for recall.';
        return memory.recall(key);
      case 'search':
        final query = args['query'] as String? ?? '';
        if (query.trim().isEmpty) {
          return 'Error: "query" is required for search.';
        }
        return memory.search(query);
      case 'list':
        final tags = args['tags'] as List<dynamic>?;
        final tag = tags != null && tags.isNotEmpty ? tags.first.toString() : null;
        return memory.list(tag: tag);
      case 'delete':
        final key = args['key'] as String? ?? '';
        if (key.trim().isEmpty) return 'Error: "key" is required for delete.';
        return memory.delete(key);
      default:
        return 'Error: Unknown memory action "$action". '
            'Use save, recall, search, list, or delete.';
    }
  }

  /// Execute the delegate_to_agent meta-tool: run a sub-agent via
  /// [AgentExecutor] and return its result as a tool output.
  ///
  /// Pushes live updates to [subAgentActivity] so the UI can show a
  /// real-time dialog of the sub-agent's progress. Completed activities
  /// are stored in [completedSubAgentActivities] so they can be re-opened.
  Future<String> _executeDelegateToAgent(
    Map<String, dynamic> args, {
    String? toolCallId,
  }) async {
    final agentName = args['agent'] as String? ?? '';
    final taskDesc = args['task'] as String? ?? '';
    final context = args['context'] as String?;

    if (agentName.isEmpty) return 'Error: Agent name is required.';
    if (taskDesc.isEmpty) return 'Error: Task description is required.';

    final agent = _agentRegistry.get(agentName);
    if (agent == null) {
      return 'Error: Unknown agent "$agentName". '
          'Available agents: ${_agentRegistry.names.join(", ")}';
    }

    // Use the currently selected model for the sub-agent
    final model = selectedModel;
    if (model == null) return 'Error: No model selected for sub-agent execution.';

    // Start live activity tracking
    final activity = SubAgentActivity(
      agentName: agent.name,
      agentRole: agent.role,
      taskDescription: taskDesc,
      toolCallId: toolCallId,
    );
    subAgentActivity.value = activity;

    final task = AgentTask(description: taskDesc, context: context);
    final result = await _agentExecutor.run(
      agent: agent,
      task: task,
      model: model,
      onToken: (token) {
        activity.streamingContent += token;
        subAgentActivity.notify();
      },
      onToolCall: (toolName, arguments, resultContent) {
        if (resultContent == null) {
          // Tool call started
          activity.toolCalls.add(SubAgentToolCall(
            toolName: toolName,
            arguments: arguments,
          ));
        } else {
          // Tool call finished -- update the last matching entry
          final entry = activity.toolCalls.lastWhere(
            (t) => t.toolName == toolName && t.result == null,
            orElse: () => activity.toolCalls.last,
          );
          entry.result = resultContent;
          entry.status = resultContent.startsWith('Error')
              ? SubAgentToolStatus.error
              : SubAgentToolStatus.completed;
        }
        subAgentActivity.notify();
      },
    );

    // Mark activity as complete
    activity.isRunning = false;
    activity.isComplete = true;
    if (!result.success) {
      activity.error = result.error;
    } else {
      // Update streaming content with final result in case the last
      // streaming round cleared it
      activity.streamingContent = result.content;
    }
    subAgentActivity.notify();

    // Store the completed activity so it can be re-opened from the tile
    if (toolCallId != null) {
      completedSubAgentActivities[toolCallId] = activity;
    }

    if (!result.success) {
      return 'Sub-agent "$agentName" failed: ${result.error}';
    }

    return '[Sub-agent: ${agent.name}]\n\n${result.content}';
  }

  void _updateMessage(String id, {String? content, bool? streaming, List<ToolCallEntry>? toolCalls}) {
    final idx = messages.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      if (content != null) messages[idx].content = content;
      if (streaming != null) messages[idx].isStreaming = streaming;
      if (toolCalls != null) {
        messages[idx] = messages[idx].copyWith(toolCalls: toolCalls);
      }
      notifyListeners();
    }
  }

  /// Mark any tool calls still in [ToolCallStatus.running] as cancelled.
  void _markRunningToolCallsAsCancelled(String assistantId) {
    final idx = messages.indexWhere((m) => m.id == assistantId);
    if (idx < 0 || messages[idx].toolCalls.isEmpty) return;
    final updated = messages[idx].toolCalls.map((e) {
      if (e.status == ToolCallStatus.running) {
        return ToolCallEntry(
          id: e.id,
          toolName: e.toolName,
          arguments: e.arguments,
          result: 'Cancelled',
          status: ToolCallStatus.cancelled,
          round: e.round,
          thinkingText: e.thinkingText,
        );
      }
      return e;
    }).toList();
    _updateMessage(assistantId, toolCalls: updated);
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
