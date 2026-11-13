import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show FakeApi, MemorySessionStorage;

class CountingApi extends FakeApi {
  int exports = 0;
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    if (path == '/export') exports++;
    return super.request(method, path, body);
  }
}

Future<void> completeOperation(
  WidgetTester tester,
  Future<void> operation,
) async {
  bool done = false;
  Object? failure;
  operation.then(
    (_) => done = true,
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  for (int i = 0; i < 200 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done, isTrue, reason: 'Operation did not complete in the fake clock');
  if (failure != null) throw failure!;
}

void main() {
  testWidgets('idle signed-in workspace makes no periodic cloud requests', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = CountingApi();
    final store = SelfTextStore(
      api: api,
      sessionStorage: MemorySessionStorage(),
    );
    addTearDown(store.dispose);
    await completeOperation(tester, store.load());
    await completeOperation(tester, store.signIn('test@example.com', 'test'));
    await completeOperation(tester, store.sync());
    // Drain the one-off save/debounce timers before measuring idle time.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final before = api.exports;
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
    }
    expect(
      api.exports,
      before,
      reason: 'An idle app must let cloud SQL suspend',
    );
    await completeOperation(tester, store.resumeNotificationActions());
    expect(
      api.exports,
      greaterThan(before),
      reason: 'Returning to the app must still refresh',
    );
    final posts = api.messagePosts;
    store.capture('cloud-inbox', 'A new note while using the app');
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      api.messagePosts,
      posts + 1,
      reason: 'New messages must still sync promptly',
    );
  });
}
