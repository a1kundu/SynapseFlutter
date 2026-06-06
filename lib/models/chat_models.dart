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
}

/// Sender role for a chat message.
enum MessageRole { user, assistant }

/// A single chat message.
class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  final int timestamp;
  final List<ChatAttachment> attachments;
  final LlmModel? model;
  bool isStreaming;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.attachments = const [],
    this.model,
    this.isStreaming = false,
  });

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      attachments: attachments,
      model: model,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  static String generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
