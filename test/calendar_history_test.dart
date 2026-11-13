import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
  test(
    'cached chat timestamps restore in the saved account timezone',
    () async {
      SharedPreferences.setMockInitialValues({});
      final vault = MemorySessionStorage();
      final store = SelfTextStore(sessionStorage: vault);
      await store.load();
      store.accountTimezone = 'America/New_York';
      store.messages.add(
        Entry(
          id: 'zone-message',
          chatId: store.chats.first.id,
          text: 'Timezone fixture',
          createdAt: DateTime.utc(2030, 1, 2, 2),
        ),
      );
      store.changed(scheduleSync: false);
      await store.flush();
      store.dispose();
      final restored = SelfTextStore(sessionStorage: vault);
      await restored.load();
      expect(restored.messages.single.createdAt.hour, 21);
      expect(restored.messages.single.createdAt.day, 1);
      expect(
        restored.messages.single.createdAt.isAtSameMomentAs(
          DateTime.utc(2030, 1, 2, 2),
        ),
        true,
      );
      restored.dispose();
    },
  );
  test('offline one-occurrence edit preserves future recurrence fields', () {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage());
    final task = store.createRecord(
      title: 'Daily original',
      kind: RecordKind.task,
      chatId: 'inbox',
      dueAt: DateTime(2030, 1, 1, 9),
      recurrence: 'daily',
    );
    store.prepareRecurringEdit(task, 'occurrence');
    task.title = 'One-off';
    task.dueAt = DateTime(2030, 1, 1, 20);
    task.done = true;
    task.status = 'done';
    store.finishRecurringEdit(task);
    store.completeOfflineRecurrence(task);
    final successor = store.records.where((item) => item.id != task.id).single;
    expect(successor.title, 'Daily original');
    expect(successor.dueAt!.hour, 9);
    expect(successor.dueAt!.day, 2);
    store.dispose();
  });
  test('account calendar dates preserve instants and DST wall times', () {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage());
    store.accountTimezone = 'America/New_York';
    final before = store.calendarTime(2030, 3, 9, 9);
    final after = store.calendarTime(2030, 3, 10, 9);
    expect(after.hour, 9);
    expect(after.difference(before).inHours, 23);
    final record = ProductivityRecord(
      id: 'zone-fixture',
      title: 'Timed',
      kind: RecordKind.task,
      chatId: 'inbox',
      dueAt: after,
    );
    final restored = ProductivityRecord.fromJson(record.toJson());
    expect(restored.dueAt!.isAtSameMomentAs(after), isTrue);
    expect(store.displayTime(restored.dueAt!).hour, 9);
    store.records.add(record);
    expect(store.onDay(store.calendarTime(2030, 3, 10)), contains(record));
    expect(store.onDay(store.calendarTime(2030, 3, 9)), isEmpty);
    store.dispose();
  });
  test('local reminders defer across midnight in the account timezone', () {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage());
    store.accountTimezone = 'Asia/Karachi';
    store.accountPreferences = {
      'quiet_hours': {'enabled': true, 'start': '22:00', 'end': '07:00'},
    };
    expect(
      store.localReminderTime(DateTime.utc(2030, 1, 1, 18)).toUtc(),
      DateTime.utc(2030, 1, 2, 2),
    );
    expect(
      store.localReminderTime(DateTime.utc(2030, 1, 2, 1)).toUtc(),
      DateTime.utc(2030, 1, 2, 2),
    );
    expect(
      store.localReminderTime(DateTime.utc(2030, 1, 2, 3)).toUtc(),
      DateTime.utc(2030, 1, 2, 3),
    );
    store.accountPreferences = {
      'quiet_hours': {'enabled': true, 'start': '07:00', 'end': '07:00'},
    };
    expect(
      store.localReminderTime(DateTime.utc(2030, 1, 2, 1)).toUtc(),
      DateTime.utc(2030, 1, 2, 1),
    );
    store.dispose();
  });
  test(
    'all-day exclusive end, rescheduling offsets and encrypted history survive restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final vault = MemorySessionStorage();
      final store = SelfTextStore(sessionStorage: vault);
      await store.load();
      final event = store.createRecord(
        title: 'Conference',
        kind: RecordKind.event,
        chatId: 'inbox',
        allDay: true,
        location: 'Campus',
        dueAt: DateTime(2030, 1, 2),
        endAt: DateTime(2030, 1, 4),
        reminderTimes: [DateTime(2030, 1, 1, 18)],
      );
      expect(store.onDay(DateTime(2030, 1, 3)), contains(event));
      expect(store.onDay(DateTime(2030, 1, 4)), isEmpty);
      store.rescheduleRecord(event, DateTime(2030, 1, 5));
      expect(event.endAt, DateTime(2030, 1, 7));
      expect(event.reminderTimes.single, DateTime(2030, 1, 4, 18));
      store.rememberSearch('Private idea');
      store.rememberSearch('private IDEA');
      expect(store.recentSearches, ['private IDEA']);
      await store.flush();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(SelfTextStore.storageKey),
        isNot(contains('private IDEA')),
      );
      final restored = SelfTextStore(sessionStorage: vault);
      await restored.load();
      expect(restored.records.single.allDay, true);
      expect(restored.records.single.location, 'Campus');
      expect(restored.recentSearches, ['private IDEA']);
      restored.clearRecentSearches();
      expect(restored.recentSearches, isEmpty);
      store.dispose();
      restored.dispose();
    },
  );
  test('invalid calendar moves do not partially change reminders', () {
    final store = SelfTextStore();
    final due = DateTime.now().add(const Duration(hours: 3));
    final task = store.createRecord(
      title: 'Task',
      kind: RecordKind.task,
      chatId: 'inbox',
      dueAt: due,
      reminderTimes: [due.subtract(const Duration(hours: 2))],
    );
    expect(() => store.rescheduleRecord(task, DateTime.now()), throwsException);
    expect(task.dueAt, due);
    store.dispose();
  });
}
