import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification channel used for LLM-triggered notifications.
const _channelId = 'synapse_tool_notify';
const _channelName = 'Synapse Notifications';
const _channelDescription = 'Notifications sent by the AI assistant';

/// Base notification ID — incremented for each notification to avoid overwrites.
int _nextNotifId = 5000;

/// Service for sending local notifications triggered by the LLM via the
/// `notify_user` system tool.
class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();
  NotificationService._();

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  /// Initialize the notification plugin. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;
    _plugin = FlutterLocalNotificationsPlugin();
    await _plugin!.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );
    // Request permission on Android 13+.
    await _plugin!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Send a notification with the given parameters.
  ///
  /// Returns a human-readable status string for the tool result.
  Future<String> notify({
    required String title,
    String? body,
    bool vibrate = true,
    bool playSound = true,
    bool silent = false,
    String priority = 'default',
    String? bigText,
    String? subText,
    String? ticker,
    int? timeoutAfterMs,
  }) async {
    if (kIsWeb) {
      return 'Notifications are not supported on web.';
    }

    try {
      await init();

      final Importance importance;
      final Priority notifPriority;
      switch (priority.toLowerCase()) {
        case 'high':
        case 'urgent':
          importance = Importance.high;
          notifPriority = Priority.high;
        case 'low':
          importance = Importance.low;
          notifPriority = Priority.low;
        case 'min':
          importance = Importance.min;
          notifPriority = Priority.min;
        case 'max':
          importance = Importance.max;
          notifPriority = Priority.max;
        default:
          importance = Importance.defaultImportance;
          notifPriority = Priority.defaultPriority;
      }

      // Vibration pattern: [wait, vibrate, wait, vibrate] in ms.
      final Int64List? vibrationPattern = vibrate
          ? Int64List.fromList([0, 250, 100, 250])
          : null;

      StyleInformation? styleInfo;
      if (bigText != null && bigText.isNotEmpty) {
        styleInfo = BigTextStyleInformation(
          bigText,
          contentTitle: title,
          summaryText: subText,
        );
      }

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: importance,
        priority: notifPriority,
        enableVibration: vibrate,
        vibrationPattern: vibrationPattern,
        playSound: playSound && !silent,
        enableLights: true,
        ledColor: const Color(0xFF673AB7),
        ledOnMs: 1000,
        ledOffMs: 500,
        ticker: ticker ?? title,
        subText: subText,
        styleInformation: styleInfo,
        timeoutAfter: timeoutAfterMs,
        autoCancel: true,
        color: const Color(0xFF673AB7),
        largeIcon: const DrawableResourceAndroidBitmap(
          'ic_notification_large',
        ),
        // Silent mode: no sound, no vibration, no heads-up.
        silent: silent,
      );

      final notifId = _nextNotifId++;
      await _plugin!.show(
        notifId,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );

      return 'Notification sent successfully (id: $notifId).';
    } catch (e) {
      return 'Error sending notification: $e';
    }
  }
}
