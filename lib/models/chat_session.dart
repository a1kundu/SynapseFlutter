import 'dart:math';

/// Represents a single chat session / conversation.
class ChatSession {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  static String generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random();
    return List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Auto-generate a session name from the first user message.
  static String generateName(String firstMessage) {
    final trimmed = firstMessage.trim();
    if (trimmed.isEmpty) return 'New Chat';
    // Take first line, truncate at 50 chars
    final firstLine = trimmed.split('\n').first;
    if (firstLine.length > 50) return '${firstLine.substring(0, 47)}...';
    return firstLine;
  }
}
