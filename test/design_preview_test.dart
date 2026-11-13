import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/app.dart';
import 'package:selftext/store.dart';
import 'package:selftext/connected_screens.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show FontLoader;

void main() {
  setUpAll(() async {
    if (Platform.environment['SELFTEXT_DESIGN_PREVIEW'] == '1') {
      for (final font in {
        'Roboto': 'C:/Windows/Fonts/segoeui.ttf',
        'MaterialIcons':
            'D:/Android/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(font.key)
          ..addFont(File(font.value).readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    }
  });
  testWidgets('capture flow stays in chat and offers date pickers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SelfTextStore()
      ..onboarded = true
      ..autoSaveReminders = false;
    addTearDown(store.dispose);
    final message = store.capture(
      'inbox',
      'Remind me in 5 minutes to check SelfText',
    );
    final due = DateTime(2026, 10, 5, 9, 5).toIso8601String();
    store.messages
      ..clear()
      ..add(
        Entry(
          id: message.id,
          chatId: message.chatId,
          text: message.text,
          createdAt: DateTime(2026, 10, 5, 9),
        ),
      );
    final proposal = <String, dynamic>{
      'id': 'preview-proposal',
      'message_id': message.id,
      'status': 'pending',
      'model_version': 'rules-v1',
      'structured_output': {
        'actions': [
          {
            'kind': 'reminder',
            'title': 'Check SelfText',
            'due_at': due,
            'reminders': [due],
            'confidence': 0.9,
            'ambiguities': [],
          },
        ],
      },
    };
    store.proposals.add(proposal);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('preview'),
        child: SelfTextApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    if (Platform.environment['SELFTEXT_DESIGN_PREVIEW'] == '1') {
      await expectLater(
        find.byKey(const Key('preview')),
        matchesGoldenFile('../../dist/design-chats.png'),
      );
    }
    await tester.tap(find.widgetWithText(NavigationDestination, 'Chats'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Check SelfText'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Set reminder or save note'), findsNothing);
    if (Platform.environment['SELFTEXT_DESIGN_PREVIEW'] == '1') {
      await expectLater(
        find.byKey(const Key('preview')),
        matchesGoldenFile('../../dist/design-chat.png'),
      );
    }
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(ProposalScreen), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    if (Platform.environment['SELFTEXT_DESIGN_PREVIEW'] == '1') {
      await expectLater(
        find.byKey(const Key('preview')),
        matchesGoldenFile('../../dist/design-review.png'),
      );
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('reminder list fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SelfTextStore()..onboarded = true;
    addTearDown(store.dispose);
    store.createRecord(
      title: 'Review OS notes',
      kind: RecordKind.task,
      chatId: store.chats.first.id,
      dueAt: store.calendarNow.add(const Duration(hours: 1)),
      subtasks: [
        {'title': 'Read chapter one', 'done': false},
      ],
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('today-preview'),
        child: SelfTextApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Build a plan'), findsNothing);
    expect(tester.takeException(), isNull);
    if (Platform.environment['SELFTEXT_DESIGN_PREVIEW'] == '1') {
      await expectLater(
        find.byKey(const Key('today-preview')),
        matchesGoldenFile('../../dist/design-today-0.5.png'),
      );
    }
  });
  testWidgets('render organized idea spaces', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SelfTextStore()..onboarded = true;
    addTearDown(store.dispose);
    for (final name in [
      'Study club',
      'Campus book exchange',
      'A better morning',
    ]) {
      final space = store.createChat(name, kind: 'idea');
      store.createRecord(
        title: 'Overview',
        body: 'A thought worth exploring.',
        kind: RecordKind.note,
        chatId: space.id,
      );
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('ideas-preview'),
        child: SelfTextApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Notepad'));
    await tester.pumpAndSettle();
    expect(find.text('Ideas'), findsNothing);
    expect(tester.takeException(), isNull);
    if (Platform.environment['SELFTEXT_DESIGN_PREVIEW'] == '1') {
      await expectLater(
        find.byKey(const Key('ideas-preview')),
        matchesGoldenFile('../../dist/design-ideas-0.5.png'),
      );
    }
  });
}
