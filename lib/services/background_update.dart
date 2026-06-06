import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'update_service.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _taskName = 'backgroundUpdateCheck';
const _channelId = 'app_updates';
const _channelName = 'App Updates';
const _channelDescription = 'Notifications for available app updates';

// ---------------------------------------------------------------------------
// Top-level callback – runs in its own isolate
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _taskName) return true;

    try {
      final enabled = await UpdateService.isAutoUpdateEnabled();
      if (!enabled) return true;

      final update = await UpdateService.checkForUpdate();
      if (update == null) return true;

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
        ),
      );

      final changelogPreview = update.changelog.isNotEmpty
          ? '\n${update.changelog.length > 200 ? '${update.changelog.substring(0, 200)}...' : update.changelog}'
          : '';

      await plugin.show(
        0,
        'Update Available — v${update.version}',
        '${update.releaseName}$changelogPreview',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            largeIcon: const DrawableResourceAndroidBitmap(
              'ic_notification_large',
            ),
            color: const Color(0xFF673AB7), // deepPurple
            styleInformation: changelogPreview.isNotEmpty
                ? BigTextStyleInformation(
                    '${update.releaseName}$changelogPreview',
                  )
                : null,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Background update check failed: $e');
    }
    return true;
  });
}

// ---------------------------------------------------------------------------
// Registration helpers – called from foreground code
// ---------------------------------------------------------------------------

class BackgroundUpdateManager {
  static String get _taskUniqueName => kDebugMode
      ? 'in.arijitk.synapse.debug.backgroundUpdateCheck'
      : 'in.arijitk.synapse.backgroundUpdateCheck';

  /// Initialise the Workmanager plugin. Call once from [main].
  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  /// Register (or re-register) a periodic background update check.
  static Future<void> register() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      _taskName,
      frequency: const Duration(hours: 6),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Cancel the periodic background update check.
  static Future<void> cancel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await Workmanager().cancelByUniqueName(_taskUniqueName);
  }

  /// Sync the worker registration with the current preference.
  static Future<void> syncWithPreference() async {
    final enabled = await UpdateService.isAutoUpdateEnabled();
    if (enabled) {
      await register();
    } else {
      await cancel();
    }
  }
}
