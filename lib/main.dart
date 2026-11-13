import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'notifications.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(selfTextBackgroundMessage);
  }
  final store = SelfTextStore();
  await store.load();
  runApp(SelfTextApp(store: store));
}
