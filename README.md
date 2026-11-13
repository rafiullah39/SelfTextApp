# SelfTextApp

The public Flutter/Android client source for SelfText. Capture a message or voice transcript to create reminders, manage tasks, and keep notes. This repository contains no backend source, user data, database credentials, AI keys, push-service keys, or release-signing files.

The production service runs separately. This source alone is **not** a complete deployable service. To build a connected client, an authorized developer must supply their own Firebase Android configuration and build-time values (`API_URL`, `FIREBASE_API_KEY`, `FIREBASE_APP_ID`) through private local configuration. Do not commit those files or a signing key.

For local code checks, run `flutter pub get`, `flutter analyze`, and `flutter test` in this directory. Some tests need local platform tooling. The Android build requires `android/app/google-services.json` from the project owner or a separate Firebase project.

Only the owner can push to this repository. Its public setting lets anyone read and fork the source; it does not grant write access to the backend or production data.
