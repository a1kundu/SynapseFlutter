import 'dart:math';

/// Represents a selectable LLM model.
class LlmModel {
  final String id;
  final String displayName;
  final String provider;
  final bool supportsTools;

  const LlmModel({
    required this.id,
    required this.displayName,
    required this.provider,
    this.supportsTools = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'provider': provider,
        'supportsTools': supportsTools,
      };

  factory LlmModel.fromJson(Map<String, dynamic> json) => LlmModel(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        provider: json['provider'] as String,
        supportsTools: json['supportsTools'] as bool? ?? true,
      );
}

/// A file attachment on a chat message.
class ChatAttachment {
  final String fileName;
  final int fileSizeBytes;
  final String mimeType;
  final List<int>? bytes;

  const ChatAttachment({
    required this.fileName,
    required this.fileSizeBytes,
    required this.mimeType,
    this.bytes,
  });

  String get displaySize {
    final kb = fileSizeBytes / 1024.0;
    if (kb < 1024) {
      return '${(kb * 10).truncate() / 10.0} KB';
    } else {
      return '${(kb / 1024.0 * 10).truncate() / 10.0} MB';
    }
  }

  /// Whether this is a text-based file whose content can be included in LLM context.
  bool get isTextBased {
    return mimeType.startsWith('text/') ||
        mimeType == 'application/json' ||
        mimeType == 'application/xml' ||
        mimeType == 'application/javascript';
  }

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'fileSizeBytes': fileSizeBytes,
        'mimeType': mimeType,
        // bytes are NOT persisted (too large for SharedPreferences)
      };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        fileName: json['fileName'] as String,
        fileSizeBytes: json['fileSizeBytes'] as int,
        mimeType: json['mimeType'] as String,
      );
}

/// Sender role for a chat message.
enum MessageRole { user, assistant }

/// Status of a tool call execution.
enum ToolCallStatus { running, completed, error, cancelled }

/// Represents a single tool call with its arguments and result.
class ToolCallEntry {
  final String id;
  final String toolName;
  final String arguments;
  String result;
  ToolCallStatus status;
  /// Which tool-calling round this entry belongs to (1-indexed).
  final int round;
  /// Text the model streamed before emitting this round's tool calls.
  /// Only set on the first entry of each round to avoid duplication.
  final String thinkingText;

  ToolCallEntry({
    required this.id,
    required this.toolName,
    required this.arguments,
    this.result = '',
    this.status = ToolCallStatus.running,
    this.round = 0,
    this.thinkingText = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'toolName': toolName,
        'arguments': arguments,
        'result': result,
        'status': status.name,
        'round': round,
        if (thinkingText.isNotEmpty) 'thinkingText': thinkingText,
      };

  factory ToolCallEntry.fromJson(Map<String, dynamic> json) => ToolCallEntry(
        id: json['id'] as String? ?? '',
        toolName: json['toolName'] as String? ?? '',
        arguments: json['arguments'] as String? ?? '',
        result: json['result'] as String? ?? '',
        status: ToolCallStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => ToolCallStatus.completed,
        ),
        round: json['round'] as int? ?? 0,
        thinkingText: json['thinkingText'] as String? ?? '',
      );
}

/// A single chat message.
class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  final int timestamp;
  final List<ChatAttachment> attachments;
  final LlmModel? model;
  bool isStreaming;
  final List<ToolCallEntry> toolCalls;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.attachments = const [],
    this.model,
    this.isStreaming = false,
    this.toolCalls = const [],
  });

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    List<ToolCallEntry>? toolCalls,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      attachments: attachments,
      model: model,
      isStreaming: isStreaming ?? this.isStreaming,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'timestamp': timestamp,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        if (model != null) 'model': model!.toJson(),
        if (toolCalls.isNotEmpty)
          'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: MessageRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => MessageRole.assistant,
        ),
        content: json['content'] as String? ?? '',
        timestamp: json['timestamp'] as int? ?? 0,
        attachments: (json['attachments'] as List?)
                ?.map(
                    (a) => ChatAttachment.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        model: json['model'] != null
            ? LlmModel.fromJson(json['model'] as Map<String, dynamic>)
            : null,
        toolCalls: (json['toolCalls'] as List?)
                ?.map(
                    (t) => ToolCallEntry.fromJson(t as Map<String, dynamic>))
                .toList() ??
            [],
      );

  static String generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
