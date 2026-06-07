# Synapse

An AI Chat Client with full **MCP (Model Context Protocol)** support, built with Flutter. Synapse connects to multiple LLM providers, discovers and executes tools from MCP servers, and renders rich responses -- all from a single mobile-first app.

## Features

### AI Chat
- **Multi-provider LLM support** -- OpenAI, OpenRouter, and GitHub Models via OpenAI-compatible API format
- **Streaming responses** -- Real-time token-by-token rendering via Server-Sent Events (SSE)
- **Dynamic model selection** -- Fetches available models from the provider endpoint with grouped display; includes a curated fallback list of 22+ models (GPT-4.1, o3, Llama 4, Mistral, DeepSeek, Grok 3, Phi-4, and more)
- **Custom system prompt** -- User-configurable instructions layered on top of a base system prompt with current date/time context
- **File attachments** -- Attach files to messages; text-based files are automatically included in LLM context as inline content

### MCP (Model Context Protocol) Integration
- **MCP server management** -- Add and remove MCP servers via the Settings UI with name, URL, and transport type
- **Two transport modes** -- HTTP Streamable and SSE (Server-Sent Events)
- **Full JSON-RPC 2.0 lifecycle** -- `initialize` -> `notifications/initialized` -> `tools/list` -> `tools/call`
- **Automatic tool discovery** -- Tools from all configured MCP servers are discovered on startup
- **Tool selection UI** -- Expandable panel with per-tool checkboxes, select all/none toggles
- **Automated tool-calling loop** -- LLM decides which tools to call, Synapse executes them via MCP, feeds results back, and gets a final natural-language response
- **Infinite loop prevention** -- Follow-up requests after tool execution are sent without tools to prevent recursive calling

### Chat Session Management
- **Multiple sessions** -- Create, switch, rename, and delete conversations
- **Auto-naming** -- Sessions are automatically named from the first user message
- **Persistent storage** -- All sessions and messages persisted via SharedPreferences
- **Session restore** -- Last active session restored on launch

### Chat Operations
- **Edit messages** -- Edit any user message and auto-regenerate the response
- **Fork conversations** -- Branch a conversation from any message point into a new session
- **Copy & Export** -- Copy individual messages or export the entire conversation as formatted JSON
- **Clear conversation** -- Wipe current session messages

### Rich Markdown Rendering
- **GitHub-Flavored Markdown** -- Headers, lists, tables, blockquotes, links, horizontal rules
- **Syntax-highlighted code blocks** -- Language detection with Atom One Dark/Light themes, language label, and copy button
- **Mermaid diagrams** -- Mermaid code blocks rendered as visual diagrams with dark mode support and source code fallback
- **Selectable text** -- Assistant responses are fully selectable

### Theming & Appearance
- **Material 3** -- Full Material Design 3 with comprehensive widget theming
- **Three theme modes** -- System, Light, and Dark with cross-session persistence
- **Dynamic Color (Material You)** -- Uses device wallpaper colors on Android 12+; toggleable in settings

### Auto-Update System (Android)
- **GitHub Releases integration** -- Checks for updates from the GitHub repository
- **Channel-aware** -- Separate debug/release channels with build-number comparison
- **Resumable downloads** -- HTTP Range header support for interrupted downloads
- **Exponential backoff retries** -- Up to 5 retries with progressive delay
- **Foreground service** -- Downloads run as a foreground service with real-time progress, speed, ETA, and cancel
- **Background checks** -- Periodic checks every 6 hours via Workmanager with local notifications

### Responsive Layout
- **Wide screens (>=768px)** -- Persistent sidebar with chat history + main chat area
- **Narrow screens (<768px)** -- Navigation drawer for chat history

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Android  | Full   | Auto-updates, background tasks, notifications, Material You |
| Web      | Partial | Core chat features; model catalog may be limited by CORS |
| iOS      | Partial | Core features only, no auto-update |
| Desktop  | Limited | Basic functionality |

## Tech Stack

| Category | Technology |
|----------|------------|
| Framework | Flutter (Dart SDK ^3.10.0) |
| Language | Dart, Kotlin (Android native) |
| State Management | `provider` (ChangeNotifier), `ValueNotifier` |
| Networking | `http`, `dart:io` HttpClient |
| Persistence | `shared_preferences` |
| Markdown | `flutter_markdown`, `markdown` (GitHub Web extensions) |
| Syntax Highlighting | `flutter_highlight`, `highlight` |
| File Handling | `file_picker`, `mime` |
| Notifications | `flutter_local_notifications` |
| Background Tasks | `workmanager` |
| File Install | `open_filex` |
| URLs | `url_launcher` |
| Theming | `dynamic_color` (Material You) |
| i18n | `intl` |
| CI/CD | GitHub Actions |
| Design System | Material 3 |

## Architecture

```
lib/
  main.dart                        # App entry point
  version.dart                     # Version placeholder (CI-stamped)
  models/
    chat_models.dart               # LlmModel, ChatAttachment, ChatMessage
    chat_session.dart              # ChatSession model
    llm_models.dart                # LLM provider enum, OpenAI tool types, stream events
    mcp_models.dart                # MCP server config, McpTool, McpServerTool
  screens/
    chat_screen.dart               # Chat UI with markdown, code blocks, Mermaid
    home_shell.dart                # Responsive shell (sidebar vs drawer)
    settings_screen.dart           # Settings: LLM provider, API key, MCP, theme
  services/
    chat_controller.dart           # Core chat orchestration (ChangeNotifier)
    chat_storage.dart              # SharedPreferences-based persistence
    llm_api_client.dart            # LLM API client (streaming, tool support)
    mcp_client.dart                # MCP protocol client (JSON-RPC 2.0)
    update_service.dart            # GitHub Releases update checker + downloader
    background_update.dart         # Workmanager background update checks
  settings/
    settings_repository.dart       # Central settings singleton
  theme/
    app_colors.dart                # Seed color configuration
    app_theme.dart                 # Material 3 theme builder with persistence
  utils/
    snackbar_service.dart          # Global snackbar utility
  widgets/
    icon_box.dart                  # Reusable icon box widget
    section_header.dart            # Reusable section header widget
```

### Tool-Calling Flow

```
User message
  -> ChatController.sendMessage()
    -> _generateResponse()
      -> _doGenerate()
        -> _streamWithToolCalling()
          -> LLM returns tool_calls
            -> _handleToolCalls()
              -> McpClient.callTool() (per tool)
            -> Results appended to conversation
          -> _streamWithToolCalling() (tools=null, final response)
        -> Stream final answer to UI
```

## Getting Started

### Prerequisites

- Flutter SDK `>=3.10.0`
- Dart SDK `>=3.8.0`

### Run

```bash
flutter pub get
flutter run
```

### Build

```bash
# Android APK
flutter build apk

# Web
flutter build web
```

## CI/CD

GitHub Actions workflow (`.github/workflows/build.yml`) automates:
- Debug and Release APK builds
- Keystore signing for release builds
- Version stamping with git commit count and short SHA
- Auto-generated changelog from git log
- GitHub Release creation with APK artifact upload

---

## Upcoming Features

### In-App Addon System (MCP-Based Device Tool Providers)

Synapse's MCP integration currently connects to **remote** MCP servers over HTTP. The next evolution is to bring MCP **inside the device itself** -- turning the phone into a local tool provider that exposes Android capabilities directly to the LLM through the same tool-calling protocol.

#### How It Works

The addon system will run a lightweight, **local MCP server embedded within the app**. Each addon registers a set of tools following the MCP `tools/list` and `tools/call` contract. When the LLM decides it needs to place a call, read an SMS, or scan for Bluetooth devices, it issues a tool call -- and Synapse routes it to the appropriate on-device addon instead of a remote server. The user experience remains identical: the LLM asks, the tool executes, results flow back, and the LLM responds in natural language.

#### Planned Addon Categories

| Addon | Exposed Capabilities | Example Use Cases |
|-------|---------------------|-------------------|
| **Phone & Calls** | Place calls, read call history, get active call state | "Call mom", "Show my missed calls from today", "Who called me last?" |
| **Messaging (SMS/MMS)** | Read, send, and search SMS/MMS messages | "Text John that I'm running late", "Find the OTP I received", "Summarize unread messages" |
| **Contacts** | Read, search, create, and update contacts | "What's Sarah's number?", "Add a new contact for the plumber", "Find all contacts from Bangalore" |
| **Bluetooth** | Scan for devices, connect/disconnect, list paired devices | "What Bluetooth devices are nearby?", "Connect to my car speaker", "Is my headset connected?" |
| **Wi-Fi & Network** | Scan networks, get connection status, signal info | "What Wi-Fi am I connected to?", "List available networks", "What's my IP address?" |
| **Location & GPS** | Get current location, geocoding, geofencing | "Where am I?", "What's my altitude?", "Navigate to the nearest gas station" |
| **Camera & Media** | Capture photos/video, access gallery, media metadata | "Take a photo", "Show my recent photos", "What's in this picture?" (with vision models) |
| **Sensors & Hardware** | Accelerometer, gyroscope, barometer, proximity, ambient light | "What's the current temperature from the barometer?", "Is the phone lying flat?", "Detect motion" |
| **Battery & Power** | Battery level, charging state, power profiles | "What's my battery level?", "Am I charging?", "How long until full charge?" |
| **Calendar & Reminders** | Read/create events, check availability, set reminders | "What's on my schedule today?", "Create a meeting for 3 PM tomorrow", "Remind me to buy groceries" |
| **Notifications** | Read notification history, notification content, app-specific filtering | "What notifications did I miss?", "Any messages from WhatsApp?", "Summarize my notifications" |
| **Clipboard** | Read/write clipboard content | "What did I copy?", "Copy this to clipboard" |
| **Storage & Files** | Browse files, read/write documents, storage stats | "How much storage is left?", "Find PDFs in Downloads", "Read this text file" |
| **System Info** | Device model, OS version, installed apps, memory/CPU usage | "What phone is this?", "How much RAM is free?", "Is Spotify installed?" |
| **Accessibility** | Screen reader state, UI automation, app interaction | "Read what's on screen", "Open Settings", "Tap the submit button" |

#### Addon Architecture

```
Synapse App
  |
  |-- LLM Chat (existing)
  |     |
  |     |-- Tool Call Router
  |           |
  |           |-- Remote MCP Servers (existing, over HTTP)
  |           |
  |           |-- Local Addon MCP Host (new)
  |                 |
  |                 |-- Phone Addon       -> Platform Channel -> Android Telephony API
  |                 |-- SMS Addon         -> Platform Channel -> Android SMS ContentProvider
  |                 |-- Bluetooth Addon   -> Platform Channel -> Android BluetoothAdapter
  |                 |-- Location Addon    -> Platform Channel -> Android LocationManager / FusedLocationProvider
  |                 |-- Contacts Addon    -> Platform Channel -> Android ContactsContract
  |                 |-- Camera Addon      -> Platform Channel -> Android CameraX / MediaStore
  |                 |-- Sensors Addon     -> Platform Channel -> Android SensorManager
  |                 |-- Calendar Addon    -> Platform Channel -> Android CalendarContract
  |                 |-- Notifications Addon -> NotificationListenerService -> Android Notification API
  |                 |-- System Addon      -> Platform Channel -> Android Build, ActivityManager
  |                 |-- ... (more addons)
```

Each addon:
1. **Declares tools** via MCP `tools/list` with name, description, and JSON Schema parameters
2. **Executes calls** via MCP `tools/call`, bridging Dart to native Kotlin/Java through Flutter Platform Channels
3. **Returns structured results** that the LLM can interpret and present naturally
4. **Requests permissions on demand** -- the addon prompts for Android runtime permissions only when the LLM triggers a tool that needs them

#### Permission & Privacy Model

- **Granular opt-in** -- Each addon category is individually enabled/disabled by the user in Settings
- **Runtime permissions** -- Android permissions are requested only when a tool is first invoked, not upfront
- **On-device processing** -- Tool execution happens entirely on the device; only the structured result (not raw data) is sent to the LLM
- **Consent prompts** -- Sensitive actions (sending SMS, placing calls, deleting data) will require explicit user confirmation before execution
- **Audit log** -- All tool calls and results are visible in the chat history for full transparency

---

## Future Possibilities

The addon-based architecture opens up a fundamentally new paradigm: **the LLM becomes an intelligent interface to the entire device**. Instead of switching between dozens of apps, the user converses with a single AI that can reach into any part of the phone.

### Cross-Addon Orchestration

When the LLM has access to multiple addons simultaneously, it can compose complex workflows that span several device capabilities in a single conversation:

- *"Text everyone in my 'Project Alpha' contact group that tomorrow's meeting is moved to 3 PM, and add the new time to my calendar"* -- Contacts + SMS + Calendar
- *"Take a photo of this whiteboard, OCR the text, and create a reminder for each action item"* -- Camera + Vision Model + Calendar
- *"When I get home (detect home Wi-Fi), turn off Bluetooth and send my wife a message that I've arrived"* -- Wi-Fi + Bluetooth + SMS + Location

### Third-Party Addon Ecosystem

The addon system can be extended beyond built-in device APIs:

- **App-specific addons** -- Integrate with apps like WhatsApp, Spotify, banking apps, or fitness trackers via Android's Accessibility Services or app-specific APIs
- **IoT & Smart Home** -- Control smart lights, thermostats, locks, and appliances through local network APIs or cloud bridges
- **Health & Fitness** -- Access Google Health Connect data (steps, heart rate, sleep) to provide health insights
- **Developer tools** -- ADB-over-network, logcat reading, APK installation -- turning the phone into a mobile dev companion
- **Community addons** -- An open addon spec allows third-party developers to publish addons that users can install and enable, each exposing new MCP tools to the LLM

### Proactive & Contextual Intelligence

Beyond reactive tool calling, the addon system enables **ambient awareness**:

- **Context-aware responses** -- The LLM can factor in current battery level, network connectivity, location, and time of day when making suggestions
- **Event-driven triggers** -- Addons can push context updates (low battery, new SMS, geofence entry) that the LLM can act on proactively
- **Personalized behavior** -- Over time, the LLM learns usage patterns and can preemptively suggest actions: *"You usually call your team at 9 AM -- want me to start the call?"*

### On-Device Model Support

Future versions may support running smaller LLMs directly on-device (via ONNX Runtime, TensorFlow Lite, or llama.cpp), enabling:

- **Fully offline operation** -- Chat and tool execution without any internet connection
- **Privacy-first mode** -- Sensitive queries (health, finance, passwords) processed entirely on-device
- **Hybrid routing** -- Simple queries handled locally, complex ones routed to cloud models
- **Reduced latency** -- Instant responses for common operations without network round-trips

### Wearable & Multi-Device Expansion

- **Wear OS companion** -- Voice-driven tool calling from a smartwatch ("Hey Synapse, read my last message")
- **Cross-device sync** -- Share chat sessions and addon configurations across phone, tablet, and desktop
- **Automotive integration** -- Android Auto addon for hands-free tool calling while driving

### The Vision

Synapse aims to evolve from a chat client into a **universal AI interface layer for Android** -- a single conversational surface through which any device capability, any app, and any service can be accessed. The MCP protocol provides the standardized contract, addons provide the bridge to platform APIs, and the LLM provides the intelligence to orchestrate it all naturally.

The phone stops being a grid of app icons and becomes a conversation.

---

## License

See repository for license details.
