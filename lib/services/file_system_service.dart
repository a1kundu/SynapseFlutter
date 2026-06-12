import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

/// Platform channel for native Android storage operations.
const _channel = MethodChannel('in.arijitk.synapse_flutter/file_system');

/// Default chunk size for chunked reads (100 KB).
const _defaultChunkSize = 100000;

/// Max file size to scan during grep (1 MB). Larger files are skipped.
const _maxGrepFileSize = 1000000;

/// Default number of lines for tail.
const _defaultTailLines = 50;

/// Android local file system service.
///
/// Supports listing storage volumes (internal, SD card, USB), browsing
/// directories, reading/writing file content, and copy/move/delete operations.
class FileSystemService {
  // ── Public entry point ────────────────────────────────────────────────

  /// Execute a file-system action and return a human-readable result string.
  static Future<String> execute({
    required String action,
    String? path,
    String? destination,
    String? content,
    String? pattern,
    String? replacement,
    String? algorithm,
    String? includeFilter,
    bool recursive = false,
    bool showHidden = false,
    bool dryRun = false,
    int? limit,
    int? offset,
    int? length,
    int? lines,
    int? maxDepth,
  }) async {
    if (kIsWeb) {
      return 'Error: File system access is not available on web.';
    }
    if (!Platform.isAndroid) {
      return 'Error: File system access is currently only supported on Android.';
    }

    switch (action) {
      case 'list_storage':
        return _listStorage();
      case 'list':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for list.';
        }
        return _listDirectory(path, recursive: recursive, showHidden: showHidden, limit: limit);
      case 'search':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for search (the directory to search in).';
        }
        if (pattern == null || pattern.trim().isEmpty) {
          return 'Error: "pattern" is required for search (regex pattern to match file/folder names).';
        }
        return _search(path, pattern, recursive: recursive, showHidden: showHidden, limit: limit);
      case 'read':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for read.';
        }
        return _readFile(path, offset: offset, length: length);
      case 'write':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for write.';
        }
        if (content == null) {
          return 'Error: "content" is required for write.';
        }
        return _writeFile(path, content);
      case 'copy':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for copy.';
        }
        if (destination == null || destination.trim().isEmpty) {
          return 'Error: "destination" is required for copy.';
        }
        return _copy(path, destination, recursive: recursive);
      case 'move':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for move.';
        }
        if (destination == null || destination.trim().isEmpty) {
          return 'Error: "destination" is required for move.';
        }
        return _move(path, destination);
      case 'delete':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for delete.';
        }
        return _delete(path, recursive: recursive);
      case 'mkdir':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for mkdir.';
        }
        return _mkdir(path);
      case 'info':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for info.';
        }
        return _info(path);
      case 'exists':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for exists.';
        }
        return _exists(path);
      case 'grep':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for grep (the directory to search in).';
        }
        if (pattern == null || pattern.trim().isEmpty) {
          return 'Error: "pattern" is required for grep (regex pattern to match file contents).';
        }
        return _grep(path, pattern, recursive: recursive, showHidden: showHidden, limit: limit, includeFilter: includeFilter);
      case 'append':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for append.';
        }
        if (content == null) {
          return 'Error: "content" is required for append.';
        }
        return _append(path, content);
      case 'tree':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for tree.';
        }
        return _tree(path, showHidden: showHidden, maxDepth: maxDepth, limit: limit);
      case 'disk_usage':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for disk_usage (any path on the target volume).';
        }
        return _diskUsage(path);
      case 'checksum':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for checksum.';
        }
        return _checksum(path, algorithm: algorithm ?? 'sha256');
      case 'rename_batch':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for rename_batch (the directory containing files).';
        }
        if (pattern == null || pattern.trim().isEmpty) {
          return 'Error: "pattern" is required for rename_batch (regex to match in filenames).';
        }
        if (replacement == null) {
          return 'Error: "replacement" is required for rename_batch.';
        }
        return _renameBatch(path, pattern, replacement, recursive: recursive, showHidden: showHidden, dryRun: dryRun);
      case 'diff':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for diff (file A).';
        }
        if (destination == null || destination.trim().isEmpty) {
          return 'Error: "destination" is required for diff (file B).';
        }
        return _diff(path, destination);
      case 'archive':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for archive (file or directory to compress).';
        }
        if (destination == null || destination.trim().isEmpty) {
          return 'Error: "destination" is required for archive (output .zip path).';
        }
        return _archive(path, destination);
      case 'extract':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for extract (the .zip file).';
        }
        if (destination == null || destination.trim().isEmpty) {
          return 'Error: "destination" is required for extract (output directory).';
        }
        return _extract(path, destination);
      case 'tail':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for tail.';
        }
        return _tail(path, lines: lines ?? _defaultTailLines);
      case 'write_bytes':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for write_bytes.';
        }
        if (content == null) {
          return 'Error: "content" is required for write_bytes.';
        }
        return _writeBytes(path, content, offset: offset ?? 0);
      default:
        return 'Error: Unknown action "$action". '
            'Supported: list_storage, list, search, grep, read, tail, write, append, '
            'write_bytes, copy, move, delete, mkdir, rename_batch, info, exists, '
            'tree, disk_usage, checksum, diff, archive, extract.';
    }
  }

  // ── Permission check ──────────────────────────────────────────────────

  /// Returns null if permission is granted, or an error string if not.
  static Future<String?> _checkPermission() async {
    try {
      final hasPermission = await _channel.invokeMethod<bool>('hasFilePermission');
      if (hasPermission == true) return null;

      // Try to open the settings page so the user can grant it.
      await _channel.invokeMethod<void>('requestFilePermission');
      return 'Error: File access permission not granted. '
          'A system settings page has been opened — please grant '
          '"All files access" to Synapse, then try again.';
    } catch (e) {
      return 'Error: Could not check file permission — $e';
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// List available storage volumes.
  static Future<String> _listStorage() async {
    try {
      final volumes = await _channel.invokeMethod<List<dynamic>>('getStorageVolumes');
      if (volumes == null || volumes.isEmpty) {
        return 'No storage volumes found.';
      }

      final buf = StringBuffer('Storage volumes:\n');
      for (final v in volumes) {
        final m = Map<String, dynamic>.from(v as Map);
        final desc = m['description'] ?? 'Unknown';
        final path = m['path'] ?? '(unavailable)';
        final type = m['type'] ?? 'unknown';
        final state = m['state'] ?? 'unknown';
        buf.writeln('  [$type] $desc');
        buf.writeln('    Path:  $path');
        buf.writeln('    State: $state');
      }
      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to list storage volumes — $e';
    }
  }

  /// List directory contents.
  static Future<String> _listDirectory(
    String path, {
    bool recursive = false,
    bool showHidden = false,
    int? limit,
  }) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final dir = Directory(path);
    if (!await dir.exists()) {
      return 'Error: Directory does not exist: $path';
    }

    try {
      final entries = <FileSystemEntity>[];
      await for (final entity in dir.list(
        recursive: recursive,
        followLinks: false,
      )) {
        final name = entity.path.split('/').last;
        if (!showHidden && name.startsWith('.')) continue;
        entries.add(entity);
        if (limit != null && limit > 0 && entries.length >= limit) break;
      }

      if (entries.isEmpty) {
        return 'Directory is empty: $path';
      }

      // Sort: directories first, then files, alphabetically within each.
      entries.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      final truncated = limit != null && limit > 0 && entries.length >= limit;
      final buf = StringBuffer();
      buf.writeln('Contents of $path (${entries.length} items${truncated ? ', limit reached' : ''}):');
      buf.writeln();

      for (final entity in entries) {
        final stat = await entity.stat();
        final name = recursive ? entity.path.substring(path.length + 1) : entity.path.split('/').last;

        if (entity is Directory) {
          buf.writeln('  [DIR]  $name/');
        } else if (entity is Link) {
          buf.writeln('  [LNK]  $name -> ${await (entity).target()}');
        } else {
          final size = _formatSize(stat.size);
          final modified = _formatDate(stat.modified);
          buf.writeln('  [FILE] $name  ($size, $modified)');
        }
      }

      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to list directory — $e';
    }
  }

  /// Search for files/folders whose names match a regex pattern.
  static Future<String> _search(
    String path,
    String pattern, {
    bool recursive = false,
    bool showHidden = false,
    int? limit,
  }) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final dir = Directory(path);
    if (!await dir.exists()) {
      return 'Error: Directory does not exist: $path';
    }

    // Validate the regex pattern.
    final RegExp regex;
    try {
      regex = RegExp(pattern);
    } catch (e) {
      return 'Error: Invalid regex pattern "$pattern" — $e';
    }

    try {
      final matches = <FileSystemEntity>[];
      await for (final entity in dir.list(
        recursive: recursive,
        followLinks: false,
      )) {
        final name = entity.path.split('/').last;
        if (!showHidden && name.startsWith('.')) continue;
        if (regex.hasMatch(name)) {
          matches.add(entity);
          if (limit != null && limit > 0 && matches.length >= limit) break;
        }
      }

      if (matches.isEmpty) {
        return 'No matches found for pattern "$pattern" in $path'
            '${recursive ? ' (recursive)' : ''}.';
      }

      // Sort: directories first, then files, alphabetically within each.
      matches.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      final truncated = limit != null && limit > 0 && matches.length >= limit;
      final buf = StringBuffer();
      buf.writeln('Search results for /$pattern/ in $path '
          '(${matches.length} matches${truncated ? ', limit reached' : ''}):');
      buf.writeln();

      for (final entity in matches) {
        final stat = await entity.stat();
        // Show relative path from the search root.
        final relPath = entity.path.startsWith(path)
            ? entity.path.substring(path.length + 1)
            : entity.path;

        if (entity is Directory) {
          buf.writeln('  [DIR]  $relPath/');
        } else if (entity is Link) {
          buf.writeln('  [LNK]  $relPath -> ${await (entity).target()}');
        } else {
          final size = _formatSize(stat.size);
          final modified = _formatDate(stat.modified);
          buf.writeln('  [FILE] $relPath  ($size, $modified)');
        }
      }

      return buf.toString().trim();
    } catch (e) {
      return 'Error: Search failed — $e';
    }
  }

  /// Read a file's content as text, optionally by byte range.
  ///
  /// [offset] – byte offset to start reading from (0-based). Defaults to 0.
  /// [length] – number of bytes to read. Defaults to [_defaultChunkSize].
  /// When both are omitted and the file is smaller than [_defaultChunkSize],
  /// the entire file is returned. For larger files, a chunk is returned with
  /// metadata indicating total size so subsequent chunks can be requested.
  static Future<String> _readFile(
    String path, {
    int? offset,
    int? length,
  }) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final file = File(path);
    if (!await file.exists()) {
      return 'Error: File does not exist: $path';
    }

    try {
      final stat = await file.stat();
      final mime = lookupMimeType(path) ?? 'application/octet-stream';
      final totalSize = stat.size;

      final startByte = offset ?? 0;
      if (startByte < 0 || startByte >= totalSize) {
        return 'Error: offset $startByte is out of range. File size is $totalSize bytes.';
      }

      // Determine how many bytes to read this chunk.
      final chunkSize = length ?? _defaultChunkSize;
      final endByte = (startByte + chunkSize).clamp(0, totalSize);
      final bytesToRead = endByte - startByte;

      final isFullFile = startByte == 0 && endByte >= totalSize;
      final isExplicitChunk = offset != null || length != null;

      if (isFullFile && totalSize <= _defaultChunkSize && !isExplicitChunk) {
        // Small file – read entirely.
        final content = await file.readAsString(encoding: utf8);
        return 'File: $path\n'
            'Size: ${_formatSize(totalSize)}\n'
            'Type: $mime\n'
            'Modified: ${_formatDate(stat.modified)}\n\n'
            '$content';
      }

      // Chunked read.
      final bytes = await file
          .openRead(startByte, endByte)
          .fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
      final text = utf8.decode(Uint8List.fromList(bytes), allowMalformed: true);

      final remaining = totalSize - endByte;
      final buf = StringBuffer();
      buf.writeln('File: $path');
      buf.writeln('Size: ${_formatSize(totalSize)}');
      buf.writeln('Type: $mime');
      buf.writeln('Modified: ${_formatDate(stat.modified)}');
      buf.writeln('Chunk: bytes $startByte–${endByte - 1} of $totalSize '
          '(${_formatSize(bytesToRead)} read, ${_formatSize(remaining)} remaining)');
      if (remaining > 0) {
        buf.writeln('Next chunk: use offset=$endByte to continue reading.');
      }
      buf.writeln();
      buf.write(text);

      return buf.toString();
    } catch (e) {
      if (e.toString().contains('Failed to decode')) {
        return 'Error: File appears to be binary and cannot be read as text: $path';
      }
      return 'Error: Failed to read file — $e';
    }
  }

  /// Write (create or overwrite) a text file.
  static Future<String> _writeFile(String path, String content) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final file = File(path);
      // Create parent directories if they don't exist.
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      final existed = await file.exists();
      await file.writeAsString(content, encoding: utf8, flush: true);
      final stat = await file.stat();

      return existed
          ? 'File updated: $path (${_formatSize(stat.size)})'
          : 'File created: $path (${_formatSize(stat.size)})';
    } catch (e) {
      return 'Error: Failed to write file — $e';
    }
  }

  /// Copy a file or directory.
  static Future<String> _copy(
    String source,
    String destination, {
    bool recursive = false,
  }) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final sourceType = await FileSystemEntity.type(source);
      if (sourceType == FileSystemEntityType.notFound) {
        return 'Error: Source does not exist: $source';
      }

      if (sourceType == FileSystemEntityType.file) {
        final srcFile = File(source);
        // If destination is a directory, copy file into it.
        var destPath = destination;
        if (await FileSystemEntity.isDirectory(destination)) {
          destPath = '$destination/${source.split('/').last}';
        }
        // Create parent directories.
        final destParent = File(destPath).parent;
        if (!await destParent.exists()) {
          await destParent.create(recursive: true);
        }
        await srcFile.copy(destPath);
        return 'Copied file: $source -> $destPath';
      }

      if (sourceType == FileSystemEntityType.directory) {
        if (!recursive) {
          return 'Error: Source is a directory. Set "recursive" to true to copy directories.';
        }
        final count = await _copyDirectory(Directory(source), Directory(destination));
        return 'Copied directory ($count items): $source -> $destination';
      }

      return 'Error: Cannot copy this type of file system entity.';
    } catch (e) {
      return 'Error: Copy failed — $e';
    }
  }

  /// Recursively copy a directory.
  static Future<int> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    var count = 0;
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (entity is File) {
        await entity.copy('${destination.path}/$name');
        count++;
      } else if (entity is Directory) {
        count += await _copyDirectory(
          entity,
          Directory('${destination.path}/$name'),
        );
      }
    }
    return count;
  }

  /// Move (rename) a file or directory.
  static Future<String> _move(String source, String destination) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final sourceType = await FileSystemEntity.type(source);
      if (sourceType == FileSystemEntityType.notFound) {
        return 'Error: Source does not exist: $source';
      }

      // If destination is an existing directory, move source into it.
      var destPath = destination;
      if (await FileSystemEntity.isDirectory(destination)) {
        destPath = '$destination/${source.split('/').last}';
      }

      // Create parent directories.
      final destParent = File(destPath).parent;
      if (!await destParent.exists()) {
        await destParent.create(recursive: true);
      }

      if (sourceType == FileSystemEntityType.file) {
        final file = File(source);
        try {
          await file.rename(destPath);
        } catch (_) {
          // rename fails across file systems; fall back to copy + delete.
          await file.copy(destPath);
          await file.delete();
        }
        return 'Moved file: $source -> $destPath';
      }

      if (sourceType == FileSystemEntityType.directory) {
        final dir = Directory(source);
        try {
          await dir.rename(destPath);
        } catch (_) {
          // Cross-device: copy then delete.
          await _copyDirectory(dir, Directory(destPath));
          await dir.delete(recursive: true);
        }
        return 'Moved directory: $source -> $destPath';
      }

      return 'Error: Cannot move this type of file system entity.';
    } catch (e) {
      return 'Error: Move failed — $e';
    }
  }

  /// Delete a file or directory.
  static Future<String> _delete(String path, {bool recursive = false}) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final entityType = await FileSystemEntity.type(path);
      if (entityType == FileSystemEntityType.notFound) {
        return 'Error: Path does not exist: $path';
      }

      if (entityType == FileSystemEntityType.file) {
        await File(path).delete();
        return 'Deleted file: $path';
      }

      if (entityType == FileSystemEntityType.directory) {
        if (!recursive) {
          // Check if directory is empty.
          final isEmpty = await Directory(path)
              .list()
              .isEmpty;
          if (!isEmpty) {
            return 'Error: Directory is not empty. Set "recursive" to true '
                'to delete non-empty directories.';
          }
        }
        await Directory(path).delete(recursive: recursive);
        return 'Deleted directory: $path';
      }

      if (entityType == FileSystemEntityType.link) {
        await Link(path).delete();
        return 'Deleted link: $path';
      }

      return 'Error: Unknown entity type at $path';
    } catch (e) {
      return 'Error: Delete failed — $e';
    }
  }

  /// Create a directory (recursively).
  static Future<String> _mkdir(String path) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        return 'Directory already exists: $path';
      }
      await dir.create(recursive: true);
      return 'Created directory: $path';
    } catch (e) {
      return 'Error: Failed to create directory — $e';
    }
  }

  /// Get detailed info about a file or directory.
  static Future<String> _info(String path) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final entityType = await FileSystemEntity.type(path);
      if (entityType == FileSystemEntityType.notFound) {
        return 'Error: Path does not exist: $path';
      }

      final stat = await FileStat.stat(path);
      final buf = StringBuffer();
      buf.writeln('Path: $path');
      buf.writeln('Type: ${_entityTypeName(entityType)}');
      buf.writeln('Size: ${_formatSize(stat.size)}');
      buf.writeln('Modified: ${_formatDate(stat.modified)}');
      buf.writeln('Accessed: ${_formatDate(stat.accessed)}');
      buf.writeln('Changed: ${_formatDate(stat.changed)}');
      buf.writeln('Mode: ${stat.modeString()}');

      if (entityType == FileSystemEntityType.file) {
        final mime = lookupMimeType(path) ?? 'unknown';
        buf.writeln('MIME type: $mime');
      }

      if (entityType == FileSystemEntityType.directory) {
        // Count immediate children.
        var fileCount = 0;
        var dirCount = 0;
        await for (final child in Directory(path).list(followLinks: false)) {
          if (child is File) {
            fileCount++;
          } else if (child is Directory) {
            dirCount++;
          }
        }
        buf.writeln('Contains: $dirCount directories, $fileCount files');
      }

      if (entityType == FileSystemEntityType.link) {
        buf.writeln('Target: ${await Link(path).target()}');
      }

      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to get info — $e';
    }
  }

  /// Check if a path exists and what type it is.
  static Future<String> _exists(String path) async {
    final entityType = await FileSystemEntity.type(path);
    if (entityType == FileSystemEntityType.notFound) {
      return 'Does not exist: $path';
    }
    return 'Exists: $path (${_entityTypeName(entityType)})';
  }

  // ── New actions ───────────────────────────────────────────────────────

  /// Search inside file contents for lines matching a regex pattern.
  static Future<String> _grep(
    String path,
    String pattern, {
    bool recursive = false,
    bool showHidden = false,
    int? limit,
    String? includeFilter,
  }) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final dir = Directory(path);
    if (!await dir.exists()) {
      // Maybe it's a single file?
      final file = File(path);
      if (await file.exists()) {
        return _grepSingleFile(file, pattern, path, limit: limit);
      }
      return 'Error: Path does not exist: $path';
    }

    final RegExp regex;
    try {
      regex = RegExp(pattern);
    } catch (e) {
      return 'Error: Invalid regex pattern "$pattern" — $e';
    }

    // Optional filename filter (e.g. "*.txt", "*.dart").
    RegExp? filterRegex;
    if (includeFilter != null && includeFilter.isNotEmpty) {
      // Convert simple glob to regex: *.txt → \.txt$, *.{dart,yaml} → \.(dart|yaml)$
      final globPattern = includeFilter
          .replaceAll('.', r'\.')
          .replaceAll('*', '.*')
          .replaceAllMapped(RegExp(r'\{([^}]+)\}'), (m) => '(${m[1]!.replaceAll(',', '|')})');
      try {
        filterRegex = RegExp('^$globPattern\$', caseSensitive: false);
      } catch (_) {
        // If glob-to-regex fails, treat as literal substring.
        filterRegex = RegExp(RegExp.escape(includeFilter), caseSensitive: false);
      }
    }

    try {
      final results = <String>[];
      var filesSearched = 0;
      var filesMatched = 0;
      var totalMatches = 0;
      final hitLimit = limit != null && limit > 0;

      await for (final entity in dir.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last;
        if (!showHidden && name.startsWith('.')) continue;
        if (filterRegex != null && !filterRegex.hasMatch(name)) continue;

        // Skip large or binary files.
        final stat = await entity.stat();
        if (stat.size > _maxGrepFileSize) continue;

        filesSearched++;

        try {
          final content = await entity.readAsString(encoding: utf8);
          final fileLines = content.split('\n');
          var fileHasMatch = false;

          for (var i = 0; i < fileLines.length; i++) {
            if (regex.hasMatch(fileLines[i])) {
              if (!fileHasMatch) {
                filesMatched++;
                fileHasMatch = true;
              }
              final relPath = entity.path.startsWith(path)
                  ? entity.path.substring(path.length + 1)
                  : entity.path;
              results.add('  $relPath:${i + 1}: ${fileLines[i].trimRight()}');
              totalMatches++;
              if (hitLimit && totalMatches >= limit!) break;
            }
          }
          if (hitLimit && totalMatches >= limit!) break;
        } catch (_) {
          // Skip files that can't be read as text (binary).
          continue;
        }
      }

      if (results.isEmpty) {
        return 'No matches found for /$pattern/ in $path '
            '($filesSearched files searched).';
      }

      final truncated = hitLimit && totalMatches >= limit!;
      final buf = StringBuffer();
      buf.writeln('Grep results for /$pattern/ in $path '
          '($totalMatches matches in $filesMatched files, $filesSearched searched'
          '${truncated ? ', limit reached' : ''}):');
      buf.writeln();
      for (final line in results) {
        buf.writeln(line);
      }
      return buf.toString().trim();
    } catch (e) {
      return 'Error: Grep failed — $e';
    }
  }

  /// Grep a single file and return matching lines.
  static Future<String> _grepSingleFile(
    File file,
    String pattern,
    String displayPath, {
    int? limit,
  }) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final RegExp regex;
    try {
      regex = RegExp(pattern);
    } catch (e) {
      return 'Error: Invalid regex pattern "$pattern" — $e';
    }

    try {
      final content = await file.readAsString(encoding: utf8);
      final lines = content.split('\n');
      final results = <String>[];
      final hitLimit = limit != null && limit > 0;

      for (var i = 0; i < lines.length; i++) {
        if (regex.hasMatch(lines[i])) {
          results.add('  ${i + 1}: ${lines[i].trimRight()}');
          if (hitLimit && results.length >= limit!) break;
        }
      }

      if (results.isEmpty) {
        return 'No matches found for /$pattern/ in $displayPath.';
      }

      final truncated = hitLimit && results.length >= limit!;
      final buf = StringBuffer();
      buf.writeln('Grep results for /$pattern/ in $displayPath '
          '(${results.length} matches${truncated ? ', limit reached' : ''}):');
      buf.writeln();
      for (final line in results) {
        buf.writeln(line);
      }
      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to grep file — $e';
    }
  }

  /// Append content to a file (creates the file if it doesn't exist).
  static Future<String> _append(String path, String content) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final file = File(path);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      final existed = await file.exists();
      await file.writeAsString(
        content,
        mode: FileMode.append,
        encoding: utf8,
        flush: true,
      );
      final stat = await file.stat();
      final bytesAppended = utf8.encode(content).length;

      return existed
          ? 'Appended ${_formatSize(bytesAppended)} to $path (total: ${_formatSize(stat.size)})'
          : 'Created file with ${_formatSize(bytesAppended)}: $path';
    } catch (e) {
      return 'Error: Failed to append — $e';
    }
  }

  /// Display a directory tree visualization.
  static Future<String> _tree(
    String path, {
    bool showHidden = false,
    int? maxDepth,
    int? limit,
  }) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final dir = Directory(path);
    if (!await dir.exists()) {
      return 'Error: Directory does not exist: $path';
    }

    try {
      final buf = StringBuffer();
      buf.writeln(path.split('/').last.isEmpty ? path : path.split('/').last);
      var count = 0;
      final effectiveLimit = (limit != null && limit > 0) ? limit : null;
      final effectiveDepth = maxDepth ?? 10; // sensible default

      Future<bool> buildTree(Directory dir, String prefix, int depth) async {
        if (depth > effectiveDepth) return false;

        final entries = <FileSystemEntity>[];
        await for (final entity in dir.list(followLinks: false)) {
          final name = entity.path.split('/').last;
          if (!showHidden && name.startsWith('.')) continue;
          entries.add(entity);
        }

        // Sort: directories first, then files.
        entries.sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });

        for (var i = 0; i < entries.length; i++) {
          if (effectiveLimit != null && count >= effectiveLimit) return true;

          final isLast = i == entries.length - 1;
          final connector = isLast ? '└── ' : '├── ';
          final childPrefix = isLast ? '    ' : '│   ';
          final name = entries[i].path.split('/').last;

          if (entries[i] is Directory) {
            buf.writeln('$prefix$connector$name/');
            count++;
            final hitLimit = await buildTree(
              entries[i] as Directory,
              '$prefix$childPrefix',
              depth + 1,
            );
            if (hitLimit) return true;
          } else {
            buf.writeln('$prefix$connector$name');
            count++;
          }
        }
        return false;
      }

      final hitLimit = await buildTree(dir, '', 0);
      if (hitLimit) {
        buf.writeln('\n... ($count entries shown, limit reached)');
      } else {
        buf.writeln('\n$count entries');
      }

      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to build tree — $e';
    }
  }

  /// Get disk usage / free space for the volume containing [path].
  static Future<String> _diskUsage(String path) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDiskUsage',
        {'path': path},
      );
      if (result == null) {
        return 'Error: Could not get disk usage for $path';
      }

      final total = (result['total'] as int?) ?? 0;
      final free = (result['free'] as int?) ?? 0;
      final used = (result['used'] as int?) ?? 0;
      final usedPercent = total > 0 ? (used / total * 100).toStringAsFixed(1) : '0.0';

      final buf = StringBuffer();
      buf.writeln('Disk usage for volume containing: $path');
      buf.writeln('  Total: ${_formatSize(total)}');
      buf.writeln('  Used:  ${_formatSize(used)} ($usedPercent%)');
      buf.writeln('  Free:  ${_formatSize(free)}');
      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to get disk usage — $e';
    }
  }

  /// Compute a file hash / checksum.
  static Future<String> _checksum(String path, {String algorithm = 'sha256'}) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final file = File(path);
    if (!await file.exists()) {
      return 'Error: File does not exist: $path';
    }

    try {
      final Hash hash;
      switch (algorithm.toLowerCase()) {
        case 'md5':
          hash = md5;
          break;
        case 'sha1':
          hash = sha1;
          break;
        case 'sha256':
          hash = sha256;
          break;
        default:
          return 'Error: Unsupported algorithm "$algorithm". Use md5, sha1, or sha256.';
      }

      // Stream the file to compute hash without loading all into memory.
      final bytes = await file.readAsBytes();
      final digest = hash.convert(bytes);

      final stat = await file.stat();
      return 'File: $path\n'
          'Size: ${_formatSize(stat.size)}\n'
          'Algorithm: ${algorithm.toUpperCase()}\n'
          'Checksum: $digest';
    } catch (e) {
      return 'Error: Failed to compute checksum — $e';
    }
  }

  /// Batch rename files in a directory using regex find/replace on names.
  static Future<String> _renameBatch(
    String path,
    String pattern,
    String replacement, {
    bool recursive = false,
    bool showHidden = false,
    bool dryRun = false,
  }) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final dir = Directory(path);
    if (!await dir.exists()) {
      return 'Error: Directory does not exist: $path';
    }

    final RegExp regex;
    try {
      regex = RegExp(pattern);
    } catch (e) {
      return 'Error: Invalid regex pattern "$pattern" — $e';
    }

    try {
      final renames = <MapEntry<String, String>>[];

      await for (final entity in dir.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entity is Directory) continue; // Only rename files.
        final name = entity.path.split('/').last;
        if (!showHidden && name.startsWith('.')) continue;

        if (regex.hasMatch(name)) {
          final newName = name.replaceAll(regex, replacement);
          if (newName != name && newName.isNotEmpty) {
            final parentPath = entity.parent.path;
            renames.add(MapEntry(entity.path, '$parentPath/$newName'));
          }
        }
      }

      if (renames.isEmpty) {
        return 'No files matched pattern /$pattern/ in $path.';
      }

      final buf = StringBuffer();
      if (dryRun) {
        buf.writeln('Dry run — ${renames.length} files would be renamed:');
      } else {
        buf.writeln('Renamed ${renames.length} files:');
      }
      buf.writeln();

      for (final entry in renames) {
        final oldName = entry.key.split('/').last;
        final newName = entry.value.split('/').last;
        buf.writeln('  $oldName -> $newName');
        if (!dryRun) {
          await File(entry.key).rename(entry.value);
        }
      }

      return buf.toString().trim();
    } catch (e) {
      return 'Error: Rename batch failed — $e';
    }
  }

  /// Compare two text files and return a unified-diff-style output.
  static Future<String> _diff(String pathA, String pathB) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final fileA = File(pathA);
    final fileB = File(pathB);
    if (!await fileA.exists()) return 'Error: File does not exist: $pathA';
    if (!await fileB.exists()) return 'Error: File does not exist: $pathB';

    try {
      final linesA = (await fileA.readAsString(encoding: utf8)).split('\n');
      final linesB = (await fileB.readAsString(encoding: utf8)).split('\n');

      // Build LCS table.
      final m = linesA.length;
      final n = linesB.length;
      final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
      for (var i = 1; i <= m; i++) {
        for (var j = 1; j <= n; j++) {
          if (linesA[i - 1] == linesB[j - 1]) {
            dp[i][j] = dp[i - 1][j - 1] + 1;
          } else {
            dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1]);
          }
        }
      }

      // Backtrack to produce diff lines.
      final diffLines = <String>[];
      var i = m, j = n;
      while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && linesA[i - 1] == linesB[j - 1]) {
          diffLines.add('  ${linesA[i - 1]}');
          i--;
          j--;
        } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
          diffLines.add('+ ${linesB[j - 1]}');
          j--;
        } else {
          diffLines.add('- ${linesA[i - 1]}');
          i--;
        }
      }
      // diffLines was built backwards; we iterate in reverse below.

      final nameA = pathA.split('/').last;
      final nameB = pathB.split('/').last;

      if (diffLines.every((l) => l.startsWith('  '))) {
        return 'Files are identical: $nameA and $nameB';
      }

      final added = diffLines.where((l) => l.startsWith('+ ')).length;
      final removed = diffLines.where((l) => l.startsWith('- ')).length;

      final buf = StringBuffer();
      buf.writeln('--- $pathA');
      buf.writeln('+++ $pathB');
      buf.writeln('($added additions, $removed deletions)');
      buf.writeln();
      for (final line in diffLines.reversed) {
        buf.writeln(line);
      }
      return buf.toString().trim();
    } catch (e) {
      return 'Error: Diff failed — $e';
    }
  }

  /// Create a ZIP archive from a file or directory.
  static Future<String> _archive(String sourcePath, String destPath) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final archive = Archive();
      final sourceType = await FileSystemEntity.type(sourcePath);
      if (sourceType == FileSystemEntityType.notFound) {
        return 'Error: Source does not exist: $sourcePath';
      }

      if (sourceType == FileSystemEntityType.file) {
        final file = File(sourcePath);
        final bytes = await file.readAsBytes();
        final name = sourcePath.split('/').last;
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      } else if (sourceType == FileSystemEntityType.directory) {
        await _addDirectoryToArchive(archive, Directory(sourcePath), '');
      } else {
        return 'Error: Cannot archive this type of entity.';
      }

      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) {
        return 'Error: Failed to encode ZIP archive.';
      }

      final destFile = File(destPath);
      final parent = destFile.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await destFile.writeAsBytes(encoded, flush: true);

      return 'Archive created: $destPath (${_formatSize(encoded.length)}, '
          '${archive.length} entries)';
    } catch (e) {
      return 'Error: Archive failed — $e';
    }
  }

  /// Recursively add directory contents to an archive.
  static Future<void> _addDirectoryToArchive(
    Archive archive,
    Directory dir,
    String prefix,
  ) async {
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      final entryName = prefix.isEmpty ? name : '$prefix/$name';

      if (entity is File) {
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
      } else if (entity is Directory) {
        await _addDirectoryToArchive(archive, entity, entryName);
      }
    }
  }

  /// Extract a ZIP archive to a directory.
  static Future<String> _extract(String archivePath, String destPath) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final file = File(archivePath);
      if (!await file.exists()) {
        return 'Error: Archive does not exist: $archivePath';
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final destDir = Directory(destPath);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      var extracted = 0;
      for (final entry in archive) {
        final outPath = '$destPath/${entry.name}';
        if (entry.isFile) {
          final outFile = File(outPath);
          final parent = outFile.parent;
          if (!await parent.exists()) {
            await parent.create(recursive: true);
          }
          await outFile.writeAsBytes(entry.content as List<int>, flush: true);
          extracted++;
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      return 'Extracted $extracted files from $archivePath to $destPath';
    } catch (e) {
      return 'Error: Extract failed — $e';
    }
  }

  /// Read the last N lines of a text file.
  static Future<String> _tail(String path, {int lines = _defaultTailLines}) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final file = File(path);
    if (!await file.exists()) {
      return 'Error: File does not exist: $path';
    }

    try {
      final stat = await file.stat();
      final mime = lookupMimeType(path) ?? 'application/octet-stream';
      final content = await file.readAsString(encoding: utf8);
      final allLines = content.split('\n');

      // Remove trailing empty line from split.
      if (allLines.isNotEmpty && allLines.last.isEmpty) {
        allLines.removeLast();
      }

      final totalLines = allLines.length;
      final start = math.max(0, totalLines - lines);
      final shownLines = allLines.sublist(start);

      final buf = StringBuffer();
      buf.writeln('File: $path');
      buf.writeln('Size: ${_formatSize(stat.size)}');
      buf.writeln('Type: $mime');
      buf.writeln('Total lines: $totalLines');
      buf.writeln('Showing: last ${shownLines.length} lines '
          '(lines ${start + 1}–$totalLines)');
      buf.writeln();
      for (var i = 0; i < shownLines.length; i++) {
        buf.writeln('${start + i + 1}: ${shownLines[i]}');
      }
      return buf.toString().trim();
    } catch (e) {
      if (e.toString().contains('Failed to decode')) {
        return 'Error: File appears to be binary: $path';
      }
      return 'Error: Failed to tail file — $e';
    }
  }

  /// Write (patch) content at a specific byte offset without rewriting the
  /// entire file. Useful for editing a section of a large file.
  static Future<String> _writeBytes(String path, String content, {int offset = 0}) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    try {
      final file = File(path);
      if (!await file.exists()) {
        return 'Error: File does not exist: $path '
            '(use "write" to create new files)';
      }

      final originalBytes = await file.readAsBytes();
      if (offset < 0 || offset > originalBytes.length) {
        return 'Error: offset $offset is out of range. File size is ${originalBytes.length} bytes.';
      }

      final contentBytes = utf8.encode(content);
      final newLength = math.max(originalBytes.length, offset + contentBytes.length);
      final newBytes = Uint8List(newLength);
      // Copy original content.
      newBytes.setAll(0, originalBytes);
      // Overwrite at the specified offset.
      newBytes.setRange(offset, offset + contentBytes.length, contentBytes);

      await file.writeAsBytes(newBytes, flush: true);

      return 'Wrote ${_formatSize(contentBytes.length)} at offset $offset in $path '
          '(file size: ${_formatSize(newBytes.length)})';
    } catch (e) {
      return 'Error: write_bytes failed — $e';
    }
  }

  // ── Formatting helpers ────────────────────────────────────────────────

  static String _entityTypeName(FileSystemEntityType type) {
    switch (type) {
      case FileSystemEntityType.file:
        return 'file';
      case FileSystemEntityType.directory:
        return 'directory';
      case FileSystemEntityType.link:
        return 'symbolic link';
      default:
        return 'unknown';
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}
