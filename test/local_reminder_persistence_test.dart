import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/local_reminders.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'refresh cancels stale pending schedules without cancelAll active alerts',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getActiveNotifications') {
              return [
                {'id': 501, 'payload': 'completed-r'},
                {'id': 502, 'payload': 'r'},
              ];
            }
            if (call.method == 'pendingNotificationRequests') {
              return [
                {'id': 123, 'title': 'old', 'body': 'old', 'payload': 'record'},
              ];
            }
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {'notificationLaunchedApp': false};
            }
            if (call.method == 'initialize' ||
                call.method == 'canScheduleExactNotifications') {
              return true;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final storage = MemorySessionStorage();
      await storage.write(key: 'selftext.snooze_minutes', value: '15');
      final service = LocalReminders(storage);
      await service.initialize((_) {}, (_, __) {});
      service.enabled = true;
      await service.replace([
        LocalReminder(
          'r',
          'Call Ali',
          DateTime.now().add(const Duration(minutes: 5)),
        ),
      ]);
      expect(calls.where((c) => c.method == 'cancelAll'), isEmpty);
      expect(calls.where((c) => c.method == 'cancel'), isNotEmpty);
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
      final schedule =
          calls.firstWhere((c) => c.method == 'zonedSchedule').arguments as Map;
      expect((schedule['platformSpecifics'] as Map)['autoCancel'], false);
      expect(
        (schedule['platformSpecifics'] as Map)['scheduleMode'],
        'alarmClock',
      );
      expect(
        (schedule['platformSpecifics'] as Map)['channelId'],
        'selftext_alarm_v3',
      );
      final actions = (schedule['platformSpecifics'] as Map)['actions'] as List;
      expect(
        actions.any(
          (a) => a['id'] == 'snooze_15' && a['title'] == 'Snooze 15 min',
        ),
        true,
      );
      expect(
        actions.every(
          (a) =>
              a['showsUserInterface'] == false &&
              a['cancelNotification'] == false,
        ),
        true,
      );
      await service.clearCompleted({'r'});
      final cancelled = calls
          .where((c) => c.method == 'cancel')
          .map((c) => (c.arguments as Map)['id'])
          .toList();
      expect(cancelled, contains(501));
      expect(cancelled, isNot(contains(502)));
    },
  );
}
