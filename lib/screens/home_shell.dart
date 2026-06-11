import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_session.dart';
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
  String _prevApiKey = '';
  String _prevProvider = '';
  int _prevMcpCount = 0;

  Future<void> _openSettings(BuildContext context) async {
    final controller = context.read<ChatController>();
    final settings = SettingsRepository.instance;
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

    if (settings.llmApiKey != _prevApiKey ||
        settings.llmProvider.name != _prevProvider) {
      controller.refreshModels();
    }
    if (settings.mcpServers.length != _prevMcpCount) {
      controller.refreshMcpTools();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final isWide = MediaQuery.of(context).size.width >= 768;

    if (isWide) {
      return _WideLayout(
        controller: controller,
        onOpenSettings: () => _openSettings(context),
      );
    } else {
      return _NarrowLayout(
        controller: controller,
        onOpenSettings: () => _openSettings(context),
      );
    }
  }
}

// ── Wide Layout (persistent sidebar) ────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final ChatController controller;
  final VoidCallback onOpenSettings;

  const _WideLayout({
    required this.controller,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          SizedBox(
            width: 280,
            child: _ChatHistoryPanel(
              controller: controller,
              onOpenSettings: onOpenSettings,
            ),
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          // Main content
          Expanded(
            child: Scaffold(
              body: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  _buildSliverAppBar(context, controller, onOpenSettings),
                ],
                body: ChatScreen(controller: controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Narrow Layout (drawer) ──────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final ChatController controller;
  final VoidCallback onOpenSettings;

  const _NarrowLayout({
    required this.controller,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: _ChatHistoryPanel(
          controller: controller,
          onOpenSettings: onOpenSettings,
          isDrawer: true,
        ),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(context, controller, onOpenSettings,
              showMenuButton: true),
        ],
        body: ChatScreen(controller: controller),
      ),
    );
  }
}

// ── Shared App Bar ──────────────────────────────────────────────────────────

SliverAppBar _buildSliverAppBar(
  BuildContext context,
  ChatController controller,
  VoidCallback onOpenSettings, {
  bool showMenuButton = false,
}) {
  return SliverAppBar(
    floating: false,
    snap: false,
    pinned: false,
    toolbarHeight: 64,
    leading: showMenuButton
        ? Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          )
        : null,
    automaticallyImplyLeading: false,
    title: Row(
      children: [
        if (!showMenuButton) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/icons/app_icon.png',
              width: 28,
              height: 28,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            controller.activeSession?.name ?? 'Synapse',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
    actions: [
      ModelSelectorChip(
        selectedModel: controller.selectedModel,
        onModelSelected: controller.selectModel,
        models: controller.availableModels,
        isLoading: controller.isLoadingModels,
        onRefresh: controller.refreshModels,
        error: controller.modelFetchError,
      ),
      const SizedBox(width: 8),
      Container(
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: IconButton(
          icon: const Icon(Icons.add, size: 20),
          tooltip: 'New Chat',
          onPressed: controller.createNewChat,
        ),
      ),
    ],
  );
}

// ── Chat History Panel ──────────────────────────────────────────────────────

class _ChatHistoryPanel extends StatelessWidget {
  final ChatController controller;
  final VoidCallback onOpenSettings;
  final bool isDrawer;

  const _ChatHistoryPanel({
    required this.controller,
    required this.onOpenSettings,
    this.isDrawer = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sessions = controller.sessions;
    final activeId = controller.activeSession?.id;

    return Container(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          // Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      width: 28,
                      height: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Synapse',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () {
                      if (isDrawer) Navigator.of(context).pop();
                      onOpenSettings();
                    },
                    tooltip: 'Settings',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Chat history list
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Text(
                      'No conversations yet',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = session.id == activeId;
                      return _ChatSessionTile(
                        session: session,
                        isActive: isActive,
                        onTap: () {
                          controller.switchToSession(session.id);
                          if (isDrawer) Navigator.of(context).pop();
                        },
                        onRename: () =>
                            _showRenameDialog(context, session),
                        onDelete: () =>
                            _showDeleteConfirm(context, session),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ChatSession session) {
    final nameController = TextEditingController(text: session.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Chat'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Chat name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              controller.renameSession(session.id, value.trim());
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                controller.renameSession(session.id, name);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, ChatSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat'),
        content: Text('Delete "${session.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              controller.deleteSession(session.id);
              Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Chat Session Tile ───────────────────────────────────────────────────────

class _ChatSessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ChatSessionTile({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: isActive
            ? cs.primaryContainer.withValues(alpha: 0.4)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: isActive ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.normal,
                          color:
                              isActive ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _formatDate(session.updatedAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                // Context menu
                PopupMenuButton<String>(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(24, 24),
                    padding: EdgeInsets.zero,
                  ),
                  icon: Icon(
                    Icons.more_horiz,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Rename'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 16,
                              color: cs.error),
                          const SizedBox(width: 8),
                          Text('Delete',
                              style: TextStyle(color: cs.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
