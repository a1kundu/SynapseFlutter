import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

/// Platform channel for native Android storage operations.
const _channel = MethodChannel('in.arijitk.synapse_flutter/file_system');

/// Maximum file content size to read/return (100 KB).
const _maxReadSize = 100000;

/// Maximum entries to return from a directory listing.
const _maxListEntries = 500;

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
    bool recursive = false,
    bool showHidden = false,
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
        return _listDirectory(path, recursive: recursive, showHidden: showHidden);
      case 'read':
        if (path == null || path.trim().isEmpty) {
          return 'Error: "path" is required for read.';
        }
        return _readFile(path);
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
      default:
        return 'Error: Unknown action "$action". '
            'Supported: list_storage, list, read, write, copy, move, delete, mkdir, info, exists.';
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
        if (entries.length >= _maxListEntries) break;
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

      final buf = StringBuffer();
      buf.writeln('Contents of $path (${entries.length} items${entries.length >= _maxListEntries ? ', truncated' : ''}):');
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

  /// Read a file's content as text.
  static Future<String> _readFile(String path) async {
    final permError = await _checkPermission();
    if (permError != null) return permError;

    final file = File(path);
    if (!await file.exists()) {
      return 'Error: File does not exist: $path';
    }

    try {
      final stat = await file.stat();
      final mime = lookupMimeType(path) ?? 'application/octet-stream';

      // Guard against reading huge or binary files.
      if (stat.size > _maxReadSize) {
        // Read only the first portion.
        final bytes = await file.openRead(0, _maxReadSize).fold<List<int>>(
          [],
          (prev, chunk) => prev..addAll(chunk),
        );
        final text = utf8.decode(Uint8List.fromList(bytes), allowMalformed: true);
        return 'File: $path\n'
            'Size: ${_formatSize(stat.size)} (showing first ${_formatSize(_maxReadSize)})\n'
            'Type: $mime\n'
            'Modified: ${_formatDate(stat.modified)}\n\n'
            '$text\n\n[content truncated at $_maxReadSize bytes]';
      }

      final content = await file.readAsString(encoding: utf8);
      return 'File: $path\n'
          'Size: ${_formatSize(stat.size)}\n'
          'Type: $mime\n'
          'Modified: ${_formatDate(stat.modified)}\n\n'
          '$content';
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
