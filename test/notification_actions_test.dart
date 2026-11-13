import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:selftext/api.dart';
import 'package:selftext/notification_actions.dart';
import 'package:selftext/local_reminders.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage, FakeApi;
import 'package:shared_preferences/shared_preferences.dart';

class ActionApi extends SelfTextApi {
  final calls = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add({'method': method, 'path': path, 'body': body});
    if (fail) throw ApiException('No internet');
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'pendingNotificationRequests' ||
              call.method == 'getActiveNotifications') {
            return <Map>[];
          }
          if (call.method == 'initialize') return true;
          if (call.method == 'getNotificationAppLaunchDetails') {
            return {'notificationLaunchedApp': false};
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  NotificationResponse response(
    String action, {
    bool cloud = true,
    String owner = 'user',
  }) => NotificationResponse(
    notificationResponseType:
        NotificationResponseType.selectedNotificationAction,
    id: 42,
    actionId: action,
    payload: jsonEncode({
      'owner': owner,
      'record_id': 'r',
      if (cloud) 'reminder_id': 'reminder',
      'title': 'Call Ali',
      'notification_id': 42,
    }),
  );
  test('three preparation alarms keep distinct schedules and ringing mode', () async {
    final storage = MemorySessionStorage()..values['selftext.alarm_sound'] = 'true';
    final service = LocalReminders(storage);
    await service.initialize((_) {}, (_, __) {});
    service.enabled = true;
    final now = DateTime.now();
    await service.replace([
      LocalReminder('task', 'Start working', now.add(const Duration(minutes: 90)), reminderId: 'start'),
      LocalReminder('task', 'Deadline approaching', now.add(const Duration(minutes: 230)), reminderId: 'warning'),
      LocalReminder('task', 'Due now', now.add(const Duration(hours: 4)), reminderId: 'due'),
    ]);
    final schedules = calls.where((c) => c.method == 'zonedSchedule').toList();
    expect(schedules, hasLength(3));
    expect(schedules.map((c) => c.arguments['id']).toSet(), hasLength(3));
    for (final call in schedules) {
      final android = call.arguments['platformSpecifics'] as Map;
      expect(android['channelId'], 'selftext_ringing_v1');
      expect(android['additionalFlags'], contains(4));
      expect((android['actions'] as List).map((a) => a['id']), ['snooze_10', 'dismiss']);
    }
  });
  test('ringing alarm keeps headless actions and alarm audio', () {
    final android = LocalReminders.actionDetails(10, alarm: true).android!;
    expect(android.channelId, 'selftext_ringing_v1');
    expect(android.audioAttributesUsage, AudioAttributesUsage.alarm);
    expect(android.additionalFlags, contains(4));
    expect(android.actions!.map((a) => a.id), ['snooze_10', 'dismiss']);
    expect(
      android.actions!.every((a) => a.showsUserInterface == false),
      isTrue,
    );
    expect(LocalReminders.actionDetails(10).android!.additionalFlags, isNull);
  });
  test(
    'cloud snooze reschedules using the button duration without UI',
    () async {
      final storage = MemorySessionStorage()
        ..values.addAll({
          'selftext.user': 'user',
          'selftext.session': 'test-session',
        });
      final api = ActionApi();
      await NotificationActions(
        storage,
        api: api,
      ).handle(response('snooze_15'));
      expect(api.calls.single['path'], '/reminders/reminder/snooze');
      expect(api.calls.single['body'], {'minutes': 15});
      expect(calls.firstWhere((c) => c.method == 'cancel').arguments['id'], 42);
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
      expect(
        jsonDecode(
          storage.values[NotificationActions.receiptKey('user', 42)]!,
        )['action'],
        'snooze_15',
      );
    },
  );
  test('dismiss and done call their owned API without opening app', () async {
    for (final action in ['dismiss', 'done']) {
      final storage = MemorySessionStorage()
        ..values.addAll({
          'selftext.user': 'user',
          'selftext.session': 'test-session',
        });
      final api = ActionApi();
      await NotificationActions(storage, api: api).handle(response(action));
      expect(api.calls.single['path'], '/records/r');
      if (action == 'done') {
        expect(api.calls.single['body'], {'status': 'done'});
      }
      expect(
        storage.values.containsKey(NotificationActions.receiptKey('user', 42)),
        true,
      );
    }
  });
  test(
    'offline snooze cancels old alert before scheduling, never cancels replacement',
    () async {
      final storage = MemorySessionStorage();
      final api = ActionApi();
      final before = DateTime.now();
      await NotificationActions(
        storage,
        api: api,
      ).handle(response('snooze_5', cloud: false, owner: 'guest'));
      expect(api.calls, isEmpty);
      final methods = calls.map((c) => c.method).toList();
      expect(methods, [
        'cancel',
        'canScheduleExactNotifications',
        'zonedSchedule',
      ]);
      final schedule = calls.last.arguments as Map;
      expect(
        DateTime.parse(
          '${schedule['scheduledDateTime']}Z',
        ).difference(before).inMilliseconds,
        closeTo(300000, 1000),
      );
      final actions = (schedule['platformSpecifics'] as Map)['actions'] as List;
      expect(
        actions.every(
          (a) =>
              a['showsUserInterface'] == false &&
              a['cancelNotification'] == false,
        ),
        true,
      );
    },
  );
  test(
    'network failure snoozes locally and queues account reconciliation',
    () async {
      final storage = MemorySessionStorage()
        ..values.addAll({
          'selftext.user': 'user',
          'selftext.session': 'session',
        });
      final api = ActionApi()..fail = true;
      await NotificationActions(
        storage,
        api: api,
      ).handle(response('snooze_10'));
      expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
      final receipt = jsonDecode(
        storage.values[NotificationActions.receiptKey('user', 42)]!,
      );
      expect(receipt['cloud'], false);
      expect(receipt['action'], 'snooze_10');
    },
  );
  test(
    'notification from a different account cannot act on current session',
    () async {
      final storage = MemorySessionStorage()
        ..values.addAll({
          'selftext.user': 'other',
          'selftext.session': 'session',
        });
      final api = ActionApi();
      await NotificationActions(storage, api: api).handle(response('done'));
      expect(api.calls, isEmpty);
      expect(calls, isEmpty);
    },
  );
  test(
    'initialization registers the headless callback and background-only buttons',
    () async {
      final local = LocalReminders(MemorySessionStorage());
      await local.initialize((_) {}, (_, __) {});
      final init =
          calls.firstWhere((c) => c.method == 'initialize').arguments as Map;
      expect(init['defaultIcon'], 'ic_stat_selftext');
      expect(init['callback_handle'], isNotNull);
      expect(init['dispatcher_handle'], isNotNull);
    },
  );
  test(
    'background done receipt reconciles cache without undoing server snooze or pending edits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = MemorySessionStorage();
      final api = FakeApi();
      final store = SelfTextStore(api: api, sessionStorage: storage);
      addTearDown(store.dispose);
      await store.load();
      await store.signIn('test@example.com', 'test');
      final record = store.createRecord(
        title: 'Call Ali',
        kind: RecordKind.task,
        chatId: 'cloud-inbox',
        reminderTimes: [DateTime.now().add(const Duration(minutes: 5))],
      );
      await store.sync();
      final id = record.id;
      final remote = api.records[id]!;
      final snoozed = DateTime.now()
          .add(const Duration(minutes: 15))
          .toUtc()
          .toIso8601String();
      remote['reminders'] = [snoozed];
      remote['status'] = 'done';
      store.records.firstWhere((r) => r.id == id).body = 'My unsynced note';
      store.changed();
      final owner = store.userId!;
      await storage.write(
        key: NotificationActions.receiptKey(owner, 42),
        value: jsonEncode({
          'owner': owner,
          'record_id': id,
          'action': 'done',
          'cloud': true,
          'at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await store.sync();
      expect(api.records[id]!['status'], 'done');
      expect(api.records[id]!['body'], 'My unsynced note');
      expect(api.records[id]!['reminders'], [snoozed]);
      expect(store.records.firstWhere((r) => r.id == id).done, true);
      expect(
        storage.values.keys.where(
          (k) => k.startsWith(NotificationActions.prefix),
        ),
        isEmpty,
      );
    },
  );
}
