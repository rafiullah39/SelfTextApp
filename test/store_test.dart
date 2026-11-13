import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
  test('overdue reminder stays until Dismiss explicitly removes it', () {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage());
    final record = store.createRecord(
      title: 'Overdue fixture',
      kind: RecordKind.task,
      chatId: 'inbox',
      reminderTimes: [DateTime.now().subtract(const Duration(minutes: 3))],
    );
    expect(store.records.any((r) => r.id == record.id), true);
    store.handleReminderAction(record.id, 'dismiss');
    expect(store.records.any((r) => r.id == record.id), false);
    store.dispose();
  });

  test(
    'notification actions snooze and complete without repeated completion',
    () {
      final store = SelfTextStore();
      final task = store.createRecord(
        title: 'Reminder fixture',
        kind: RecordKind.task,
        chatId: 'inbox',
        reminderTimes: [DateTime.now().subtract(const Duration(minutes: 1))],
      );
      store.handleReminderAction(task.id, 'snooze');
      expect(task.reminderTimes.single.isAfter(DateTime.now()), true);
      expect(task.reminderTimes.single.difference(DateTime.now()).inMilliseconds, closeTo(600000, 1000));
      store.handleReminderAction(task.id, 'done');
      store.handleReminderAction(task.id, 'done');
      expect(task.done, true);
      store.handleReminderAction('unknown', 'done');
      store.dispose();
    },
  );
  test('overnight events appear and conflict on the following day', () {
    final store = SelfTextStore();
    store.createRecord(
      title: 'Overnight',
      kind: RecordKind.event,
      chatId: 'inbox',
      dueAt: DateTime(2030, 1, 1, 23),
      endAt: DateTime(2030, 1, 2, 2),
    );
    store.createRecord(
      title: 'Early meeting',
      kind: RecordKind.event,
      chatId: 'inbox',
      dueAt: DateTime(2030, 1, 2, 1),
      endAt: DateTime(2030, 1, 2, 3),
    );
    expect(store.onDay(DateTime(2030, 1, 2)).length, 2);
    expect(store.conflictsOn(DateTime(2030, 1, 2)), [
      'Overnight / Early meeting',
    ]);
    expect(store.onDay(DateTime(2030, 1, 3)), isEmpty);
    store.dispose();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'guest monthly recurrence clamps dates and survives restart without duplicate successors',
    () async {
      final vault = MemorySessionStorage();
      final store = SelfTextStore(sessionStorage: vault);
      await store.load();
      final year = DateTime.now().year + 2;
      final source = store.capture('inbox', 'Monthly review');
      final due = DateTime(year, 1, 31, 9);
      final task = store.createRecord(
        title: 'Monthly review',
        kind: RecordKind.task,
        chatId: 'inbox',
        sourceId: source.id,
        dueAt: due,
        recurrence: 'monthly',
        subtasks: [
          {'title': 'Review notes', 'done': true},
        ],
        reminderTimes: [due.subtract(const Duration(minutes: 15))],
      );
      store.toggle(task);
      final successor = store.records.firstWhere(
        (r) => r.id == task.recurrenceSuccessorId,
      );
      expect(successor.dueAt, DateTime(year, 2, DateTime(year, 3, 0).day, 9));
      expect(successor.sourceId, source.id);
      expect(successor.subtasks.single['done'], false);
      expect(
        successor.reminderTimes.single,
        successor.dueAt!.subtract(const Duration(minutes: 15)),
      );
      await store.flush();
      store.dispose();
      final restored = SelfTextStore(sessionStorage: vault);
      await restored.load();
      final original = restored.records.firstWhere((r) => r.id == task.id);
      restored.toggle(original);
      restored.toggle(original);
      expect(restored.records.length, 2);
      restored.dispose();
    },
  );
  test('capture and linked records survive restarting the store', () async {
    final vault = MemorySessionStorage();
    final store = SelfTextStore(sessionStorage: vault);
    await store.load();
    final message = store.capture('university', 'Submit OS assignment');
    final due = DateTime(2026, 10, 5, 17);
    final task = store.createRecord(
      title: message.text,
      kind: RecordKind.task,
      chatId: message.chatId,
      sourceId: message.id,
      dueAt: due,
    );
    store.toggle(task);
    await store.flush();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(SelfTextStore.storageKey),
      isNot(contains('Submit OS assignment')),
    );
    final restored = SelfTextStore(sessionStorage: vault);
    await restored.load();
    expect(restored.messages.single.text, message.text);
    expect(restored.tasks.single.sourceId, restored.messages.single.id);
    expect(restored.tasks.single.done, true);
    expect(restored.onDay(due).single.id, task.id);
  });
  test('one message can create independent task event and note records', () {
    final store = SelfTextStore();
    final m = store.capture('inbox', 'Report, meeting and a new idea');
    for (final kind in RecordKind.values) {
      store.createRecord(
        title: kind.name,
        kind: kind,
        chatId: m.chatId,
        sourceId: m.id,
      );
    }
    store.toggle(store.tasks.single);
    expect(store.records.length, 3);
    expect(store.notes.single.done, false);
    expect(store.history('inbox').single.id, m.id);
    expect(store.onDay(DateTime.now()), isEmpty);
  });
}
