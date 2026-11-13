import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selftext/api.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage;

class LocalIntegrationApi extends SelfTextApi {
  LocalIntegrationApi(this.url);
  final String url;
  @override
  String get baseUrl => url;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final url = Platform.environment['SELFTEXT_INTEGRATION_URL'];
  test(
    'real HTTP capture, review, duplicate acceptance and completion share source IDs',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previous);
      SharedPreferences.setMockInitialValues({});
      final store = SelfTextStore(
        api: LocalIntegrationApi(url!),
        sessionStorage: MemorySessionStorage(),
      );
      addTearDown(store.dispose);
      await store.load();
      await store.signIn(
        'contract-${DateTime.now().microsecondsSinceEpoch}@example.com',
        'isolated-test-password',
        register: true,
      );
      final entry = store.capture(
        store.chats.first.id,
        'Finish contract report tomorrow at 5 PM',
      );
      await store.sync();
      expect(store.syncError, isNull);
      final proposal = store.proposals.single;
      expect(proposal['message_id'], entry.id);
      final actions = (proposal['structured_output']['actions'] as List)
          .map((a) => Map<String, dynamic>.from(a))
          .toList();
      await store.acceptProposal(proposal, actions);
      await store.acceptProposal(proposal, actions);
      expect(store.tasks.length, 1);
      expect(store.tasks.single.sourceId, entry.id);
      expect(store.tasks.single.title, 'Finish contract report');
      store.toggle(store.tasks.single);
      await store.sync();
      expect(store.tasks.single.done, isTrue);
      expect(store.messages.single.text, entry.text);
      expect(store.syncError, isNull);
    },
    skip: url == null
        ? 'Set SELFTEXT_INTEGRATION_URL to the isolated test API'
        : false,
  );
}
