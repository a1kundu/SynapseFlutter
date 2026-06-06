import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_controller.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  void _openSettings(BuildContext context) {
    Navigator.push(
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
                'assets/icons/icon-96x96.png',
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
