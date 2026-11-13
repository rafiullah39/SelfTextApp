import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/api.dart';
import 'package:selftext/store.dart';
import 'package:selftext/suggestion_widgets.dart';

class ReplyApi extends SelfTextApi {
  int reads = 0, writes = 0;
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/ai/query') {
      reads++;
      return {
        'answer': 'Review this change before applying it.',
        'record': {'id': 'owned-task', 'title': 'OS assignment'},
        'update': {'status': 'done'},
        'requires_confirmation': true,
      };
    }
    if (method == 'PATCH' && path == '/records/owned-task') {
      writes++;
      return {};
    }
    throw StateError('Unexpected request');
  }
}

class ReplyStore extends SelfTextStore {
  ReplyStore(ReplyApi api) : super(api: api);
  @override
  Future<void> sync() async {}
}

void main() {
  testWidgets(
    'chat completion requires confirmation and preserves cached reply',
    (tester) async {
      final api = ReplyApi();
      final store = ReplyStore(api);
      addTearDown(store.dispose);
      final proposal = <String, dynamic>{
        'id': 'query',
        'structured_output': {
          'actions': [],
          'query': 'I finished OS assignment',
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineSuggestionCard(store: store, proposal: proposal),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.reads, 1);
      expect(api.writes, 0);
      expect(find.text('OS assignment'), findsOneWidget);
      await tester.tap(find.text('Confirm change'));
      await tester.pumpAndSettle();
      expect(api.writes, 1);
      expect(find.text('Updated your reminders.'), findsOneWidget);
      expect(find.text('Confirm change'), findsNothing);
      expect(proposal['chat_reply']['applied'], true);
    },
  );
}
