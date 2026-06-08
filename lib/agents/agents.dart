// Multi-agent orchestration system for Synapse.
//
// This module provides an agent abstraction layer that enables the
// orchestrator (ChatController) to delegate specialized tasks to
// focused sub-agents, each with their own system prompt and tools.
//
// Architecture:
//   Agent          -- abstract base class for all agents
//   AgentExecutor  -- reusable LLM streaming + tool-calling engine
//   AgentRegistry  -- registry of available agents by name
//   AgentTask      -- task description passed to an agent
//   AgentResult    -- result returned by an agent
//
// Built-in agents:
//   ResearcherAgent  -- web search, crawl, REST APIs
//   CoderAgent       -- Lua code execution
//   SummarizerAgent  -- text analysis (no tools)

export 'agent.dart';
export 'agent_executor.dart';
export 'agent_models.dart';
export 'agent_registry.dart';
export 'builtin_agents.dart';
