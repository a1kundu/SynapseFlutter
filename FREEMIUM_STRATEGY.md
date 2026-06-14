# Synapse -- Freemium Strategy Report

> **App:** Synapse -- AI Chat Client with MCP Support  
> **Platform:** Android (primary), Web, iOS (partial)  
> **Model:** BYOK (Bring Your Own Key)  
> **Codebase:** Flutter/Dart, ~11,000 lines across 32 files  
> **Generated:** June 2026

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Codebase Architecture Overview](#codebase-architecture-overview)
3. [Complete Feature Inventory](#complete-feature-inventory)
4. [Free Tier -- Features to Keep Free](#free-tier)
5. [Premium Tier -- Features for Subscription](#premium-tier)
6. [Freemium Gate Points (Code-Level)](#freemium-gate-points)
7. [Tiered Limits -- Throttled Features](#tiered-limits)
8. [Implementation Roadmap](#implementation-roadmap)
9. [Monetization Notes](#monetization-notes)

---

## Executive Summary

Synapse currently has **zero freemium infrastructure** -- no auth gate, no subscription checks, no usage quotas, no `isPro` flags anywhere in code. It is a fully open BYOK app. This report maps every feature to a free or premium tier based on:

- **User acquisition value** -- Will this feature attract new users?
- **Differentiation value** -- Does this feature distinguish Synapse from competitors?
- **Implementation complexity** -- How much engineering went into this?
- **Power-user appeal** -- Is this used daily by all users, or occasionally by advanced users?

**Recommendation:** 18 feature groups identified. **10 stay free**, **8 go premium**, with **4 features using tiered limits** (free users get a restricted version).

---

## Codebase Architecture Overview

```
lib/                          32 files, ~11,000 lines
  main.dart                   App entry, no auth gate
  version.dart                CI-stamped version placeholder
  models/          (4 files)  Data structures: ChatSession, ChatMessage, LlmModel, McpServerConfig
  screens/         (3 files)  UI: ChatScreen (3,597 LOC), HomeShell (600 LOC), SettingsScreen (1,015 LOC)
  services/       (12 files)  Business logic: ChatController, LlmApiClient, McpClient, + 9 system tools
  agents/          (5 files)  Multi-agent system: AgentExecutor, ResearcherAgent, CoderAgent, SummarizerAgent
  settings/        (1 file)   SharedPreferences-backed config singleton
  theme/           (1 file)   Material 3 seed color
  widgets/         (5 files)  Mermaid renderer, IconBox, SectionHeader
```

### Key Service Files (by complexity)

| File | Lines | Role |
|------|-------|------|
| `chat_controller.dart` | 1,713 | Central orchestrator -- sessions, streaming, tool loop, agent delegation |
| `update_service.dart` | 1,051 | Auto-update with foreground service, resume, retry |
| `llm_api_client.dart` | 444 | Multi-provider LLM streaming client |
| `web_crawler.dart` | 317 | HTML-to-text extraction pipeline |
| `memory_service.dart` | 264 | Persistent key-value memory with YAML/MD files |
| `lua_executor.dart` | 253 | Sandboxed Lua 5.3 code execution |
| `rest_client_service.dart` | 194 | Generic HTTP API client tool |
| `mcp_client.dart` | 183 | MCP JSON-RPC 2.0 protocol client |
| `web_search_service.dart` | 170 | DuckDuckGo search (no API key needed) |
| `ssh_service.dart` | 152 | Remote SSH command execution |
| `notification_service.dart` | 139 | LLM-triggered Android notifications |
| `background_update.dart` | 119 | Periodic 6-hour update checks |
| `agent_executor.dart` | 420 | Headless LLM engine for sub-agents |

---

## Complete Feature Inventory

### 18 Feature Groups Identified

| # | Feature Group | Source Files | Complexity | Tier |
|---|---------------|-------------|------------|------|
| 1 | Core Chat + Streaming | `chat_controller`, `llm_api_client` | Very High | FREE |
| 2 | Multi-Session Management | `chat_controller`, `chat_storage` | Medium | TIERED |
| 3 | Markdown + Code Rendering | `chat_screen.dart` | Medium | FREE |
| 4 | Model Selection + Refresh | `llm_api_client`, `chat_screen` | Medium | FREE |
| 5 | Theme + Dynamic Color | `app_theme`, `settings_screen` | Low | FREE |
| 6 | Auto-Update System | `update_service`, `background_update` | Very High | FREE |
| 7 | File Attachments | `chat_controller`, `chat_screen` | Medium | TIERED |
| 8 | Message Edit + Retry | `chat_controller`, `chat_screen` | Medium | PREMIUM |
| 9 | Chat Forking | `chat_controller` | Medium | PREMIUM |
| 10 | Chat/Session Export | `chat_controller`, `home_shell` | Low | PREMIUM |
| 11 | MCP Tool Integration | `mcp_client`, `settings_screen` | High | PREMIUM |
| 12 | Multi-Agent System | `agents/*`, `agent_executor` | Very High | PREMIUM |
| 13 | Web Search + Crawl | `web_search_service`, `web_crawler` | High | PREMIUM |
| 14 | Lua Code Execution | `lua_executor` | High | PREMIUM |
| 15 | SSH Remote Execution | `ssh_service` | High | PREMIUM |
| 16 | REST API Client | `rest_client_service` | Medium | PREMIUM |
| 17 | Persistent Memory | `memory_service` | Medium | PREMIUM |
| 18 | Custom System Prompt | `settings_repository` | Low | PREMIUM |

---

## Free Tier

> Goal: Give users a **fully functional AI chat client** that is genuinely useful without paying. The free tier should be good enough that users recommend it, but leave them wanting more.

### Features to Keep Free

#### 1. Core Chat + Streaming
**Files:** `chat_controller.dart:1-1713`, `llm_api_client.dart:1-444`

- Send messages to any LLM via BYOK API key
- Real-time SSE streaming with token-by-token rendering
- Cancel generation mid-stream
- Copy messages to clipboard
- Streaming bounce indicator

**Rationale:** This is the app's identity. Gating this kills acquisition. Since users bring their own API key, there is no cost to you.

---

#### 2. Markdown + Code Rendering
**Files:** `chat_screen.dart` (MarkdownBody, _CodeBlockBuilder sections)

- Full GitHub-Flavored Markdown (headers, lists, tables, blockquotes, links)
- Syntax-highlighted code blocks with language labels
- Copy button per code block
- Selectable assistant text

**Rationale:** Table-stakes for any AI chat app. Free users expect this.

---

#### 3. Model Selection + Refresh
**Files:** `llm_api_client.dart`, `chat_screen.dart` (ModelSelectorChip)

- Fetch available models from provider endpoint
- Searchable model picker with grouping
- Tool-calling capability indicator per model
- Model refresh

**Rationale:** Essential UX. Users need to pick models. Gate the *provider count* instead (see Tiered Limits).

---

#### 4. Theme + Material You
**Files:** `settings_screen.dart`, `app_colors.dart`

- System / Light / Dark theme modes
- Material You dynamic color (Android 12+)
- Cross-session theme persistence

**Rationale:** Low complexity, no ongoing cost, and a poor experience to gate cosmetics. Keeps free users happy.

---

#### 5. Auto-Update System
**Files:** `update_service.dart:1-1051`, `background_update.dart:1-119`

- GitHub Releases update checks (3 channels: debug, release, PR)
- Foreground service download with progress, speed, ETA
- Resume + retry with exponential backoff
- Background checks every 6 hours

**Rationale:** Infrastructure, not a feature. All users need updates. Gating this creates a fragmented user base with old versions.

---

#### 6. LLM-Triggered Notifications
**Files:** `notification_service.dart:1-139`

- LLM can send Android notifications with title, body, priority
- Permission auto-request on Android 13+
- Auto-cancel timeout support

**Rationale:** Low cost, useful for all users. The LLM triggers it -- gating it would break the tool-calling contract mid-conversation.

---

#### 7. Basic Session Management (Tiered)
**Files:** `chat_storage.dart:1-81`, `home_shell.dart`

- Create, switch, rename, delete sessions
- Auto-naming from first message
- Session persistence via SharedPreferences
- Session restore on launch
- Responsive sidebar (wide) / drawer (narrow)

**Rationale:** Core UX. But limit the *count* in free tier (see Tiered Limits).

---

### Free Tier Summary

| Feature | What Free Users Get |
|---------|-------------------|
| Chat | Unlimited messages, full streaming, cancel, copy |
| Rendering | Full markdown + syntax-highlighted code |
| Models | Full model picker, 1 provider (see tiered) |
| Sessions | Up to 10 active sessions (see tiered) |
| Theme | All 3 modes + Material You |
| Updates | Full auto-update system |
| Notifications | LLM-triggered notifications |

---

## Premium Tier

> Goal: Gate features that are **high-complexity, power-user, and high-differentiation**. These are features competitors charge for or don't have at all.

### Features for Premium Subscription

#### 8. Message Edit + Retry + Fork
**Files:** `chat_controller.dart` (`editUserMessage`, `retryFromMessage`, `forkChatAtMessage`), `chat_screen.dart` (`_MessageBubble` actions)

| Sub-Feature | Code Location |
|-------------|---------------|
| Edit user message + regenerate | `chat_controller.dart` -> `editUserMessage()` |
| Retry from any message | `chat_controller.dart` -> `retryFromMessage()` |
| Fork conversation into new session | `chat_controller.dart` -> `forkChatAtMessage()` |

**Premium Value:** Conversation branching and replay is a power-user workflow. Most free AI apps don't offer this. It's a strong differentiator.

---

#### 9. Chat / Session Export
**Files:** `chat_controller.dart` (`exportChatToJson`, `exportSessionToJson`), `home_shell.dart` (context menu)

- Export current or any session as structured JSON
- Timestamped filenames
- Full metadata: session info, messages, attachments, model used

**Premium Value:** Data portability is a power feature. Users who need exports (researchers, developers) will pay.

---

#### 10. MCP Tool Integration
**Files:** `mcp_client.dart:1-183`, `settings_screen.dart` (MCP section), `chat_controller.dart` (tool loop)

| Sub-Feature | Description |
|-------------|-------------|
| MCP server management | Add/remove/enable/disable servers |
| Transport modes | HTTP Streamable + SSE |
| Auth support | None / Bearer / Custom Header |
| Tool discovery | Auto-discover tools from all servers |
| Tool selection UI | Per-tool checkboxes, select all/none |
| Tool-calling loop | LLM decides -> MCP executes -> results fed back |

**Premium Value:** MCP is Synapse's biggest differentiator. No other mobile app does this. The entire tool ecosystem justifies premium pricing alone.

**Gate point:** `settings_repository.dart` -> `mcpServers` list. Free tier: 0-1 MCP server. Premium: unlimited.

---

#### 11. Multi-Agent System (Researcher, Coder, Summarizer)
**Files:** `agents/agent.dart`, `agents/agent_registry.dart`, `agents/agent_executor.dart:1-420`, `agents/coder_agent.dart`, `agents/summarizer_agent.dart`

| Agent | Tools | Max Rounds | Purpose |
|-------|-------|-----------|---------|
| ResearcherAgent | web_search, web_crawl, rest_request | 5 | Web research with multi-step reasoning |
| CoderAgent | run_lua | 3 | Code execution + iteration |
| SummarizerAgent | (none) | 1 | Pure LLM reasoning/summarization |

**Premium Value:** Two-tier LLM architecture (orchestrator -> sub-agents) is cutting-edge. The live sub-agent dialog in `chat_screen.dart` (`_SubAgentDialog`) showing real-time streaming is a premium UX.

**Gate point:** `chat_controller.dart` -> `_executeDelegateToAgent()`. Disable entirely for free users.

---

#### 12. Web Search + Web Crawl
**Files:** `web_search_service.dart:1-170`, `web_crawler.dart:1-317`

| Sub-Feature | Limits |
|-------------|--------|
| DuckDuckGo search | 1-10 results (default 5), 10s timeout |
| Web page crawl | 50KB text cap, 15s timeout, 5 max redirects |
| Content extraction | DOM walking, noise removal, markdown output |

**Premium Value:** Web access transforms the LLM from a knowledge-cutoff chatbot into a real-time research assistant. High-value differentiation.

---

#### 13. Lua Code Execution
**Files:** `lua_executor.dart:1-253`

- Sandboxed Lua 5.3 VM (dangerous modules removed)
- Ephemeral mode (fresh VM per call) + Persistent mode (stateful)
- 10s timeout, 50KB output cap
- Isolate-based execution on native

**Premium Value:** On-device code execution is rare in mobile AI apps. The sandbox security work justifies premium.

---

#### 14. SSH Remote Execution
**Files:** `ssh_service.dart:1-152`

- Full SSH client with password + private key auth
- Command execution with stdout/stderr capture
- Formatted output with host, command, exit code

**Premium Value:** Highest-risk feature. Only devops/developer users need this. Natural premium gate.

---

#### 15. REST API Client
**Files:** `rest_client_service.dart:1-194`

- 7 HTTP methods (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS)
- Configurable headers, body, timeout
- Pretty-printed JSON response, 20KB cap

**Premium Value:** API testing from chat is a developer power tool.

---

#### 16. Persistent Memory
**Files:** `memory_service.dart:1-264`

- CRUD key-value memory with YAML/MD files
- Tag system, search across keys/content/tags
- Human-readable storage at `/storage/emulated/0/Download/SynapseMemory/`

**Premium Value:** Cross-session memory makes the LLM feel personalized. Strong retention feature for premium.

---

#### 17. Custom System Prompt
**Files:** `settings_repository.dart` (`systemPrompt`), `settings_screen.dart` (Custom system prompt section)

- User-defined instructions appended to base system prompt
- Persisted across sessions

**Premium Value:** Behavioral customization is a power-user feature. The base system prompt (formatting instructions) stays free.

---

#### 18. LaTeX / Math Rendering
**Files:** `chat_screen.dart` (math segment handling via `flutter_math_fork`)

- Block math: `$$...$$`, `\[...\]`
- Inline math: `$...$`, `\(...\)`
- Error fallback to raw source

**Premium Value:** Specialized for STEM users (students, researchers, engineers). High value for a niche audience.

---

#### 19. Mermaid Diagram Rendering
**Files:** `widgets/mermaid_view.dart:1-155`, `widgets/_mermaid_web_renderer_web.dart:1-183`

- Cross-platform: WebView (native) + JS interop (web)
- Theme-aware (dark/light)
- Pinch-to-zoom, dynamic height
- Error fallback to source code

**Premium Value:** Visual diagram rendering is a high-complexity, visually impressive feature. Strong upsell trigger.

---

### Premium Tier Summary

| Feature | What Premium Users Unlock |
|---------|--------------------------|
| Edit + Retry + Fork | Full conversation control and branching |
| Export | JSON export of any session |
| MCP Integration | Unlimited MCP servers + full tool ecosystem |
| Multi-Agent | Researcher, Coder, Summarizer sub-agents |
| Web Access | Search + crawl from within chat |
| Code Execution | Sandboxed Lua scripting |
| SSH | Remote server command execution |
| REST Client | HTTP API testing from chat |
| Memory | Persistent cross-session memory |
| System Prompt | Custom behavioral instructions |
| Math Rendering | LaTeX block + inline math |
| Mermaid Diagrams | Visual diagram rendering |

---

## Freemium Gate Points

> These are the exact code locations where limits can be enforced with minimal refactoring.

### Hard Gates (Feature On/Off)

| Feature | Gate Location | Current | Free | Premium |
|---------|--------------|---------|------|---------|
| Sub-agent delegation | `chat_controller.dart` -> `_executeDelegateToAgent()` | Enabled | Disabled | Enabled |
| SSH execution | `chat_controller.dart` -> `_executeSystemTool('ssh_execute')` | Enabled | Disabled | Enabled |
| REST client | `chat_controller.dart` -> `_executeSystemTool('rest_request')` | Enabled | Disabled | Enabled |
| Lua execution | `chat_controller.dart` -> `_executeSystemTool('run_lua')` | Enabled | Disabled | Enabled |
| Chat export | `chat_controller.dart` -> `exportChatToJson()` | Available | Disabled | Available |
| Chat forking | `chat_controller.dart` -> `forkChatAtMessage()` | Available | Disabled | Available |
| Message editing | `chat_controller.dart` -> `editUserMessage()` | Available | Disabled | Available |
| Custom system prompt | `settings_repository.dart` -> `systemPrompt` setter | Available | Disabled | Available |
| Mermaid rendering | `chat_screen.dart` -> Mermaid segment handling | Rendered | Raw code | Rendered |
| Math rendering | `chat_screen.dart` -> Math segment handling | Rendered | Raw text | Rendered |

### Soft Gates (Tiered Limits)

| Feature | Gate Location | Current | Free | Premium |
|---------|--------------|---------|------|---------|
| Active sessions | `chat_storage.dart` | Unlimited | **10** | Unlimited |
| MCP servers | `settings_repository.dart` -> `mcpServers` | Unlimited | **1** | Unlimited |
| Tool-calling rounds | `chat_controller.dart:1189` -> `_maxToolRounds` | 100 | **5** | 100 |
| Web search results | `web_search_service.dart:31` -> `maxResults` | 10 | **3** | 10 |
| Web crawl text cap | `web_crawler.dart:35` -> `_maxContentLength` | 50KB | **10KB** | 50KB |
| Memory entries | `memory_service.dart` | Unlimited | **5** | Unlimited |
| File attachments/msg | `chat_controller.dart` -> `pendingAttachments` | Unlimited | **2** | Unlimited |
| LLM providers | `LlmProvider` enum (3 providers) | 3 | **1** | 3 |

---

## Tiered Limits

> Features that both free and premium users access, but with different ceilings.

### Sessions: 10 Free / Unlimited Premium
- Free users can have up to 10 active sessions
- Oldest sessions auto-archive or user must delete to create new
- **Gate:** Check count in `ChatController.createNewChat()`

### Providers: 1 Free / 3 Premium
- Free: GitHub Models only (free tier API, good model selection)
- Premium: + OpenAI, + OpenRouter (broader model access)
- **Gate:** Check in `SettingsScreen` provider selector + `LlmApiClient`

### MCP Servers: 1 Free / Unlimited Premium
- Free: 1 MCP server to try the ecosystem
- Premium: Unlimited servers for full tool integration
- **Gate:** Check count in `SettingsRepository.addMcpServer()`

### Tool Rounds: 5 Free / 100 Premium
- Free: LLM can call up to 5 rounds of tools per response
- Premium: Full 100-round ceiling for complex multi-step tasks
- **Gate:** Already exists at `chat_controller.dart:1189` -- just lower the constant

### File Attachments: 2 Free / Unlimited Premium
- Free: 2 files per message
- Premium: Unlimited attachments
- **Gate:** Check count in `ChatController.addAttachment()`

---

## Implementation Roadmap

### Phase 1: Add Subscription Infrastructure (1-2 weeks)
```
New files needed:
  lib/services/subscription_service.dart   -- Play Store billing integration
  lib/models/subscription_model.dart       -- Plan tiers, feature flags
  lib/widgets/paywall_dialog.dart          -- Upsell UI when hitting gate

Modify:
  lib/settings/settings_repository.dart    -- Add isPremium, planType fields
  lib/main.dart                            -- Initialize subscription service
  pubspec.yaml                             -- Add in_app_purchase dependency
```

### Phase 2: Implement Hard Gates (1 week)
- Add `SettingsRepository.isPremium` check before premium features
- Show paywall dialog when free users tap gated features
- Disable gated tools in `_executeSystemTool()` switch statement
- Hide edit/fork/export actions in `_MessageBubble` for free users

### Phase 3: Implement Soft Gates (1 week)
- Add limit checks with upgrade prompts at gate points
- Session count check in `createNewChat()`
- Provider lock in settings UI
- MCP server count check in `addMcpServer()`
- Attachment count check in `addAttachment()`

### Phase 4: Premium Upsell UX (1 week)
- "Pro" badge on premium features in settings
- Upgrade prompt when free users discover gated features
- Feature comparison screen
- 7-day free trial integration

---

## Monetization Notes

### Pricing Suggestion
| Plan | Price | Billing |
|------|-------|---------|
| Free | $0 | -- |
| Premium Monthly | $4.99/mo | Google Play subscription |
| Premium Annual | $39.99/yr (~$3.33/mo) | Google Play subscription (33% savings) |

### Why This Split Works

1. **Free tier is genuinely useful** -- Full chat, markdown, code highlighting, 10 sessions, 1 MCP server. Users can daily-drive this.

2. **Premium has clear value** -- MCP ecosystem, multi-agent, web access, code execution, SSH, memory. These are features developers and power users will pay for.

3. **No cost to you for free users** -- BYOK model means users pay their own API costs. Your only costs are Play Store listing and update hosting (GitHub Releases = free).

4. **Natural upgrade triggers** -- Users discover premium features organically (try to add a 2nd MCP server, try to fork a chat, see a Mermaid diagram render as raw code) and get a tasteful upgrade prompt.

5. **No feature degradation** -- Free users never lose what they have. Premium is purely additive.

### Risk: BYOK + Open Source
Since Synapse is on GitHub with full source code, power users could build from source without gates. Consider:
- Keep the repo public but without freemium gates (community edition)
- Play Store version has gates + polish + auto-updates
- The convenience premium: most users prefer a $5/mo app over building from source

---

## Appendix: Module Dependency Map

```
lib/main.dart
  -> SettingsRepository (singleton)
  -> ChatStorage
  -> MemoryService
  -> BackgroundUpdateManager
  -> DownloadManager
  -> HomeShell
      -> ChatScreen
          -> ChatController
              -> LlmApiClient        [FREE]
              -> McpClient            [PREMIUM]
              -> ChatStorage          [TIERED]
              -> AgentExecutor        [PREMIUM]
              -> LuaExecutor          [PREMIUM]
              -> SshService           [PREMIUM]
              -> RestClientService    [PREMIUM]
              -> WebSearchService     [PREMIUM]
              -> WebCrawler           [PREMIUM]
              -> MemoryService        [PREMIUM]
              -> NotificationService  [FREE]
      -> SettingsScreen
          -> SettingsRepository
          -> UpdateService            [FREE]
```

---

*Report generated via code-graph analysis of the Synapse codebase. All line numbers and file references are accurate as of the analysis date.*
