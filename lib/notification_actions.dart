import 'dart:convert';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'api.dart';
import 'session_storage.dart';
import 'local_reminders.dart';

/// Runs in a headless Flutter engine. No navigation or Activity is required.
@pragma('vm:entry-point')
void selfTextNotificationAction(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final actions = NotificationActions(const DeviceSessionStorage());
  try {
    await actions.handle(response);
  } catch (_) {
    // Keep the original alert: the user can retry its action without opening UI.
  }
}

class NotificationActions {
  NotificationActions(
    this.storage, {
    SelfTextApi? api,
    FlutterLocalNotificationsPlugin? plugin,
  }) : api = api ?? SelfTextApi(),
       plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final SessionStorage storage;
  final SelfTextApi api;
  final FlutterLocalNotificationsPlugin plugin;
  static const prefix = 'selftext.notification-action.';
  static String receiptKey(String owner, int id) => '$prefix$owner.$id';

  Future<void> handle(NotificationResponse response) async {
    final raw = response.payload, action = response.actionId ?? '';
    if (raw == null ||
        !['done', 'dismiss', 'snooze'].contains(action.split('_').first)) {
      return;
    }
    final data = Map<String, dynamic>.from(jsonDecode(raw));
    final owner = await storage.read(key: 'selftext.user') ?? 'guest';
    if (data['owner'] != owner) return;
    final record = data['record_id'] as String;
    final id = response.id ?? data['notification_id'] as int;
    final minutes = action.startsWith('snooze_')
        ? LocalReminders.snoozeDuration(action.substring(7))
        : 10;
    var until = DateTime.now().add(Duration(minutes: minutes));
    var cloud = false;
    final session = await storage.read(key: 'selftext.session');
    if (session != null &&
        (data['reminder_id'] is String || action == 'dismiss')) {
      api.token = session;
      try {
        if (action == 'done') {
          await api
              .request('PATCH', '/records/$record', {'status': 'done'})
              .timeout(const Duration(seconds: 8));
        } else if (action == 'dismiss') {
          await api
              .request('DELETE', '/records/$record')
              .timeout(const Duration(seconds: 8));
        } else {
          final result = await api
              .request('POST', '/reminders/${data['reminder_id']}/snooze', {
                'minutes': minutes,
              })
              .timeout(const Duration(seconds: 8));
          if (result is Map && result['trigger_at'] is String) {
            until = DateTime.parse(result['trigger_at']);
          }
        }
        cloud = true;
      } catch (error) {
        // A local alarm action must still work offline. Its durable receipt is
        // reconciled with the account on the next sync; no Activity is opened.
        cloud =
            action == 'dismiss' &&
            error is ApiException &&
            error.statusCode == 404;
      } finally {
        api.close();
      }
    }
    if (action.startsWith('snooze')) {
      await plugin.cancel(id: id);
      if (data['reminder_id'] is String) {
        final key = 'selftext.local-deliveries.$owner';
        final saved = await storage.read(key: key);
        final deliveries = saved == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(saved));
        deliveries[data['reminder_id']] = until.toUtc().toIso8601String();
        await storage.write(key: key, value: jsonEncode(deliveries));
      }
      zones.initializeTimeZones();
      await plugin.zonedSchedule(
        id: id,
        title: 'SelfText reminder',
        body: data['title'] ?? 'Your reminder',
        scheduledDate: tz.TZDateTime.from(until, tz.UTC),
        notificationDetails: LocalReminders.actionDetails(
          minutes,
          text: data['title'] ?? 'Your reminder',
          alarm: await storage.read(key: 'selftext.alarm_sound') == 'true',
        ),
        androidScheduleMode: await LocalReminders.scheduleMode(plugin),
        payload: jsonEncode({
          ...data,
          'scheduled_at': until.toUtc().toIso8601String(),
        }),
      );
    }
    if (action == 'done' || action == 'dismiss') {
      for (final notification in await plugin.pendingNotificationRequests()) {
        if (notification.payload?.startsWith('{') == true &&
            jsonDecode(notification.payload!)['record_id'] == record) {
          await plugin.cancel(id: notification.id);
        }
      }
      for (final notification in await plugin.getActiveNotifications()) {
        if (notification.payload?.startsWith('{') == true &&
            jsonDecode(notification.payload!)['record_id'] == record &&
            notification.id != null) {
          await plugin.cancel(id: notification.id!);
        }
      }
    }
    // Separate receipts avoid rewriting the UI's encrypted cache from an isolate.
    await storage.write(
      key: receiptKey(owner, id),
      value: jsonEncode({
        'owner': owner,
        'record_id': record,
        'action': action,
        'cloud': cloud,
        'at': DateTime.now().toUtc().toIso8601String(),
        'until': until.toUtc().toIso8601String(),
        'notification_id': id,
      }),
    );
    // cancel(id) also cancels a snooze schedule with the same ID. Only remove the
    // original first when scheduling offline snooze (see the scheduling branch).
    if (!action.startsWith('snooze')) await plugin.cancel(id: id);
  }
}
