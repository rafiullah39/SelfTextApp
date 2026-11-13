import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/voice_capture.dart';
import 'package:selftext/notes_workspace.dart';
import 'package:selftext/store.dart';
import 'package:selftext/local_reminders.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
  testWidgets('Urdu speech result returns through the native bridge', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    String? locale;
    String? result;
    const channel = MethodChannel('selftext/voice');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('selftext/voice-events'),
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('selftext/voice-events'),
        null,
      ),
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      locale = (call.arguments as Map)['locale'];
      return 'پانچ منٹ بعد یاد دلا دینا';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await VoiceCapture.capture(context);
            },
            child: const Text('Voice'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اردو · Urdu').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start speaking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this text'));
    await tester.pumpAndSettle();
    expect(locale, 'ur-PK');
    expect(result, 'پانچ منٹ بعد یاد دلا دینا');
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('pauses keep voice session open until Stop and text approval', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final result = Completer<String?>();
    String? captured;
    bool stopped = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('selftext/voice-events'),
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      VoiceCapture.channel,
      (call) async {
        if (call.method == 'recognize') return result.future;
        if (call.method == 'stop') {
          stopped = true;
          result.complete('Remind me in five minutes to call Ali');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        VoiceCapture.channel,
        null,
      ),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('selftext/voice-events'),
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VoiceCapture.capture(context);
            },
            child: const Text('Voice'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start speaking'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Stop recording'), findsOneWidget);
    expect(captured, isNull);
    expect(stopped, false);
    await tester.tap(find.text('Stop recording'));
    await tester.pumpAndSettle();
    expect(stopped, true);
    expect(captured, isNull);
    await tester.tap(find.text('Use this text'));
    await tester.pumpAndSettle();
    expect(captured, 'Remind me in five minutes to call Ali');
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('notepad autosaves and includes preserved old space notes', (
    tester,
  ) async {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage());
    addTearDown(store.dispose);
    final space = store.createChat('Study club', kind: 'idea');
    store.createRecord(
      title: 'Idea overview',
      kind: RecordKind.note,
      chatId: space.id,
      body: 'A community for students',
    );
    await tester.pumpWidget(MaterialApp(home: NotesWorkspace(store: store)));
    expect(find.text('Idea overview'), findsOneWidget);
    await tester.tap(find.text('Write a note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Remember my books');
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      store.notes.where((n) => n.body == 'Remember my books'),
      hasLength(1),
    );
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();
    expect(find.text('Remember my books'), findsWidgets);
    expect(find.text('Ideas'), findsNothing);
    expect(find.text('Idea overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('typed spaces and snooze duration preserve their values', () async {
    final chat = Chat('idea', 'Study club', kind: 'idea');
    expect(Chat.fromJson(chat.toJson()).kind, 'idea');
    expect(Chat.fromJson({'id': 'old', 'title': 'Inbox'}).kind, 'chat');
    final storage = MemorySessionStorage();
    final store = SelfTextStore(sessionStorage: storage);
    await store.setSnoozeMinutes(15);
    expect(await storage.read(key: 'selftext.snooze_minutes'), '15');
    expect(store.snoozeMinutes, 15);
    expect(LocalReminders.snoozeDuration('999'), 10);
    final r = store.createRecord(
      title: 'Call Ali',
      kind: RecordKind.task,
      chatId: 'inbox',
    );
    final before = DateTime.now();
    store.handleReminderAction(r.id, 'snooze_15');
    expect(r.reminderTimes.single.difference(before).inMinutes, 15);
    store.dispose();
  });
  testWidgets('leaving notepad before debounce keeps the final text', (
    tester,
  ) async {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage());
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: NotesWorkspace(store: store)));
    await tester.tap(find.text('Write a note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Do not lose this thought',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      store.notes.where((r) => r.body == 'Do not lose this thought'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });
}
