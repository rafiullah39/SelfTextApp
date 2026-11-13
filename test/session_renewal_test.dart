import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:selftext/api.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main() {
  test('sign in saves renewal credential but never the password', () async {
    final storage = MemorySessionStorage();
    final api = SelfTextApi(firebaseApiKey: 'test', client: MockClient((r) async {
      if (r.url.host == 'identitytoolkit.googleapis.com') {
        return http.Response('{"idToken":"firebase","refreshToken":"new-refresh"}', 200);
      }
      return http.Response('{"access_token":"session","user":{"id":"owner"}}', 200);
    }))..sessionStorage = storage;
    await api.authenticate('owner@example.com', 'never-store-this-password');
    expect(await storage.read(key: 'selftext.firebase-refresh'), 'new-refresh');
    expect((await storage.readAll()).values, isNot(contains('never-store-this-password')));
    api.close();
  });
  test('renewal cannot replay queued changes under a different account', () async {
    final storage = MemorySessionStorage();
    await storage.write(key: 'selftext.firebase-refresh', value: 'refresh');
    await storage.write(key: 'selftext.user', value: 'original-owner');
    var writes = 0;
    final api = SelfTextApi(token: 'expired', firebaseApiKey: 'test', client: MockClient((r) async {
      if (r.url.host == 'securetoken.googleapis.com') return http.Response('{"id_token":"firebase","refresh_token":"rotated"}', 200);
      if (r.url.path == '/auth/firebase') return http.Response('{"access_token":"wrong-account-token","user":{"id":"different-owner"}}', 200);
      writes++;
      return http.Response('{"detail":"Invalid or expired session"}', 401);
    }))..sessionStorage = storage;
    await expectLater(api.request('POST', '/records', {'title': 'Private queued note'}), throwsA(isA<ApiException>()));
    expect(writes, 1);
    expect(api.token, 'expired');
    expect(await storage.read(key: 'selftext.session'), isNull);
    api.close();
  });
  test(
    'concurrent expired requests renew once and persist rotated credentials',
    () async {
      final storage = MemorySessionStorage();
      await storage.write(
        key: 'selftext.firebase-refresh',
        value: 'old-refresh',
      );
      await storage.write(key: 'selftext.user', value: 'owner');
      var renewals = 0;
      final api = SelfTextApi(
        token: 'expired',
        firebaseApiKey: 'test',
        client: MockClient((r) async {
          if (r.url.host == 'securetoken.googleapis.com') {
            renewals++;
            return http.Response(
              jsonEncode({'id_token': 'firebase', 'refresh_token': 'rotated'}),
              200,
            );
          }
          if (r.url.path == '/auth/firebase') {
            return http.Response(
              jsonEncode({
                'access_token': 'fresh',
                'user': {'id': 'owner'},
              }),
              200,
            );
          }
          if (r.headers['Authorization'] == 'Bearer expired') {
            return http.Response(
              '{"detail":"Invalid or expired session"}',
              401,
            );
          }
          expect(r.headers['Authorization'], 'Bearer fresh');
          return http.Response('{}', 200);
        }),
      )..sessionStorage = storage;
      await Future.wait([
        api.request('GET', '/export'),
        api.request('POST', '/records', {'title': 'queued'}),
      ]);
      expect(renewals, 1);
      expect(await storage.read(key: 'selftext.session'), 'fresh');
      expect(await storage.read(key: 'selftext.firebase-refresh'), 'rotated');
      api.close();
    },
  );
  test(
    'legacy missing renewal credential preserves data and requests sign in',
    () async {
      var requests = 0;
      final api = SelfTextApi(
        token: 'expired',
        firebaseApiKey: 'test',
        client: MockClient((r) async {
          requests++;
          return http.Response('{"detail":"Invalid or expired session"}', 401);
        }),
      )..sessionStorage = MemorySessionStorage();
      await expectLater(
        api.request('GET', '/export'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('remain saved'),
          ),
        ),
      );
      expect(requests, 1);
      api.close();
    },
  );
  test('explicitly revoked sessions are not renewed', () async {
    var requests = 0;
    final api = SelfTextApi(
      token: 'revoked',
      client: MockClient((r) async {
        requests++;
        return http.Response(
          '{"detail":"Session revoked. Sign in again."}',
          401,
        );
      }),
    )..sessionStorage = MemorySessionStorage();
    await expectLater(
      api.request('GET', '/export'),
      throwsA(isA<ApiException>()),
    );
    expect(requests, 1);
    api.close();
  });
}
