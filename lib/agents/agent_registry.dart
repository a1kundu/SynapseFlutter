import 'agent.dart';

/// Registry that holds all available agents by name.
///
/// Agents are registered at app startup and can be looked up by name
/// when the orchestrator delegates a task via the `delegate_to_agent` tool.
class AgentRegistry {
  final Map<String, Agent> _agents = {};

  /// Register an agent. Overwrites any existing agent with the same name.
  void register(Agent agent) {
    _agents[agent.name] = agent;
  }

  /// Look up an agent by name. Returns null if not found.
  Agent? get(String name) => _agents[name];

  /// All registered agent names.
  List<String> get names => _agents.keys.toList();

  /// All registered agents.
  List<Agent> get all => _agents.values.toList();

  /// Whether an agent with the given name is registered.
  bool has(String name) => _agents.containsKey(name);

  /// Returns a description string of all agents (for tool schema / prompts).
  String describeAll() {
    if (_agents.isEmpty) return 'No sub-agents available.';
    return _agents.values
        .map((a) => '- **${a.name}**: ${a.role}')
        .join('\n');
  }
}
