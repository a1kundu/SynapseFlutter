import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_controller.dart';
import '../settings/settings_repository.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Track settings that matter for model/MCP refresh.
  String _prevApiKey = '';
  String _prevProvider = '';
  int _prevMcpCount = 0;

  Future<void> _openSettings(BuildContext context) async {
    final controller = context.read<ChatController>();
    final settings = SettingsRepository.instance;
    // Snapshot current settings before navigating
    _prevApiKey = settings.llmApiKey;
    _prevProvider = settings.llmProvider.name;
    _prevMcpCount = settings.mcpServers.length;

    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SettingsScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
                reverseCurve: Curves.easeInOut,
              ),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );

    // After returning from settings, check if LLM config changed
    if (settings.llmApiKey != _prevApiKey ||
        settings.llmProvider.name != _prevProvider) {
      controller.refreshModels();
    }
    // Check if MCP servers changed
    if (settings.mcpServers.length != _prevMcpCount) {
      controller.refreshMcpTools();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/icons/app_icon.png',
                width: 32,
                height: 32,
              ),
            ),
          ],
        ),
        actions: [
          // Model selector chip
          ModelSelectorChip(
            selectedModel: controller.selectedModel,
            onModelSelected: controller.selectModel,
            models: controller.availableModels,
            isLoading: controller.isLoadingModels,
            onRefresh: controller.refreshModels,
            error: controller.modelFetchError,
          ),
          const SizedBox(width: 8),
          // Settings button
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.settings_rounded, size: 20),
              tooltip: 'Settings',
              onPressed: () => _openSettings(context),
            ),
          ),
        ],
      ),
      body: ChatScreen(controller: controller),
    );
  }
}
