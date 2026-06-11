import '../models/mcp_models.dart';
import '../services/chat_controller.dart';
import 'agent.dart';

/// Researcher agent -- specializes in web search, crawling, and API calls.
///
/// This agent is delegated tasks that require finding information on the
/// internet, reading web pages, or calling REST APIs.
class ResearcherAgent extends Agent {
  @override
  String get name => 'researcher';

  @override
  String get role =>
      'Web research specialist that can search the internet, read web pages, '
      'and call REST APIs to gather information.';

  @override
  String get systemPrompt => '''You are a research specialist agent within Synapse.

Your job is to gather information from the internet and external APIs to answer questions or complete research tasks.

Guidelines:
- Use web_search to find relevant sources first, then web_crawl to read the most promising results in full.
- When searching, try multiple queries if the first doesn't yield good results.
- Synthesize information from multiple sources into a clear, well-organized answer.
- Always cite your sources. Format citations as clickable markdown links, e.g. [Title or description](https://url). Group all references in a "Sources" section at the end of your response.
- If you need to call an API, use rest_request.
- Use current_date_time if you need to know the current date/time for context.
- Be thorough but concise. Focus on the most relevant information.
- If you cannot find the requested information, say so clearly rather than guessing.''';

  @override
  List<McpServerTool> get tools {
    const allowedTools = {
      'web_search',
      'web_crawl',
      'rest_request',
      'current_date_time',
    };
    return ChatController.systemTools
        .where((t) => allowedTools.contains(t.tool.name))
        .toList();
  }

  @override
  int get maxToolRounds => 5;
}

/// Coder agent -- specializes in code execution via Lua scripting.
///
/// This agent is delegated tasks that require computation, data processing,
/// algorithm implementation, or any task best solved by running code.
class CoderAgent extends Agent {
  @override
  String get name => 'coder';

  @override
  String get role =>
      'Code execution specialist that can write and run Lua scripts '
      'for computation, data processing, and problem solving.';

  @override
  String get systemPrompt => '''You are a code execution specialist agent within Synapse.

Your job is to solve problems by writing and running Lua 5.3 scripts.

Guidelines:
- Write clean, well-commented Lua code.
- Use print() to produce output that will be returned as results.
- Available: base functions (print, type, tostring, tonumber, pairs, ipairs, etc.), math, string, table, coroutine.
- NOT available: os, io, file, require, dofile, loadfile, debug, package.
- Scripts run with a 10 second timeout.
- For multi-step computations, use persistent=true to keep state across calls.
- If the first attempt has errors, read the error message carefully and fix the code.
- Always explain what the code does and interpret the results clearly.
- For mathematical problems, show your work through the code.''';

  @override
  List<McpServerTool> get tools {
    const allowedTools = {'run_lua', 'current_date_time'};
    return ChatController.systemTools
        .where((t) => allowedTools.contains(t.tool.name))
        .toList();
  }

  @override
  int get maxToolRounds => 3;
}

/// Summarizer agent -- specializes in text analysis and summarization.
///
/// This agent has NO tools. It relies purely on LLM reasoning to analyze,
/// summarize, compare, or transform text provided in its task context.
class SummarizerAgent extends Agent {
  @override
  String get name => 'summarizer';

  @override
  String get role =>
      'Text analysis and summarization specialist that distills '
      'information into clear, concise summaries.';

  @override
  String get systemPrompt => '''You are a summarization specialist agent within Synapse.

Your job is to analyze, summarize, compare, and transform text content.

Guidelines:
- Produce clear, well-structured summaries that capture the essential information.
- Use bullet points, headings, or numbered lists for readability when appropriate.
- Preserve key facts, numbers, and conclusions.
- If asked to compare, organize the comparison into clear categories.
- Adjust the level of detail based on the task -- some tasks need a brief overview, others need a detailed analysis.
- If the input is ambiguous or unclear, note what assumptions you are making.
- Never invent information that isn't in the provided context.''';

  @override
  List<McpServerTool> get tools => []; // No tools -- pure LLM reasoning

  @override
  int get maxToolRounds => 1;
}
