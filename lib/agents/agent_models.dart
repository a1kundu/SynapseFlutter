// Data classes for the multi-agent orchestration system.

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
