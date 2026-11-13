import 'api.dart';
import 'session_storage.dart';

/// Serializes token rotations and waits for in-flight writes before detaching.
class DeviceRegistration {
  DeviceRegistration(this.storage);
  final SessionStorage storage;
  static const tokenKey = 'selftext.push.token';
  bool _accepting = false;
  Future<void> _pending = Future.value();
  void begin() => _accepting = true;
  void pause() => _accepting = false;
  Future<void> register(SelfTextApi api, String token) {
    if (!_accepting) return Future.value();
    final operation = _pending.catchError((_) {}).then((_) async {
      if (!_accepting) return;
      final previous = await storage.read(key: tokenKey);
      // Persist before the request: a server may save while its reply is lost.
      await storage.write(key: tokenKey, value: token);
      final result = await api.request('POST', '/devices', {
        'token': token,
        'action_notifications': true,
      });
      if (result is Map && result['action_notifications'] == false) {
        throw StateError(
          'Notification buttons were not registered. Try again when connected.',
        );
      }
      if (previous != null && previous != token) {
        await api.request('DELETE', '/devices', {'token': previous});
      }
    });
    _pending = operation;
    return operation;
  }

  Future<bool> detach(SelfTextApi api) async {
    _accepting = false;
    await _pending.catchError((_) {});
    final token = await storage.read(key: tokenKey);
    if (token == null) return false;
    await api.request('DELETE', '/devices', {
      'token': token,
      'action_notifications': true,
    });
    await storage.delete(key: tokenKey);
    return true;
  }
}
