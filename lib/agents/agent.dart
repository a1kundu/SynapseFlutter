import '../models/mcp_models.dart';

/// Abstract base class for all agents in the multi-agent system.
///
/// Each agent is a self-contained specialist with its own identity,
/// system prompt, and set of tools. Agents are executed by [AgentExecutor].
abstract class Agent {
  /// Unique identifier for this agent (used in delegation routing).
  String get name;

  /// Human-readable role description (for logging / UI display).
  String get role;

  /// System prompt that defines this agent's behavior and expertise.
  String get systemPrompt;

  /// The tools this agent is allowed to use during execution.
  /// Return an empty list if the agent uses no tools.
  List<McpServerTool> get tools;

  /// Optional: maximum number of tool-calling rounds this agent can perform.
  /// Defaults to 3. Set to 1 for agents that should only call tools once.
  int get maxToolRounds => 3;
}
