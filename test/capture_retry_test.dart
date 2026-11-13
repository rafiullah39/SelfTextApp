import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/api.dart';
import 'package:selftext/store.dart';

class RetryApi extends SelfTextApi {
  RetryApi() : super(token: 'synthetic-session');
  bool fail = true;
  final ids = <String>[];
  Completer<void>? gate;
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    ids.add(body!['client_id']);
    await gate?.future;
    return {
      'message': {'ai_status': fail ? 'failed' : 'proposed'},
      'interpretation': fail
          ? null
          : {
              'id': 'same-proposal',
              'message_id': body['client_id'],
              'status': 'pending',
            },
      if (fail) 'error': 'Synthetic provider unavailable; message saved',
    };
  }
}

void main() {
  test(
    'retry retains failed capture and does not duplicate suggestions or overlapping requests',
    () async {
      final api = RetryApi();
      final store = SelfTextStore(api: api)..userId = 'synthetic-account';
      final message = store.capture('inbox', 'Original saved message');
      await expectLater(
        store.retryCapture(message),
        throwsA(isA<ApiException>()),
      );
      expect(message.aiStatus, 'failed');
      expect(store.messages.length, 1);
      expect(store.records, isEmpty);
      api.fail = false;
      api.gate = Completer<void>();
      final first = store.retryCapture(message);
      await store.retryCapture(message);
      expect(api.ids.length, 2);
      api.gate!.complete();
      await first;
      await store.retryCapture(message);
      expect(store.proposals.length, 1);
      expect(message.aiStatus, 'proposed');
      expect(api.ids.toSet(), {message.id});
      expect(store.messages.single.text, 'Original saved message');
      store.dispose();
    },
  );
}
