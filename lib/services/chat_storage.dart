import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_models.dart';
import '../models/chat_session.dart';

/// Persistent storage for chat sessions and messages using SharedPreferences.
class ChatStorage {
  static const _sessionsKey = 'chat_sessions';
  static const _sessionPrefix = 'chat_session_';
  static const _activeSessionKey = 'active_session_id';

  static ChatStorage? _instance;
  static ChatStorage get instance => _instance ??= ChatStorage._();
  ChatStorage._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get all chat sessions, sorted by most recently updated first.
  List<ChatSession> getSessions() {
    final json = _prefs?.getString(_sessionsKey);
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return [];
    }
  }

  /// Save all session metadata.
  void saveSessions(List<ChatSession> sessions) {
    final json = jsonEncode(sessions.map((s) => s.toJson()).toList());
    _prefs?.setString(_sessionsKey, json);
  }

  /// Get messages for a specific session.
  List<ChatMessage> getMessages(String sessionId) {
    final json = _prefs?.getString('$_sessionPrefix$sessionId');
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save messages for a specific session.
  void saveMessages(String sessionId, List<ChatMessage> messages) {
    final json = jsonEncode(messages.map((m) => m.toJson()).toList());
    _prefs?.setString('$_sessionPrefix$sessionId', json);
  }

  /// Delete a session and its messages.
  void deleteSessionData(String sessionId) {
    _prefs?.remove('$_sessionPrefix$sessionId');
    final sessions = getSessions().where((s) => s.id != sessionId).toList();
    saveSessions(sessions);
  }

  /// Get the last active session ID.
  String? get activeSessionId => _prefs?.getString(_activeSessionKey);

  /// Set the active session ID.
  set activeSessionId(String? id) {
    if (id != null) {
      _prefs?.setString(_activeSessionKey, id);
    } else {
      _prefs?.remove(_activeSessionKey);
    }
  }
}
