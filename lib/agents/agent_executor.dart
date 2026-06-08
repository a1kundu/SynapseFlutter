import 'dart:convert';
import '../models/chat_models.dart';
import '../models/llm_models.dart';
import '../models/mcp_models.dart';
import '../services/llm_api_client.dart';
import '../services/mcp_client.dart';
import '../services/lua_executor.dart';
import '../services/notification_service.dart';
import '../services/rest_client_service.dart';
import '../services/web_search_service.dart';
import '../services/web_crawler.dart';
import 'agent.dart';
import 'agent_models.dart';

/// Callback for streaming tokens from a sub-agent (optional, for UI).
typedef TokenCallback = void Function(String token);

/// Callback for tool call progress from a sub-agent (optional, for UI).
typedef ToolCallCallback = void Function(
    String toolName, String arguments, String? result);

/// Executes an [Agent] by running the LLM streaming + tool-calling loop.
///
/// This is the reusable engine extracted from ChatController. It can run
/// any Agent headlessly (no UI state) -- the orchestrator or a sub-agent.
class AgentExecutor {
  final LlmApiClient _apiClient;
  final McpClient _mcpClient;
  final LuaExecutor _luaExecutor;

  AgentExecutor({
    LlmApiClient? apiClient,
    McpClient? mcpClient,
    LuaExecutor? luaExecutor,
  })  : _apiClient = apiClient ?? LlmApiClient(),
        _mcpClient = mcpClient ?? McpClient(),
        _luaExecutor = luaExecutor ?? LuaExecutor();

  /// Execute an [agent] with the given [task] using the specified [model].
  ///
  /// Returns an [AgentResult] with the agent's final response.
  /// Optional callbacks [onToken] and [onToolCall] allow the caller to
  /// observe streaming progress (useful for UI updates).
  Future<AgentResult> run({
    required Agent agent,
    required AgentTask task,
    required LlmModel model,
    TokenCallback? onToken,
    ToolCallCallback? onToolCall,
  }) async {
    try {
      // Build the initial conversation for this agent
      final conversationHistory = _buildInitialHistory(agent, task);
      final tools = agent.tools;
      final hasTools = tools.isNotEmpty;
      final modelSupportsTools = model.supportsTools;

      // Convert agent tools to OpenAI format if the model supports native
      // function calling
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

      // If the model does NOT support native tool calling, describe tools in
      // the system prompt so the model can attempt to use them via text output.
      if (hasTools && !modelSupportsTools) {
        final toolDescriptions = tools.map((st) {
          final schema = st.tool.inputSchema != null
              ? jsonEncode(st.tool.inputSchema)
              : '{}';
          return '- **${st.tool.name}**: '
              '${st.tool.description ?? "No description"}\n'
              '  Input schema: $schema';
        }).join('\n\n');

        // Prepend tool descriptions to the system prompt
        final systemMsg = conversationHistory.first;
        conversationHistory[0] = ChatRequestMessage(
          role: 'system',
          content:
              '${systemMsg.content}\n\n## Available Tools\n\n$toolDescriptions\n\n'
              'To use a tool, respond with a JSON block: '
              '{"tool": "tool_name", "arguments": {...}}',
        );
      }

      final result = await _streamWithToolCalling(
        model: model,
        conversationHistory: conversationHistory,
        openAiTools: openAiTools,
        tools: modelSupportsTools ? tools : [],
        maxRounds: agent.maxToolRounds,
        onToken: onToken,
        onToolCall: onToolCall,
      );

      return AgentResult(content: result);
    } catch (e) {
      return AgentResult.failure('Agent "${agent.name}" failed: $e');
    }
  }

  /// Build the initial conversation history for an agent task.
  List<ChatRequestMessage> _buildInitialHistory(Agent agent, AgentTask task) {
    final history = <ChatRequestMessage>[];

    // System message with agent's persona
    history.add(ChatRequestMessage(
      role: 'system',
      content: agent.systemPrompt,
    ));

    // User message with the task
    final userContent = StringBuffer(task.description);
    if (task.context != null && task.context!.isNotEmpty) {
      userContent.write('\n\n## Additional Context\n\n${task.context}');
    }
    history.add(ChatRequestMessage(
      role: 'user',
      content: userContent.toString(),
    ));

    return history;
  }

  /// Core streaming + tool-calling loop. Extracted from ChatController.
  ///
  /// Supports multiple tool-calling rounds (up to [maxRounds]) unlike the
  /// original which was hardcoded to a single round.
  Future<String> _streamWithToolCalling({
    required LlmModel model,
    required List<ChatRequestMessage> conversationHistory,
    required List<OpenAiTool>? openAiTools,
    required List<McpServerTool> tools,
    required int maxRounds,
    TokenCallback? onToken,
    ToolCallCallback? onToolCall,
    int currentRound = 0,
  }) async {
    final eventStream = _apiClient.streamWithTools(
      model: model,
      conversationHistory: conversationHistory,
      tools: currentRound < maxRounds ? openAiTools : null,
    );

    final builder = StringBuffer();
    var toolCallHandled = false;

    await for (final event in eventStream) {
      switch (event) {
        case TokenEvent():
          builder.write(event.text);
          onToken?.call(event.text);
        case DoneEvent():
          if (toolCallHandled) continue;
          final toolCalls = event.toolCalls;
          if (toolCalls.isNotEmpty &&
              toolCalls.any((tc) => tc.function.name.isNotEmpty) &&
              currentRound < maxRounds) {
            toolCallHandled = true;
            final result = await _handleToolCalls(
              model: model,
              originalHistory: conversationHistory,
              toolCalls: toolCalls,
              tools: tools,
              openAiTools: openAiTools,
              maxRounds: maxRounds,
              currentRound: currentRound + 1,
              onToken: onToken,
              onToolCall: onToolCall,
            );
            builder.clear();
            builder.write(result);
          }
        case ErrorEvent():
          if (builder.isEmpty) {
            builder.write('Error: ${event.message}');
          }
      }
    }

    return builder.toString();
  }

  /// Handle tool calls: execute each tool, build extended history, recurse.
  Future<String> _handleToolCalls({
    required LlmModel model,
    required List<ChatRequestMessage> originalHistory,
    required List<ToolCallInfo> toolCalls,
    required List<McpServerTool> tools,
    required List<OpenAiTool>? openAiTools,
    required int maxRounds,
    required int currentRound,
    TokenCallback? onToken,
    ToolCallCallback? onToolCall,
  }) async {
    final results = <String, String>{}; // toolCallId -> result

    for (final call in toolCalls) {
      final toolName = call.function.name;
      if (toolName.isEmpty) continue;

      final serverTool =
          tools.where((t) => t.tool.name == toolName).firstOrNull;

      Map<String, dynamic> args;
      try {
        args = jsonDecode(call.function.arguments) as Map<String, dynamic>;
      } catch (_) {
        args = {};
      }

      onToolCall?.call(toolName, call.function.arguments, null);

      String resultContent;
      if (serverTool != null && serverTool.isSystemTool) {
        resultContent = await _executeSystemTool(toolName, args);
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

      results[call.id] = resultContent;
      onToolCall?.call(toolName, call.function.arguments, resultContent);
    }

    // Build extended history with tool calls + results
    final extendedHistory = originalHistory.toList();

    // Add assistant message that contains the tool_calls
    extendedHistory.add(ChatRequestMessage(
      role: 'assistant',
      toolCalls:
          toolCalls.where((tc) => tc.function.name.isNotEmpty).toList(),
    ));

    // Add tool result messages
    for (final call in toolCalls) {
      if (call.function.name.isEmpty) continue;
      extendedHistory.add(ChatRequestMessage(
        role: 'tool',
        content: results[call.id] ?? '',
        toolCallId: call.id,
      ));
    }

    // Recurse with updated history
    return _streamWithToolCalling(
      model: model,
      conversationHistory: extendedHistory,
      openAiTools: openAiTools,
      tools: tools,
      maxRounds: maxRounds,
      currentRound: currentRound,
      onToken: onToken,
      onToolCall: onToolCall,
    );
  }

  /// Execute a built-in system tool. Mirrors ChatController._executeSystemTool
  /// but is self-contained so sub-agents can use system tools independently.
  Future<String> _executeSystemTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    switch (toolName) {
      case 'current_date_time':
        final now = DateTime.now();
        final days = [
          'Monday', 'Tuesday', 'Wednesday', 'Thursday',
          'Friday', 'Saturday', 'Sunday',
        ];
        final months = [
          'January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December',
        ];
        return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      case 'run_lua':
        final script = args['script'] as String? ?? '';
        if (script.trim().isEmpty) return 'Error: No script provided.';
        final persistent = args['persistent'] as bool? ?? false;
        final result = await _luaExecutor.execute(
          script,
          persistent: persistent,
        );
        return result.toToolOutput();
      case 'notify_user':
        final title = args['title'] as String? ?? '';
        if (title.trim().isEmpty) return 'Error: Notification title is required.';
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
        if (url.trim().isEmpty) return 'Error: URL is required.';
        final includeLinks = args['include_links'] as bool? ?? false;
        final result = await WebCrawler.crawl(url, includeLinks: includeLinks);
        if (!result.isSuccess) return 'Error: ${result.error}';
        return result.toString();
      case 'web_search':
        final query = args['query'] as String? ?? '';
        if (query.trim().isEmpty) return 'Error: Search query is required.';
        final maxResults = (args['max_results'] as int?) ?? 5;
        return await WebSearchService.search(query, maxResults: maxResults);
      case 'rest_request':
        final url = args['url'] as String? ?? '';
        if (url.trim().isEmpty) return 'Error: URL is required.';
        final method = (args['method'] as String?) ?? 'GET';
        final headersRaw = args['headers'];
        Map<String, String>? headers;
        if (headersRaw is Map) {
          headers =
              headersRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
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
      default:
        return "Error: Unknown system tool '$toolName'";
    }
  }
}
