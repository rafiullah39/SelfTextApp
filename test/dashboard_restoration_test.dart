import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/app.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
  testWidgets('dashboard opens named chats and tasks filter and complete', (
    tester,
  ) async {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage())
      ..onboarded = true;
    addTearDown(store.dispose);
    final due = store.calendarNow.add(const Duration(minutes: 20));
    store.createRecord(
      title: 'University assignment',
      kind: RecordKind.task,
      chatId: 'university',
      dueAt: due,
      reminderTimes: [due],
    );
    store.createRecord(
      title: 'Personal errand',
      kind: RecordKind.task,
      chatId: 'personal',
      dueAt: due,
      reminderTimes: [due],
    );
    await tester.pumpWidget(SelfTextApp(store: store));
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    expect(find.byType(CalendarDatePicker), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('University'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'University'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Personal'));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'University'));
    await tester.pumpAndSettle();
    expect(find.text('University assignment'), findsOneWidget);
    expect(find.text('Personal errand'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(store.tasks.first.done, isTrue);
    expect(find.text('University assignment'), findsNothing);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('University assignment'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Personal errand'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'tabs return to dashboard and legacy chat names have no idea label',
    (tester) async {
      final store = SelfTextStore(sessionStorage: MemorySessionStorage())
        ..onboarded = true;
      addTearDown(store.dispose);
      store.chats.add(Chat('ideas', 'Startup ideas'));
      await tester.pumpWidget(SelfTextApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Startup ideas'), findsNothing);
      for (final tab in ['Chats', 'Tasks', 'Calendar', 'Profile']) {
        await tester.tap(find.widgetWithText(NavigationDestination, tab));
        await tester.pumpAndSettle();
        expect(find.text('Startup ideas'), findsNothing);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
        expect(find.text('YOUR EVERYDAY, SIMPLIFIED'), findsOneWidget);
        expect(find.text('Today'), findsNothing);
      }
      await tester.tap(find.byTooltip('Notepad'));
      await tester.pumpAndSettle();
      expect(find.text('Notepad'), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.text('YOUR EVERYDAY, SIMPLIFIED'), findsOneWidget);
    },
  );
}
