import 'dart:io';
import 'dart:math';

/// Valid memory categories for structured browsing.
///
/// Categories provide a fixed taxonomy so the LLM can organise and browse
/// memories without inventing inconsistent ad-hoc keys.
enum MemoryCategory {
  personal, // name, preferences, habits, personal info
  project, // codebase structure, tech stack, conventions
  instruction, // how the user wants things done
  fact, // reference data, API keys, URLs, definitions
  context, // ongoing tasks, decisions, session context
  general; // default catch-all

  static MemoryCategory fromString(String s) {
    return MemoryCategory.values.firstWhere(
      (c) => c.name == s.toLowerCase(),
      orElse: () => MemoryCategory.general,
    );
  }
}

/// A single memory entry backed by a `.md` file.
class MemoryEntry {
  final String key;
  String content;
  final MemoryCategory category;
  final List<String> tags;
  final DateTime createdAt;
  DateTime updatedAt;

  MemoryEntry({
    required this.key,
    required this.content,
    this.category = MemoryCategory.general,
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
    buf.writeln('category: ${category.name}');
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
    MemoryCategory category = MemoryCategory.general;
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
        case 'category':
          category = MemoryCategory.fromString(value);
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
      category: category,
      tags: tags,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Persistent memory store with **BM25-ranked search**, category-based
/// browsing, and manifest generation for automatic system-prompt injection.
///
/// Architecture:
/// - Each memory is a `.md` file with YAML frontmatter (backward-compatible).
/// - On [init], all files are loaded into an in-memory cache and an inverted
///   index is built for O(1)-per-token search.
/// - [search] tokenizes the query, scores every candidate document using
///   BM25 (Okapi), and returns results sorted by relevance.
/// - [buildManifest] produces a compact summary of all stored memories that
///   is injected into the system prompt so the LLM passively knows what
///   memories exist without having to call search/recall.
class MemoryService {
  static const _basePath = '/storage/emulated/0/Download/SynapseMemory';

  // BM25 tuning constants (standard Okapi defaults).
  static const double _k1 = 1.2;
  static const double _b = 0.75;

  static MemoryService? _instance;
  static MemoryService get instance => _instance ??= MemoryService._();
  MemoryService._();

  // ---- In-memory cache & inverted index ----

  /// Cached entries keyed by memory key.
  final Map<String, MemoryEntry> _cache = {};

  /// Inverted index: token -> { docKey: termFrequency }.
  final Map<String, Map<String, int>> _index = {};

  /// Document lengths (in tokens) for BM25 normalization.
  final Map<String, int> _docLengths = {};

  /// Average document length across all memories.
  double _avgDocLength = 0;

  /// Whether the index has been built at least once.
  bool _indexBuilt = false;

  /// Minimal stop-word list for English. These are excluded from both
  /// indexing and query tokenization to improve BM25 precision.
  static const _stopWords = {
    'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'been',
    'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will',
    'would', 'could', 'should', 'may', 'might', 'shall', 'can',
    'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from',
    'as', 'into', 'through', 'during', 'before', 'after', 'above',
    'below', 'between', 'and', 'but', 'or', 'nor', 'not', 'so',
    'if', 'then', 'than', 'too', 'very', 'just', 'about',
    'it', 'its', 'this', 'that', 'these', 'those', 'he', 'she',
    'they', 'we', 'you', 'me', 'him', 'her', 'us', 'them',
    'my', 'your', 'his', 'our', 'their',
  };

  // ==================================================================
  // Initialization
  // ==================================================================

  /// Ensure the storage directory exists and build the initial index.
  Future<void> init() async {
    final dir = Directory(_basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _rebuildFullIndex();
  }

  // ==================================================================
  // Tokenization
  // ==================================================================

  /// Tokenize [text] into searchable terms: lowercase, split on
  /// non-alphanumeric boundaries, drop stop words and single chars.
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length > 1 && !_stopWords.contains(t))
        .toList();
  }

  /// Build the full searchable text blob for a [MemoryEntry].
  /// Includes key (weighted by repetition), category, tags, and content.
  String _searchableText(MemoryEntry entry) {
    // Repeat key twice to give it more weight in BM25 scoring.
    return '${entry.key} ${entry.key} '
        '${entry.category.name} '
        '${entry.tags.join(' ')} '
        '${entry.content}';
  }

  // ==================================================================
  // Index management
  // ==================================================================

  /// Rebuild the entire inverted index from disk.
  void _rebuildFullIndex() {
    _cache.clear();
    _index.clear();
    _docLengths.clear();

    final entries = _loadAllFromDisk();
    int totalLength = 0;

    for (final entry in entries) {
      _cache[entry.key] = entry;
      final tokens = _tokenize(_searchableText(entry));
      _docLengths[entry.key] = tokens.length;
      totalLength += tokens.length;

      // Count term frequencies per document.
      final tf = <String, int>{};
      for (final t in tokens) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      for (final MapEntry(key: token, value: freq) in tf.entries) {
        _index.putIfAbsent(token, () => {});
        _index[token]![entry.key] = freq;
      }
    }

    _avgDocLength = entries.isNotEmpty ? totalLength / entries.length : 0;
    _indexBuilt = true;
  }

  /// Incrementally add or update a single entry in the index.
  void _updateIndex(MemoryEntry entry) {
    // Remove stale data for this key first.
    _removeFromIndex(entry.key);

    _cache[entry.key] = entry;
    final tokens = _tokenize(_searchableText(entry));
    _docLengths[entry.key] = tokens.length;

    final tf = <String, int>{};
    for (final t in tokens) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    for (final MapEntry(key: token, value: freq) in tf.entries) {
      _index.putIfAbsent(token, () => {});
      _index[token]![entry.key] = freq;
    }

    _recomputeAvgDocLength();
  }

  /// Remove a single entry from the index.
  void _removeFromIndex(String key) {
    _cache.remove(key);
    _docLengths.remove(key);

    // Remove key from all posting lists; drop empty lists.
    _index.removeWhere((token, docs) {
      docs.remove(key);
      return docs.isEmpty;
    });

    _recomputeAvgDocLength();
  }

  /// Recompute [_avgDocLength] from current [_docLengths].
  void _recomputeAvgDocLength() {
    if (_cache.isNotEmpty) {
      _avgDocLength =
          _docLengths.values.fold<int>(0, (a, b) => a + b) / _cache.length;
    } else {
      _avgDocLength = 0;
    }
  }

  // ==================================================================
  // BM25 scoring
  // ==================================================================

  /// Compute the BM25 (Okapi) relevance score for [docKey] given
  /// [queryTokens].
  ///
  /// Formula per term:
  ///   IDF = ln((N - df + 0.5) / (df + 0.5) + 1)
  ///   score += IDF * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avgdl))
  double _bm25(List<String> queryTokens, String docKey) {
    final dl = _docLengths[docKey] ?? 0;
    if (dl == 0) return 0;
    final n = _cache.length; // total documents
    double score = 0;

    for (final token in queryTokens) {
      final postings = _index[token];
      if (postings == null) continue;

      final df = postings.length; // document frequency
      final tf = postings[docKey] ?? 0; // term frequency in this doc
      if (tf == 0) continue;

      final idf = log((n - df + 0.5) / (df + 0.5) + 1);
      final tfNorm =
          (tf * (_k1 + 1)) / (tf + _k1 * (1 - _b + _b * dl / _avgDocLength));
      score += idf * tfNorm;
    }
    return score;
  }

  // ==================================================================
  // Disk I/O
  // ==================================================================

  /// Sanitise a key into a safe filename (without extension).
  String _keyToFileName(String key) {
    return key
        .replaceAll(RegExp(r'[^\w\-. ]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  /// Get the [File] handle for a given key.
  File _fileForKey(String key) {
    return File('$_basePath/${_keyToFileName(key)}.md');
  }

  /// Load all memory entries from disk (cold load, bypasses cache).
  List<MemoryEntry> _loadAllFromDisk() {
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

  // ==================================================================
  // Public API
  // ==================================================================

  /// Save or update a memory. Returns a status message.
  ///
  /// If [category] is null on update, the existing category is preserved.
  /// Tags are merged (union) on update.
  String save({
    required String key,
    required String content,
    String? category,
    List<String> tags = const [],
  }) {
    if (!_indexBuilt) _rebuildFullIndex();

    final file = _fileForKey(key);
    final bool updating = file.existsSync();
    final cat = category != null
        ? MemoryCategory.fromString(category)
        : MemoryCategory.general;

    MemoryEntry entry;
    if (updating) {
      final existing = _cache[key] ??
          MemoryEntry.fromFileContent(
            file.readAsStringSync(),
            fallbackKey: key,
          );
      final mergedTags = existing != null && tags.isNotEmpty
          ? {...existing.tags, ...tags}.toList()
          : (tags.isNotEmpty ? tags : (existing?.tags ?? []));
      entry = MemoryEntry(
        key: key,
        content: content,
        category: category != null ? cat : (existing?.category ?? cat),
        tags: mergedTags,
        createdAt: existing?.createdAt,
        updatedAt: DateTime.now(),
      );
    } else {
      entry = MemoryEntry(
        key: key,
        content: content,
        category: cat,
        tags: tags,
      );
    }

    file.writeAsStringSync(entry.toFileContent());
    _updateIndex(entry);

    return updating
        ? 'Memory "$key" updated successfully.'
        : 'Memory "$key" saved successfully.';
  }

  /// Recall a memory by exact key.
  String recall(String key) {
    if (!_indexBuilt) _rebuildFullIndex();

    // Try cache first; fall back to disk.
    final entry = _cache[key];
    if (entry != null) return _formatEntry(entry);

    final file = _fileForKey(key);
    if (!file.existsSync()) {
      return 'No memory found with key "$key".';
    }
    final parsed =
        MemoryEntry.fromFileContent(file.readAsStringSync(), fallbackKey: key);
    if (parsed == null) {
      return 'Error: Could not parse memory file for "$key".';
    }
    _updateIndex(parsed); // warm cache
    return _formatEntry(parsed);
  }

  /// Search memories using **BM25-ranked full-text search**.
  ///
  /// The query is tokenized and scored against an inverted index built from
  /// each memory's key, content, tags, and category. Results are returned
  /// sorted by relevance score (highest first).
  ///
  /// Falls back to substring matching when all query tokens are stop words
  /// or contain only special characters.
  String search(String query) {
    if (!_indexBuilt) _rebuildFullIndex();

    final queryTokens = _tokenize(query);
    if (queryTokens.isEmpty) {
      // Query was entirely stop words / special chars — substring fallback.
      return _substringSearch(query);
    }

    // Collect every document that has at least one matching token.
    final candidates = <String>{};
    for (final t in queryTokens) {
      final postings = _index[t];
      if (postings != null) candidates.addAll(postings.keys);
    }

    if (candidates.isEmpty) {
      // No token hits — try substring fallback.
      return _substringSearch(query);
    }

    final scored = <MapEntry<String, double>>[];
    for (final docKey in candidates) {
      final score = _bm25(queryTokens, docKey);
      if (score > 0) scored.add(MapEntry(docKey, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));

    if (scored.isEmpty) {
      return 'No memories found matching "$query".';
    }

    final buf = StringBuffer(
        'Found ${scored.length} matching memories (ranked by relevance):\n\n');
    for (final pair in scored) {
      final entry = _cache[pair.key];
      if (entry != null) {
        buf.writeln(_formatEntry(entry));
        buf.writeln();
      }
    }
    return buf.toString().trimRight();
  }

  /// Substring fallback for when BM25 produces no results (e.g. query is
  /// all stop words or contains special characters).
  String _substringSearch(String query) {
    final q = query.toLowerCase();
    final matches = _cache.values.where((e) {
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

  /// List memories, optionally filtered by [category] and/or [tag].
  String list({String? category, String? tag}) {
    if (!_indexBuilt) _rebuildFullIndex();
    if (_cache.isEmpty) return 'No memories stored.';

    var entries = _cache.values.toList();

    if (category != null && category.isNotEmpty) {
      final cat = MemoryCategory.fromString(category);
      entries = entries.where((e) => e.category == cat).toList();
      if (entries.isEmpty) {
        return 'No memories found in category "$category".';
      }
    }

    if (tag != null && tag.isNotEmpty) {
      final t = tag.toLowerCase();
      entries = entries
          .where((e) => e.tags.any((et) => et.toLowerCase() == t))
          .toList();
      if (entries.isEmpty) return 'No memories found with tag "$tag".';
    }

    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final buf = StringBuffer('${entries.length} memories stored:\n\n');
    for (final entry in entries) {
      final tagsStr =
          entry.tags.isNotEmpty ? ' [${entry.tags.join(", ")}]' : '';
      final preview = entry.content.length > 100
          ? '${entry.content.substring(0, 100)}...'
          : entry.content;
      buf.writeln(
          '- **${entry.key}** (${entry.category.name})$tagsStr: $preview');
    }
    return buf.toString().trimRight();
  }

  /// Delete a memory by key. Returns a status message.
  String delete(String key) {
    if (!_indexBuilt) _rebuildFullIndex();

    final file = _fileForKey(key);
    if (!file.existsSync() && !_cache.containsKey(key)) {
      return 'No memory found with key "$key".';
    }
    if (file.existsSync()) file.deleteSync();
    _removeFromIndex(key);
    return 'Memory "$key" deleted successfully.';
  }

  // ==================================================================
  // Formatting
  // ==================================================================

  /// Format a single entry for tool output.
  String _formatEntry(MemoryEntry entry) {
    final tagsStr =
        entry.tags.isNotEmpty ? '\nTags: ${entry.tags.join(", ")}' : '';
    return 'Key: ${entry.key}\n'
        'Category: ${entry.category.name}$tagsStr\n'
        'Created: ${entry.createdAt.toIso8601String()}\n'
        'Updated: ${entry.updatedAt.toIso8601String()}\n'
        'Content:\n${entry.content}';
  }
}
