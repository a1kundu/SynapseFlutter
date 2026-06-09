import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_update.dart';
import '../main.dart' show navigatorKey;
import '../version.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class AppUpdate {
  final int buildNumber;
  final String version;
  final String tagName;
  final String downloadUrl;
  final int sizeBytes;
  final String releaseName;
  final String changelog;

  const AppUpdate({
    required this.buildNumber,
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.releaseName,
    required this.changelog,
  });
}

// ---------------------------------------------------------------------------
// Service (business logic only)
// ---------------------------------------------------------------------------

class UpdateService {
  static const owner = 'a1kundu';
  static const repo = 'SynapseFlutter';
  static const repoUrl = 'https://github.com/$owner/$repo';
  static const _autoUpdateKey = 'autoUpdateCheck';

  static const _prNumber =
      String.fromEnvironment('PR_NUMBER', defaultValue: '');

  static String get channel {
    if (_prNumber.isNotEmpty) return 'pr$_prNumber';
    return kDebugMode ? 'debug' : 'release';
  }

  static Future<bool> isAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoUpdateKey) ?? true;
  }

  static Future<void> setAutoUpdateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoUpdateKey, enabled);
  }

  static int? get currentBuildNumber {
    if (appVersion == 'APP_VERSION_PLACEHOLDER') return null;
    return int.tryParse(appVersion.split('.').first);
  }

  static Future<AppUpdate?> checkForUpdate() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid) return null;

    try {
      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(
          Uri.parse('https://api.github.com/repos/$owner/$repo/releases'),
        );
        request.headers.set('Accept', 'application/vnd.github+json');
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

        if (response.statusCode != 200) return null;

        final body = await response.transform(utf8.decoder).join();
        final List<dynamic> releases = jsonDecode(body);
        final ch = channel;

        AppUpdate? latest;

        for (final release in releases) {
          final tag = release['tag_name'] as String? ?? '';
          if (!tag.contains('-$ch-')) continue;

          final buildNum = _extractBuildNumber(tag);
          if (buildNum == null) continue;

          final assets = release['assets'] as List<dynamic>? ?? [];
          final apkAsset = assets
              .cast<Map<String, dynamic>>()
              .where((a) => (a['name'] as String? ?? '').endsWith('.apk'))
              .firstOrNull;
          if (apkAsset == null) continue;

          if (latest == null || buildNum > latest.buildNumber) {
            latest = AppUpdate(
              buildNumber: buildNum,
              version: _extractVersion(tag),
              tagName: tag,
              downloadUrl: apkAsset['browser_download_url'] as String,
              sizeBytes: apkAsset['size'] as int? ?? 0,
              releaseName: release['name'] as String? ?? '',
              changelog: _extractChangelog(release['body'] as String? ?? ''),
            );
          }
        }

        if (latest == null) return null;

        final current = currentBuildNumber;
        if (current == null || latest.buildNumber > current) {
          return latest;
        }
        return null;
      } finally {
        httpClient.close();
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  static String apkFileName(AppUpdate update) {
    return 'synapse-$channel-${update.version}.apk';
  }

  static Future<Directory> _downloadDir() async {
    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File?> getExistingApk(AppUpdate update) async {
    final dir = await _downloadDir();
    final file = File('${dir.path}/${apkFileName(update)}');
    if (await file.exists()) {
      final length = await file.length();
      if (update.sizeBytes > 0 && length == update.sizeBytes) return file;
      if (update.sizeBytes <= 0 && length > 0) return file;
      await file.delete();
    }
    return null;
  }

  static Future<void> installApk(File file) async {
    await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
  }

  static Future<void> downloadAndInstall(
    AppUpdate update, {
    ValueChanged<double>? onProgress,
    ValueChanged<List<String>>? onCleaned,
    int maxRetries = 5,
    bool Function()? isCancelled,
  }) async {
    final existing = await getExistingApk(update);
    if (existing != null) {
      onProgress?.call(1.0);
      await installApk(existing);
      return;
    }

    final dir = await _downloadDir();
    final fileName = apkFileName(update);
    final file = File('${dir.path}/$fileName');
    final partFile = File('${dir.path}/$fileName.part');

    final cleaned = await _cleanOldApks(dir, fileName);
    if (cleaned.isNotEmpty) onCleaned?.call(cleaned);

    final totalBytes = update.sizeBytes;
    int attempt = 0;

    while (true) {
      if (isCancelled?.call() == true) {
        throw Exception('Download cancelled');
      }

      HttpClient? httpClient;
      try {
        int alreadyReceived = 0;
        if (await partFile.exists()) {
          alreadyReceived = await partFile.length();
          if (totalBytes > 0 && alreadyReceived >= totalBytes) {
            await partFile.delete();
            alreadyReceived = 0;
          }
        }

        httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(update.downloadUrl));

        if (alreadyReceived > 0) {
          request.headers.set('Range', 'bytes=$alreadyReceived-');
        }

        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('Download failed: HTTP ${response.statusCode}');
        }

        if (response.statusCode == 200 && alreadyReceived > 0) {
          await partFile.delete();
          alreadyReceived = 0;
        }

        final sink = partFile.openWrite(
          mode: alreadyReceived > 0 ? FileMode.append : FileMode.write,
        );
        int received = alreadyReceived;

        try {
          await for (final chunk in response) {
            if (isCancelled?.call() == true) {
              throw Exception('Download cancelled');
            }
            sink.add(chunk);
            received += chunk.length;
            if (totalBytes > 0) {
              onProgress?.call(received / totalBytes);
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        if (totalBytes > 0 && received < totalBytes) {
          throw Exception(
            'Incomplete download ($received / $totalBytes bytes)',
          );
        }

        final partLen = await partFile.length();
        if (totalBytes > 0 && partLen != totalBytes) {
          await partFile.delete();
          throw Exception(
            'File verification failed (disk: $partLen, expected: $totalBytes bytes)',
          );
        }

        await partFile.rename(file.path);
        onProgress?.call(1.0);
        await installApk(file);
        return;
      } catch (e) {
        if (e.toString().contains('Download cancelled')) rethrow;

        attempt++;
        httpClient?.close(force: true);

        if (attempt >= maxRetries) {
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
          rethrow;
        }

        final delay = Duration(seconds: 1 << attempt);
        debugPrint(
          'Download interrupted (attempt $attempt/$maxRetries), '
          'retrying in ${delay.inSeconds}s: $e',
        );
        await Future.delayed(delay);
      }
    }
  }

  static Future<List<String>> _cleanOldApks(
    Directory dir,
    String currentName,
  ) async {
    final deleted = <String>[];
    final prefix = 'synapse-$channel-';
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith(prefix) &&
              name.endsWith('.apk') &&
              name != currentName) {
            final version = name
                .replaceFirst(prefix, '')
                .replaceFirst('.apk', '');
            await entity.delete();
            deleted.add(version);
          }
        }
      }
    } catch (_) {}
    return deleted;
  }

  static int? _extractBuildNumber(String tag) {
    final match = RegExp(r'^v(\d+)-').firstMatch(tag);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  static String _extractVersion(String tag) {
    final parts = tag.substring(1).split('-');
    if (parts.length >= 3) {
      return '${parts[0]}.0.0-${parts.last}';
    }
    return tag;
  }

  static String _extractChangelog(String body) {
    final idx = body.indexOf('### Changelog');
    if (idx >= 0) {
      return body.substring(idx + '### Changelog'.length).trim();
    }
    final bullets = body
        .split('\n')
        .where(
          (l) => l.trimLeft().startsWith('•') || l.trimLeft().startsWith('- '),
        )
        .join('\n');
    return bullets;
  }
}

// ---------------------------------------------------------------------------
// Download Manager – singleton that survives dialog dismissal
// ---------------------------------------------------------------------------

const _downloadNotifId = 42;
const _downloadChannelId = 'download_progress';
const _downloadChannelName = 'Download Progress';

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final ValueNotifier<double> progress = ValueNotifier(0);

  AppUpdate? activeUpdate;

  bool get isDownloading => _downloading;
  bool _downloading = false;

  String? error;
  bool completed = false;
  bool _cancelled = false;

  DateTime? startTime;

  double _speedBps = 0;
  double _lastProgress = 0;
  DateTime _lastSpeedSample = DateTime.now();

  bool _foregroundServiceRunning = false;
  DateTime _lastNotifUpdate = DateTime.now();

  String get remainingFormatted {
    if (_speedBps <= 0 || activeUpdate == null) return '';
    final remainingBytes = (1.0 - progress.value) * activeUpdate!.sizeBytes;
    if (remainingBytes <= 0) return '';
    final secondsLeft = (remainingBytes / _speedBps).round();
    if (secondsLeft <= 0) return '';
    if (secondsLeft >= 3600) {
      final h = secondsLeft ~/ 3600;
      final m = (secondsLeft % 3600) ~/ 60;
      return '${h}h ${m}m left';
    }
    if (secondsLeft >= 60) {
      final m = secondsLeft ~/ 60;
      final s = secondsLeft % 60;
      return '${m}m ${s}s left';
    }
    return '${secondsLeft}s left';
  }

  String get speedFormatted {
    if (_speedBps <= 0) return '';
    if (_speedBps >= 1024 * 1024) {
      return '${(_speedBps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(_speedBps / 1024).toStringAsFixed(0)} KB/s';
  }

  FlutterLocalNotificationsPlugin? _notifPlugin;
  bool _notifInitialized = false;

  Future<void> initNotifications() async {
    if (_notifInitialized) return;
    if (kIsWeb) return;
    _notifPlugin = FlutterLocalNotificationsPlugin();
    await _notifPlugin!.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    await _notifPlugin!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _notifInitialized = true;
  }

  FlutterLocalNotificationsPlugin _getNotifPluginSync() {
    if (_notifPlugin == null) {
      _notifPlugin = FlutterLocalNotificationsPlugin();
      _notifPlugin!.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
        ),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
    }
    return _notifPlugin!;
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == 'download_complete') {
      _installCompletedUpdate();
      return;
    }
    if (response.payload != 'download_progress') return;
    _reopenDownloadDialog();
  }

  Future<void> _installCompletedUpdate() async {
    final update = activeUpdate;
    if (update == null) return;
    final apk = await UpdateService.getExistingApk(update);
    if (apk != null) {
      await UpdateService.installApk(apk);
    }
  }

  void _reopenDownloadDialog() {
    final update = activeUpdate;
    if (update == null) return;
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => DownloadProgressDialog(update: update),
    );
  }

  Future<void> start(AppUpdate update) async {
    if (_downloading && activeUpdate?.tagName == update.tagName) return;

    activeUpdate = update;
    _downloading = true;
    _cancelled = false;
    error = null;
    completed = false;
    progress.value = 0;
    startTime = DateTime.now();
    _speedBps = 0;
    _lastProgress = 0;
    _lastSpeedSample = DateTime.now();
    _lastNotifUpdate = DateTime.now();

    // Start foreground service to maintain download speed in background
    await _startForeground(update);

    try {
      await UpdateService.downloadAndInstall(
        update,
        onProgress: (p) {
          _updateSpeed(p, update.sizeBytes);
          progress.value = p;
          _throttledNotifUpdate(update, p);
        },
        isCancelled: () => _cancelled,
      );
      completed = true;
    } catch (e) {
      if (!_cancelled) {
        error = e.toString();
      }
    } finally {
      _downloading = false;
      await _stopForeground();
      if (completed) {
        await _showCompletedNotification(update);
      } else if (!_cancelled) {
        await _showFailedNotification(update);
      }
    }
  }

  void cancel() {
    _cancelled = true;
    _stopForeground();
  }

  void reset() {
    activeUpdate = null;
    error = null;
    completed = false;
    progress.value = 0;
    startTime = null;
    _speedBps = 0;
  }

  void _updateSpeed(double p, int totalBytes) {
    final now = DateTime.now();
    final dt = now.difference(_lastSpeedSample).inMilliseconds;
    if (dt > 500) {
      final bytesInInterval = (p - _lastProgress) * totalBytes;
      final instantSpeed = bytesInInterval / (dt / 1000);
      _speedBps = _speedBps == 0
          ? instantSpeed
          : _speedBps * 0.7 + instantSpeed * 0.3;
      _lastProgress = p;
      _lastSpeedSample = now;
    }
  }

  // ---- Foreground service for background download speed ----

  Future<void> _startForeground(AppUpdate update) async {
    if (kIsWeb) return;
    try {
      await initNotifications();
      final androidPlugin = _getNotifPluginSync()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin == null) return;

      // Ensure POST_NOTIFICATIONS is granted before starting the foreground
      // service.  PR / sideloaded builds have a unique application-id, so
      // Android treats them as a brand-new app without any pre-granted
      // permissions.  Re-requesting here is safe: the system returns
      // immediately if the permission was already granted.
      await androidPlugin.requestNotificationsPermission();

      await androidPlugin.startForegroundService(
        _downloadNotifId,
        'Downloading update v${update.version}',
        'Starting download\u2026',
        notificationDetails: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelName,
          channelDescription: 'Shows download progress for app updates',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          maxProgress: 100,
          progress: 0,
          largeIcon: const DrawableResourceAndroidBitmap(
            'ic_notification_large',
          ),
          color: const Color(0xFF673AB7), // deepPurple
          actions: [
            const AndroidNotificationAction(
              'cancel_download',
              'Cancel',
              showsUserInterface: false,
            ),
          ],
        ),
        payload: 'download_progress',
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
      _foregroundServiceRunning = true;
    } catch (e) {
      debugPrint('Failed to start foreground service: $e');
    }
  }

  Future<void> _stopForeground() async {
    if (!_foregroundServiceRunning) return;
    if (kIsWeb) return;
    try {
      final androidPlugin = _getNotifPluginSync()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.stopForegroundService();
    } catch (e) {
      debugPrint('Failed to stop foreground service: $e');
    }
    _foregroundServiceRunning = false;
  }

  void _throttledNotifUpdate(AppUpdate update, double p) {
    final now = DateTime.now();
    if (now.difference(_lastNotifUpdate).inMilliseconds < 500) return;
    _lastNotifUpdate = now;
    _updateForegroundNotification(update, p);
  }

  Future<void> _updateForegroundNotification(AppUpdate update, double p) async {
    if (!_foregroundServiceRunning) return;
    if (kIsWeb) return;

    final plugin = _getNotifPluginSync();
    final percent = (p * 100).round();
    final totalMb = (update.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final dlMb = (p * update.sizeBytes / (1024 * 1024)).toStringAsFixed(1);

    final remaining = remainingFormatted;
    final speed = speedFormatted;
    final subText = [
      '$dlMb / $totalMb MB \u2014 $percent%',
      if (remaining.isNotEmpty) remaining,
      if (speed.isNotEmpty) speed,
    ].join(' \u00B7 ');

    await plugin.show(
      _downloadNotifId,
      'Downloading update v${update.version}',
      subText,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelName,
          channelDescription: 'Shows download progress for app updates',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          largeIcon: const DrawableResourceAndroidBitmap(
            'ic_notification_large',
          ),
          color: const Color(0xFF673AB7), // deepPurple
          actions: [
            const AndroidNotificationAction(
              'cancel_download',
              'Cancel',
              showsUserInterface: false,
            ),
          ],
        ),
      ),
      payload: 'download_progress',
    );
  }

  Future<void> _showCompletedNotification(AppUpdate update) async {
    if (kIsWeb) return;
    final plugin = _getNotifPluginSync();
    await plugin.show(
      _downloadNotifId,
      'Update ready',
      'v${update.version} downloaded — tap to install',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
          color: Color(0xFF673AB7), // deepPurple
        ),
      ),
      payload: 'download_complete',
    );
  }

  Future<void> _showFailedNotification(AppUpdate update) async {
    if (kIsWeb) return;
    final plugin = _getNotifPluginSync();
    await plugin.show(
      _downloadNotifId,
      'Download failed',
      'v${update.version} — open app to retry',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
          color: Color(0xFF673AB7), // deepPurple
        ),
      ),
      payload: 'download_progress',
    );
  }
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------

Future<void> showUpdateDialog(BuildContext context, AppUpdate update) async {
  final sizeMb = (update.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
  final existingApk = await UpdateService.getExistingApk(update);
  final alreadyDownloaded = existingApk != null;

  if (!context.mounted) return;

  final shouldProceed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      bool dontShowAgain = false;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: const Icon(Icons.system_update, size: 36),
          title: const Text('Update Available'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420, maxWidth: 340),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(update.releaseName),
                  const SizedBox(height: 8),
                  Text(
                    'Version: ${update.version}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  Text(
                    'Size: $sizeMb MB',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  Text(
                    'Channel: ${UpdateService.channel}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  if (alreadyDownloaded) ...[
                    const SizedBox(height: 8),
                    Text(
                      'APK already downloaded — ready to install.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                  ],
                  if (update.changelog.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'What\'s New',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const Divider(),
                    Text(
                      update.changelog,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: dontShowAgain,
                          onChanged: (v) =>
                              setDialogState(() => dontShowAgain = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(
                            () => dontShowAgain = !dontShowAgain,
                          ),
                          child: Text(
                            'Don\'t remind me again',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (dontShowAgain)
                    Padding(
                      padding: const EdgeInsets.only(left: 32, top: 2),
                      child: Text(
                        'You can re-enable this in Settings -> Updates.',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.outline,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (dontShowAgain) {
                  UpdateService.setAutoUpdateEnabled(false);
                  BackgroundUpdateManager.cancel();
                }
                Navigator.pop(ctx, false);
              },
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: Icon(
                alreadyDownloaded ? Icons.install_mobile : Icons.download,
              ),
              label: Text(alreadyDownloaded ? 'Install' : 'Download & Install'),
            ),
          ],
        ),
      );
    },
  );

  if (shouldProceed != true || !context.mounted) return;

  if (alreadyDownloaded) {
    await UpdateService.installApk(existingApk);
    return;
  }

  final dm = DownloadManager.instance;

  if (!dm.isDownloading || dm.activeUpdate?.tagName != update.tagName) {
    dm.reset();
  }

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => DownloadProgressDialog(update: update),
  );
}

// ---------------------------------------------------------------------------
// Download progress dialog
// ---------------------------------------------------------------------------

class DownloadProgressDialog extends StatefulWidget {
  final AppUpdate update;
  const DownloadProgressDialog({super.key, required this.update});

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog>
    with WidgetsBindingObserver {
  final DownloadManager _dm = DownloadManager.instance;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dm.progress.addListener(_onProgress);

    if (_dm.isDownloading) {
      // Re-attach to existing download
    } else if (_dm.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (_dm.error != null) {
      _error = _dm.error;
    } else {
      _startDownload();
    }
  }

  @override
  void dispose() {
    _dm.progress.removeListener(_onProgress);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  Future<void> _startDownload() async {
    setState(() {
      _error = null;
    });

    await _dm.start(widget.update);

    if (!mounted) return;

    if (_dm.completed) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (_dm.error != null) {
      setState(() => _error = _dm.error);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onCancel() {
    _dm.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AlertDialog(
        icon: const Icon(Icons.error_outline, size: 36),
        title: const Text('Download Failed'),
        content: Text(_error!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    final p = _dm.progress.value;
    final totalMb = (widget.update.sizeBytes / (1024 * 1024)).toStringAsFixed(
      1,
    );
    final downloadedMb = (p * widget.update.sizeBytes / (1024 * 1024))
        .toStringAsFixed(1);

    return PopScope(
      canPop: true,
      child: AlertDialog(
        title: Text('Downloading Update v${widget.update.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400, maxWidth: 340),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: p > 0 ? p : null,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text('$downloadedMb / $totalMb MB'),
                const SizedBox(height: 4),
                Text(
                  '${(p * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_dm.remainingFormatted.isNotEmpty)
                      Text(
                        _dm.remainingFormatted,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    if (_dm.remainingFormatted.isNotEmpty &&
                        _dm.speedFormatted.isNotEmpty)
                      Text(
                        ' · ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    if (_dm.speedFormatted.isNotEmpty)
                      Text(
                        _dm.speedFormatted,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                  ],
                ),
                if (widget.update.changelog.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'What\'s New',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.update.changelog,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _onCancel,
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.minimize, size: 18),
            label: const Text('Background'),
          ),
        ],
      ),
    );
  }
}
