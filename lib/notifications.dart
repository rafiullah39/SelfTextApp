import 'local_reminders.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';
import 'session_storage.dart';
import 'device_registration.dart';

class SelfTextNotifications {
  SelfTextNotifications(this.storage)
    : registration = DeviceRegistration(storage);
  final SessionStorage storage;
  final DeviceRegistration registration;
  static const tokenKey = 'selftext.push.token';
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _foreground, _opened;
  bool _enabled = false;
  Future<void>? _binding;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> enable(
    SelfTextApi api,
    Future<void> Function() refresh,
    void Function(String) openRecord, {
    bool requestPermission = true,
  }) {
    if (_binding != null) return _binding!;
    _enabled = true;
    registration.begin();
    final operation = _enable(
      api,
      refresh,
      openRecord,
      requestPermission: requestPermission,
    );
    _binding = operation;
    unawaited(operation.whenComplete(() => _binding = null).catchError((_) {}));
    return operation;
  }

  Future<void> _enable(
    SelfTextApi api,
    Future<void> Function() refresh,
    void Function(String) openRecord, {
    required bool requestPermission,
  }) async {
    if (!supported) {
      throw ApiException(
        'Push notifications are available in the Android app. The browser shows reminder history.',
      );
    }
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    final permission = requestPermission
        ? await messaging.requestPermission()
        : await messaging.getNotificationSettings();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw ApiException(
        'Notifications were not allowed. You can enable them in Android settings.',
      );
    }
    if (!_enabled || api.token == null) return;
    await messaging.setAutoInitEnabled(true);
    final token = await messaging.getToken();
    if (token == null) {
      throw ApiException(
        'Could not register this device. Check Google Play services and try again.',
      );
    }
    if (!_enabled || api.token == null) return;
    await registration.register(api, token);
    if (!_enabled) return;
    await _tokens?.cancel();
    _tokens = messaging.onTokenRefresh.listen((token) {
      if (_enabled && api.token != null) {
        unawaited(registration.register(api, token).catchError((_) {}));
      }
    });
    await _foreground?.cancel();
    await _opened?.cancel();
    _foreground = FirebaseMessaging.onMessage.listen((message) {
      if (_enabled && api.token != null) {
        unawaited(
          LocalReminders.showRemote(message.data, initializePlugin: false),
        );
        refresh();
      }
    });
    void open(RemoteMessage message) {
      if (_enabled &&
          api.token != null &&
          message.data['record_id'] is String) {
        openRecord(message.data['record_id']);
      }
    }

    _opened = FirebaseMessaging.onMessageOpenedApp.listen(open);
    final initial = await messaging.getInitialMessage();
    if (initial != null) open(initial);
  }

  Future<void> restore(
    SelfTextApi api,
    Future<void> Function() refresh,
    void Function(String) openRecord,
  ) async {
    if (supported && api.token != null) {
      await enable(api, refresh, openRecord, requestPermission: false);
    }
  }

  Future<void> disable(SelfTextApi api) async {
    _enabled = false;
    registration.pause();
    await _binding?.catchError((_) {});
    await _tokens?.cancel();
    await _foreground?.cancel();
    await _opened?.cancel();
    if (supported &&
        (Firebase.apps.isNotEmpty ||
            await storage.read(key: tokenKey) != null)) {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    }
    try {
      final hadToken = await registration.detach(api);
      if (hadToken) await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      throw ApiException(
        'Connect to the server before signing out so device notifications can be detached from this account.',
      );
    }
  }

  void dispose() {
    _enabled = false;
    registration.pause();
    _tokens?.cancel();
    _foreground?.cancel();
    _opened?.cancel();
  }
}

@pragma('vm:entry-point')
Future<void> selfTextBackgroundMessage(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  await LocalReminders.showRemote(message.data);
}
