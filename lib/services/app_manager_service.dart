import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel for native Android app management operations.
const _channel = MethodChannel('in.arijitk.synapse_flutter/app_manager');

/// Android app manager service.
///
/// Provides access to installed applications on the device: listing apps,
/// launching them, querying app details, searching by name, and opening
/// system app settings.
class AppManagerService {
  // ── Public entry point ────────────────────────────────────────────────

  /// Execute an app-manager action and return a human-readable result string.
  static Future<String> execute({
    required String action,
    String? packageName,
    String? query,
    bool includeSystemApps = false,
    int? limit,
  }) async {
    if (kIsWeb) {
      return 'Error: App manager is not available on web.';
    }

    switch (action) {
      case 'list_apps':
        return _listApps(
          includeSystemApps: includeSystemApps,
          limit: limit,
        );
      case 'search_apps':
        if (query == null || query.trim().isEmpty) {
          return 'Error: "query" is required for search_apps.';
        }
        return _searchApps(
          query,
          includeSystemApps: includeSystemApps,
          limit: limit,
        );
      case 'app_info':
        if (packageName == null || packageName.trim().isEmpty) {
          return 'Error: "package_name" is required for app_info.';
        }
        return _appInfo(packageName);
      case 'launch_app':
        if (packageName == null || packageName.trim().isEmpty) {
          return 'Error: "package_name" is required for launch_app.';
        }
        return _launchApp(packageName);
      case 'is_installed':
        if (packageName == null || packageName.trim().isEmpty) {
          return 'Error: "package_name" is required for is_installed.';
        }
        return _isInstalled(packageName);
      case 'open_app_settings':
        if (packageName == null || packageName.trim().isEmpty) {
          return 'Error: "package_name" is required for open_app_settings.';
        }
        return _openAppSettings(packageName);
      default:
        return 'Error: Unknown action "$action". '
            'Supported: list_apps, search_apps, app_info, launch_app, '
            'is_installed, open_app_settings.';
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// List all installed apps.
  static Future<String> _listApps({
    bool includeSystemApps = false,
    int? limit,
  }) async {
    try {
      final apps = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
        {'includeSystemApps': includeSystemApps},
      );
      if (apps == null || apps.isEmpty) {
        return 'No installed apps found.';
      }

      // Sort by app name alphabetically.
      final appList = apps
          .map((a) => Map<String, dynamic>.from(a as Map))
          .toList()
        ..sort((a, b) => (a['appName'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['appName'] as String? ?? '').toLowerCase()));

      final effectiveLimit = (limit != null && limit > 0) ? limit : null;
      final displayApps = effectiveLimit != null
          ? appList.take(effectiveLimit).toList()
          : appList;
      final truncated = effectiveLimit != null && appList.length > effectiveLimit;

      final buf = StringBuffer();
      buf.writeln(
          'Installed apps (${displayApps.length}${truncated ? ' of ${appList.length}' : ''}):');
      buf.writeln();

      for (final app in displayApps) {
        final name = app['appName'] ?? 'Unknown';
        final pkg = app['packageName'] ?? '';
        final version = app['versionName'] ?? '';
        final isSystem = app['isSystemApp'] == true;
        buf.writeln('  $name');
        buf.writeln('    Package: $pkg');
        if (version.isNotEmpty) {
          buf.writeln('    Version: $version');
        }
        if (isSystem) {
          buf.writeln('    Type: System app');
        }
        buf.writeln();
      }

      if (truncated) {
        buf.writeln('... limit reached. Use a higher "limit" to see more, '
            'or use "search_apps" to find specific apps.');
      }

      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to list installed apps -- $e';
    }
  }

  /// Search installed apps by name or package name.
  static Future<String> _searchApps(
    String query, {
    bool includeSystemApps = false,
    int? limit,
  }) async {
    try {
      final apps = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
        {'includeSystemApps': includeSystemApps},
      );
      if (apps == null || apps.isEmpty) {
        return 'No installed apps found.';
      }

      final queryLower = query.toLowerCase();
      final matches = apps
          .map((a) => Map<String, dynamic>.from(a as Map))
          .where((app) {
        final name = (app['appName'] as String? ?? '').toLowerCase();
        final pkg = (app['packageName'] as String? ?? '').toLowerCase();
        return name.contains(queryLower) || pkg.contains(queryLower);
      }).toList()
        ..sort((a, b) => (a['appName'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['appName'] as String? ?? '').toLowerCase()));

      if (matches.isEmpty) {
        return 'No apps found matching "$query".';
      }

      final effectiveLimit = (limit != null && limit > 0) ? limit : null;
      final displayApps = effectiveLimit != null
          ? matches.take(effectiveLimit).toList()
          : matches;
      final truncated = effectiveLimit != null && matches.length > effectiveLimit;

      final buf = StringBuffer();
      buf.writeln(
          'Apps matching "$query" (${displayApps.length}${truncated ? ' of ${matches.length}' : ''} results):');
      buf.writeln();

      for (final app in displayApps) {
        final name = app['appName'] ?? 'Unknown';
        final pkg = app['packageName'] ?? '';
        final version = app['versionName'] ?? '';
        final isSystem = app['isSystemApp'] == true;
        buf.writeln('  $name');
        buf.writeln('    Package: $pkg');
        if (version.isNotEmpty) {
          buf.writeln('    Version: $version');
        }
        if (isSystem) {
          buf.writeln('    Type: System app');
        }
        buf.writeln();
      }

      if (truncated) {
        buf.writeln('... limit reached.');
      }

      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to search apps -- $e';
    }
  }

  /// Get detailed info about a specific app by package name.
  static Future<String> _appInfo(String packageName) async {
    try {
      final info = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAppInfo',
        {'packageName': packageName},
      );
      if (info == null) {
        return 'Error: App not found: $packageName';
      }

      final data = Map<String, dynamic>.from(info);
      final buf = StringBuffer();
      buf.writeln('App: ${data['appName'] ?? 'Unknown'}');
      buf.writeln('Package: ${data['packageName'] ?? packageName}');
      if (data['versionName'] != null) {
        buf.writeln('Version: ${data['versionName']}');
      }
      if (data['versionCode'] != null) {
        buf.writeln('Version code: ${data['versionCode']}');
      }
      if (data['targetSdkVersion'] != null) {
        buf.writeln('Target SDK: ${data['targetSdkVersion']}');
      }
      if (data['minSdkVersion'] != null) {
        buf.writeln('Min SDK: ${data['minSdkVersion']}');
      }
      buf.writeln('System app: ${data['isSystemApp'] == true ? 'Yes' : 'No'}');
      buf.writeln('Enabled: ${data['isEnabled'] == true ? 'Yes' : 'No'}');
      if (data['installedAt'] != null) {
        buf.writeln('Installed: ${_formatTimestamp(data['installedAt'] as int)}');
      }
      if (data['updatedAt'] != null) {
        buf.writeln('Last updated: ${_formatTimestamp(data['updatedAt'] as int)}');
      }
      if (data['dataDir'] != null) {
        buf.writeln('Data dir: ${data['dataDir']}');
      }
      if (data['permissions'] != null) {
        final permissions = (data['permissions'] as List<dynamic>?)
            ?.map((p) => p.toString())
            .toList();
        if (permissions != null && permissions.isNotEmpty) {
          buf.writeln('Permissions (${permissions.length}):');
          for (final perm in permissions) {
            // Show short permission name (strip android.permission. prefix).
            final short =
                perm.replaceFirst('android.permission.', '');
            buf.writeln('  - $short');
          }
        }
      }

      return buf.toString().trim();
    } catch (e) {
      return 'Error: Failed to get app info -- $e';
    }
  }

  /// Launch an app by its package name.
  static Future<String> _launchApp(String packageName) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        'launchApp',
        {'packageName': packageName},
      );
      if (success == true) {
        return 'Launched app: $packageName';
      } else {
        return 'Error: Could not launch app "$packageName". '
            'It may not have a launchable activity.';
      }
    } catch (e) {
      return 'Error: Failed to launch app -- $e';
    }
  }

  /// Check if an app is installed.
  static Future<String> _isInstalled(String packageName) async {
    try {
      final installed = await _channel.invokeMethod<bool>(
        'isAppInstalled',
        {'packageName': packageName},
      );
      if (installed == true) {
        return 'App is installed: $packageName';
      } else {
        return 'App is NOT installed: $packageName';
      }
    } catch (e) {
      return 'Error: Failed to check if app is installed -- $e';
    }
  }

  /// Open the system settings page for a specific app.
  static Future<String> _openAppSettings(String packageName) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        'openAppSettings',
        {'packageName': packageName},
      );
      if (success == true) {
        return 'Opened system settings for: $packageName';
      } else {
        return 'Error: Could not open settings for "$packageName".';
      }
    } catch (e) {
      return 'Error: Failed to open app settings -- $e';
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static String _formatTimestamp(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
