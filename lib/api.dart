import 'dart:convert';
import 'session_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class SelfTextApi {
  SelfTextApi({this.token, http.Client? client, String? firebaseApiKey})
    : _client = client ?? http.Client(),
      _firebaseKey = firebaseApiKey ?? firebaseKey;
  String? token;
  SessionStorage sessionStorage = const DeviceSessionStorage();
  Future<void>? _renewing;
  Future<void> _renewSession() async {
    final refresh = await sessionStorage.read(key: 'selftext.firebase-refresh');
    if (refresh == null || refresh.isEmpty || _firebaseKey.isEmpty) {
      throw ApiException(
        'Please sign in again to reconnect. Your messages remain saved on this phone.',
        statusCode: 401,
      );
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(
              'https://securetoken.googleapis.com/v1/token?key=$_firebaseKey',
            ),
            body: {'grant_type': 'refresh_token', 'refresh_token': refresh},
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ApiException(
        'Cannot renew your connection right now. Your messages remain saved on this phone. Try Sync now when online.',
      );
    }
    if (response.statusCode == 429 || response.statusCode >= 500) {
      throw ApiException(
        'Sign-in service is temporarily busy. Your messages remain saved on this phone. Try Sync now shortly.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        'Please sign in again to reconnect. Your messages remain saved on this phone.',
        statusCode: 401,
      );
    }
    final Map<String, dynamic> firebase;
    try {
      firebase = jsonDecode(response.body) as Map<String, dynamic>;
      if (firebase['id_token'] is! String ||
          (firebase['id_token'] as String).isEmpty) {
        throw const FormatException();
      }
    } catch (_) {
      throw ApiException(
        'The sign-in service sent an unreadable response. Your messages remain saved. Try Sync now shortly.',
      );
    }
    final rotated = firebase['refresh_token'] as String?;
    if (rotated != null) {
      await sessionStorage.write(
        key: 'selftext.firebase-refresh',
        value: rotated,
      );
    }
    final session = Map<String, dynamic>.from(
      await _request('POST', '/auth/firebase', {
        'id_token': firebase['id_token'],
      }),
    );
    final expected = await sessionStorage.read(key: 'selftext.user');
    if (expected != null && session['user']['id'] != expected) {
      throw ApiException(
        'Sign in to your original account to sync these messages.',
        statusCode: 401,
      );
    }
    token = session['access_token'] as String;
    await sessionStorage.write(key: 'selftext.session', value: token);
  }

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final attemptedToken = token;
    try {
      return await _request(method, path, body);
    } on ApiException catch (error) {
      if (error.statusCode != 401 ||
          error.message != 'Invalid or expired session' ||
          path.startsWith('/auth/')) {
        rethrow;
      }
      if (token == attemptedToken) {
        final pending = _renewing ??= _renewSession();
        try {
          await pending;
        } finally {
          if (identical(_renewing, pending)) _renewing = null;
        }
      }
      return _request(method, path, body);
    }
  }

  static const configuredUrl = String.fromEnvironment('API_URL');
  static const firebaseKey = String.fromEnvironment('FIREBASE_API_KEY');
  String get baseUrl => configuredUrl.isNotEmpty
      ? configuredUrl
      : kIsWeb
      ? 'http://127.0.0.1:8000'
      : 'http://10.0.2.2:8000';
  final http.Client _client;
  final String _firebaseKey;
  Future<dynamic> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$baseUrl$path');
    if (kReleaseMode && uri.scheme != 'https') {
      throw ApiException('This release requires a secure HTTPS server.');
    }
    final request = http.Request(method, uri);
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 90)),
      ).timeout(const Duration(seconds: 90));
    } catch (_) {
      throw ApiException(
        'Cannot reach the server. Your changes stay saved on this device.',
      );
    }
    final dynamic data;
    try {
      data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        response.statusCode >= 500
            ? 'The service is temporarily unavailable. Your changes stay saved on this device.'
            : 'The server sent an unreadable response. Please try again.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      final detail = data is Map ? data['detail'] : null;
      throw ApiException(
        detail is String
            ? detail
            : response.statusCode == 429
            ? 'Too many requests. Please wait a minute and try again.'
            : response.statusCode >= 500
            ? 'The service is temporarily unavailable. Your changes stay saved on this device.'
            : 'Please check the entered fields (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> authenticate(
    String email,
    String password, {
    bool register = false,
    String timezone = 'Asia/Karachi',
    bool verificationOnly = false,
  }) async {
    if (_firebaseKey.isEmpty) {
      return Map<String, dynamic>.from(
        await request('POST', register ? '/auth/register' : '/auth/login', {
          'email': email,
          'password': password,
          if (register) 'timezone': timezone,
        }),
      );
    }
    final endpoint = register ? 'signUp' : 'signInWithPassword';
    final response = await _client
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:$endpoint?key=$_firebaseKey',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        data['error']?['message']?.toString() ?? 'Firebase sign-in failed',
      );
    }
    if (register || verificationOnly) {
      final verification = await _client
          .post(
            Uri.parse(
              'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$_firebaseKey',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'requestType': 'VERIFY_EMAIL',
              'idToken': data['idToken'],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (verification.statusCode >= 400) {
        final failure = jsonDecode(verification.body) as Map<String, dynamic>;
        final reason = failure['error']?['message']?.toString();
        throw ApiException(
          'Verification email could not be sent: ${reason ?? 'Please try again.'}',
        );
      }
      if (verificationOnly) {
        return {'verification_sent': true};
      }
      throw ApiException('Account created. Verify your email, then sign in.');
    }
    final session = Map<String, dynamic>.from(
      await request('POST', '/auth/firebase', {'id_token': data['idToken']}),
    );
    await sessionStorage.write(
      key: 'selftext.firebase-refresh',
      value: data['refreshToken'] as String?,
    );
    return session;
  }

  Future<void> resendVerification(String email, String password) async {
    if (_firebaseKey.isEmpty) {
      throw ApiException('Firebase email verification is not configured.');
    }
    await authenticate(email, password, verificationOnly: true);
  }

  Future<String> reauthenticateFirebase(String email, String password) async {
    final response = await _client
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_firebaseKey',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException('Could not confirm your SelfText password.');
    }
    return data['idToken'] as String;
  }

  Future<void> resetPassword(String email) async {
    if (_firebaseKey.isEmpty) {
      throw ApiException('Password recovery requires Firebase configuration.');
    }
    final response = await _client
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$_firebaseKey',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'requestType': 'PASSWORD_RESET', 'email': email}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      final data = jsonDecode(response.body);
      throw ApiException(
        data['error']?['message']?.toString() ??
            'Password reset request failed.',
      );
    }
  }

  void close() => _client.close();
}
