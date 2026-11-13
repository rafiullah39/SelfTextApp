import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/api.dart';
import 'package:selftext/device_registration.dart';
import 'sync_test.dart' show MemorySessionStorage;

class RegistrationApi extends SelfTextApi {
  final events = <String>[];
  final started = Completer<void>();
  Completer<void>? gate;
  bool loseReply = false;
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    events.add('$method ${body!['token']}');
    if (method == 'POST') {
      if (!started.isCompleted) started.complete();
      await gate?.future;
      if (loseReply) throw ApiException('Reply lost');
    }
    return {};
  }
}

void main() {
  test(
    'sign out waits for registration and prevents later token refresh writes',
    () async {
      final storage = MemorySessionStorage();
      final api = RegistrationApi()..gate = Completer<void>();
      final registration = DeviceRegistration(storage)..begin();
      final adding = registration.register(api, 'first');
      await api.started.future;
      final detaching = registration.detach(api);
      await registration.register(api, 'later');
      api.gate!.complete();
      await adding;
      expect(await detaching, isTrue);
      expect(api.events, ['POST first', 'DELETE first']);
      expect(storage.values[DeviceRegistration.tokenKey], isNull);
    },
  );

  test(
    'lost registration reply leaves token recoverable for sign out',
    () async {
      final storage = MemorySessionStorage();
      final api = RegistrationApi()..loseReply = true;
      final registration = DeviceRegistration(storage)..begin();
      await expectLater(
        registration.register(api, 'saved'),
        throwsA(isA<ApiException>()),
      );
      expect(storage.values[DeviceRegistration.tokenKey], 'saved');
      expect(await registration.detach(api), isTrue);
      expect(api.events, ['POST saved', 'DELETE saved']);
      expect(storage.values[DeviceRegistration.tokenKey], isNull);
    },
  );
}
