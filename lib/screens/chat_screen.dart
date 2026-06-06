import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_models.dart';
import '../services/chat_controller.dart';
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
    // Auto-scroll when new messages arrive or content updates
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
                    return _MessageBubble(message: _ctrl.messages[index]);
                  },
                ),
        ),

        // Pending attachments preview
        if (_ctrl.pendingAttachments.isNotEmpty)
          _AttachmentPreviewBar(
            attachments: _ctrl.pendingAttachments,
            onRemove: _ctrl.removeAttachment,
          ),

        // MCP tools status
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

        // Refresh button at top
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
          // Show error when no models loaded
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
          // Group models by provider
          final grouped = <String, List<LlmModel>>{};
          for (final m in widget.models) {
            (grouped[m.provider] ??= []).add(m);
          }

          var isFirst = true;
          for (final entry in grouped.entries) {
            if (!isFirst) items.add(const PopupMenuDivider());
            isFirst = false;

            // Provider header
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

            // Models under this provider
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

// ── Message Bubble ──────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final cs = Theme.of(context).colorScheme;

    final bubbleColor = isUser ? cs.primaryContainer : cs.surfaceContainerHighest;
    final contentColor = isUser ? cs.onPrimaryContainer : cs.onSurface;
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          // Role label
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
                    message.model?.displayName ?? 'Assistant',
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
              maxWidth: isUser ? 340 : MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Attachments
                if (message.attachments.isNotEmpty) ...[
                  ...message.attachments.map(
                    (a) => _AttachmentChip(attachment: a, tint: contentColor),
                  ),
                  if (message.content.isNotEmpty) const SizedBox(height: 8),
                ],

                // Text content
                if (message.content.isNotEmpty) ...[
                  if (isUser || message.isStreaming)
                    // Plain text for user messages and during streaming
                    SelectableText(
                      message.content,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: contentColor,
                          ),
                    )
                  else
                    // Markdown for completed assistant messages
                    _AssistantMarkdown(
                      content: message.content,
                      contentColor: contentColor,
                    ),
                ] else if (!message.isStreaming)
                  Text(
                    'Empty response',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: contentColor.withValues(alpha: 0.5),
                        ),
                  ),

                // Streaming indicator
                if (message.isStreaming) ...[
                  const SizedBox(height: 4),
                  _StreamingIndicator(tint: contentColor),
                ],
              ],
            ),
          ),
        ],
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
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: contentColor),
        h1: Theme.of(context).textTheme.titleLarge?.copyWith(color: contentColor),
        h2: Theme.of(context).textTheme.titleMedium?.copyWith(color: contentColor),
        h3: Theme.of(context).textTheme.titleSmall?.copyWith(color: contentColor),
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
        listBullet: Theme.of(context).textTheme.bodyMedium?.copyWith(color: contentColor),
        blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: contentColor.withValues(alpha: 0.7),
            ),
        code: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: contentColor,
              fontFamily: 'monospace',
              backgroundColor: contentColor.withValues(alpha: 0.08),
            ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF282C34) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: contentColor.withValues(alpha: 0.3),
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
        tableBody: Theme.of(context).textTheme.bodyMedium?.copyWith(color: contentColor),
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

/// Custom code block builder with syntax highlighting.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;
  _CodeBlockBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Only handle fenced code blocks (pre > code)
    if (element.tag != 'code') return null;

    final text = element.textContent;
    String? language;

    // Extract language from class attribute
    final classes = element.attributes['class'];
    if (classes != null && classes.startsWith('language-')) {
      language = classes.substring(9);
    }

    if (language == null || language.isEmpty) return null;

    // Use highlight.js for syntax highlighting
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;

    try {
      final result = highlight.parse(text, language: language);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF282C34) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _buildHighlightedText(result.nodes!, theme, isDark),
        ),
      );
    } catch (_) {
      return null; // Fall back to default rendering
    }
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
            Icons.insert_drive_file_outlined,
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

// ── MCP Tools Status ────────────────────────────────────────────────────────

class _McpToolsStatus extends StatelessWidget {
  final ChatController controller;

  const _McpToolsStatus({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final toolCount = controller.mcpTools.length;
    final error = controller.mcpError;
    final isLoading = controller.isLoadingMcpTools;

    if (!isLoading && toolCount == 0 && error == null) {
      return const SizedBox.shrink();
    }

    return Padding(
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
                onPressed: controller.refreshMcpTools,
              ),
            ),
          ] else if (toolCount > 0) ...[
            Icon(Icons.extension_outlined, size: 14, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$toolCount MCP tool${toolCount > 1 ? 's' : ''} available',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                    ),
              ),
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 14,
                icon: Icon(Icons.refresh, color: cs.primary),
                onPressed: controller.refreshMcpTools,
              ),
            ),
          ],
        ],
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
  final VoidCallback onClearChat;
  final bool hasMessages;

  const _ChatInputBar({
    required this.textController,
    required this.focusNode,
    required this.onTextChange,
    required this.onSend,
    required this.onAttach,
    required this.isGenerating,
    required this.onClearChat,
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

          // Bottom toolbar: attach, clear, send
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

              const Spacer(),

              // Send button
              SizedBox(
                width: 40,
                height: 40,
                child: FilledButton(
                  onPressed: textController.text.trim().isNotEmpty && !isGenerating
                      ? onSend
                      : null,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: cs.primary,
                    disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.send,
                    size: 18,
                    color: textController.text.trim().isNotEmpty && !isGenerating
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
