/// LLM provider enum with display names and default URLs.
enum LlmProvider {
  openai('OpenAI', 'https://api.openai.com/v1'),
  openRouter('OpenRouter', 'https://openrouter.ai/api/v1'),
  githubModels('GitHub Models', 'https://models.github.ai');

  final String displayName;
  final String defaultBaseUrl;
  const LlmProvider(this.displayName, this.defaultBaseUrl);
}

/// OpenAI-compatible chat request message.
class ChatRequestMessage {
  final String role;
  final String? content;
  final String? toolCallId;
  final List<ToolCallInfo>? toolCalls;

  const ChatRequestMessage({
    required this.role,
    this.content,
    this.toolCallId,
    this.toolCalls,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'role': role};
    if (content != null) map['content'] = content;
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    if (toolCalls != null) {
      map['tool_calls'] = toolCalls!.map((t) => t.toJson()).toList();
    }
    return map;
  }
}

/// OpenAI tool definition.
class OpenAiTool {
  final String type;
  final OpenAiFunction function;

  const OpenAiTool({this.type = 'function', required this.function});

  Map<String, dynamic> toJson() => {
    'type': type,
    'function': function.toJson(),
  };
}

/// OpenAI function definition.
class OpenAiFunction {
  final String name;
  final String description;
  final Map<String, dynamic>? parameters;

  const OpenAiFunction({
    required this.name,
    this.description = '',
    this.parameters,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'description': description,
    };
    if (parameters != null) map['parameters'] = parameters;
    return map;
  }
}

/// Tool call info from a response.
class ToolCallInfo {
  final String id;
  final String type;
  final ToolCallFunctionInfo function;

  const ToolCallInfo({
    this.id = '',
    this.type = 'function',
    this.function = const ToolCallFunctionInfo(),
  });

  factory ToolCallInfo.fromJson(Map<String, dynamic> json) {
    return ToolCallInfo(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'function',
      function: ToolCallFunctionInfo.fromJson(
        json['function'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'function': function.toJson(),
  };
}

/// Tool call function info.
class ToolCallFunctionInfo {
  final String name;
  final String arguments;

  const ToolCallFunctionInfo({this.name = '', this.arguments = ''});

  factory ToolCallFunctionInfo.fromJson(Map<String, dynamic> json) {
    return ToolCallFunctionInfo(
      name: json['name'] as String? ?? '',
      arguments: json['arguments'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'arguments': arguments,
  };
}

/// Events emitted from a streaming chat completion with tool support.
sealed class StreamEvent {}

class TokenEvent extends StreamEvent {
  final String text;
  TokenEvent(this.text);
}

class DoneEvent extends StreamEvent {
  final List<ToolCallInfo> toolCalls;
  DoneEvent(this.toolCalls);
}

class ErrorEvent extends StreamEvent {
  final String message;
  ErrorEvent(this.message);
}
