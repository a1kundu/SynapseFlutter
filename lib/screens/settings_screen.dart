import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/llm_models.dart';
import '../models/mcp_models.dart';
import '../services/background_update.dart';
import '../services/chat_controller.dart';
import '../services/update_service.dart';
import '../settings/settings_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/icon_box.dart';
import '../utils/snackbar_service.dart';
import '../version.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoUpdate = true;
  Timer? _modelRefreshDebounce;

  // LLM Provider state
  late LlmProvider _llmProvider;
  late TextEditingController _apiKeyController;
  late TextEditingController _serverUrlController;
  bool _showApiKey = false;

  // System Prompt state
  late TextEditingController _systemPromptController;

  // MCP Servers state
  late List<McpServerConfig> _mcpServers;

  @override
  void initState() {
    super.initState();
    _loadAutoUpdatePref();

    final settings = SettingsRepository.instance;
    _llmProvider = settings.llmProvider;
    _apiKeyController = TextEditingController(text: settings.llmApiKey);
    _serverUrlController = TextEditingController(text: settings.llmServerUrl);
    _systemPromptController = TextEditingController(
      text: settings.systemPrompt,
    );
    _mcpServers = settings.mcpServers;
  }

  @override
  void dispose() {
    _modelRefreshDebounce?.cancel();
    _apiKeyController.dispose();
    _serverUrlController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  Future<void> _loadAutoUpdatePref() async {
    final enabled = await UpdateService.isAutoUpdateEnabled();
    if (mounted) setState(() => _autoUpdate = enabled);
  }

  Future<void> _toggleAutoUpdate(bool value) async {
    setState(() => _autoUpdate = value);
    await UpdateService.setAutoUpdateEnabled(value);
    await BackgroundUpdateManager.syncWithPreference();
  }

  static Future<void> _checkForUpdate(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    final update = await UpdateService.checkForUpdate();

    if (!context.mounted) return;
    Navigator.of(context).pop();

    if (update != null) {
      showUpdateDialog(context, update);
    } else {
      showRootSnackBar(
        const SnackBar(content: Text('You\'re already on the latest version.')),
      );
    }
  }

  void _selectProvider(LlmProvider provider) {
    final settings = SettingsRepository.instance;
    setState(() {
      _llmProvider = provider;
      settings.llmProvider = provider;
      if (_serverUrlController.text.isEmpty ||
          LlmProvider.values
              .where((p) => p != provider)
              .any((p) => p.defaultBaseUrl == _serverUrlController.text)) {
        _serverUrlController.clear();
        settings.llmServerUrl = '';
      }
    });
    _refreshModelsIfConfigured();
  }

  void _onApiKeyChanged(String value) {
    SettingsRepository.instance.llmApiKey = value;
    _refreshModelsIfConfigured();
  }

  void _onServerUrlChanged(String value) {
    SettingsRepository.instance.llmServerUrl = value;
    _refreshModelsIfConfigured();
  }

  void _onSystemPromptChanged(String value) {
    SettingsRepository.instance.systemPrompt = value;
  }

  void _refreshModelsIfConfigured() {
    _modelRefreshDebounce?.cancel();
    _modelRefreshDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (!SettingsRepository.instance.isLlmConfigured) return;
      try {
        context.read<ChatController>().refreshModels();
      } catch (_) {}
    });
  }

  void _addMcpServer(McpServerConfig server) {
    final settings = SettingsRepository.instance;
    settings.addMcpServer(server);
    setState(() {
      _mcpServers = settings.mcpServers;
    });
    try {
      final chatController = context.read<ChatController>();
      chatController.refreshMcpTools();
    } catch (_) {}
  }

  void _removeMcpServer(String name) {
    final settings = SettingsRepository.instance;
    settings.removeMcpServer(name);
    setState(() {
      _mcpServers = settings.mcpServers;
    });
    try {
      final chatController = context.read<ChatController>();
      chatController.refreshMcpTools();
    } catch (_) {}
  }

  void _toggleMcpServer(String name, {required bool enabled}) {
    final settings = SettingsRepository.instance;
    settings.toggleMcpServer(name, enabled: enabled);
    setState(() {
      _mcpServers = settings.mcpServers;
    });
    try {
      final chatController = context.read<ChatController>();
      chatController.refreshMcpTools();
    } catch (_) {}
  }

  void _showAddMcpServerDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddMcpServerDialog(
        onAdd: (server) {
          Navigator.of(context).pop();
          _addMcpServer(server);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (context, mode, _) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                children: [
                  // App logo, name, and info
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/icons/app_icon.png',
                            width: 80,
                            height: 80,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Synapse',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          appVersion == 'APP_VERSION_PLACEHOLDER'
                              ? 'dev (${UpdateService.channel})'
                              : 'v$appVersion (${UpdateService.channel})',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                      ],
                    ),
                  ),

                  // ── LLM Provider section ──────────────────────────────
                  const SectionHeader(title: 'LLM Provider'),
                  Card(
                    child: Column(
                      children: LlmProvider.values.map((provider) {
                        final isSelected = _llmProvider == provider;
                        return ListTile(
                          leading: IconBox(
                            icon: _providerIcon(provider),
                            colorScheme: isSelected
                                ? ColorScheme.fromSeed(
                                    seedColor: cs.primary,
                                    primary: cs.primary,
                                    onPrimary: cs.onPrimary,
                                  )
                                : cs,
                          ),
                          title: Text(
                            provider.displayName,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected ? cs.primary : null,
                            ),
                          ),
                          subtitle: Text(provider.defaultBaseUrl),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: cs.primary)
                              : const SizedBox.shrink(),
                          onTap: () => _selectProvider(provider),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // API Key and Server URL card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'API Key',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: cs.onSurface),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _apiKeyController,
                            onChanged: _onApiKeyChanged,
                            obscureText: !_showApiKey,
                            decoration: InputDecoration(
                              hintText: 'Enter your API key',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showApiKey
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () {
                                  setState(() => _showApiKey = !_showApiKey);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Server URL',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: cs.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Leave empty to use default: ${_llmProvider.defaultBaseUrl}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _serverUrlController,
                            onChanged: _onServerUrlChanged,
                            decoration: InputDecoration(
                              hintText: _llmProvider.defaultBaseUrl,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── System Prompt section ─────────────────────────────
                  const SectionHeader(title: 'System Prompt'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Base prompt (always included):',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: cs.onSurface),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'You are Synapse, a helpful AI assistant.\n\n'
                              'Response formatting:\n'
                              'Your responses are rendered as rich markdown in the UI. '
                              'The following features are fully supported:\n'
                              '- Text styling (bold, italic, strikethrough, headings, blockquotes, horizontal rules)\n'
                              '- Lists (bullet, numbered, task lists)\n'
                              '- Tables (GitHub-flavored pipe tables)\n'
                              '- Code (fenced code blocks with syntax highlighting, inline code)\n'
                              '- Math/LaTeX (block and inline)\n'
                              '- Links and images',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Custom instructions (appended to base prompt):',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: cs.onSurface),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _systemPromptController,
                            onChanged: _onSystemPromptChanged,
                            maxLines: 6,
                            minLines: 3,
                            decoration: InputDecoration(
                              hintText:
                                  'e.g. Always respond in markdown. Be concise...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              helperText:
                                  'This text is added to every conversation as system instructions.',
                              helperMaxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── MCP Servers section ───────────────────────────────
                  const SectionHeader(title: 'MCP Servers'),
                  Card(
                    child: Column(
                      children: [
                        if (_mcpServers.isEmpty)
                          ListTile(
                            leading: IconBox(
                              icon: Icons.extension_outlined,
                              colorScheme: cs,
                            ),
                            title: const Text('No MCP servers configured'),
                            subtitle: const Text(
                              'Add servers to enable tool calling in chat',
                            ),
                          )
                        else
                          ..._mcpServers.map((server) {
                            return ListTile(
                              leading: IconBox(
                                icon: Icons.extension_outlined,
                                colorScheme: ColorScheme.fromSeed(
                                  seedColor: cs.secondary,
                                  primary: cs.secondary,
                                  onPrimary: cs.onSecondary,
                                ),
                              ),
                              title: Text(server.name),
                              subtitle: Text(
                                '${server.type == McpTransportType.httpStreamable ? 'HTTP Streamable' : 'SSE'} \u00b7 ${server.url}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: server.enabled,
                                    onChanged: (val) => _toggleMcpServer(
                                      server.name,
                                      enabled: val,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outlined,
                                      color: cs.error,
                                    ),
                                    onPressed: () =>
                                        _removeMcpServer(server.name),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ListTile(
                          leading: IconBox(
                            icon: Icons.add,
                            colorScheme: ColorScheme.fromSeed(
                              seedColor: cs.primary,
                              primary: cs.primary,
                              onPrimary: cs.onPrimary,
                            ),
                          ),
                          title: Text(
                            'Add MCP Server',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 8,
                            top: 8,
                          ),
                          onTap: _showAddMcpServerDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Appearance section ────────────────────────────────
                  const SectionHeader(title: 'Appearance'),
                  Card(
                    child: Column(
                      children: [
                        _ThemeTile(
                          icon: Icons.brightness_auto,
                          title: 'System',
                          subtitle: 'Follow device theme',
                          selected: mode == ThemeMode.system,
                          onTap: () => setThemeMode(ThemeMode.system),
                        ),
                        _ThemeTile(
                          icon: Icons.light_mode,
                          title: 'Light',
                          subtitle: 'Always use light theme',
                          selected: mode == ThemeMode.light,
                          onTap: () => setThemeMode(ThemeMode.light),
                        ),
                        _ThemeTile(
                          icon: Icons.dark_mode,
                          title: 'Dark',
                          subtitle: 'Always use dark theme',
                          selected: mode == ThemeMode.dark,
                          onTap: () => setThemeMode(ThemeMode.dark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: dynamicColorNotifier,
                      builder: (context, useDynamic, _) {
                        return SwitchListTile(
                          secondary: IconBox(
                            icon: Icons.palette,
                            colorScheme: cs,
                          ),
                          title: const Text('Dynamic color'),
                          subtitle: const Text(
                            'Use wallpaper colors (Android 12+)',
                          ),
                          value: useDynamic,
                          onChanged: (v) => setDynamicColor(v),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Updates section (Android only) ────────────────────
                  if (!kIsWeb) ...[
                    const SectionHeader(title: 'Updates'),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: IconBox(
                              icon: Icons.update,
                              colorScheme: cs,
                            ),
                            title: const Text('Automatic update check'),
                            subtitle: const Text(
                              'Check for updates when the app opens or using background updates.',
                            ),
                            value: _autoUpdate,
                            onChanged: _toggleAutoUpdate,
                          ),
                          ListTile(
                            leading: IconBox(
                              icon: Icons.system_update,
                              colorScheme: cs,
                            ),
                            title: const Text('Check for updates'),
                            subtitle: Text('Channel: ${UpdateService.channel}'),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: cs.onSurfaceVariant,
                            ),
                            onTap: () => _checkForUpdate(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── GitHub section ────────────────────────────────────
                  const SectionHeader(title: 'GitHub'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: IconBox(icon: Icons.source, colorScheme: cs),
                          title: const Text('Source Code'),
                          subtitle: Text(
                            '${UpdateService.owner}/${UpdateService.repo}',
                          ),
                          trailing: Icon(
                            Icons.open_in_new,
                            color: cs.onSurfaceVariant,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse(UpdateService.repoUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        ListTile(
                          leading: IconBox(
                            icon: Icons.bug_report,
                            colorScheme: cs,
                          ),
                          title: const Text('Report an Issue'),
                          subtitle: const Text('Bugs & feature requests'),
                          trailing: Icon(
                            Icons.open_in_new,
                            color: cs.onSurfaceVariant,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse('${UpdateService.repoUrl}/issues'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        ListTile(
                          leading: IconBox(
                            icon: Icons.new_releases_outlined,
                            colorScheme: cs,
                          ),
                          title: const Text('Releases'),
                          subtitle: const Text('Download latest versions'),
                          trailing: Icon(
                            Icons.open_in_new,
                            color: cs.onSurfaceVariant,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse('${UpdateService.repoUrl}/releases'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _providerIcon(LlmProvider provider) {
    switch (provider) {
      case LlmProvider.openai:
        return Icons.smart_toy_outlined;
      case LlmProvider.githubModels:
        return Icons.code;
      case LlmProvider.openRouter:
        return Icons.hub_outlined;
      case LlmProvider.nvidia:
        return Icons.memory_outlined;
      case LlmProvider.huggingFace:
        return Icons.emoji_nature_outlined;
    }
  }
}

// ── Theme Tile ──────────────────────────────────────────────────────────────

class _ThemeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? cs.primary : null,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle, color: cs.primary)
          : const SizedBox.shrink(),
      onTap: onTap,
    );
  }
}

// ── Add MCP Server Dialog ───────────────────────────────────────────────────

class _AddMcpServerDialog extends StatefulWidget {
  final ValueChanged<McpServerConfig> onAdd;

  const _AddMcpServerDialog({required this.onAdd});

  @override
  State<_AddMcpServerDialog> createState() => _AddMcpServerDialogState();
}

class _AddMcpServerDialogState extends State<_AddMcpServerDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _headerNameController = TextEditingController();
  final _headerValueController = TextEditingController();
  McpTransportType _transportType = McpTransportType.httpStreamable;
  McpAuthType _authType = McpAuthType.none;
  String? _nameError;
  String? _urlError;
  String? _authError;
  bool _obscureToken = true;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    _headerNameController.dispose();
    _headerValueController.dispose();
    super.dispose();
  }

  void _onAdd() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();
    final headerName = _headerNameController.text.trim();
    final headerValue = _headerValueController.text.trim();
    bool valid = true;

    setState(() {
      _nameError = null;
      _urlError = null;
      _authError = null;

      if (name.isEmpty) {
        _nameError = 'Name is required';
        valid = false;
      }
      if (url.isEmpty) {
        _urlError = 'URL is required';
        valid = false;
      } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
        _urlError = 'Must start with http:// or https://';
        valid = false;
      }

      // Validate auth fields
      if (_authType == McpAuthType.bearer && token.isEmpty) {
        _authError = 'Bearer token is required';
        valid = false;
      } else if (_authType == McpAuthType.customHeader) {
        if (headerName.isEmpty || headerValue.isEmpty) {
          _authError = 'Both header name and value are required';
          valid = false;
        }
      }
    });

    if (valid) {
      widget.onAdd(McpServerConfig(
        name: name,
        url: url,
        type: _transportType,
        authType: _authType,
        authToken: _authType == McpAuthType.bearer ? token : null,
        authHeaderName: _authType == McpAuthType.customHeader ? headerName : null,
        authHeaderValue: _authType == McpAuthType.customHeader ? headerValue : null,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add MCP Server'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. My Tools Server',
                  errorText: _nameError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://example.com/mcp',
                  errorText: _urlError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) {
                  if (_urlError != null) {
                    setState(() => _urlError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Transport Type',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  return Wrap(
                    spacing: 8,
                    children: McpTransportType.values.map((type) {
                      final isSelected = _transportType == type;
                      return FilterChip(
                        selected: isSelected,
                        label: Text(
                          type == McpTransportType.httpStreamable
                              ? 'HTTP Streamable'
                              : 'SSE',
                        ),
                        onSelected: (_) {
                          setState(() => _transportType = type);
                        },
                        showCheckmark: true,
                        selectedColor: cs.primaryContainer,
                        checkmarkColor: cs.onPrimaryContainer,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? cs.onPrimaryContainer
                              : cs.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? cs.primary : cs.outline,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Authentication',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  return Wrap(
                    spacing: 8,
                    children: McpAuthType.values.map((authType) {
                      final isSelected = _authType == authType;
                      final label = switch (authType) {
                        McpAuthType.none => 'None',
                        McpAuthType.bearer => 'Bearer Token',
                        McpAuthType.customHeader => 'Custom Header',
                      };
                      return FilterChip(
                        selected: isSelected,
                        label: Text(label),
                        onSelected: (_) {
                          setState(() {
                            _authType = authType;
                            _authError = null;
                          });
                        },
                        showCheckmark: true,
                        selectedColor: cs.primaryContainer,
                        checkmarkColor: cs.onPrimaryContainer,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? cs.onPrimaryContainer
                              : cs.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? cs.primary : cs.outline,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              if (_authType == McpAuthType.bearer) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'Bearer Token',
                    hintText: 'Enter your API token',
                    errorText: _authError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscureToken = !_obscureToken);
                      },
                    ),
                  ),
                  onChanged: (_) {
                    if (_authError != null) {
                      setState(() => _authError = null);
                    }
                  },
                ),
              ],
              if (_authType == McpAuthType.customHeader) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _headerNameController,
                  decoration: InputDecoration(
                    labelText: 'Header Name',
                    hintText: 'e.g. X-API-Key',
                    errorText: _authError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) {
                    if (_authError != null) {
                      setState(() => _authError = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _headerValueController,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'Header Value',
                    hintText: 'Enter the header value',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscureToken = !_obscureToken);
                      },
                    ),
                  ),
                  onChanged: (_) {
                    if (_authError != null) {
                      setState(() => _authError = null);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _onAdd, child: const Text('Add')),
      ],
    );
  }
}
