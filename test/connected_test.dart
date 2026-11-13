import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/connected_screens.dart';
import 'package:selftext/store.dart';

void main() {
  testWidgets('server proposal shape renders ambiguity and editable dates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SelfTextStore();
    addTearDown(store.dispose);
    final proposal = <String, dynamic>{
      'id': 'proposal-1',
      'status': 'pending',
      'model_version': 'rules-v1',
      'structured_output': {
        'provider': 'rules-v1',
        'actions': [
          {
            'kind': 'task',
            'title': 'Finish report',
            'due_at': null,
            'end_at': null,
            'reminders': [],
            'confidence': 0.6,
            'ambiguities': ['Choose a time'],
          },
        ],
      },
    };
    store.proposals.add(proposal);
    await tester.pumpWidget(MaterialApp(home: ConnectedScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Finish report'), findsOneWidget);
    await tester.ensureVisible(find.text('Finish report'));
    await tester.tap(find.text('Finish report'));
    await tester.pumpAndSettle();
    expect(find.text('Needs review: Choose a time'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('When'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('In 5 min'));
    await tester.tap(find.text('In 5 min'));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'AM|PM')), findsWidgets);
    expect(store.records, isEmpty);
  });
}
