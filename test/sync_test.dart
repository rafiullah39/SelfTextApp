import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selftext/api.dart';
import 'package:selftext/session_storage.dart';
import 'package:selftext/store.dart';

class MemorySessionStorage implements SessionStorage {
  final values = <String, String>{};
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class FakeApi extends SelfTextApi {
  bool online = true, loseCreateReply = false;
  int messagePosts = 0;
  final messages = <Map<String, dynamic>>[];
  final records = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>> authenticate(
    String email,
    String password, {
    bool register = false,
    bool verificationOnly = false,
    String timezone = 'Asia/Karachi',
  }) async => {
    'access_token': 'fake-session',
    'user': {'id': 'account-1', 'email': email},
  };
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    await Future<void>.delayed(Duration.zero);
    if (!online) throw ApiException('Offline');
    if (path == '/export') {
      return jsonDecode(
        jsonEncode({
          'chats': [
            {'id': 'cloud-inbox', 'title': 'Inbox'},
          ],
          'messages': messages,
          'records': records.values.toList(),
          'reminders': [],
        }),
      );
    }
    if (path == '/interpretations') return [];
    if (method == 'POST' && path.endsWith('/messages')) {
      messagePosts++;
      if (!messages.any((m) => m['id'] == body!['client_id'])) {
        messages.add({
          'id': body!['client_id'],
          'chat_id': 'cloud-inbox',
          'content': body['content'],
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      return {'interpretation': null};
    }
    if (method == 'POST' && path == '/records') {
      records.putIfAbsent(
        body!['client_id'],
        () => {...body, 'id': body['client_id'], 'status': 'planned'},
      );
      if (loseCreateReply) {
        loseCreateReply = false;
        throw ApiException('Response lost after server saved');
      }
      return records[body['client_id']];
    }
    if (method == 'PATCH' && path.startsWith('/records/')) {
      records[path.split('/').last]!.addAll(body!);
      return records[path.split('/').last];
    }
    if (method == 'DELETE' && path.startsWith('/records/')) {
      records.remove(path.split('/').last);
      return {'deleted': true};
    }
    throw StateError('Unexpected $method $path');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('same-account reconnect syncs pending capture without signing out', () async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeApi();
    final store = SelfTextStore(api: api, sessionStorage: MemorySessionStorage());
    addTearDown(store.dispose);
    await store.load();
    await store.signIn('test@example.com', 'test');
    api.online = false;
    final capture = store.capture('cloud-inbox', 'Preserve during reconnect');
    await store.sync();
    expect(store.syncError, isNotNull);
    await expectLater(store.signIn('other@example.com', 'test'), throwsA(isA<ApiException>()));
    api.online = true;
    await store.signIn('test@example.com', 'test');
    expect(store.signedIn, isTrue);
    expect(store.messages.single.id, capture.id);
    expect(api.messages.single['id'], capture.id);
    expect(store.syncError, isNull);
  });
  test(
    'concurrent refresh saves each capture once and keeps its client ID',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeApi();
      final store = SelfTextStore(
        api: api,
        sessionStorage: MemorySessionStorage(),
      );
      addTearDown(store.dispose);
      await store.load();
      await store.signIn('test@example.com', 'test');
      final capture = store.capture('cloud-inbox', 'Finish OS report');
      await Future.wait([store.sync(), store.sync()]);
      expect(api.messagePosts, 1);
      expect(api.messages.single['id'], capture.id);
      expect(store.messages.single.id, capture.id);
      expect(store.syncError, isNull);
    },
  );
  test(
    'lost create response cannot overwrite newer offline edits on retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeApi();
      final store = SelfTextStore(
        api: api,
        sessionStorage: MemorySessionStorage(),
      );
      addTearDown(store.dispose);
      await store.load();
      await store.signIn('test@example.com', 'test');
      final task = store.createRecord(
        title: 'Original title',
        status: 'inbox',
        kind: RecordKind.task,
        chatId: 'cloud-inbox',
      );
      api.loseCreateReply = true;
      await store.sync();
      expect(store.syncError, isNotNull);
      task.title = 'Edited after response loss';
      store.changed();
      await store.sync();
      expect(api.records.length, 1);
      expect(api.records[task.id]!['title'], 'Edited after response loss');
      expect(api.records[task.id]!['status'], 'inbox');
      expect(store.records.single.title, 'Edited after response loss');
    },
  );
  test(
    'account cache preserves offline captures across sign-out and sign-in',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeApi();
      final vault = MemorySessionStorage();
      final store = SelfTextStore(api: api, sessionStorage: vault);
      addTearDown(store.dispose);
      await store.load();
      await store.signIn('test@example.com', 'test');
      api.online = false;
      final capture = store.capture('cloud-inbox', 'Captured offline');
      await store.sync();
      await store.signOut();
      expect(store.messages, isEmpty);
      expect(store.signedIn, isFalse);
      api.online = true;
      await store.signIn('test@example.com', 'test');
      expect(store.messages.single.id, capture.id);
      await store.sync();
      expect(api.messages.single['id'], capture.id);
    },
  );
}
