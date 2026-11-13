import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/app.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
  testWidgets('opens directly to capture with four focused destinations', (
    tester,
  ) async {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage())
      ..onboarded = true;
    addTearDown(store.dispose);
    await tester.pumpWidget(SelfTextApp(store: store));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Chats'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Save message'), findsOneWidget);
    expect(find.byTooltip('Speak a message'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final label in [
      'Ideas',
      'Projects',
      'Today',
      'AI plan',
      'Focus',
      'Capture something',
    ]) {
      expect(find.text(label), findsNothing);
    }
    await tester.enterText(find.byType(TextField), 'Call Ali');
    await tester.tap(find.byTooltip('Save message'));
    await tester.pumpAndSettle();
    expect(store.messages.single.text, 'Call Ali');
    await tester.tap(find.text('Set reminder or save note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In 5 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(store.records.single.reminderTimes, hasLength(1));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Call Ali'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('save message as note keeps its text and source', (tester) async {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage())
      ..onboarded = true;
    addTearDown(store.dispose);
    final entry = store.capture('inbox', 'Bring my notebook tomorrow');
    await tester.pumpWidget(SelfTextApp(store: store));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Chats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set reminder or save note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    expect(find.text('Bring my notebook tomorrow'), findsOneWidget);
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();
    expect(store.notes.single.body, entry.text);
    expect(store.notes.single.sourceId, entry.id);
  });
  testWidgets(
    'all four screens fit a small phone in actual light and dark themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = SelfTextStore(sessionStorage: MemorySessionStorage())
        ..onboarded = true;
      addTearDown(store.dispose);
      for (final appearance in ['light', 'dark']) {
        await store.setAppearance(appearance);
        await tester.pumpWidget(SelfTextApp(store: store));
        await tester.pumpAndSettle();
        for (final label in [
          'Dashboard',
          'Chats',
          'Tasks',
          'Calendar',
          'Profile',
        ]) {
          await tester.tap(find.widgetWithText(NavigationDestination, label));
          await tester.pumpAndSettle();
          expect(
            Theme.of(tester.element(find.byType(NavigationBar))).brightness,
            appearance == 'light' ? Brightness.light : Brightness.dark,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$label in $appearance',
          );
        }
      }
    },
  );
  testWidgets(
    'legacy idea and project notes stay available in the plain notepad',
    (tester) async {
      final store = SelfTextStore(sessionStorage: MemorySessionStorage())
        ..onboarded = true;
      addTearDown(store.dispose);
      for (final kind in ['idea', 'project']) {
        final chat = store.createChat('Old $kind', kind: kind);
        store.createRecord(
          title: 'Saved $kind note',
          body: 'Keep this',
          kind: RecordKind.note,
          chatId: chat.id,
        );
      }
      await tester.pumpWidget(SelfTextApp(store: store));
      await tester.tap(find.byTooltip('Notepad'));
      await tester.pumpAndSettle();
      expect(find.text('Saved idea note'), findsOneWidget);
      expect(find.text('Saved project note'), findsOneWidget);
      expect(find.text('Ideas'), findsNothing);
      expect(find.text('Projects'), findsNothing);
      expect(store.notes, hasLength(2));
    },
  );
}
