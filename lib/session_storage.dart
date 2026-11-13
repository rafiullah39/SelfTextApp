import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionStorage {
  Future<Map<String, String>> readAll();
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
  Future<void> delete({required String key});
}

class DeviceSessionStorage implements SessionStorage {
  const DeviceSessionStorage();
  static const _storage = FlutterSecureStorage();
  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
  @override
  Future<String?> read({required String key}) => _storage.read(key: key);
  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}
