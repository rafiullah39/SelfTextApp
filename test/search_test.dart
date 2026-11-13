import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/search_workspace.dart';
import 'package:selftext/store.dart';

void main() {
  testWidgets(
    'search combines type and tag filters and opens the matching record',
    (tester) async {
      final store = SelfTextStore();
      store.createRecord(
        title: 'Report task',
        kind: RecordKind.task,
        chatId: 'inbox',
        tags: ['work'],
      );
      store.createRecord(
        title: 'Report note',
        kind: RecordKind.note,
        chatId: 'inbox',
        tags: ['personal'],
      );
      ProductivityRecord? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchWorkspace(
              store: store,
              openRecord: (r) => opened = r,
              openMessage: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'report');
      await tester.pump();
      expect(find.text('Report task'), findsOneWidget);
      expect(find.text('Report note'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'work');
      await tester.pump();
      expect(find.text('Report note'), findsNothing);
      await tester.tap(find.text('Report task'));
      expect(opened?.title, 'Report task');
      expect(find.text('Search by meaning'), findsNothing);
      store.dispose();
    },
  );
}
