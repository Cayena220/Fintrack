import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local (on-device) notifications used for budget alerts.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _androidChannel = AndroidNotificationDetails(
    'budget_alerts',
    'Budget alerts',
    channelDescription: 'Warnings when you are close to or over a budget',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (_ready || !(Platform.isAndroid || Platform.isWindows)) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: 'FinTrack',
            appUserModelId: 'io.fintrack.FinTrack',
            guid: '6f1c9d1e-6c0a-4f7e-9d0b-3c8a1f2e7b54',
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      // Notifications are a nice-to-have; never block the app on them.
      debugPrint('Notification init failed: $e');
    }
  }

  /// Asks for the Android 13+ notification permission. No-op elsewhere.
  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> show({required int id, required String title, required String body}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: _androidChannel,
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }
}
