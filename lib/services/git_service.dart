import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel for native Android Git operations (JGit).
const _channel = MethodChannel('in.arijitk.synapse_flutter/git');

/// Git service providing full Git operations on Android via JGit.
///
/// Operates on the local file system — works on the same files as
/// [FileSystemService]. Supports init, clone, status, add, commit, log,
/// diff, branch, checkout, merge, pull, push, remote, stash, tag,
/// reset, and clean.
class GitService {
  // ── Public entry point ──────────────────────────────────────────────

  /// Execute a Git action and return a human-readable result string.
  static Future<String> execute({
    required String action,
    String? path,
    String? url,
    String? branch,
    String? name,
    String? oldName,
    String? newName,
    String? message,
    String? filepattern,
    String? remote,
    String? ref,
    String? stashRef,
    String? mode,
    String? authorName,
    String? authorEmail,
    String? algorithm,
    String? username,
    String? password,
    String? startPoint,
    bool? staged,
    bool? cached,
    bool? amend,
    bool? force,
    bool? bare,
    bool? all,
    bool? tags,
    bool? createBranch,
    bool? includeUntracked,
    bool? directories,
    bool? dryRun,
    bool? drop,
    int? maxCount,
  }) async {
    if (kIsWeb) {
      return 'Error: Git operations are not available on web.';
    }
    if (!Platform.isAndroid) {
      return 'Error: Git operations are currently only supported on Android.';
    }

    try {
      switch (action) {
        // ── Repository ────────────────────────────────────────────────
        case 'init':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for init.';
          }
          return await _callString('init', {
            'path': path,
            'bare': bare ?? false,
          });

        case 'clone':
          if (url == null || url.trim().isEmpty) {
            return 'Error: "url" is required for clone.';
          }
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for clone (destination directory).';
          }
          return await _callString('clone', {
            'url': url,
            'path': path,
            if (branch != null) 'branch': branch,
            if (username != null) 'username': username,
            if (password != null) 'password': password,
          });

        // ── Status ────────────────────────────────────────────────────
        case 'status':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for status.';
          }
          return await _formatStatus(path);

        // ── Stage / Unstage ───────────────────────────────────────────
        case 'add':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for add.';
          }
          return await _callString('add', {
            'path': path,
            'filepattern': filepattern ?? '.',
          });

        case 'remove':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for remove.';
          }
          if (filepattern == null || filepattern.trim().isEmpty) {
            return 'Error: "filepattern" is required for remove.';
          }
          return await _callString('remove', {
            'path': path,
            'filepattern': filepattern,
            'cached': cached ?? false,
          });

        // ── Commit ────────────────────────────────────────────────────
        case 'commit':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for commit.';
          }
          if (message == null || message.trim().isEmpty) {
            return 'Error: "message" is required for commit.';
          }
          return await _callString('commit', {
            'path': path,
            'message': message,
            'amend': amend ?? false,
            if (authorName != null) 'author_name': authorName,
            if (authorEmail != null) 'author_email': authorEmail,
          });

        // ── Log ───────────────────────────────────────────────────────
        case 'log':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for log.';
          }
          return await _formatLog(path, maxCount: maxCount ?? 20);

        // ── Diff ──────────────────────────────────────────────────────
        case 'diff':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for diff.';
          }
          return await _callString('diff', {
            'path': path,
            'staged': staged ?? false,
          });

        // ── Branch ────────────────────────────────────────────────────
        case 'branch_list':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for branch_list.';
          }
          return await _formatBranchList(path, all: all ?? false);

        case 'branch_create':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for branch_create.';
          }
          if (name == null || name.trim().isEmpty) {
            return 'Error: "name" is required for branch_create.';
          }
          return await _callString('branch_create', {
            'path': path,
            'name': name,
            if (startPoint != null) 'start_point': startPoint,
          });

        case 'branch_delete':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for branch_delete.';
          }
          if (name == null || name.trim().isEmpty) {
            return 'Error: "name" is required for branch_delete.';
          }
          return await _callString('branch_delete', {
            'path': path,
            'name': name,
            'force': force ?? false,
          });

        case 'branch_rename':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for branch_rename.';
          }
          if (oldName == null || oldName.trim().isEmpty) {
            return 'Error: "old_name" is required for branch_rename.';
          }
          if (newName == null || newName.trim().isEmpty) {
            return 'Error: "new_name" is required for branch_rename.';
          }
          return await _callString('branch_rename', {
            'path': path,
            'old_name': oldName,
            'new_name': newName,
          });

        // ── Checkout ──────────────────────────────────────────────────
        case 'checkout':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for checkout.';
          }
          if (name == null || name.trim().isEmpty) {
            return 'Error: "name" is required for checkout (branch or commit).';
          }
          return await _callString('checkout', {
            'path': path,
            'name': name,
            'create_branch': createBranch ?? false,
          });

        // ── Merge ─────────────────────────────────────────────────────
        case 'merge':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for merge.';
          }
          if (branch == null || branch.trim().isEmpty) {
            return 'Error: "branch" is required for merge.';
          }
          return await _callString('merge', {
            'path': path,
            'branch': branch,
          });

        // ── Pull / Push ───────────────────────────────────────────────
        case 'pull':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for pull.';
          }
          return await _callString('pull', {
            'path': path,
            'remote': remote ?? 'origin',
            if (branch != null) 'branch': branch,
            if (username != null) 'username': username,
            if (password != null) 'password': password,
          });

        case 'push':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for push.';
          }
          return await _callString('push', {
            'path': path,
            'remote': remote ?? 'origin',
            if (branch != null) 'branch': branch,
            'force': force ?? false,
            'tags': tags ?? false,
            if (username != null) 'username': username,
            if (password != null) 'password': password,
          });

        // ── Remote ────────────────────────────────────────────────────
        case 'remote_list':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for remote_list.';
          }
          return await _formatRemoteList(path);

        case 'remote_add':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for remote_add.';
          }
          if (name == null || name.trim().isEmpty) {
            return 'Error: "name" is required for remote_add.';
          }
          if (url == null || url.trim().isEmpty) {
            return 'Error: "url" is required for remote_add.';
          }
          return await _callString('remote_add', {
            'path': path,
            'name': name,
            'url': url,
          });

        case 'remote_remove':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for remote_remove.';
          }
          if (name == null || name.trim().isEmpty) {
            return 'Error: "name" is required for remote_remove.';
          }
          return await _callString('remote_remove', {
            'path': path,
            'name': name,
          });

        // ── Stash ─────────────────────────────────────────────────────
        case 'stash_create':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for stash_create.';
          }
          return await _callString('stash_create', {
            'path': path,
            if (message != null) 'message': message,
            'include_untracked': includeUntracked ?? false,
          });

        case 'stash_list':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for stash_list.';
          }
          return await _formatStashList(path);

        case 'stash_apply':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for stash_apply.';
          }
          return await _callString('stash_apply', {
            'path': path,
            'stash_ref': stashRef ?? 'stash@{0}',
            'drop': drop ?? false,
          });

        case 'stash_drop':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for stash_drop.';
          }
          return await _callString('stash_drop', {
            'path': path,
            'stash_ref': stashRef ?? 'stash@{0}',
          });

        // ── Tag ───────────────────────────────────────────────────────
        case 'tag_list':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for tag_list.';
          }
          return await _formatTagList(path);

        case 'tag_create':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for tag_create.';
          }
          if (name == null || name.trim().isEmpty) {
            return 'Error: "name" is required for tag_create.';
          }
          return await _callString('tag_create', {
            'path': path,
            'name': name,
            if (message != null) 'message': message,
          });

        case 'tag_delete':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for tag_delete.';
          }
          if (name == null || name.trim().isEmpty) {
            return 'Error: "name" is required for tag_delete.';
          }
          return await _callString('tag_delete', {
            'path': path,
            'name': name,
          });

        // ── Reset / Clean ─────────────────────────────────────────────
        case 'reset':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for reset.';
          }
          final resetMode = mode ?? 'mixed';
          if (!const {'soft', 'mixed', 'hard'}.contains(resetMode)) {
            return 'Error: Invalid reset mode "$resetMode". Use soft, mixed, or hard.';
          }
          return await _callString('reset', {
            'path': path,
            'mode': resetMode,
            'ref': ref ?? 'HEAD',
          });

        case 'clean':
          if (path == null || path.trim().isEmpty) {
            return 'Error: "path" is required for clean.';
          }
          return await _callString('clean', {
            'path': path,
            'directories': directories ?? false,
            'force': force ?? false,
            'dry_run': dryRun ?? false,
          });

        default:
          return 'Error: Unknown git action "$action". '
              'Supported: init, clone, status, add, remove, commit, log, diff, '
              'branch_list, branch_create, branch_delete, branch_rename, '
              'checkout, merge, pull, push, remote_list, remote_add, remote_remove, '
              'stash_create, stash_list, stash_apply, stash_drop, '
              'tag_list, tag_create, tag_delete, reset, clean.';
      }
    } on PlatformException catch (e) {
      return 'Error: ${e.message ?? e.toString()}';
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────

  /// Call the platform channel and return the string result.
  static Future<String> _callString(
    String method,
    Map<String, dynamic> args,
  ) async {
    final result = await _channel.invokeMethod<dynamic>(method, args);
    if (result == null) return 'Error: No response from git service.';
    if (result is String) return result;
    return result.toString();
  }

  /// Format the status map returned from JGit into a readable string.
  static Future<String> _formatStatus(String path) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'status',
      {'path': path},
    );
    if (result == null) return 'Error: Could not get status.';

    final branch = result['branch'] ?? '(unknown)';
    final isClean = result['is_clean'] as bool? ?? true;

    final buf = StringBuffer();
    buf.writeln('On branch $branch');

    if (isClean) {
      buf.writeln('Nothing to commit, working tree clean.');
      return buf.toString().trim();
    }

    void writeSection(String label, List<dynamic>? items) {
      if (items != null && items.isNotEmpty) {
        buf.writeln('\n$label:');
        for (final item in items) {
          buf.writeln('  $item');
        }
      }
    }

    writeSection('Staged (new files)', result['staged_added'] as List<dynamic>?);
    writeSection('Staged (modified)', result['staged_changed'] as List<dynamic>?);
    writeSection('Staged (deleted)', result['staged_removed'] as List<dynamic>?);
    writeSection('Unstaged (modified)', result['unstaged_modified'] as List<dynamic>?);
    writeSection('Unstaged (deleted)', result['unstaged_deleted'] as List<dynamic>?);
    writeSection('Untracked files', result['untracked'] as List<dynamic>?);
    writeSection('Conflicting', result['conflicting'] as List<dynamic>?);

    return buf.toString().trim();
  }

  /// Format the log list from JGit into a readable string.
  static Future<String> _formatLog(String path, {int maxCount = 20}) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'log',
      {'path': path, 'max_count': maxCount},
    );
    if (result == null || result.isEmpty) {
      return 'No commits found.';
    }

    final buf = StringBuffer();
    buf.writeln('Commit log (${result.length} commits):');
    for (final entry in result) {
      final m = Map<String, dynamic>.from(entry as Map);
      buf.writeln();
      buf.writeln('commit ${m['hash'] ?? ''}');
      buf.writeln('Author: ${m['author'] ?? ''}');
      buf.writeln('');
      // Indent the message
      final msg = (m['message'] as String? ?? '').trim();
      for (final line in msg.split('\n')) {
        buf.writeln('    $line');
      }
    }
    return buf.toString().trim();
  }

  /// Format the branch list from JGit into a readable string.
  static Future<String> _formatBranchList(String path, {bool all = false}) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'branch_list',
      {'path': path, 'all': all},
    );
    if (result == null) return 'Error: Could not list branches.';

    final branches = result['branches'] as List<dynamic>? ?? [];

    if (branches.isEmpty) return 'No branches found.';

    final buf = StringBuffer();
    buf.writeln('Branches${all ? ' (all)' : ''}:');
    for (final entry in branches) {
      final m = Map<String, dynamic>.from(entry as Map);
      final name = m['name'] ?? '';
      final isCurrent = m['is_current'] as bool? ?? false;
      final hash = m['hash'] ?? '';
      buf.writeln('  ${isCurrent ? '* ' : '  '}$name ($hash)');
    }
    return buf.toString().trim();
  }

  /// Format the remote list from JGit into a readable string.
  static Future<String> _formatRemoteList(String path) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'remote_list',
      {'path': path},
    );
    if (result == null || result.isEmpty) {
      return 'No remotes configured.';
    }

    final buf = StringBuffer();
    buf.writeln('Remotes:');
    for (final entry in result) {
      final m = Map<String, dynamic>.from(entry as Map);
      buf.writeln('  ${m['name'] ?? ''}  ${m['url'] ?? ''}');
    }
    return buf.toString().trim();
  }

  /// Format the stash list from JGit into a readable string.
  static Future<String> _formatStashList(String path) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'stash_list',
      {'path': path},
    );
    if (result == null || result.isEmpty) {
      return 'No stashes.';
    }

    final buf = StringBuffer();
    buf.writeln('Stashes:');
    for (final entry in result) {
      final m = Map<String, dynamic>.from(entry as Map);
      buf.writeln('  ${m['index'] ?? ''}  ${m['hash'] ?? ''}  ${m['message'] ?? ''}');
    }
    return buf.toString().trim();
  }

  /// Format the tag list from JGit into a readable string.
  static Future<String> _formatTagList(String path) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'tag_list',
      {'path': path},
    );
    if (result == null || result.isEmpty) {
      return 'No tags.';
    }

    final buf = StringBuffer();
    buf.writeln('Tags:');
    for (final entry in result) {
      final m = Map<String, dynamic>.from(entry as Map);
      buf.writeln('  ${m['name'] ?? ''}  (${m['hash'] ?? ''})');
    }
    return buf.toString().trim();
  }
}
