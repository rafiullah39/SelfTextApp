import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/api.dart';
import 'package:selftext/feedback_dialog.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage;

class ReportApi extends SelfTextApi {
  Map<String, dynamic>? submitted;
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    expect(method, 'POST');
    expect(path, '/feedback');
    submitted = body;
    return {'received': true, 'reference': 'synthetic-report'};
  }
}

void main() {
  testWidgets(
    'reporting stays in the app and sends only entered feedback and reference',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReportApi()..token = 'synthetic-session';
      final store = SelfTextStore(
        api: api,
        sessionStorage: MemorySessionStorage(),
      )..userId = 'synthetic-user';
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => reportProblem(
                  context,
                  store,
                  interpretationId: 'synthetic-proposal',
                ),
                child: const Text('Open report'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send report'));
      await tester.pump();
      expect(api.submitted, isNull);
      expect(
        find.text('Please describe the issue in a few words.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'The date is incorrect.');
      await tester.ensureVisible(find.text('Send report'));
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(api.submitted, {
        'category': 'other',
        'description': 'The date is incorrect.',
        'interpretation_id': 'synthetic-proposal',
      });
      expect(find.textContaining('Report received.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
