import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'session_storage.dart';
import 'notification_actions.dart';

class LocalReminder {
  LocalReminder(this.recordId, this.title, this.time, {this.reminderId});
  final String? reminderId;
  String get key => reminderId ?? '$recordId:${time.toUtc().toIso8601String()}';
  final String recordId, title;
  final DateTime time;
}

class LocalReminders {
  LocalReminders(this.storage);
  final SessionStorage storage;
  final plugin = FlutterLocalNotificationsPlugin();
  bool enabled = false, initialized = false, precise = false;
  Future<void> pending = Future.value();
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> initialize(
    void Function(String) open,
    void Function(String, String) action,
  ) async {
    if (initialized) return;
    zones.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_selftext'),
      ),
      onDidReceiveBackgroundNotificationResponse: selfTextNotificationAction,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          if (response.actionId?.isNotEmpty == true) {
            action(response.payload!, response.actionId!);
          } else {
            open(response.payload!);
          }
        }
      },
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload != null) {
      final response = launch!.notificationResponse!;
      if (response.actionId?.isNotEmpty == true) {
        action(response.payload!, response.actionId!);
      } else {
        open(response.payload!);
      }
    }
    initialized = true;
  }

  Future<void> enable(
    void Function(String) open,
    void Function(String, String) action, {
    bool requestExactPermission = true,
    bool requestOnlyOnce = false,
  }) async {
    if (!supported) {
      throw StateError('Offline reminders are available in the Android app.');
    }
    await initialize(open, action);
    final allowed = await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!
        .requestNotificationsPermission();
    if (allowed != true) {
      throw StateError('Allow notifications in Android settings first.');
    }
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    if (requestExactPermission &&
        await android.canScheduleExactNotifications() != true &&
        (!requestOnlyOnce ||
            await storage.read(key: 'selftext.exact-requested') != 'true')) {
      await storage.write(key: 'selftext.exact-requested', value: 'true');
      await android.requestExactAlarmsPermission();
    }
    precise = await android.canScheduleExactNotifications() == true;
    enabled = true;
    await storage.write(key: 'selftext.local-reminders', value: 'true');
  }

  Future<void> restore(
    void Function(String) open,
    void Function(String, String) action,
  ) async {
    if (!supported) return;
    enabled = await storage.read(key: 'selftext.local-reminders') == 'true';
    if (enabled) await initialize(open, action);
  }

  Future<void> replace(List<LocalReminder> reminders) {
    if (!enabled) return Future.value();
    final operation = pending.catchError((_) {}).then((_) async {
      if (!enabled) return;
      final minutes = snoozeDuration(
        await storage.read(key: 'selftext.snooze_minutes'),
      );
      final alarm = await storage.read(key: 'selftext.alarm_sound') == 'true';
      final requests = await plugin.pendingNotificationRequests();
      final futureKeys = reminders
          .where((r) => r.time.isAfter(DateTime.now()))
          .map((r) => notificationId(r.key))
          .toSet();
      for (final request in requests) {
        if (!futureKeys.contains(request.id)) {
          await plugin.cancel(id: request.id);
        }
      }
      final future =
          reminders.where((r) => r.time.isAfter(DateTime.now())).toList()
            ..sort((a, b) => a.time.compareTo(b.time));

      final owner = await storage.read(key: 'selftext.user') ?? 'guest';
      final deliveryKey = 'selftext.local-deliveries.$owner';
      final previousDeliveries = await storage.read(key: deliveryKey);
      final deliveries = previousDeliveries == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(previousDeliveries));
      deliveries.removeWhere(
        (_, value) =>
            DateTime.tryParse(
              '$value',
            )?.isBefore(DateTime.now().subtract(const Duration(days: 7))) !=
            false,
      );
      for (final r in future.take(100)) {
        if (r.reminderId != null) {
          deliveries[r.reminderId!] = r.time.toUtc().toIso8601String();
        }
      }
      await storage.write(key: deliveryKey, value: jsonEncode(deliveries));
      for (final reminder in future.take(100)) {
        if (!enabled) return;
        await plugin.zonedSchedule(
          id: notificationId(reminder.key),
          title: 'SelfText reminder',
          body: '${reminder.title}\nChoose Snooze or Dismiss below.',
          scheduledDate: tz.TZDateTime.from(reminder.time, tz.UTC),
          notificationDetails: actionDetails(
            minutes,
            text: reminder.title,
            alarm: alarm,
          ),
          androidScheduleMode: await scheduleMode(plugin),
          payload: jsonEncode({
            'record_id': reminder.recordId,
            if (reminder.reminderId != null) 'reminder_id': reminder.reminderId,
            'owner': await storage.read(key: 'selftext.user') ?? 'guest',
            'title': reminder.title,
            'scheduled_at': reminder.time.toUtc().toIso8601String(),
            'notification_id': notificationId(reminder.key),
          }),
        );
      }
    });
    pending = operation;
    return operation;
  }

  Future<void> clearCompleted(Set<String> openRecordIds) async {
    if (!supported || !initialized) return;
    final alerts = await plugin.getActiveNotifications();
    for (final alert in alerts) {
      var recordId = alert.payload;
      if (recordId == null) continue;
      if (recordId.startsWith('{')) {
        try {
          recordId = jsonDecode(recordId)['record_id'] as String;
        } catch (_) {
          continue;
        }
      }
      if (!openRecordIds.contains(recordId) && alert.id != null) {
        await plugin.cancel(id: alert.id!);
      }
    }
  }

  static NotificationDetails actionDetails(
    int minutes, {
    String? text,
    bool alarm = false,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      alarm ? 'selftext_ringing_v1' : 'selftext_alarm_v3',
      alarm ? 'Ringing alarms' : 'Reminders with actions',
      channelDescription:
          'Choose Snooze or Dismiss directly from the notification',
      icon: 'ic_stat_selftext',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: false,
      ongoing: true,
      category: alarm
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      sound: alarm
          ? const UriAndroidNotificationSound(
              'content://settings/system/alarm_alert',
            )
          : null,
      audioAttributesUsage: alarm
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      additionalFlags: alarm ? Int32List.fromList([4]) : null,
      styleInformation: BigTextStyleInformation(
        text == null
            ? 'Choose an action below'
            : '$text\nChoose Snooze or Dismiss below.',
        summaryText: 'Done · Snooze · Dismiss',
      ),
      actions: [
        AndroidNotificationAction(
          'snooze_$minutes',
          'Snooze $minutes min',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          'dismiss',
          'Dismiss',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    ),
  );

  static Future<AndroidScheduleMode> scheduleMode(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final allowed = await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.canScheduleExactNotifications();
    return allowed == true
        ? AndroidScheduleMode.alarmClock
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static int snoozeDuration(String? value) {
    final minutes = int.tryParse(value ?? '') ?? 10;
    return minutes >= 1 && minutes <= 120 ? minutes : 10;
  }

  static int notificationId(String key) {
    var hash = 2166136261;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  static Future<void> showRemote(
    Map<String, dynamic> data, {
    bool initializePlugin = true,
  }) async {
    if (data['record_id'] is! String || data['reminder_id'] is! String) return;
    const storage = DeviceSessionStorage();
    if (await storage.read(key: 'selftext.push.token') == null) return;
    final owner = await storage.read(key: 'selftext.user');
    if (data['user_id'] != null && data['user_id'] != owner) return;
    final local = await storage.read(
      key: 'selftext.local-deliveries.${owner ?? 'guest'}',
    );
    if (local != null && data['trigger_at'] is String) {
      final scheduled = (jsonDecode(local) as Map)[data['reminder_id']];
      if (scheduled is String &&
          DateTime.parse(
            scheduled,
          ).isAtSameMomentAs(DateTime.parse(data['trigger_at']))) {
        return;
      }
    }
    final previous = await storage.read(
      key: NotificationActions.receiptKey(
        owner ?? 'guest',
        notificationId(data['reminder_id']),
      ),
    );
    if (previous != null) {
      final receipt = jsonDecode(previous) as Map;
      if (receipt['action'] == 'done' || receipt['action'] == 'dismiss') return;
      if ((receipt['action'] as String).startsWith('snooze') &&
          DateTime.parse(receipt['until']).isAfter(DateTime.now())) {
        return;
      }
    }
    final minutes = snoozeDuration(
      await storage.read(key: 'selftext.snooze_minutes'),
    );
    final alerts = FlutterLocalNotificationsPlugin();
    if (initializePlugin) {
      await alerts.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_selftext'),
        ),
        onDidReceiveBackgroundNotificationResponse: selfTextNotificationAction,
      );
    }
    await alerts.show(
      id: notificationId(data['reminder_id']),
      title: 'SelfText reminder',
      body:
          '${data['title'] ?? 'Your reminder'}\nChoose Snooze or Dismiss below.',
      payload: jsonEncode({
        'record_id': data['record_id'],
        'reminder_id': data['reminder_id'],
        'owner': owner,
        'title': data['title'] ?? 'Your reminder',
        'notification_id': notificationId(data['reminder_id']),
      }),
      notificationDetails: actionDetails(
        minutes,
        text: data['title'] ?? 'Your reminder',
        alarm: await storage.read(key: 'selftext.alarm_sound') == 'true',
      ),
    );
  }

  Future<void> disable() async {
    enabled = false;
    await pending.catchError((_) {});
    if (initialized) await plugin.cancelAll();
    await storage.delete(key: 'selftext.local-reminders');
  }
}
