import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/app.dart';
import 'package:selftext/store.dart';
import 'package:selftext/suggestion_widgets.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
 setUpAll(() async {if(Platform.environment['SELFTEXT_DESIGN_PREVIEW']!='1') return;for(final font in {'Roboto':'C:/Windows/Fonts/segoeui.ttf','MaterialIcons':'D:/Android/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries) {final loader=FontLoader(font.key)..addFont(File(font.value).readAsBytes().then(ByteData.sublistView));await loader.load();}});

  test(
    'feedback distinguishes removed or dismissed suggestions from missing time',
    () {
      expect(
        captureFeedback({'status': 'accepted'}),
        contains('already handled'),
      );
      expect(captureFeedback({'status': 'rejected'}), contains('dismissed'));
      expect(captureFeedback(null), isNot(contains('No reminder time found')));
    },
  );
  testWidgets(
    'five-video plan shows all tasks and assumptions without autosaving',
    (tester) async {
      if(Platform.environment['SELFTEXT_DESIGN_PREVIEW']=='1') {tester.view.physicalSize=const Size(390,1100);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);}
      final store = SelfTextStore(sessionStorage: MemorySessionStorage());
      addTearDown(store.dispose);
      final due = DateTime.now().add(const Duration(days: 2)).toIso8601String();
      final proposal = <String, dynamic>{
        'id': 'plan',
        'status': 'pending',
        'structured_output': {
          'intent': 'plan',
          'explanation': 'Suggested evening times. Review before saving.',
          'actions': [
            for (var i = 1; i <= 5; i++)
              {
                'kind': 'task',
                'title': 'Create video $i of 5',
                'due_at': due,
                'reminders': [due],
                'confidence': .95,
                'ambiguities': <String>[],
              },
          ],
        },
      };
      expect(
        SelfTextStore.canAutoSaveReminder(
          proposal,
          'Remind me to make five videos this week',
        ),
        isFalse,
      );
      await tester.pumpWidget(
        RepaintBoundary(key: const Key('plan-preview'), child: MaterialApp(theme: SelfTextApp(store: store).theme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: InlineSuggestionCard(store: store, proposal: proposal),
            ),
          ),
        )),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your suggested plan'), findsOneWidget);
      expect(find.text('Create video 5 of 5'), findsOneWidget);
      expect(
        find.text('Suggested evening times. Review before saving.'),
        findsOneWidget,
      );
      expect(find.text('Save plan'), findsOneWidget);
      expect(store.records, isEmpty);
      expect(tester.takeException(), isNull);
      if(Platform.environment['SELFTEXT_DESIGN_PREVIEW']=='1') {await expectLater(find.byKey(const Key('plan-preview')),matchesGoldenFile('../../dist/ui-0.9.3-plan.png'));}
    },
  );
}
