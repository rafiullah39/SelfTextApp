import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:selftext/api.dart';
import 'package:selftext/app.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
  test('HTML outage response becomes a recoverable API error', () async {
    final api = SelfTextApi(
      client: MockClient(
        (_) async => http.Response('<html>Unavailable</html>', 503),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.request('GET', '/me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
    );
  });
  test(
    'malformed success response does not escape as FormatException',
    () async {
      final api = SelfTextApi(
        client: MockClient((_) async => http.Response('not-json', 200)),
      );
      addTearDown(api.close);
      await expectLater(
        api.request('GET', '/me'),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test('empty success and validation errors are handled', () async {
    final api = SelfTextApi(
      client: MockClient(
        (r) async => r.method == 'DELETE'
            ? http.Response('', 204)
            : http.Response('{"detail":[{"msg":"invalid"}]}', 422),
      ),
    );
    addTearDown(api.close);
    expect(await api.request('DELETE', '/records/test'), isEmpty);
    await expectLater(
      api.request('GET', '/me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
    );
  });
  testWidgets('a long chat builds visible messages and opens at latest entry', (
    tester,
  ) async {
    final store = SelfTextStore(sessionStorage: MemorySessionStorage())
      ..onboarded = true;
    addTearDown(store.dispose);
    for (var i = 0; i < 1000; i++) {
      store.messages.add(
        Entry(
          id: 'entry-$i',
          chatId: 'inbox',
          text: 'Message $i',
          createdAt: DateTime.now(),
          aiStatus: 'proposed',
        ),
      );
    }
    await tester.pumpWidget(SelfTextApp(store: store));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Chats'));
    await tester.pumpAndSettle();
    expect(find.text('Message 999'), findsOneWidget);
    expect(find.text('Message 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
