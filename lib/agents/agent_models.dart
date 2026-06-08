// Data classes for the multi-agent orchestration system.

import 'package:flutter/foundation.dart';

/// A task to be executed by an agent.
class AgentTask {
  /// Human-readable description of what the agent should do.
  final String description;

  /// Optional additional context (e.g. data from prior agent results).
  final String? context;

  const AgentTask({required this.description, this.context});
}

/// The result returned by an agent after execution.
class AgentResult {
  /// The final text content produced by the agent.
  final String content;

  /// Whether the agent completed successfully.
  final bool success;

  /// Optional error message if the agent failed.
  final String? error;

  const AgentResult({
    required this.content,
    this.success = true,
    this.error,
  });

  factory AgentResult.failure(String error) =>
      AgentResult(content: '', success: false, error: error);
}

/// Status of a tool call within a sub-agent's execution.
enum SubAgentToolStatus { running, completed, error }

/// A single tool call made by a sub-agent (for live UI display).
class SubAgentToolCall {
  final String toolName;
  final String arguments;
  String? result;
  SubAgentToolStatus status;

  SubAgentToolCall({
    required this.toolName,
    required this.arguments,
    this.result,
    this.status = SubAgentToolStatus.running,
  });
}

/// Live activity state of a running sub-agent.
///
/// Used by the UI to show a real-time dialog of what the sub-agent is doing.
/// Emitted via a [ValueNotifier] so only the dialog rebuilds on each update.
class SubAgentActivity {
  /// The sub-agent's name (e.g. "researcher", "coder").
  final String agentName;

  /// The sub-agent's role description.
  final String agentRole;

  /// The task description given to the sub-agent.
  final String taskDescription;

  /// The tool call ID that triggered this sub-agent (for matching with tiles).
  final String? toolCallId;

  /// The content being streamed by the sub-agent (accumulated tokens).
  String streamingContent;

  /// Tool calls the sub-agent has made so far.
  final List<SubAgentToolCall> toolCalls;

  /// Whether the sub-agent is still running.
  bool isRunning;

  /// Whether the sub-agent has completed (successfully or with error).
  bool isComplete;

  /// Error message if the sub-agent failed.
  String? error;

  SubAgentActivity({
    required this.agentName,
    required this.agentRole,
    required this.taskDescription,
    this.toolCallId,
    this.streamingContent = '',
    List<SubAgentToolCall>? toolCalls,
    this.isRunning = true,
    this.isComplete = false,
    this.error,
  }) : toolCalls = toolCalls ?? [];
}

/// A ValueNotifier that holds the current sub-agent activity.
///
/// null means no sub-agent is running. The dialog listens to this and
/// shows/hides itself accordingly.
class SubAgentActivityNotifier extends ValueNotifier<SubAgentActivity?> {
  SubAgentActivityNotifier() : super(null);
}
