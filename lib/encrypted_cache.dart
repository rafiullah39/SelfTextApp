import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'session_storage.dart';

class EncryptedCache {
  EncryptedCache(this.storage);
  final SessionStorage storage;
  final cipher = AesGcm.with256bits();
  Future<SecretKey> key(String workspace) async {
    final name = '$workspace.encryption-key';
    var encoded = await storage.read(key: name);
    if (encoded == null) {
      encoded = base64Encode(
        await (await cipher.newSecretKey()).extractBytes(),
      );
      await storage.write(key: name, value: encoded);
    }
    return SecretKey(base64Decode(encoded));
  }

  Future<String> encrypt(String value, String workspace) async {
    final box = await cipher.encrypt(
      utf8.encode(value),
      secretKey: await key(workspace),
      aad: utf8.encode(workspace),
    );
    return jsonEncode({
      'encrypted': 1,
      'nonce': base64Encode(box.nonce),
      'data': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  Future<String> decrypt(String value, String workspace) async {
    final data = jsonDecode(value) as Map<String, dynamic>;
    if (data['encrypted'] != 1) return value; // Migrated on the next save.
    final box = SecretBox(
      base64Decode(data['data']),
      nonce: base64Decode(data['nonce']),
      mac: Mac(base64Decode(data['mac'])),
    );
    return utf8.decode(
      await cipher.decrypt(
        box,
        secretKey: await key(workspace),
        aad: utf8.encode(workspace),
      ),
    );
  }
}
