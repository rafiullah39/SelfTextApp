import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selftext/quick_reminder.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage, FakeApi;

void main() {
  final captured = DateTime(2026, 11, 12, 21, 42);
  for (final text in [
    'hello remind me after 5 minutes',
    'Remind Me after 5 minutes',
    'Remind me in five minutes to call Ali',
    'mujhe 5 minut baad call ali yaad dilana',
    'مجھے پانچ منٹ بعد دوا کی یاد دلانا',
    'مجھے ۵ منٹ بعد یاد دلانا',
  ]) {
    test('countdown works without a server: $text', () {
      final reminder = QuickReminder.parse(text, captured);
      expect(reminder, isNotNull);
      expect(reminder!.dueAt, captured.add(const Duration(minutes: 5)));
    });
  }
  test('task words are not converted into numbers', () {
    expect(
      QuickReminder.parse(
        'remind me in five minutes to do homework',
        captured,
      )!.title,
      'do homework',
    );
  });
  for (final text in [
    "don't remind me in 5 minutes",
    'do not remind me in 5 minutes',
    'cancel remind me in 5 minutes',
    'if it rains remind me in 5 minutes',
    'remind me 5 minutes ago',
    'مجھے پانچ منٹ بعد یاد نہیں دلانا',
  ]) {
    test(
      'negated, conditional or past instruction is not scheduled: $text',
      () {
        expect(QuickReminder.parse(text, captured), isNull);
      },
    );
  }
  for (final text in [
    'I worked for 5 minutes',
    'remind me soon',
    'remind me in 0 minutes',
    'remind me in 5 minutes and 2 hours',
    'remind me in 4 hours this takes 2 hours',
    'remind me every 5 minutes',
    'remind me in 5 minutes tomorrow',
    'remind me in 5 minutes at 7 pm',
  ]) {
    test(
      'ambiguous or unsupported request is not silently scheduled: $text',
      () {
        expect(QuickReminder.parse(text, captured), isNull);
      },
    );
  }
  test(
    'signed-out capture creates and persists a reminder linked to the message',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secure = MemorySessionStorage();
      final store = SelfTextStore(sessionStorage: secure);
      await store.load();
      final entry = store.capture('inbox', 'hello remind me after 5 minutes');
      expect(store.signedIn, isFalse);
      expect(store.records.single.sourceId, entry.id);
      expect(
        store.records.single.dueAt,
        entry.createdAt.add(const Duration(minutes: 5)),
      );
      expect(store.records.single.reminderTimes, [store.records.single.dueAt]);
      await store.flush();
      store.dispose();
      final restored = SelfTextStore(sessionStorage: secure);
      await restored.load();
      expect(restored.records.single.sourceId, entry.id);
      expect(restored.messages.single.id, entry.id);
      restored.dispose();
    },
  );
  test(
    'clear account capture also schedules locally while server is offline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeApi();
      final store = SelfTextStore(
        api: api,
        sessionStorage: MemorySessionStorage(),
      );
      await store.load();
      await store.signIn('test@example.com', 'test');
      api.online = false;
      final entry = store.capture(
        'cloud-inbox',
        'remind me in 5 minutes to call Ali',
      );
      await store.sync();
      expect(store.syncError, isNotNull);
      expect(store.records.single.sourceId, entry.id);
      api.online = true;
      await store.sync();
      expect(api.records.length, 1);
      expect(store.records.length, 1);
      await store.flush();
      store.dispose();
    },
  );
}
