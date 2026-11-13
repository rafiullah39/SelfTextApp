import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/api.dart';
import 'package:selftext/store.dart';
import 'package:selftext/task_assist_screen.dart';

class PlanApi extends SelfTextApi {
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path != '/ai/task-plan') throw StateError('Unexpected mutation');
    return {
      'explanation': 'A practical starting point.',
      'tasks': [
        {
          'title': 'Review chapter one',
          'steps': ['Read notes', 'Try practice questions'],
        },
      ],
    };
  }
}

void main() {
  testWidgets(
    'AI task plans stay drafts until the selected tasks are approved',
    (tester) async {
      final store = SelfTextStore(api: PlanApi());
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskAssistScreen(store: store),
                  ),
                ),
                child: const Text('Plan'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Prepare for OS exam');
      await tester.tap(find.text('Build my plan'));
      await tester.pumpAndSettle();
      expect(find.text('Review chapter one'), findsOneWidget);
      expect(store.tasks, isEmpty);
      await tester.ensureVisible(find.text('Add selected tasks'));
      await tester.tap(find.text('Add selected tasks'));
      await tester.pumpAndSettle();
      expect(store.tasks.single.title, 'Review chapter one');
      expect(store.tasks.single.subtasks.length, 2);
    },
  );
}
