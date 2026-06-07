import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_models.dart';
import '../services/chat_controller.dart';
import '../utils/snackbar_service.dart';
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
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  ChatController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
    _textController.text = _ctrl.inputText;
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
    if (_ctrl.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _onSend() {
    final text = _textController.text;
    if (text.trim().isEmpty && _ctrl.pendingAttachments.isEmpty) return;
    _ctrl.sendMessage(text);
    _textController.clear();
  }

  Future<void> _onAttach() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    for (final file in result.files) {
      _ctrl.addAttachment(ChatAttachment(
        fileName: file.name,
        fileSizeBytes: file.size,
        mimeType: _guessMimeType(file.name),
        bytes: file.bytes,
      ));
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
    // Dispose is handled when dialog closes; controller is short-lived.
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
    return Column(
      children: [
        // Messages list
        Expanded(
          child: _ctrl.messages.isEmpty
              ? _EmptyState(modelName: _ctrl.selectedModel?.displayName)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _ctrl.messages.length,
                  itemBuilder: (context, index) {
                    return _MessageBubble(
                      message: _ctrl.messages[index],
                      onCopy: _copyMessage,
                      onEdit: _showEditDialog,
                      onFork: _forkChat,
                      isGenerating: _ctrl.isGenerating,
                    );
                  },
                ),
        ),

        // Pending attachments preview
        if (_ctrl.pendingAttachments.isNotEmpty)
          _AttachmentPreviewBar(
            attachments: _ctrl.pendingAttachments,
            onRemove: _ctrl.removeAttachment,
          ),

        // MCP tools status with selection
        _McpToolsStatus(controller: _ctrl),

        // Input bar
        _ChatInputBar(
          textController: _textController,
          focusNode: _focusNode,
          onTextChange: _ctrl.onInputTextChange,
          onSend: _onSend,
          onAttach: _onAttach,
          isGenerating: _ctrl.isGenerating,
          onClearChat: _ctrl.clearConversation,
          onExportChat: _exportChat,
          hasMessages: _ctrl.messages.isNotEmpty,
        ),
      ],
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
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<dynamic>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value is LlmModel) {
          widget.onModelSelected(value);
        } else if (value == '__refresh__') {
          widget.onRefresh();
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<dynamic>>[];

        items.add(PopupMenuItem<dynamic>(
          value: '__refresh__',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                widget.isLoading ? 'Fetching models...' : 'Refresh models',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ));
        items.add(const PopupMenuDivider());

        if (widget.isLoading && widget.models.isEmpty) {
          items.add(PopupMenuItem<dynamic>(
            enabled: false,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ));
        } else if (widget.error != null && widget.models.isEmpty) {
          items.add(PopupMenuItem<dynamic>(
            enabled: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.error!,
                      style: TextStyle(fontSize: 12, color: cs.error),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ));
        } else {
          final grouped = <String, List<LlmModel>>{};
          for (final m in widget.models) {
            (grouped[m.provider] ??= []).add(m);
          }

          var isFirst = true;
          for (final entry in grouped.entries) {
            if (!isFirst) items.add(const PopupMenuDivider());
            isFirst = false;

            items.add(PopupMenuItem<dynamic>(
              enabled: false,
              height: 32,
              child: Text(
                entry.key,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
            ));

            for (final model in entry.value) {
              items.add(PopupMenuItem<dynamic>(
                value: model,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        model.displayName,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (model.id == widget.selectedModel?.id)
                      Icon(Icons.check, size: 18, color: cs.primary),
                  ],
                ),
              ));
            }
          }
        }

        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
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
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                widget.selectedModel?.displayName ?? 'Select model',
                style: Theme.of(context).textTheme.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 14, color: cs.onSurfaceVariant),
          ],
        ),
      ),
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: cs.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              modelName != null
                  ? 'Using $modelName'
                  : 'Configure your API key in Settings',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Type a message below or attach a file to get started',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
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
  final bool isGenerating;

  const _MessageBubble({
    required this.message,
    required this.onCopy,
    required this.onEdit,
    required this.onFork,
    required this.isGenerating,
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

    final bubbleColor =
        isUser ? cs.primaryContainer : cs.secondaryContainer;
    final contentColor =
        isUser ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    final alignment =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

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
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                    ),
                  ] else
                    Text(
                      'You',
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.7),
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
                    : MediaQuery.of(context).size.width * 0.85,
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
                      (a) =>
                          _AttachmentChip(attachment: a, tint: contentColor),
                    ),
                    if (widget.message.content.isNotEmpty)
                      const SizedBox(height: 8),
                  ],

                  // Text content
                  if (widget.message.content.isNotEmpty) ...[
                    if (isUser || widget.message.isStreaming)
                      Text(
                        widget.message.content,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: contentColor),
                      )
                    else
                      _AssistantMarkdown(
                        content: widget.message.content,
                        contentColor: contentColor,
                      ),
                  ] else if (!widget.message.isStreaming)
                    Text(
                      'Empty response',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return MarkdownBody(
      data: content,
      selectable: false,
      extensionSet: md.ExtensionSet.gitHubWeb,
      styleSheet: MarkdownStyleSheet(
        p: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: contentColor),
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
        listBullet: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: contentColor),
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
        blockquotePadding:
            const EdgeInsets.only(left: 12, top: 4, bottom: 4),
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
        tableBody: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: contentColor),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        tableHeadAlign: TextAlign.left,
      ),
      builders: {
        'code': _CodeBlockBuilder(isDark: isDark),
      },
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        }
      },
    );
  }
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
    final headerColor = isDark ? const Color(0xFF21252B) : const Color(0xFFE8E8E8);
    final textColor = isDark ? const Color(0xFFABB2BF) : const Color(0xFF383A42);
    final labelColor = isDark ? const Color(0xFF7F848E) : const Color(0xFF999999);

    Widget codeContent;
    if (isMermaid) {
      // Render Mermaid as an actual graph via mermaid.ink
      // Inject theme directive into the diagram source for dark mode
      final mermaidSource = isDark
          ? '%%{init: {"theme":"dark"}}%%\n$text'
          : text;
      final encoded = base64.encode(utf8.encode(mermaidSource));
      final imageUrl = 'https://mermaid.ink/img/$encoded';
      codeContent = Image.network(
        imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          // Fallback: show the raw Mermaid code if rendering fails
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: labelColor),
                    const SizedBox(width: 4),
                    Text(
                      'Diagram render failed — showing source',
                      style: TextStyle(fontSize: 11, color: labelColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: textColor,
                ),
              ),
            ],
          );
        },
      );
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
                if (isMermaid)
                  Icon(Icons.schema_outlined, size: 14, color: labelColor),
                if (isMermaid) const SizedBox(width: 4),
                Text(
                  isMermaid ? 'Mermaid Diagram' : language,
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
                          Icon(Icons.copy_outlined, size: 12, color: labelColor),
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
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tint,
                    ),
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
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
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
    return Material(
      elevation: 2,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final a = attachments[index];
            return InputChip(
              label: Text(
                a.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              avatar: const Icon(Icons.insert_drive_file_outlined, size: 16),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => onRemove(index),
              onPressed: () {},
            );
          },
        ),
      ),
    );
  }
}

// ── MCP Tools Status with Selection ─────────────────────────────────────────

class _McpToolsStatus extends StatefulWidget {
  final ChatController controller;

  const _McpToolsStatus({required this.controller});

  @override
  State<_McpToolsStatus> createState() => _McpToolsStatusState();
}

class _McpToolsStatusState extends State<_McpToolsStatus> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ctrl = widget.controller;
    final toolCount = ctrl.mcpTools.length;
    final activeCount = ctrl.activeTools.length;
    final error = ctrl.mcpError;
    final isLoading = ctrl.isLoadingMcpTools;

    if (!isLoading && toolCount == 0 && error == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Status bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              if (isLoading) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 6),
                Text(
                  'Discovering MCP tools...',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ] else if (error != null && toolCount == 0) ...[
                Icon(Icons.error_outline, size: 14, color: cs.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'MCP error: $error',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.error,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    icon: Icon(Icons.refresh, color: cs.error),
                    onPressed: ctrl.refreshMcpTools,
                  ),
                ),
              ] else if (toolCount > 0) ...[
                Icon(Icons.extension_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      '$activeCount of $toolCount tool${toolCount > 1 ? 's' : ''} enabled',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                          ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: cs.primary,
                    ),
                    onPressed: () =>
                        setState(() => _expanded = !_expanded),
                  ),
                ),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    icon: Icon(Icons.refresh, color: cs.primary),
                    onPressed: ctrl.refreshMcpTools,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Expanded tool selection
        if (_expanded && toolCount > 0)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Select all / none buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        'Tool Selection',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: ctrl.enableAllTools,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('All',
                            style: TextStyle(fontSize: 11, color: cs.primary)),
                      ),
                      TextButton(
                        onPressed: ctrl.disableAllTools,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('None',
                            style: TextStyle(fontSize: 11, color: cs.primary)),
                      ),
                    ],
                  ),
                ),
                // Tool list
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: ctrl.mcpTools.length,
                    itemBuilder: (context, index) {
                      final tool = ctrl.mcpTools[index];
                      final isEnabled = ctrl.enabledToolNames
                          .contains(tool.tool.name);
                      return InkWell(
                        onTap: () => ctrl.toggleTool(tool.tool.name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: isEnabled,
                                  onChanged: (_) =>
                                      ctrl.toggleTool(tool.tool.name),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tool.tool.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    if (tool.tool.description != null)
                                      Text(
                                        tool.tool.description!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                tool.serverName,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
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
  final VoidCallback onClearChat;
  final VoidCallback onExportChat;
  final bool hasMessages;

  const _ChatInputBar({
    required this.textController,
    required this.focusNode,
    required this.onTextChange,
    required this.onSend,
    required this.onAttach,
    required this.isGenerating,
    required this.onClearChat,
    required this.onExportChat,
    required this.hasMessages,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Text field with rounded border
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outline.withValues(alpha: 0.3),
              ),
            ),
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              onChanged: onTextChange,
              onSubmitted: (_) {
                if (textController.text.trim().isNotEmpty && !isGenerating) {
                  onSend();
                }
              },
              enabled: !isGenerating,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: isGenerating
                    ? 'Waiting for response...'
                    : 'Type a message...',
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                  ),
            ),
          ),

          const SizedBox(height: 8),

          // Bottom toolbar
          Row(
            children: [
              // Attach button
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: Icon(
                    Icons.attach_file,
                    color: isGenerating
                        ? cs.onSurfaceVariant.withValues(alpha: 0.4)
                        : cs.onSurfaceVariant,
                  ),
                  onPressed: isGenerating ? null : onAttach,
                  tooltip: 'Attach file',
                ),
              ),

              // Clear chat button
              if (hasMessages)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(
                      Icons.delete_sweep_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: onClearChat,
                    tooltip: 'Clear chat',
                  ),
                ),

              // Export chat button
              if (hasMessages)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(
                      Icons.download_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: onExportChat,
                    tooltip: 'Export chat as JSON',
                  ),
                ),

              const Spacer(),

              // Send button
              SizedBox(
                width: 40,
                height: 40,
                child: FilledButton(
                  onPressed:
                      textController.text.trim().isNotEmpty && !isGenerating
                          ? onSend
                          : null,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: cs.primary,
                    disabledBackgroundColor:
                        cs.onSurface.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.send,
                    size: 18,
                    color:
                        textController.text.trim().isNotEmpty && !isGenerating
                            ? cs.onPrimary
                            : cs.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
