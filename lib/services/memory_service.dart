import 'dart:io';

/// A single memory entry backed by a `.md` file.
class MemoryEntry {
  final String key;
  String content;
  final List<String> tags;
  final DateTime createdAt;
  DateTime updatedAt;

  MemoryEntry({
    required this.key,
    required this.content,
    this.tags = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Serialise to a markdown file with YAML frontmatter.
  String toFileContent() {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('key: $key');
    buf.writeln('tags: [${tags.join(", ")}]');
    buf.writeln('created: ${createdAt.toIso8601String()}');
    buf.writeln('updated: ${updatedAt.toIso8601String()}');
    buf.writeln('---');
    buf.writeln();
    buf.write(content);
    return buf.toString();
  }

  /// Parse a markdown file with YAML frontmatter back into a [MemoryEntry].
  /// Returns null if the file cannot be parsed.
  static MemoryEntry? fromFileContent(String text, {String? fallbackKey}) {
    if (!text.startsWith('---')) return null;
    final endIndex = text.indexOf('---', 3);
    if (endIndex < 0) return null;

    final frontmatter = text.substring(3, endIndex).trim();
    final body = text.substring(endIndex + 3).trim();

    String? key;
    List<String> tags = [];
    DateTime? createdAt;
    DateTime? updatedAt;

    for (final line in frontmatter.split('\n')) {
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final field = line.substring(0, colonIdx).trim();
      final value = line.substring(colonIdx + 1).trim();

      switch (field) {
        case 'key':
          key = value;
          break;
        case 'tags':
          // Parse [tag1, tag2] format
          final inner = value.startsWith('[') && value.endsWith(']')
              ? value.substring(1, value.length - 1)
              : value;
          tags = inner
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();
          break;
        case 'created':
          createdAt = DateTime.tryParse(value);
          break;
        case 'updated':
          updatedAt = DateTime.tryParse(value);
          break;
      }
    }

    key ??= fallbackKey;
    if (key == null || key.isEmpty) return null;

    return MemoryEntry(
      key: key,
      content: body,
      tags: tags,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Persistent key-value memory store backed by markdown files in
/// `/storage/emulated/0/Download/SynapseMemory/`.
///
/// Each memory is stored as `<key>.md` with YAML frontmatter for metadata
/// (tags, timestamps). Files are human-readable and editable outside the app.
class MemoryService {
  static const _basePath = '/storage/emulated/0/Download/SynapseMemory';

  static MemoryService? _instance;
  static MemoryService get instance => _instance ??= MemoryService._();
  MemoryService._();

  /// Ensure the storage directory exists.
  Future<void> init() async {
    final dir = Directory(_basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Sanitise a key into a safe filename (without extension).
  String _keyToFileName(String key) {
    return key
        .replaceAll(RegExp(r'[^\w\-. ]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  /// Get the file for a given key.
  File _fileForKey(String key) {
    return File('$_basePath/${_keyToFileName(key)}.md');
  }

  /// Load all memory entries from disk.
  List<MemoryEntry> _loadAll() {
    final dir = Directory(_basePath);
    if (!dir.existsSync()) return [];

    final entries = <MemoryEntry>[];
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.md')) {
        try {
          final text = entity.readAsStringSync();
          final fileName = entity.uri.pathSegments.last;
          final fallbackKey = fileName.endsWith('.md')
              ? fileName.substring(0, fileName.length - 3)
              : fileName;
          final entry =
              MemoryEntry.fromFileContent(text, fallbackKey: fallbackKey);
          if (entry != null) entries.add(entry);
        } catch (_) {
          // Skip unreadable files.
        }
      }
    }
    return entries;
  }

  /// Save or update a memory. Returns a status message.
  String save({
    required String key,
    required String content,
    List<String> tags = const [],
  }) {
    final file = _fileForKey(key);
    final bool updating = file.existsSync();

    MemoryEntry entry;
    if (updating) {
      // Preserve original createdAt, merge tags.
      final existing = MemoryEntry.fromFileContent(file.readAsStringSync(),
          fallbackKey: key);
      final mergedTags = existing != null && tags.isNotEmpty
          ? {...existing.tags, ...tags}.toList()
          : (tags.isNotEmpty ? tags : (existing?.tags ?? []));
      entry = MemoryEntry(
        key: key,
        content: content,
        tags: mergedTags,
        createdAt: existing?.createdAt,
        updatedAt: DateTime.now(),
      );
    } else {
      entry = MemoryEntry(key: key, content: content, tags: tags);
    }

    file.writeAsStringSync(entry.toFileContent());
    return updating
        ? 'Memory "$key" updated successfully.'
        : 'Memory "$key" saved successfully.';
  }

  /// Recall a memory by exact key. Returns the content or an error.
  String recall(String key) {
    final file = _fileForKey(key);
    if (!file.existsSync()) {
      return 'No memory found with key "$key".';
    }
    final entry =
        MemoryEntry.fromFileContent(file.readAsStringSync(), fallbackKey: key);
    if (entry == null) return 'Error: Could not parse memory file for "$key".';
    return _formatEntry(entry);
  }

  /// Search memories by substring in key, content, or tags.
  String search(String query) {
    final entries = _loadAll();
    final q = query.toLowerCase();
    final matches = entries.where((e) {
      return e.key.toLowerCase().contains(q) ||
          e.content.toLowerCase().contains(q) ||
          e.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    if (matches.isEmpty) {
      return 'No memories found matching "$query".';
    }
    final buf = StringBuffer('Found ${matches.length} matching memories:\n\n');
    for (final entry in matches) {
      buf.writeln(_formatEntry(entry));
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  /// List all memories. Returns a formatted summary.
  String list({String? tag}) {
    final entries = _loadAll();
    if (entries.isEmpty) return 'No memories stored.';

    var filtered = entries;
    if (tag != null && tag.isNotEmpty) {
      final t = tag.toLowerCase();
      filtered = entries
          .where((e) => e.tags.any((et) => et.toLowerCase() == t))
          .toList();
      if (filtered.isEmpty) return 'No memories found with tag "$tag".';
    }

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final buf = StringBuffer('${filtered.length} memories stored:\n\n');
    for (final entry in filtered) {
      final tagsStr =
          entry.tags.isNotEmpty ? ' [${entry.tags.join(", ")}]' : '';
      final preview = entry.content.length > 100
          ? '${entry.content.substring(0, 100)}...'
          : entry.content;
      buf.writeln('- **${entry.key}**$tagsStr: $preview');
    }
    return buf.toString().trimRight();
  }

  /// Delete a memory by key. Returns a status message.
  String delete(String key) {
    final file = _fileForKey(key);
    if (!file.existsSync()) {
      return 'No memory found with key "$key".';
    }
    file.deleteSync();
    return 'Memory "$key" deleted successfully.';
  }

  /// Format a single entry for output.
  String _formatEntry(MemoryEntry entry) {
    final tagsStr =
        entry.tags.isNotEmpty ? '\nTags: ${entry.tags.join(", ")}' : '';
    return 'Key: ${entry.key}$tagsStr\n'
        'Created: ${entry.createdAt.toIso8601String()}\n'
        'Updated: ${entry.updatedAt.toIso8601String()}\n'
        'Content:\n${entry.content}';
  }
}
