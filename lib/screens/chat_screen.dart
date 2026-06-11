import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../agents/agent_models.dart';
import '../models/chat_models.dart';
import '../services/chat_controller.dart';
import '../utils/snackbar_service.dart';
import '../widgets/mermaid_view.dart'; // MermaidView
import 'package:markdown/markdown.dart' as md;

/// Main chat screen displaying conversation messages with markdown rendering,
/// file attachments, MCP tools status, and an input bar.
class ChatScreen extends StatefulWidget {
  final ChatController controller;

  const ChatScreen({super.key, required this.controller});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _subAgentDialogShowing = false;

  /// The activity the user manually dismissed. Prevents auto-reopening
  /// the dialog on every token update while the same sub-agent runs.
  SubAgentActivity? _userDismissedActivity;

  ChatController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
    _ctrl.subAgentActivity.addListener(_onSubAgentActivityChanged);
    _textController.text = _ctrl.inputText;
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      oldWidget.controller.subAgentActivity.removeListener(_onSubAgentActivityChanged);
      widget.controller.addListener(_onControllerChanged);
      widget.controller.subAgentActivity.addListener(_onSubAgentActivityChanged);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _ctrl.subAgentActivity.removeListener(_onSubAgentActivityChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSubAgentActivityChanged() {
    final activity = _ctrl.subAgentActivity.value;

    if (activity == null) {
      // Sub-agent finished and was cleared -- reset dismiss tracking
      _userDismissedActivity = null;
      return;
    }

    // If this is a different activity than what the user dismissed,
    // reset the flag (a new sub-agent started)
    if (_userDismissedActivity != null && _userDismissedActivity != activity) {
      _userDismissedActivity = null;
    }

    // Auto-open only if: not already showing, and user hasn't dismissed this one
    if (!_subAgentDialogShowing && _userDismissedActivity == null) {
      _openLiveSubAgentDialog();
    }
  }

  /// Open the live sub-agent dialog (for a running sub-agent).
  void _openLiveSubAgentDialog() {
    if (_subAgentDialogShowing) return;
    _subAgentDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _SubAgentDialog(
        activityNotifier: _ctrl.subAgentActivity,
        onDismiss: () {
          Navigator.of(dialogContext).pop();
        },
      ),
    ).then((_) {
      _subAgentDialogShowing = false;
      // If the sub-agent is still running, mark as user-dismissed
      final activity = _ctrl.subAgentActivity.value;
      if (activity != null && activity.isRunning) {
        _userDismissedActivity = activity;
      }
    });
  }

  /// Show the sub-agent activity dialog for a given tool call.
  /// If the sub-agent is still running (live), opens the live dialog.
  /// If completed, opens a static replay dialog.
  void _showSubAgentActivity(String toolCallId) {
    // Check if this is the currently running sub-agent
    final liveActivity = _ctrl.subAgentActivity.value;
    if (liveActivity != null &&
        liveActivity.toolCallId == toolCallId &&
        liveActivity.isRunning) {
      // Re-open the live dialog and clear the dismiss flag
      _userDismissedActivity = null;
      _openLiveSubAgentDialog();
      return;
    }

    // Otherwise, show completed activity as static replay
    var activity = _ctrl.completedSubAgentActivities[toolCallId];

    // If not in the in-memory map (e.g. after app restart), reconstruct
    // from the persisted ToolCallEntry data so the dialog still works.
    if (activity == null) {
      activity = _reconstructSubAgentActivity(toolCallId);
      if (activity == null) return;
      // Cache so subsequent taps are instant
      _ctrl.completedSubAgentActivities[toolCallId] = activity;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _SubAgentDialog(
        staticActivity: activity,
        onDismiss: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  /// Reconstruct a [SubAgentActivity] from a persisted [ToolCallEntry].
  ///
  /// After an app restart `completedSubAgentActivities` is empty, but
  /// [ChatMessage.toolCalls] are persisted. We can extract the agent name,
  /// task, and final result from the `delegate_to_agent` call's arguments
  /// and result to build a static replay activity.
  SubAgentActivity? _reconstructSubAgentActivity(String toolCallId) {
    for (final msg in _ctrl.messages) {
      for (final entry in msg.toolCalls) {
        if (entry.id == toolCallId && entry.toolName == 'delegate_to_agent') {
          try {
            final args =
                json.decode(entry.arguments) as Map<String, dynamic>;
            final agentName = args['agent'] as String? ?? 'unknown';
            final task = args['task'] as String? ?? '';

            // Strip the "[Sub-agent: …]\n\n" prefix from the result if present
            var resultContent = entry.result;
            final prefixPattern = RegExp(r'^\[Sub-agent: [^\]]+\]\n\n');
            resultContent = resultContent.replaceFirst(prefixPattern, '');

            return SubAgentActivity(
              agentName: agentName,
              agentRole: '',
              taskDescription: task,
              toolCallId: toolCallId,
              streamingContent: resultContent,
              isRunning: false,
              isComplete: true,
              error: entry.status == ToolCallStatus.error ? resultContent : null,
            );
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  void _onControllerChanged() {
    setState(() {});
  }

  void _onSend() {
    final text = _textController.text;
    if (text.trim().isEmpty && _ctrl.pendingAttachments.isEmpty) return;
    _ctrl.sendMessage(text);
    _textController.clear();
    _focusNode.unfocus();
  }

  Future<void> _onAttach() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    for (final file in result.files) {
      _ctrl.addAttachment(
        ChatAttachment(
          fileName: file.name,
          fileSizeBytes: file.size,
          mimeType: _guessMimeType(file.name),
          bytes: file.bytes,
        ),
      );
    }
  }

  String _guessMimeType(String name) {
    final ext = name.split('.').last.toLowerCase();
    const mimeMap = {
      'txt': 'text/plain',
      'md': 'text/markdown',
      'json': 'application/json',
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'svg': 'image/svg+xml',
      'html': 'text/html',
      'css': 'text/css',
      'js': 'application/javascript',
      'ts': 'text/typescript',
      'dart': 'text/x-dart',
      'py': 'text/x-python',
      'rs': 'text/x-rust',
      'go': 'text/x-go',
      'java': 'text/x-java',
      'kt': 'text/x-kotlin',
      'swift': 'text/x-swift',
      'c': 'text/x-c',
      'cpp': 'text/x-c++',
      'h': 'text/x-c',
      'xml': 'application/xml',
      'yaml': 'text/yaml',
      'yml': 'text/yaml',
      'toml': 'text/toml',
      'csv': 'text/csv',
      'zip': 'application/zip',
      'tar': 'application/x-tar',
      'gz': 'application/gzip',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    showRootSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showEditDialog(ChatMessage message) {
    final editController = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Message'),
          content: TextField(
            controller: editController,
            maxLines: 8,
            minLines: 3,
            decoration: InputDecoration(
              hintText: 'Edit your message...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final newContent = editController.text.trim();
                if (newContent.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  _ctrl.editUserMessage(message.id, newContent);
                }
              },
              child: const Text('Save & Resend'),
            ),
          ],
        );
      },
    );
  }

  void _forkChat(String messageId) {
    _ctrl.forkChatAtMessage(messageId);
    showRootSnackBar(
      const SnackBar(
        content: Text('Chat forked from this message'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _retryMessage(String messageId) {
    _ctrl.retryFromMessage(messageId);
  }

  void _exportChat() {
    final json = _ctrl.exportChatToJson();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(json);
    Clipboard.setData(ClipboardData(text: jsonStr));
    showRootSnackBar(
      const SnackBar(
        content: Text('Chat exported to clipboard as JSON'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: false,
      child: Stack(
      children: [
        // Messages list – fills entire area, scrolls behind input bar
        Positioned.fill(
          child: _ctrl.messages.isEmpty
              ? _EmptyState(modelName: _ctrl.selectedModel?.displayName)
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 120),
                  itemCount: _ctrl.messages.length,
                  itemBuilder: (context, index) {
                    return _MessageBubble(
                      message: _ctrl.messages[index],
                      onCopy: _copyMessage,
                      onEdit: _showEditDialog,
                      onFork: _forkChat,
                      onRetry: _retryMessage,
                      isGenerating: _ctrl.isGenerating,
                      onSubAgentTap: _showSubAgentActivity,
                    );
                  },
                ),
        ),

        // Bottom-aligned input area (overlays messages)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pending attachments preview
              if (_ctrl.pendingAttachments.isNotEmpty)
                _AttachmentPreviewBar(
                  attachments: _ctrl.pendingAttachments,
                  onRemove: _ctrl.removeAttachment,
                ),

              // Chat input bar with integrated tools button
              _ChatInputBar(
                textController: _textController,
                focusNode: _focusNode,
                onTextChange: _ctrl.onInputTextChange,
                onSend: _onSend,
                onAttach: _onAttach,
                isGenerating: _ctrl.isGenerating,
                onExportChat: _exportChat,
                onCancel: _ctrl.cancelGeneration,
                hasMessages: _ctrl.messages.isNotEmpty,
                controller: _ctrl,
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

// ── Model Selector Chip (used in HomeShell app bar) ─────────────────────────

class ModelSelectorChip extends StatefulWidget {
  final LlmModel? selectedModel;
  final ValueChanged<LlmModel> onModelSelected;
  final List<LlmModel> models;
  final bool isLoading;
  final VoidCallback onRefresh;
  final String? error;

  const ModelSelectorChip({
    super.key,
    required this.selectedModel,
    required this.onModelSelected,
    required this.models,
    this.isLoading = false,
    required this.onRefresh,
    this.error,
  });

  @override
  State<ModelSelectorChip> createState() => _ModelSelectorChipState();
}

class _ModelSelectorChipState extends State<ModelSelectorChip> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void didUpdateWidget(ModelSelectorChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _overlayEntry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() {});
  }

  void _toggleOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    _overlayEntry = OverlayEntry(
      builder: (_) => _ModelPickerDropdown(
        layerLink: _layerLink,
        models: widget.models,
        selectedModel: widget.selectedModel,
        isLoading: widget.isLoading,
        error: widget.error,
        onModelSelected: (model) {
          widget.onModelSelected(model);
          _removeOverlay();
        },
        onDismiss: _removeOverlay,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.outline.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Model picker toggle ──
            GestureDetector(
              onTap: _toggleOverlay,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isLoading)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else if (widget.error != null && widget.models.isEmpty)
                      Icon(Icons.error_outline, size: 14, color: cs.error)
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          width: 14,
                          height: 14,
                        ),
                      ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        widget.selectedModel?.displayName ?? 'Select model',
                        style: Theme.of(context).textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _overlayEntry != null
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            // ── Divider ──
            Container(
              width: 1,
              height: 22,
              color: cs.outline.withValues(alpha: 0.25),
            ),
            // ── Refresh split button ──
            InkWell(
              onTap: widget.isLoading ? null : widget.onRefresh,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: widget.isLoading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : Icon(Icons.refresh, size: 16, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Model Picker Dropdown Overlay ────────────────────────────────────────────

class _ModelPickerDropdown extends StatefulWidget {
  final LayerLink layerLink;
  final List<LlmModel> models;
  final LlmModel? selectedModel;
  final bool isLoading;
  final String? error;
  final ValueChanged<LlmModel> onModelSelected;
  final VoidCallback onDismiss;

  const _ModelPickerDropdown({
    required this.layerLink,
    required this.models,
    required this.selectedModel,
    required this.isLoading,
    required this.error,
    required this.onModelSelected,
    required this.onDismiss,
  });

  @override
  State<_ModelPickerDropdown> createState() => _ModelPickerDropdownState();
}

class _ModelPickerDropdownState extends State<_ModelPickerDropdown> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final filtered = _query.isEmpty
        ? widget.models
        : widget.models.where((m) {
            final q = _query.toLowerCase();
            return m.displayName.toLowerCase().contains(q) ||
                m.provider.toLowerCase().contains(q);
          }).toList();

    final grouped = <String, List<LlmModel>>{};
    for (final m in filtered) {
      (grouped[m.provider] ??= []).add(m);
    }

    return Stack(
      children: [
        // Dismiss barrier
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // Dropdown panel
        CompositedTransformFollower(
          link: widget.layerLink,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          child: Material(
            elevation: 0,
            borderRadius: BorderRadius.circular(12),
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Container(
                width: 280,
                constraints: const BoxConstraints(maxHeight: 400),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search field
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (v) => setState(() => _query = v),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search models…',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Icon(
                                Icons.search,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    padding: EdgeInsets.zero,
                                    iconSize: 14,
                                    icon: Icon(
                                      Icons.close,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    onPressed: () => setState(() {
                                      _query = '';
                                      _searchController.clear();
                                    }),
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: cs.outline.withValues(alpha: 0.15),
                      ),
                      // Model list
                      Flexible(
                        child: widget.isLoading && widget.models.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : widget.error != null && widget.models.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 16,
                                      color: cs.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.error!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.error,
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : grouped.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No models match "$_query"',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                shrinkWrap: true,
                                children: [
                                  for (final entry in grouped.entries) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        8,
                                        14,
                                        2,
                                      ),
                                      child: Text(
                                        entry.key,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: cs.primary,
                                        ),
                                      ),
                                    ),
                                    for (final model in entry.value)
                                      InkWell(
                                        onTap: () =>
                                            widget.onModelSelected(model),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 9,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  model.displayName,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (model.supportsTools)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 6,
                                                      ),
                                                  child: Tooltip(
                                                    message:
                                                        'Supports tool calling',
                                                    child: Icon(
                                                      Icons
                                                          .build_circle_outlined,
                                                      size: 14,
                                                      color: cs.primary
                                                          .withValues(
                                                            alpha: 0.7,
                                                          ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 6,
                                                      ),
                                                  child: Tooltip(
                                                    message:
                                                        'No tool calling support',
                                                    child: Icon(
                                                      Icons
                                                          .build_circle_outlined,
                                                      size: 14,
                                                      color: cs.onSurfaceVariant
                                                          .withValues(
                                                            alpha: 0.25,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              if (model.id ==
                                                  widget.selectedModel?.id)
                                                Icon(
                                                  Icons.check,
                                                  size: 16,
                                                  color: cs.primary,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    Divider(
                                      height: 1,
                                      indent: 14,
                                      endIndent: 14,
                                      color: cs.outline.withValues(alpha: 0.08),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String? modelName;

  const _EmptyState({this.modelName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.asset(
                'assets/icons/app_icon.png',
                width: 72,
                height: 72,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start a conversation',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              modelName != null
                  ? 'Using $modelName'
                  : 'Configure your API key in Settings',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Type a message below or attach a file to get started',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message Bubble with Actions ─────────────────────────────────────────────

class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final ValueChanged<String> onCopy;
  final ValueChanged<ChatMessage> onEdit;
  final ValueChanged<String> onFork;
  final ValueChanged<String> onRetry;
  final bool isGenerating;
  final void Function(String toolCallId)? onSubAgentTap;

  const _MessageBubble({
    required this.message,
    required this.onCopy,
    required this.onEdit,
    required this.onFork,
    required this.onRetry,
    required this.isGenerating,
    this.onSubAgentTap,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _showActions = false;

  void _toggleActions() {
    if (widget.message.isStreaming || widget.isGenerating) return;
    setState(() => _showActions = !_showActions);
  }

  void _dismissActions() {
    if (_showActions) setState(() => _showActions = false);
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    final cs = Theme.of(context).colorScheme;

    final bubbleColor = isUser ? cs.primaryContainer : cs.secondaryContainer;
    final contentColor = isUser
        ? cs.onPrimaryContainer
        : cs.onSecondaryContainer;
    final alignment = isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return GestureDetector(
      onLongPress: _toggleActions,
      onTap: _dismissActions,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: alignment,
          children: [
            // Role label row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isUser) ...[
                    ClipOval(
                      child: Image.asset(
                        'assets/icons/app_icon.png',
                        width: 14,
                        height: 14,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.message.model?.displayName ?? 'Synapse',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ] else
                    Text(
                      'You',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),

            // Message bubble
            Container(
              constraints: BoxConstraints(
                minWidth: 60,
                maxWidth: isUser
                    ? 340
                    : MediaQuery.of(context).size.width,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Attachments
                  if (widget.message.attachments.isNotEmpty) ...[
                    ...widget.message.attachments.map(
                      (a) => _AttachmentChip(attachment: a, tint: contentColor),
                    ),
                    if (widget.message.content.isNotEmpty ||
                        widget.message.toolCalls.isNotEmpty)
                      const SizedBox(height: 8),
                  ],

                  // Tool call steps (shown before final content)
                  if (widget.message.toolCalls.isNotEmpty) ...[
                    _ToolCallSteps(
                      toolCalls: widget.message.toolCalls,
                      contentColor: contentColor,
                      onSubAgentTap: widget.onSubAgentTap,
                    ),
                    if (widget.message.content.isNotEmpty)
                      const SizedBox(height: 10),
                  ],

                  // Text content
                  if (widget.message.content.isNotEmpty) ...[
                    if (isUser || widget.message.isStreaming)
                      Text(
                        widget.message.content,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: contentColor),
                      )
                    else
                      _AssistantMarkdown(
                        content: widget.message.content,
                        contentColor: contentColor,
                      ),
                  ] else if (!widget.message.isStreaming &&
                      widget.message.toolCalls.isEmpty)
                    Text(
                      'Empty response',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: contentColor.withValues(alpha: 0.5),
                      ),
                    ),

                  // Streaming indicator
                  if (widget.message.isStreaming) ...[
                    const SizedBox(height: 4),
                    _StreamingIndicator(tint: contentColor),
                  ],
                ],
              ),
            ),

            // Action buttons (shown on long press)
            if (_showActions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionChip(
                      icon: Icons.copy_outlined,
                      label: 'Copy',
                      onTap: () {
                        widget.onCopy(widget.message.content);
                        _dismissActions();
                      },
                    ),
                    if (isUser)
                      _ActionChip(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onTap: () {
                          widget.onEdit(widget.message);
                          _dismissActions();
                        },
                      ),
                    _ActionChip(
                      icon: Icons.fork_right_outlined,
                      label: 'Fork',
                      onTap: () {
                        widget.onFork(widget.message.id);
                        _dismissActions();
                      },
                    ),
                    if (isUser)
                      _ActionChip(
                        icon: Icons.refresh,
                        label: 'Retry',
                        onTap: () {
                          widget.onRetry(widget.message.id);
                          _dismissActions();
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small action chip shown below the message bubble on long press.
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Assistant Markdown Renderer ─────────────────────────────────────────────

class _AssistantMarkdown extends StatelessWidget {
  final String content;
  final Color contentColor;

  const _AssistantMarkdown({required this.content, required this.contentColor});

  /// Regex for block math: $$...$$ or \[...\]
  static final _blockMathPattern = RegExp(
    r'\$\$([\s\S]*?)\$\$'
    r'|\\\[([\s\S]*?)\\\]',
    multiLine: true,
  );

  /// Regex for inline math: $...$ or \(...\)
  static final _inlineMathPattern = RegExp(
    r'\$([^\$\n]+?)\$'
    r'|\\\((.+?)\\\)',
  );

  /// Check if text contains any math expressions.
  static bool _hasMath(String text) =>
      _blockMathPattern.hasMatch(text) || _inlineMathPattern.hasMatch(text);

  @override
  Widget build(BuildContext context) {
    // Fast path: no math at all.
    if (!_hasMath(content)) {
      return _buildMarkdown(context, content);
    }

    // Split on block math boundaries into segments.
    final segments = <_MathSegment>[];
    var lastEnd = 0;
    for (final match in _blockMathPattern.allMatches(content)) {
      if (match.start > lastEnd) {
        segments.add(_MathSegment(
          _SegmentType.markdown,
          content.substring(lastEnd, match.start),
        ));
      }
      final tex = (match.group(1) ?? match.group(2))!.trim();
      segments.add(_MathSegment(_SegmentType.mathBlock, tex));
      lastEnd = match.end;
    }
    if (lastEnd < content.length) {
      segments.add(_MathSegment(
        _SegmentType.markdown,
        content.substring(lastEnd),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: segments.map((seg) {
        if (seg.type == _SegmentType.mathBlock) {
          return _buildBlockMath(context, seg.text);
        }
        // Markdown segment — may contain inline math.
        if (seg.text.trim().isEmpty) return const SizedBox.shrink();
        if (_inlineMathPattern.hasMatch(seg.text)) {
          return _buildMixedContent(context, seg.text);
        }
        return _buildMarkdown(context, seg.text);
      }).toList(),
    );
  }

  /// Build mixed content: split text into lines, render lines with inline math
  /// using Text.rich, and lines without inline math using MarkdownBody.
  Widget _buildMixedContent(BuildContext context, String text) {
    // Split into paragraphs separated by blank lines.
    // For each paragraph, check if it contains inline math.
    // If yes → render with Text.rich. If no → render as markdown.
    final lines = text.split('\n');
    final widgets = <Widget>[];
    final mdBuffer = StringBuffer();

    void flushMarkdown() {
      final md = mdBuffer.toString();
      mdBuffer.clear();
      if (md.trim().isNotEmpty) {
        widgets.add(_buildMarkdown(context, md));
      }
    }

    for (final line in lines) {
      if (_inlineMathPattern.hasMatch(line)) {
        flushMarkdown();
        widgets.add(_buildInlineMathLine(context, line));
      } else {
        mdBuffer.writeln(line);
      }
    }
    flushMarkdown();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// Render a single line that contains inline math as Text.rich with WidgetSpans.
  Widget _buildInlineMathLine(BuildContext context, String line) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: contentColor,
    );

    final children = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in _inlineMathPattern.allMatches(line)) {
      if (match.start > lastEnd) {
        children.add(TextSpan(
          text: line.substring(lastEnd, match.start),
          style: textStyle,
        ));
      }
      final tex = (match.group(1) ?? match.group(2))!.trim();
      children.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          tex,
          textStyle: TextStyle(fontSize: 14, color: contentColor),
          onErrorFallback: (e) => Text(
            '\$$tex\$',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: cs.error,
            ),
          ),
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < line.length) {
      children.add(TextSpan(
        text: line.substring(lastEnd),
        style: textStyle,
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(TextSpan(children: children)),
    );
  }

  Widget _buildMarkdown(BuildContext context, String data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return MarkdownBody(
      data: data,
      selectable: false,
      extensionSet: md.ExtensionSet.gitHubWeb,
      styleSheet: MarkdownStyleSheet(
        p: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: contentColor),
        h1: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: contentColor,
          fontWeight: FontWeight.bold,
        ),
        h2: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: contentColor,
          fontWeight: FontWeight.bold,
        ),
        h3: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: contentColor,
          fontWeight: FontWeight.bold,
        ),
        h4: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: contentColor,
        ),
        h5: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: contentColor,
        ),
        h6: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: contentColor,
        ),
        listBullet: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: contentColor),
        blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: contentColor.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        ),
        code: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.primary,
          fontFamily: 'monospace',
          backgroundColor: cs.primary.withValues(alpha: 0.08),
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF282C34) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: EdgeInsets.zero,
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: cs.primary.withValues(alpha: 0.4),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: contentColor.withValues(alpha: 0.2)),
          ),
        ),
        a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
        tableBorder: TableBorder.all(
          color: contentColor.withValues(alpha: 0.2),
          width: 1,
        ),
        tableHead: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: contentColor,
        ),
        tableBody: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: contentColor),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        tableHeadAlign: TextAlign.left,
      ),
      builders: {'code': _CodeBlockBuilder(isDark: isDark)},
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  /// Render a block-level math expression (centered, horizontally scrollable).
  Widget _buildBlockMath(BuildContext context, String tex) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            tex,
            textStyle: TextStyle(fontSize: 16, color: contentColor),
            onErrorFallback: (e) => Text(
              tex,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: cs.error,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SegmentType { markdown, mathBlock }

class _MathSegment {
  final _SegmentType type;
  final String text;
  _MathSegment(this.type, this.text);
}

/// Custom code block builder with syntax highlighting, language label, and copy button.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;
  _CodeBlockBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'code') return null;

    final text = element.textContent;
    String? language;

    final classes = element.attributes['class'];
    if (classes != null && classes.startsWith('language-')) {
      language = classes.substring(9);
    }

    // Check if parent is 'pre' (fenced code block) vs inline code
    // For inline code without language, return null to use default styling
    final isInlineCode = language == null || language.isEmpty;

    if (isInlineCode) return null;

    final isMermaid = language.toLowerCase() == 'mermaid';
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final bgColor = isDark ? const Color(0xFF282C34) : const Color(0xFFF5F5F5);
    final headerColor = isDark
        ? const Color(0xFF21252B)
        : const Color(0xFFE8E8E8);
    final textColor = isDark
        ? const Color(0xFFABB2BF)
        : const Color(0xFF383A42);
    final labelColor = isDark
        ? const Color(0xFF7F848E)
        : const Color(0xFF999999);

    Widget codeContent;
    if (isMermaid) {
      // Mermaid gets its own StatefulWidget so the reload button in the header
      // can trigger a full re-render of the diagram.
      return _MermaidCodeBlock(code: text, isDark: isDark);
    } else {
      try {
        final result = highlight.parse(text, language: language);
        codeContent = _buildHighlightedText(result.nodes!, theme, isDark);
      } catch (_) {
        codeContent = SelectableText(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: textColor,
          ),
        );
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with language label and copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Text(
                  language,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Builder(
                  builder: (context) => InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: text));
                      showRootSnackBar(
                        const SnackBar(
                          content: Text('Code copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_outlined,
                            size: 12,
                            color: labelColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Copy',
                            style: TextStyle(fontSize: 11, color: labelColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code content
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: codeContent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(
    List<dynamic> nodes,
    Map<String, TextStyle> theme,
    bool isDark,
  ) {
    final spans = <TextSpan>[];
    _buildSpans(nodes, theme, spans, null);

    return SelectableText.rich(
      TextSpan(
        children: spans,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? const Color(0xFFABB2BF) : const Color(0xFF383A42),
        ),
      ),
    );
  }

  void _buildSpans(
    List<dynamic> nodes,
    Map<String, TextStyle> theme,
    List<TextSpan> spans,
    TextStyle? parentStyle,
  ) {
    for (final node in nodes) {
      if (node is String) {
        spans.add(TextSpan(text: node, style: parentStyle));
      } else if (node.children != null) {
        final className = node.className;
        final style = className != null ? theme[className] : null;
        _buildSpans(node.children!, theme, spans, style ?? parentStyle);
      } else if (node.value != null) {
        final className = node.className;
        final style = className != null ? theme[className] : null;
        spans.add(TextSpan(text: node.value, style: style ?? parentStyle));
      }
    }
  }
}

// ── Attachment Chip (inside message) ────────────────────────────────────────

class _AttachmentChip extends StatelessWidget {
  final ChatAttachment attachment;
  final Color tint;

  const _AttachmentChip({required this.attachment, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _fileIcon(attachment.mimeType),
            size: 16,
            color: tint.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                attachment.fileName,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: tint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                attachment.displaySize,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: tint.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType.startsWith('text/')) return Icons.description_outlined;
    if (mimeType == 'application/json') return Icons.data_object_outlined;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

// ── Tool Call Steps ─────────────────────────────────────────────────────────

class _ToolCallSteps extends StatelessWidget {
  final List<ToolCallEntry> toolCalls;
  final Color contentColor;
  final void Function(String toolCallId)? onSubAgentTap;

  const _ToolCallSteps({
    required this.toolCalls,
    required this.contentColor,
    this.onSubAgentTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Group tool calls by round.
    final rounds = <int, List<ToolCallEntry>>{};
    for (final entry in toolCalls) {
      rounds.putIfAbsent(entry.round, () => []).add(entry);
    }
    final sortedRounds = rounds.keys.toList()..sort();
    final hasMultipleRounds = sortedRounds.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final round in sortedRounds) ...[
          // Collapsible thinking text (from first entry of this round)
          if (rounds[round]!.first.thinkingText.isNotEmpty)
            _ThinkingTextCollapse(
              text: rounds[round]!.first.thinkingText,
              contentColor: contentColor,
            ),
          // Round header (only when multiple rounds exist)
          if (hasMultipleRounds)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 12,
                      color: cs.outline.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(
                    'Round $round',
                    style:
                        Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.outline.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          // Tool call tiles for this round
          ...rounds[round]!.map((entry) {
            final isSubAgent = entry.toolName == 'delegate_to_agent';
            final IconData icon;
            final Color iconColor;
            switch (entry.status) {
              case ToolCallStatus.running:
                icon = isSubAgent
                    ? Icons.smart_toy_outlined
                    : Icons.hourglass_top_rounded;
                iconColor = isSubAgent ? cs.primary : cs.tertiary;
              case ToolCallStatus.completed:
                icon = isSubAgent
                    ? Icons.smart_toy_rounded
                    : Icons.check_circle_outline_rounded;
                iconColor = Colors.green;
              case ToolCallStatus.error:
                icon = isSubAgent
                    ? Icons.smart_toy_outlined
                    : Icons.error_outline_rounded;
                iconColor = cs.error;
              case ToolCallStatus.cancelled:
                icon = isSubAgent
                    ? Icons.smart_toy_outlined
                    : Icons.cancel_outlined;
                iconColor = Colors.orange;
            }
            return _ToolCallTile(
              entry: entry,
              icon: icon,
              iconColor: iconColor,
              contentColor: contentColor,
              isSubAgent: isSubAgent,
              onSubAgentTap: isSubAgent ? onSubAgentTap : null,
            );
          }),
        ],
      ],
    );
  }
}

/// Collapsible section showing text the model streamed before tool calls.
class _ThinkingTextCollapse extends StatefulWidget {
  final String text;
  final Color contentColor;

  const _ThinkingTextCollapse({
    required this.text,
    required this.contentColor,
  });

  @override
  State<_ThinkingTextCollapse> createState() => _ThinkingTextCollapseState();
}

class _ThinkingTextCollapseState extends State<_ThinkingTextCollapse> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final truncated = widget.text.length > 60
        ? '${widget.text.substring(0, 60)}...'
        : widget.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.psychology_outlined,
                    size: 14,
                    color: cs.outline.withValues(alpha: 0.6)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _expanded ? widget.text : truncated,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: widget.contentColor.withValues(alpha: 0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 14,
                  color: cs.outline.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolCallTile extends StatefulWidget {
  final ToolCallEntry entry;
  final IconData icon;
  final Color iconColor;
  final Color contentColor;
  final bool isSubAgent;
  final void Function(String toolCallId)? onSubAgentTap;

  const _ToolCallTile({
    required this.entry,
    required this.icon,
    required this.iconColor,
    required this.contentColor,
    this.isSubAgent = false,
    this.onSubAgentTap,
  });

  @override
  State<_ToolCallTile> createState() => _ToolCallTileState();
}

class _ToolCallTileState extends State<_ToolCallTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasResult = widget.entry.result.isNotEmpty;

    // For sub-agent calls, extract the agent name from arguments for display
    String displayName = widget.entry.toolName;
    String? subAgentTask;
    if (widget.isSubAgent) {
      try {
        final args = json.decode(widget.entry.arguments) as Map<String, dynamic>;
        final agentName = args['agent'] as String? ?? '';
        subAgentTask = args['task'] as String?;
        if (agentName.isNotEmpty) {
          displayName = 'Agent: ${agentName[0].toUpperCase()}${agentName.substring(1)}';
        }
      } catch (_) {
        displayName = 'Sub-agent';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row (tap to expand or open sub-agent dialog)
          InkWell(
            onTap: widget.isSubAgent && widget.onSubAgentTap != null
                ? () {
                    // Open the sub-agent activity dialog (works even while running)
                    widget.onSubAgentTap!(widget.entry.id);
                  }
                : hasResult
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: widget.isSubAgent
                    ? cs.primaryContainer.withValues(alpha: 0.25)
                    : widget.contentColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isSubAgent
                      ? cs.primary.withValues(alpha: 0.3)
                      : cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 16, color: widget.iconColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: widget.contentColor,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.isSubAgent && subAgentTask != null && subAgentTask.isNotEmpty)
                          Text(
                            subAgentTask,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: widget.contentColor.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (hasResult || (widget.isSubAgent && widget.onSubAgentTap != null)) ...[
                    const SizedBox(width: 4),
                    Icon(
                      widget.isSubAgent && widget.onSubAgentTap != null
                          ? Icons.open_in_new_rounded
                          : _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                      size: 16,
                      color: widget.contentColor.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expanded details (arguments + result)
          if (_expanded) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.entry.arguments.isNotEmpty &&
                      widget.entry.arguments != '{}') ...[
                    _CopyableSection(
                      label: 'Arguments',
                      content: widget.entry.arguments,
                      contentColor: widget.contentColor,
                    ),
                    const SizedBox(height: 6),
                  ],
                  _CopyableSection(
                    label: 'Result',
                    content: widget.entry.result,
                    contentColor: widget.contentColor,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labeled section with monospace content and a copy button.
class _CopyableSection extends StatelessWidget {
  final String label;
  final String content;
  final Color contentColor;

  const _CopyableSection({
    required this.label,
    required this.content,
    required this.contentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label:',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: contentColor.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              height: 20,
              width: 20,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 13,
                icon: Icon(
                  Icons.copy_rounded,
                  color: contentColor.withValues(alpha: 0.45),
                ),
                tooltip: 'Copy $label',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$label copied'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SelectableText(
          content,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: contentColor.withValues(alpha: 0.8),
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ── Streaming Indicator ─────────────────────────────────────────────────────

class _StreamingIndicator extends StatefulWidget {
  final Color tint;

  const _StreamingIndicator({required this.tint});

  @override
  State<_StreamingIndicator> createState() => _StreamingIndicatorState();
}

class _StreamingIndicatorState extends State<_StreamingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 2,
          height: 14,
          decoration: BoxDecoration(
            color: widget.tint.withValues(alpha: _animation.value),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      },
    );
  }
}

// ── Attachment Preview Bar ──────────────────────────────────────────────────

class _AttachmentPreviewBar extends StatelessWidget {
  final List<ChatAttachment> attachments;
  final ValueChanged<int> onRemove;

  const _AttachmentPreviewBar({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final a = attachments[index];
            return DecoratedBox(
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: cs.secondary.withValues(alpha: 0.15),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insert_drive_file_rounded,
                      size: 15,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        a.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 14,
                        icon: Icon(
                          Icons.close_rounded,
                          color: cs.onSecondaryContainer
                              .withValues(alpha: 0.7),
                        ),
                        onPressed: () => onRemove(index),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Chat Input Bar ──────────────────────────────────────────────────────────

class _ChatInputBar extends StatelessWidget {
  final TextEditingController textController;
  final FocusNode focusNode;
  final ValueChanged<String> onTextChange;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool isGenerating;
  final VoidCallback onExportChat;
  final VoidCallback onCancel;
  final bool hasMessages;
  final ChatController controller;

  const _ChatInputBar({
    required this.textController,
    required this.focusNode,
    required this.onTextChange,
    required this.onSend,
    required this.onAttach,
    required this.isGenerating,
    required this.onExportChat,
    required this.onCancel,
    required this.hasMessages,
    required this.controller,
  });

  void _showToolsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (ctx, __) => _ToolsBottomSheet(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasText = textController.text.trim().isNotEmpty;
    final toolCount = controller.allTools.length;
    final activeCount = controller.activeTools.length;
    final isLoadingTools = controller.isLoadingMcpTools;
    final hasToolsError =
        controller.mcpError != null && controller.allTools.isEmpty;
    final showToolsButton =
        isLoadingTools || toolCount > 0 || controller.mcpError != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.6 : 0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: isDark ? 0.5 : 0.18),
                blurRadius: 24,
                offset: const Offset(0, 6),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: cs.shadow.withValues(alpha: isDark ? 0.25 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
                spreadRadius: -1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: ColoredBox(
                color: isDark
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.92)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.92),
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Text input area ──
                TextField(
                  controller: textController,
                  focusNode: focusNode,
                  autofocus: false,
                  onChanged: onTextChange,
                  onSubmitted: (_) {
                    if (hasText && !isGenerating) onSend();
                  },
                  minLines: 1,
                  maxLines: 8,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: isGenerating
                        ? 'Generating\u2026 tap stop to cancel'
                        : 'Message Synapse\u2026',
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w400,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding:
                        const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  ),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurface,
                        height: 1.45,
                        fontSize: 15,
                      ),
                ),

                // ── Subtle toolbar divider ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.45),
                  ),
                ),

                // ── Action toolbar ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
                  child: Row(
                    children: [
                      // ── Left group ──
                      Expanded(
                        child: Row(
                          children: [
                            _InputToolbarButton(
                              icon: Icons.attach_file_rounded,
                              tooltip: 'Attach file',
                              onPressed: onAttach,
                            ),
                            if (hasMessages)
                              _InputToolbarButton(
                                icon: Icons.download_rounded,
                                tooltip: 'Export chat as JSON',
                                onPressed: onExportChat,
                              ),
                          ],
                        ),
                      ),

                      // ── Center – Tools split button ──
                      if (showToolsButton)
                        _ToolsSplitButton(
                          toolCount: toolCount,
                          activeCount: activeCount,
                          isLoading: isLoadingTools,
                          hasError: hasToolsError,
                          onTap: () => _showToolsSheet(context),
                          onRefresh: controller.refreshMcpTools,
                        ),

                      // ── Right group ──
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Send / Stop button
                            SizedBox(
                              width: 38,
                              height: 38,
                              child: isGenerating
                                  ? Material(
                                      color: cs.errorContainer,
                                      shape: const CircleBorder(),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: onCancel,
                                        customBorder: const CircleBorder(),
                                        child: Center(
                                          child: Icon(
                                            Icons.stop_rounded,
                                            size: 22,
                                            color: cs.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Material(
                                      color: hasText
                                          ? cs.primary
                                          : cs.onSurface.withValues(
                                              alpha: 0.08),
                                      shape: const CircleBorder(),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: hasText ? onSend : null,
                                        customBorder: const CircleBorder(),
                                        child: Center(
                                          child: Icon(
                                            Icons.arrow_upward_rounded,
                                            size: 22,
                                            color: hasText
                                                ? cs.onPrimary
                                                : cs.onSurface.withValues(
                                                    alpha: 0.25),
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}

// ── Input Toolbar Button ────────────────────────────────────────────────────

class _InputToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _InputToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

// ── Tools Split Button ──────────────────────────────────────────────────────

class _ToolsSplitButton extends StatelessWidget {
  final int toolCount;
  final int activeCount;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const _ToolsSplitButton({
    required this.toolCount,
    required this.activeCount,
    required this.isLoading,
    required this.hasError,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Main area – opens bottom sheet ──
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else if (hasError)
                    Icon(Icons.error_outline, size: 14, color: cs.error)
                  else
                    Icon(
                      Icons.extension_rounded,
                      size: 14,
                      color: cs.primary,
                    ),
                  const SizedBox(width: 5),
                  if (isLoading)
                    Text(
                      'Loading Tools\u2026',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else if (hasError)
                    Text(
                      'Error in Tools',
                      style: TextStyle(fontSize: 11, color: cs.error),
                    )
                  else
                    Text(
                      'Tools $activeCount/$toolCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // ── Divider ──
          Container(
            width: 1,
            height: 20,
            color: cs.outline.withValues(alpha: 0.25),
          ),

          // ── Refresh split ──
          InkWell(
            onTap: isLoading ? null : onRefresh,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(17),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: isLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  : Icon(
                      Icons.refresh,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tools Bottom Sheet ──────────────────────────────────────────────────────

class _ToolsBottomSheet extends StatelessWidget {
  final ChatController controller;

  const _ToolsBottomSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allTools = controller.allTools;
    final activeTools = controller.activeTools;
    final error = controller.mcpError;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              children: [
                Icon(Icons.extension_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Tools',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${activeTools.length}/${allTools.length} active',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: controller.enableAllTools,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    minimumSize: const Size(48, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('All', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: controller.disableAllTools,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    minimumSize: const Size(48, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('None', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),

          // ── Error banner ──
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: cs.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: TextStyle(fontSize: 12, color: cs.error),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // ── Tool list ──
          Flexible(
            child: allTools.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No tools discovered yet',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16, top: 4),
                    itemCount: allTools.length,
                    itemBuilder: (context, index) {
                      final tool = allTools[index];
                      final isEnabled = activeTools.any(
                        (t) => t.tool.name == tool.tool.name,
                      );
                      return ListTile(
                        dense: true,
                        visualDensity:
                            const VisualDensity(vertical: -2),
                        leading: SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: isEnabled,
                            onChanged: (_) =>
                                controller.toggleTool(tool.tool.name),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        title: Text(
                          tool.tool.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: tool.tool.description != null
                            ? Text(
                                tool.tool.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              )
                            : null,
                        trailing: Text(
                          tool.isSystemTool ? 'System' : tool.serverName,
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () =>
                            controller.toggleTool(tool.tool.name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mermaid code block with reload button in the header
// ---------------------------------------------------------------------------

class _MermaidCodeBlock extends StatefulWidget {
  final String code;
  final bool isDark;

  const _MermaidCodeBlock({required this.code, required this.isDark});

  @override
  State<_MermaidCodeBlock> createState() => _MermaidCodeBlockState();
}

class _MermaidCodeBlockState extends State<_MermaidCodeBlock> {
  int _reloadCount = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF282C34) : const Color(0xFFF5F5F5);
    final headerColor = isDark
        ? const Color(0xFF21252B)
        : const Color(0xFFE8E8E8);
    final labelColor = isDark
        ? const Color(0xFF7F848E)
        : const Color(0xFF999999);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with label, reload, and copy buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schema_outlined, size: 14, color: labelColor),
                const SizedBox(width: 4),
                Text(
                  'Mermaid Diagram',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                // Reload button
                InkWell(
                  onTap: () => setState(() => _reloadCount++),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 12,
                          color: labelColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Reload',
                          style: TextStyle(fontSize: 11, color: labelColor),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Copy button
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    showRootSnackBar(
                      const SnackBar(
                        content: Text('Code copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_outlined,
                          size: 12,
                          color: labelColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(fontSize: 11, color: labelColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Mermaid diagram content
          Padding(
            padding: const EdgeInsets.all(12),
            // On native, the WebView handles its own scrolling and pinch zoom.
            // On web, SingleChildScrollView allows wide diagrams to scroll.
            child: kIsWeb
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: MermaidView(
                      key: ValueKey('mermaid-${widget.code.hashCode}-$isDark-$_reloadCount'),
                      code: widget.code,
                      isDark: isDark,
                    ),
                  )
                : MermaidView(
                    key: ValueKey('mermaid-${widget.code.hashCode}-$isDark-$_reloadCount'),
                    code: widget.code,
                    isDark: isDark,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-Agent Live Activity Dialog ─────────────────────────────────────

/// Dialog that shows real-time sub-agent activity, mirroring the main
/// chat experience: streaming text, tool call tiles, and status indicators.
class _SubAgentDialog extends StatefulWidget {
  /// Live notifier for a running sub-agent. null when showing a static replay.
  final SubAgentActivityNotifier? activityNotifier;

  /// Static activity for replaying a completed sub-agent run.
  final SubAgentActivity? staticActivity;

  final VoidCallback onDismiss;

  const _SubAgentDialog({
    this.activityNotifier,
    this.staticActivity,
    required this.onDismiss,
  });

  @override
  State<_SubAgentDialog> createState() => _SubAgentDialogState();
}

class _SubAgentDialogState extends State<_SubAgentDialog> {
  final ScrollController _scrollController = ScrollController();

  /// Whether this is a live dialog (with a notifier) or a static replay.
  bool get _isLive => widget.activityNotifier != null;

  SubAgentActivity? get _activity =>
      _isLive ? widget.activityNotifier!.value : widget.staticActivity;

  @override
  void initState() {
    super.initState();
    if (_isLive) {
      widget.activityNotifier!.addListener(_onActivityChanged);
    }
  }

  @override
  void dispose() {
    if (_isLive) {
      widget.activityNotifier!.removeListener(_onActivityChanged);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onActivityChanged() {
    final activity = widget.activityNotifier!.value;
    if (activity == null) {
      // Sub-agent cleared -- dismiss the dialog
      widget.onDismiss();
      return;
    }
    setState(() {});
    // Auto-scroll to bottom as content streams in
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activity = _activity;
    if (activity == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentColor = isDark ? Colors.white : Colors.black87;
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: screenSize.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                border: Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    activity.isRunning
                        ? Icons.smart_toy_outlined
                        : Icons.smart_toy_rounded,
                    size: 20,
                    color: activity.isComplete && activity.error != null
                        ? cs.error
                        : cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Agent: ${activity.agentName[0].toUpperCase()}${activity.agentName.substring(1)}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activity.taskDescription,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: contentColor.withValues(alpha: 0.6),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (activity.isRunning)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  else
                    Icon(
                      activity.error != null
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: activity.error != null ? cs.error : Colors.green,
                    ),
                ],
              ),
            ),

            // ── Scrollable content ──────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tool calls
                    if (activity.toolCalls.isNotEmpty) ...[
                      ...activity.toolCalls.map((tc) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _SubAgentToolCallTile(
                          toolCall: tc,
                          contentColor: contentColor,
                        ),
                      )),
                      if (activity.streamingContent.isNotEmpty)
                        const SizedBox(height: 10),
                    ],

                    // Streaming text content
                    if (activity.streamingContent.isNotEmpty)
                      SelectableText(
                        activity.streamingContent,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: contentColor,
                        ),
                      )
                    else if (activity.isRunning && activity.toolCalls.isEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StreamingIndicator(tint: contentColor),
                          const SizedBox(width: 8),
                          Text(
                            'Thinking...',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: contentColor.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),

                    // Error
                    if (activity.error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 16, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                activity.error!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────
            if (activity.isComplete || !_isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onDismiss,
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tool call tile within the sub-agent dialog.
class _SubAgentToolCallTile extends StatefulWidget {
  final SubAgentToolCall toolCall;
  final Color contentColor;

  const _SubAgentToolCallTile({
    required this.toolCall,
    required this.contentColor,
  });

  @override
  State<_SubAgentToolCallTile> createState() => _SubAgentToolCallTileState();
}

class _SubAgentToolCallTileState extends State<_SubAgentToolCallTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasResult = widget.toolCall.result != null &&
        widget.toolCall.result!.isNotEmpty;

    final IconData icon;
    final Color iconColor;
    switch (widget.toolCall.status) {
      case SubAgentToolStatus.running:
        icon = Icons.hourglass_top_rounded;
        iconColor = cs.tertiary;
      case SubAgentToolStatus.completed:
        icon = Icons.check_circle_outline_rounded;
        iconColor = Colors.green;
      case SubAgentToolStatus.error:
        icon = Icons.error_outline_rounded;
        iconColor = cs.error;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasResult
              ? () => setState(() => _expanded = !_expanded)
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: widget.contentColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.toolCall.toolName,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: widget.contentColor,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasResult) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: widget.contentColor.withValues(alpha: 0.5),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded && hasResult) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.toolCall.arguments.isNotEmpty &&
                    widget.toolCall.arguments != '{}') ...[
                  _CopyableSection(
                    label: 'Arguments',
                    content: widget.toolCall.arguments,
                    contentColor: widget.contentColor,
                  ),
                  const SizedBox(height: 6),
                ],
                _CopyableSection(
                  label: 'Result',
                  content: widget.toolCall.result!,
                  contentColor: widget.contentColor,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
