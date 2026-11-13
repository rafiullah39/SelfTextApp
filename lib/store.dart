import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_actions.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_storage.dart';
import 'quick_reminder.dart';
import 'api.dart';
import 'notifications.dart';
import 'encrypted_cache.dart';
import 'local_reminders.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

class Entry {
  Entry({
    required this.id,
    required this.chatId,
    required this.text,
    required this.createdAt,
    this.aiStatus = 'pending',
    this.revisedFrom,
  });
  final String id, chatId, text;
  final DateTime createdAt;
  final String? revisedFrom;
  String aiStatus;
  Map<String, dynamic> toJson() => {
    'id': id,
    'chatId': chatId,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'aiStatus': aiStatus,
    'revisedFrom': revisedFrom,
  };
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'],
    chatId: j['chatId'],
    text: j['text'],
    createdAt: DateTime.parse(j['createdAt']),
    aiStatus: j['aiStatus'] ?? 'pending',
    revisedFrom: j['revisedFrom'],
  );
}

class Chat {
  Chat(this.id, this.title, {this.kind = 'chat'});
  final String id, title;
  final String kind;
  String get displayTitle =>
      RegExp(r'\bideas?\b', caseSensitive: false).hasMatch(title)
      ? 'Saved notes'
      : title;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'kind': kind};
  factory Chat.fromJson(Map<String, dynamic> j) =>
      Chat(j['id'], j['title'], kind: j['kind'] ?? 'chat');
}

enum RecordKind { task, event, note }

class ProductivityRecord {
  ProductivityRecord({
    required this.id,
    required this.title,
    required this.kind,
    required this.chatId,
    this.sourceId,
    this.dueAt,
    this.endAt,
    this.startAt,
    this.allDay = false,
    this.location = '',
    this.done = false,
    this.priority = 'Normal',
    this.body = '',
    this.status = 'planned',
    this.recurrence,
    this.recurrenceScope = 'series',
    this.recurrenceTemplate,
    this.recurrenceSuccessorId,
    this.pinned = false,
    List<String>? tags,
    List<Map<String, dynamic>>? subtasks,
    List<DateTime>? reminderTimes,
  }) : tags = tags ?? [],
       subtasks = subtasks ?? [],
       reminderTimes = reminderTimes ?? [];
  final String id;
  String title, chatId, priority, body;
  final RecordKind kind;
  final String? sourceId;
  DateTime? dueAt, endAt, startAt;
  bool allDay;
  String location;
  bool done;
  String status;
  String? recurrence;
  String recurrenceScope;
  Map<String, dynamic>? recurrenceTemplate;
  String? recurrenceSuccessorId;
  bool pinned;
  List<String> tags;
  List<Map<String, dynamic>> subtasks;
  List<DateTime> reminderTimes;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'chatId': chatId,
    'sourceId': sourceId,
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'startAt': startAt?.toUtc().toIso8601String(),
    'allDay': allDay,
    'location': location,
    'done': done,
    'priority': priority,
    'body': body,
    'status': status,
    'recurrence': recurrence,
    'recurrenceScope': recurrenceScope,
    'recurrenceTemplate': recurrenceTemplate,
    'recurrenceSuccessorId': recurrenceSuccessorId,
    'pinned': pinned,
    'tags': tags,
    'subtasks': subtasks,
    'reminderTimes': reminderTimes
        .map((t) => t.toUtc().toIso8601String())
        .toList(),
  };
  factory ProductivityRecord.fromJson(Map<String, dynamic> j) =>
      ProductivityRecord(
        id: j['id'],
        title: j['title'],
        kind: RecordKind.values.byName(j['kind']),
        chatId: j['chatId'],
        sourceId: j['sourceId'],
        dueAt: DateTime.tryParse(j['dueAt'] ?? ''),
        endAt: DateTime.tryParse(j['endAt'] ?? ''),
        startAt: DateTime.tryParse(j['startAt'] ?? ''),
        allDay: j['allDay'] ?? false,
        location: j['location'] ?? '',
        done: j['done'] ?? false,
        priority: j['priority'] ?? 'Normal',
        body: j['body'] ?? '',
        status: j['status'] ?? ((j['done'] ?? false) ? 'done' : 'planned'),
        recurrence: j['recurrence'],
        recurrenceScope: j['recurrenceScope'] ?? 'series',
        recurrenceTemplate: j['recurrenceTemplate'] == null
            ? null
            : Map<String, dynamic>.from(j['recurrenceTemplate']),
        recurrenceSuccessorId: j['recurrenceSuccessorId'],
        pinned: j['pinned'] ?? false,
        tags: List<String>.from(j['tags'] ?? []),
        subtasks: (j['subtasks'] as List? ?? [])
            .map((t) => Map<String, dynamic>.from(t))
            .toList(),
        reminderTimes: (j['reminderTimes'] as List? ?? [])
            .map((t) => DateTime.parse(t))
            .toList(),
      );
}

class SelfTextStore extends ChangeNotifier {
  SelfTextStore({SelfTextApi? api, SessionStorage? sessionStorage})
    : api = api ?? SelfTextApi(),
      _secure = sessionStorage ?? const DeviceSessionStorage(),
      notifications = SelfTextNotifications(
        sessionStorage ?? const DeviceSessionStorage(),
      ) {
    this.api.sessionStorage = _secure;
    zones.initializeTimeZones();
  }
  static const storageKey = 'selftext.local.v1';
  String? accountTimezone;
  Map<String, dynamic> accountPreferences = {};
  DateTime displayTime(DateTime value) => accountTimezone == null
      ? value.toLocal()
      : tz.TZDateTime.from(value, tz.getLocation(accountTimezone!));
  DateTime get calendarNow => displayTime(DateTime.now());
  DateTime calendarTime(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) => accountTimezone == null
      ? DateTime(year, month, day, hour, minute, second)
      : tz.TZDateTime(
          tz.getLocation(accountTimezone!),
          year,
          month,
          day,
          hour,
          minute,
          second,
        );
  void _normalizeRecordDates() {
    for (var index = 0; index < messages.length; index++) {
      final entry = messages[index];
      messages[index] = Entry(
        id: entry.id,
        chatId: entry.chatId,
        text: entry.text,
        createdAt: displayTime(entry.createdAt),
        aiStatus: entry.aiStatus,
        revisedFrom: entry.revisedFrom,
      );
    }
    for (final record in records) {
      if (record.dueAt != null) record.dueAt = displayTime(record.dueAt!);
      if (record.endAt != null) record.endAt = displayTime(record.endAt!);
      if (record.startAt != null) record.startAt = displayTime(record.startAt!);
      record.reminderTimes = record.reminderTimes.map(displayTime).toList();
    }
  }

  DateTime localReminderTime(DateTime instant) {
    final hours = accountPreferences['quiet_hours'];
    if (hours is! Map || hours['enabled'] != true || accountTimezone == null) {
      return instant;
    }
    final zone = tz.getLocation(accountTimezone!);
    final local = tz.TZDateTime.from(instant, zone);
    int minute(String value) {
      final parts = value.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final start = minute(hours['start']);
    final end = minute(hours['end']);
    final current = local.hour * 60 + local.minute;
    final quiet =
        start != end &&
        (start < end
            ? current >= start && current < end
            : current >= start || current < end);
    if (!quiet) return instant;
    return tz.TZDateTime(
      zone,
      local.year,
      local.month,
      local.day + (start > end && current >= start ? 1 : 0),
      end ~/ 60,
      end % 60,
    );
  }

  final List<Chat> chats = [
    Chat('inbox', 'Inbox'),
    Chat('university', 'University'),
    Chat('personal', 'Personal'),
  ];
  final List<Entry> messages = [];
  final List<ProductivityRecord> records = [];
  final List<Map<String, dynamic>> proposals = [];
  final List<Map<String, dynamic>> reminders = [];
  final List<String> recentSearches = [];
  void rememberSearch(String value) {
    final term = value.trim();
    if (term.isEmpty || storageError != null) return;
    final limited = term.length > 200 ? term.substring(0, 200) : term;
    recentSearches.removeWhere(
      (item) => item.toLowerCase() == limited.toLowerCase(),
    );
    recentSearches.insert(0, limited);
    if (recentSearches.length > 10) {
      recentSearches.removeRange(10, recentSearches.length);
    }
    changed(scheduleSync: false);
  }

  void clearRecentSearches() {
    recentSearches.clear();
    changed(scheduleSync: false);
  }

  final SelfTextApi api;
  final SelfTextNotifications notifications;
  String? notificationRecordId;
  String? notificationError;
  bool get quietHoursActive {
    final hours = accountPreferences['quiet_hours'];
    if (hours is! Map || hours['enabled'] != true) return false;
    int minute(String value) {
      final parts = value.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    try {
      final start = minute(hours['start']);
      final end = minute(hours['end']);
      final local = calendarNow;
      final current = local.hour * 60 + local.minute;
      return start == end
          ? false
          : start < end
          ? current >= start && current < end
          : current >= start || current < end;
    } catch (_) {
      return false;
    }
  }

  Future<void> enableNotifications() async {
    if (!signedIn) throw ApiException('Sign in first.');
    await localReminders.enable(_openLocal, handleReminderAction);
    await _scheduleLocal();
    await notifications.enable(api, sync, (id) {
      notificationRecordId = id;
      notifyListeners();
    });
  }

  final SessionStorage _secure;
  late final EncryptedCache _cache = EncryptedCache(_secure);
  late final LocalReminders localReminders = LocalReminders(_secure);
  Timer? _localTimer;
  void _openLocal(String id) {
    if (id.startsWith('{')) id = jsonDecode(id)['record_id'] as String;
    notificationRecordId = id;
    notifyListeners();
  }

  Future<void> enableLocalReminders() async {
    await localReminders.enable(_openLocal, handleReminderAction);
    await _scheduleLocal();
    notificationError = localReminders.precise
        ? null
        : 'Allow Alarms & reminders for on-time alerts.';
    notifyListeners();
  }

  bool alarmSound = false;

  Future<void> setAlarmSound(bool value) async {
    await _secure.write(key: 'selftext.alarm_sound', value: value.toString());
    alarmSound = value;
    await _scheduleLocal();
    notifyListeners();
  }

  int get snoozeMinutes => LocalReminders.snoozeDuration(
    accountPreferences['snooze_minutes']?.toString(),
  );

  Future<void> setSnoozeMinutes(int minutes) async {
    if (minutes < 1 || minutes > 120) {
      throw ArgumentError('Choose 1–120 minutes.');
    }
    final workspace = activeStorageKey;
    if (api.token != null) {
      await api.request('PATCH', '/me', {
        'preferences': {...accountPreferences, 'snooze_minutes': minutes},
      });
    }
    if (workspace != activeStorageKey) {
      throw StateError('Account changed. Try again.');
    }
    accountPreferences['snooze_minutes'] = minutes;
    await _secure.write(
      key: 'selftext.snooze_minutes',
      value: minutes.toString(),
    );
    changed();
  }

  void handleReminderAction(String payload, String action) async {
    if (!payload.startsWith('{')) {
      final record = records.where((r) => r.id == payload).firstOrNull;
      if (record == null || record.done || storageError != null) return;
      if (action == 'dismiss') {
        records.remove(record);
        changed();
      } else if (action == 'done') {
        toggle(record);
      } else if (action.startsWith('snooze')) {
        final minutes = action.startsWith('snooze_')
            ? LocalReminders.snoozeDuration(action.substring(7))
            : snoozeMinutes;
        record.reminderTimes = [
          ...record.reminderTimes
              .where((t) => t.isAfter(DateTime.now()))
              .take(9),
          DateTime.now().add(Duration(minutes: minutes)),
        ];
        changed();
      }
      return;
    }
    try {
      await NotificationActions(_secure).handle(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: action,
          payload: payload,
        ),
      );
      await resumeNotificationActions();
    } catch (e) {
      notificationError = e.toString();
      notifyListeners();
    }
  }

  Future<void> _scheduleLocal() async {
    final open = records
        .where((r) => !r.done && r.status != 'cancelled')
        .toList();
    await _secure.write(
      key: 'selftext.snooze_minutes',
      value: snoozeMinutes.toString(),
    );
    await localReminders.clearCompleted(open.map((r) => r.id).toSet());
    await localReminders.replace([
      for (final r in open)
        for (final t in r.reminderTimes)
          LocalReminder(
            r.id,
            r.startAt != null && t.isAtSameMomentAs(r.startAt!)
                ? 'Start working · ${r.title}'
                : r.startAt != null &&
                      r.dueAt != null &&
                      t.isAtSameMomentAs(r.dueAt!)
                ? 'Due now · ${r.title}'
                : r.startAt != null && r.dueAt != null && t.isBefore(r.dueAt!)
                ? 'Deadline approaching · ${r.title}'
                : r.title,
            localReminderTime(t),
            reminderId:
                reminders
                        .where(
                          (m) =>
                              m['record_id'] == r.id &&
                              DateTime.parse(
                                m['trigger_at'],
                              ).isAtSameMomentAs(t),
                        )
                        .firstOrNull?['id']
                    as String?,
          ),
    ]);
  }

  String? userId, email, syncError;
  bool syncing = false;
  Timer? _syncTimer;
  Completer<void>? _syncCompletion;
  int _revision = 0;
  final Set<String> _knownMessages = {}, _knownChats = {};
  final Map<String, String> _knownRecords = {};
  String get activeStorageKey =>
      userId == null ? storageKey : '$storageKey.account.$userId';
  bool get signedIn => userId != null && api.token != null;
  String appearance = 'system';
  bool autoSaveReminders = true;
  Future<void> setAppearance(String value) async {
    if (!['system', 'light', 'dark'].contains(value)) return;
    await _secure.write(key: 'selftext.appearance', value: value);
    appearance = value;
    notifyListeners();
  }

  Future<void> setAutoSaveReminders(bool value) async {
    await _secure.write(
      key: 'selftext.auto-save-reminders',
      value: value.toString(),
    );
    autoSaveReminders = value;
    notifyListeners();
  }

  bool onboarded = false;
  String? storageError;
  SharedPreferences? _prefs;
  Future<void> _writes = Future.value();
  int _counter = 0;
  String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      appearance = await _secure.read(key: 'selftext.appearance') ?? 'system';
      autoSaveReminders =
          await _secure.read(key: 'selftext.auto-save-reminders') != 'false';
      try {
        api.token = await _secure.read(key: 'selftext.session');
        userId = await _secure.read(key: 'selftext.user');
        email = await _secure.read(key: 'selftext.email');
      } catch (_) {
        api.token = null;
        userId = null;
      }
      final raw = _prefs!.getString(activeStorageKey);
      if (raw == null) {
        if (signedIn) {
          try {
            _applyRemote(
              Map<String, dynamic>.from(await api.request('GET', '/export')),
              List<dynamic>.from(await api.request('GET', '/interpretations')),
            );
          } catch (e) {
            syncError = e.toString();
            chats
              ..clear()
              ..add(Chat(newId(), 'Inbox'));
          }
          onboarded = true;
          changed(scheduleSync: false);
          _restoreNotifications();
        }
        return;
      }
      final j =
          jsonDecode(await _cache.decrypt(raw, activeStorageKey))
              as Map<String, dynamic>;
      final loadedChats = (j['chats'] as List)
          .map((e) => Chat.fromJson(e))
          .toList();
      final loadedMessages = (j['messages'] as List)
          .map((e) => Entry.fromJson(e))
          .toList();
      final loadedRecords = (j['records'] as List)
          .map((e) => ProductivityRecord.fromJson(e))
          .toList();
      if (loadedChats.isEmpty) throw const FormatException('Missing inbox');
      chats
        ..clear()
        ..addAll(loadedChats);
      messages
        ..clear()
        ..addAll(loadedMessages);
      records
        ..clear()
        ..addAll(loadedRecords);
      onboarded = j['onboarded'] ?? false;
      accountTimezone = j['accountTimezone'];
      accountPreferences = Map<String, dynamic>.from(
        j['accountPreferences'] ?? {},
      );
      _normalizeRecordDates();
      recentSearches
        ..clear()
        ..addAll(List<String>.from(j['recentSearches'] ?? []));
      _knownMessages.addAll(List<String>.from(j['knownMessages'] ?? []));
      _knownChats.addAll(List<String>.from(j['knownChats'] ?? []));
      _knownRecords.addAll(Map<String, String>.from(j['knownRecords'] ?? {}));
      proposals.addAll(
        (j['proposals'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e),
        ),
      );
      reminders.addAll(
        (j['reminders'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e),
        ),
      );
      if (signedIn) {
        _syncTimer = Timer(const Duration(seconds: 1), sync);
        _restoreNotifications();
      }
      changed(scheduleSync: false);
    } catch (_) {
      storageError =
          'Local data could not be loaded. Avoid creating new items until storage is available.';
    } finally {
      if (storageError == null) {
        try {
          await drainNotificationActions();
          alarmSound =
              await _secure.read(key: 'selftext.alarm_sound') == 'true';
          await localReminders.restore(_openLocal, handleReminderAction);
          await _scheduleLocal();
        } catch (e) {
          notificationError = e.toString();
        }
      }
    }
  }

  Future<void> flush() => _writes;
  List<String> conflictsOn(DateTime day) {
    final events = records
        .where(
          (r) =>
              r.kind == RecordKind.event &&
              !r.done &&
              r.status != 'cancelled' &&
              r.dueAt != null &&
              r.endAt != null &&
              r.dueAt!.isBefore(
                calendarTime(day.year, day.month, day.day + 1),
              ) &&
              r.endAt!.isAfter(calendarTime(day.year, day.month, day.day)),
        )
        .toList();
    final result = <String>[];
    for (var i = 0; i < events.length; i++) {
      for (var j = i + 1; j < events.length; j++) {
        if (events[i].dueAt!.isBefore(events[j].endAt!) &&
            events[j].dueAt!.isBefore(events[i].endAt!)) {
          result.add('${events[i].title} / ${events[j].title}');
        }
      }
    }
    return result;
  }

  void changed({bool scheduleSync = true}) {
    if (_prefs != null) {
      _localTimer?.cancel();
      _localTimer = Timer(const Duration(milliseconds: 300), () {
        unawaited(
          _scheduleLocal().catchError((e) {
            notificationError = e.toString();
            notifyListeners();
          }),
        );
      });
    }
    _revision++;
    notifyListeners();
    if (_prefs == null || storageError != null) return;
    final raw = jsonEncode({
      'chats': chats.map((e) => e.toJson()).toList(),
      'messages': messages.map((e) => e.toJson()).toList(),
      'records': records.map((e) => e.toJson()).toList(),
      'onboarded': onboarded,
      'knownMessages': _knownMessages.toList(),
      'knownChats': _knownChats.toList(),
      'knownRecords': _knownRecords,
      'proposals': proposals,
      'reminders': reminders,
      'recentSearches': recentSearches,
      'accountTimezone': accountTimezone,
      'accountPreferences': accountPreferences,
    });
    final key = activeStorageKey;
    _writes = _writes.then((_) async {
      try {
        if (!await _prefs!.setString(key, await _cache.encrypt(raw, key))) {
          throw StateError('Save failed');
        }
      } catch (_) {
        storageError =
            'Changes are in memory, but could not be saved to this device.';
        notifyListeners();
      }
    });
    if (scheduleSync && signedIn && !syncing) {
      _syncTimer?.cancel();
      _syncTimer = Timer(const Duration(milliseconds: 600), sync);
    }
  }

  Map<String, dynamic> _recordPayload(ProductivityRecord r) => {
    'title': r.title,
    'body': r.body,
    'kind': r.kind.name,
    'chat_id': r.chatId,
    'source_message_id': r.sourceId,
    'status': r.done
        ? (r.status == 'cancelled' ? 'cancelled' : 'done')
        : (['inbox', 'planned', 'in_progress'].contains(r.status)
              ? r.status
              : 'planned'),
    'priority': r.priority,
    'due_at': r.dueAt?.toUtc().toIso8601String(),
    'end_at': r.endAt?.toUtc().toIso8601String(),
    'start_at': r.startAt?.toUtc().toIso8601String(),
    'all_day': r.allDay,
    'location': r.location,
    'recurrence': r.recurrence,
    'recurrence_scope': r.recurrenceScope,
    'recurrence_template': r.recurrenceTemplate,
    'pinned': r.pinned,
    'tags': r.tags,
    'subtasks': r.subtasks,
    'reminders': r.reminderTimes
        .map((t) => t.toUtc().toIso8601String())
        .toList(),
  };
  Future<void> signIn(
    String address,
    String password, {
    bool register = false,
  }) async {
    if (signedIn) {
      if (register || address.trim().toLowerCase() != email?.toLowerCase()) {
        throw ApiException(
          'Reconnect using the same account. Sign out before changing accounts.',
        );
      }
      final session = await api.authenticate(address, password);
      if (session['user']['id'] != userId) {
        throw ApiException('Reconnect using the original account.');
      }
      api.token = session['access_token'];
      await _secure.write(key: 'selftext.session', value: api.token);
      await sync();
      return;
    }
    await flush();
    final session = await api.authenticate(
      address,
      password,
      register: register,
    );
    api.token = session['access_token'];
    final data = Map<String, dynamic>.from(await api.request('GET', '/export'));
    final interpretations = List<dynamic>.from(
      await api.request('GET', '/interpretations'),
    );
    _localTimer?.cancel();
    await localReminders.disable();
    userId = session['user']['id'];
    email = session['user']['email'];
    await _secure.write(key: 'selftext.session', value: api.token);
    await _secure.write(key: 'selftext.user', value: userId);
    await _secure.write(key: 'selftext.email', value: email);
    _knownChats.clear();
    _knownMessages.clear();
    _knownRecords.clear();
    proposals.clear();
    reminders.clear();
    recentSearches.clear();
    if (_prefs?.getString(activeStorageKey) != null) {
      // Preserve unsynced account changes when signing back in.
      await load();
    } else {
      _applyRemote(data, interpretations);
    }
    onboarded = true;
    await _restoreNotifications(requestPermission: true);
    changed();
  }

  Future<void> signOut() async {
    if (syncing) throw ApiException('Wait for the current sync to finish.');
    await flush();
    await notifications.disable(api);
    await localReminders.disable();
    _syncTimer?.cancel();
    await _secure.delete(key: 'selftext.session');
    await _secure.delete(key: 'selftext.firebase-refresh');
    await _secure.delete(key: 'selftext.user');
    await _secure.delete(key: 'selftext.email');
    api.token = null;
    userId = null;
    email = null;
    accountTimezone = null;
    accountPreferences = {};
    syncError = null;
    chats
      ..clear()
      ..addAll([
        Chat('inbox', 'Inbox'),
        Chat('university', 'University'),
        Chat('personal', 'Personal'),
      ]);
    messages.clear();
    records.clear();
    proposals.clear();
    reminders.clear();
    recentSearches.clear();
    _knownMessages.clear();
    _knownChats.clear();
    _knownRecords.clear();
    await load();
    notifyListeners();
  }

  Future<void> revokeSessions() async {
    if (syncing) throw ApiException('Wait for sync to finish.');
    await flush();
    await notifications.disable(api);
    await api.request('POST', '/auth/revoke-all');
    await signOut();
  }

  Future<void> deleteAccount({String? password}) async {
    if (syncing) throw ApiException('Wait for sync to finish.');
    final deletingUser = userId;
    final deletingWorkspace = activeStorageKey;
    String? firebaseIdToken;
    if (SelfTextApi.firebaseKey.isNotEmpty) {
      if (password == null || password.isEmpty || email == null) {
        throw ApiException('Enter your SelfText password to confirm deletion.');
      }
      firebaseIdToken = await api.reauthenticateFirebase(email!, password);
      if (userId != deletingUser || activeStorageKey != deletingWorkspace) {
        throw ApiException('Account changed. Open account settings again.');
      }
    }
    _syncTimer?.cancel();
    await flush();
    if (userId != deletingUser || activeStorageKey != deletingWorkspace) {
      throw ApiException('Account changed. Open account settings again.');
    }
    await notifications.disable(api);
    if (userId != deletingUser || activeStorageKey != deletingWorkspace) {
      throw ApiException('Account changed. Open account settings again.');
    }
    await api.request('DELETE', '/account', {
      if (firebaseIdToken != null) 'firebase_id_token': firebaseIdToken,
    });
    final workspace = deletingWorkspace;
    await _prefs?.remove(workspace);
    await _secure.delete(key: '$workspace.encryption-key');
    if (userId == deletingUser) await signOut();
  }

  void _applyRemote(Map<String, dynamic> data, List<dynamic> interpretations) {
    accountTimezone = data['user']?['timezone'];
    accountPreferences = Map<String, dynamic>.from(
      data['user']?['preferences'] ?? {},
    );
    chats
      ..clear()
      ..addAll(
        (data['chats'] as List).map(
          (c) => Chat(c['id'], c['title'], kind: c['kind'] ?? 'chat'),
        ),
      );
    messages
      ..clear()
      ..addAll(
        (data['messages'] as List).map(
          (m) => Entry(
            id: m['id'],
            chatId: m['chat_id'],
            text: m['content'],
            createdAt: displayTime(DateTime.parse(m['created_at'])),
            aiStatus: m['ai_status'] ?? 'pending',
            revisedFrom: m['revised_from'],
          ),
        ),
      );
    records
      ..clear()
      ..addAll(
        (data['records'] as List).map(
          (r) => ProductivityRecord(
            id: r['id'],
            title: r['title'],
            kind: RecordKind.values.byName(r['kind']),
            chatId: r['chat_id'],
            sourceId: r['source_message_id'],
            dueAt: r['due_at'] == null
                ? null
                : displayTime(DateTime.parse(r['due_at'])),
            endAt: r['end_at'] == null
                ? null
                : displayTime(DateTime.parse(r['end_at'])),
            startAt: r['start_at'] == null
                ? null
                : displayTime(DateTime.parse(r['start_at'])),
            allDay: r['all_day'] ?? false,
            location: r['location'] ?? '',
            done: r['status'] == 'done' || r['status'] == 'cancelled',
            priority: r['priority'],
            body: r['body'],
            status: r['status'],
            recurrence: r['recurrence'],
            recurrenceScope: r['recurrence_scope'] ?? 'series',
            recurrenceTemplate: r['recurrence_template'] == null
                ? null
                : Map<String, dynamic>.from(r['recurrence_template']),
            pinned: r['pinned'] ?? false,
            tags: List<String>.from(r['tags'] ?? []),
            subtasks: (r['subtasks'] as List? ?? [])
                .map((t) => Map<String, dynamic>.from(t))
                .toList(),
            reminderTimes: (data['reminders'] as List)
                .where(
                  (t) =>
                      t['record_id'] == r['id'] &&
                      [
                        'scheduled',
                        'due',
                        'delivered',
                        'failed',
                      ].contains(t['status']),
                )
                .map((t) => displayTime(DateTime.parse(t['trigger_at'])))
                .toList(),
          ),
        ),
      );
    final savedReplies = {
      for (final p in proposals)
        if (p['chat_reply'] != null) p['id']: p['chat_reply'],
    };
    proposals
      ..clear()
      ..addAll(
        interpretations.map(
          (i) => {
            ...Map<String, dynamic>.from(i),
            if (savedReplies.containsKey(i['id']))
              'chat_reply': savedReplies[i['id']],
          },
        ),
      );
    reminders
      ..clear()
      ..addAll(
        (data['reminders'] as List).map((r) => Map<String, dynamic>.from(r)),
      );
    _knownChats
      ..clear()
      ..addAll(chats.map((c) => c.id));
    _knownMessages
      ..clear()
      ..addAll(messages.map((m) => m.id));
    _knownRecords
      ..clear()
      ..addEntries(
        records.map((r) => MapEntry(r.id, jsonEncode(_recordPayload(r)))),
      );
  }

  Future<void> resumeNotificationActions() async {
    if (storageError != null) return;
    try {
      await drainNotificationActions();
      if (signedIn) {
        await _restoreNotifications();
        await sync();
      }
    } catch (error) {
      notificationError = error.toString();
      notifyListeners();
    }
  }

  Future<void>? _actionDrain;
  Future<void> drainNotificationActions() {
    if (_actionDrain != null) return _actionDrain!;
    final operation = _drainNotificationActions();
    _actionDrain = operation;
    return operation.whenComplete(() => _actionDrain = null);
  }

  Future<void> _drainNotificationActions() async {
    final workspace = activeStorageKey, owner = userId ?? 'guest';
    final entries = (await _secure.readAll()).entries
        .where((e) => e.key.startsWith('${NotificationActions.prefix}$owner.'))
        .toList();
    entries.sort((a, b) => a.value.compareTo(b.value));
    for (final item in entries) {
      if (workspace != activeStorageKey) return;
      final receipt = jsonDecode(item.value) as Map;
      if (receipt['owner'] != owner) continue;
      final record = records
          .where((r) => r.id == receipt['record_id'])
          .firstOrNull;
      if (record != null) {
        final action = receipt['action'] as String;
        if (action == 'dismiss') {
          records.removeWhere((r) => r.id == record.id);
          reminders.removeWhere((r) => r['record_id'] == record.id);
        }
        if (action == 'done' && !record.done) {
          record.done = true;
          record.status = 'done';
          completeOfflineRecurrence(record);
        }
        if (action.startsWith('snooze') && !record.done) {
          final until = DateTime.parse(receipt['until']);
          if (!record.reminderTimes.any((t) => t.isAtSameMomentAs(until))) {
            record.reminderTimes = [
              ...record.reminderTimes
                  .where((t) => t.isAfter(DateTime.now()))
                  .take(9),
              until,
            ];
          }
        }
        if (receipt['cloud'] == true &&
            action.startsWith('snooze') &&
            _knownRecords.containsKey(record.id)) {
          final baseline =
              jsonDecode(_knownRecords[record.id]!) as Map<String, dynamic>;
          baseline['reminders'] = record.reminderTimes
              .map((t) => t.toUtc().toIso8601String())
              .toList();
          _knownRecords[record.id] = jsonEncode(baseline);
        }
        if (receipt['cloud'] == true &&
            action == 'done' &&
            _knownRecords.containsKey(record.id)) {
          final baseline =
              jsonDecode(_knownRecords[record.id]!) as Map<String, dynamic>;
          baseline['status'] = 'done';
          _knownRecords[record.id] = jsonEncode(baseline);
        }
        changed(scheduleSync: false);
        await flush();
        if (storageError != null) return;
      }
      // A newer action may have replaced this receipt while we were saving.
      if (await _secure.read(key: item.key) == item.value) {
        await _secure.delete(key: item.key);
      }
    }
  }

  Future<void> sync() async {
    if (!signedIn) return;
    if (syncing) {
      await _syncCompletion?.future;
      return;
    }
    _syncCompletion = Completer<void>();
    _syncTimer?.cancel();
    syncing = true;
    syncError = null;
    notifyListeners();
    var revision = _revision;
    try {
      await drainNotificationActions();
      revision = _revision;
      for (final c in List<Chat>.from(chats)) {
        if (!_knownChats.contains(c.id)) {
          await api.request('POST', '/chats', {
            'title': c.title,
            'kind': c.kind,
            'client_id': c.id,
          });
          _knownChats.add(c.id);
        }
      }
      for (final m in List<Entry>.from(messages)) {
        if (!_knownMessages.contains(m.id)) {
          final data = await api
              .request('POST', '/chats/${m.chatId}/messages', {
                'content': m.text,
                'client_id': m.id,
                'created_at': m.createdAt.toUtc().toIso8601String(),
                'revised_from': m.revisedFrom,
              });
          _knownMessages.add(m.id);
          m.aiStatus = data['message']?['ai_status'] ?? 'pending';
          if (data['interpretation'] != null) {
            final proposal = Map<String, dynamic>.from(data['interpretation']);
            proposals.add(proposal);
            if (autoSaveReminders &&
                !records.any((record) => record.sourceId == m.id) &&
                m.revisedFrom == null &&
                canAutoSaveReminder(proposal, m.text)) {
              try {
                await api.request(
                  'POST',
                  '/interpretations/${proposal['id']}/accept',
                  {},
                );
                proposal['status'] = 'accepted';
              } catch (_) {
                // Preserve the editable suggestion if saving fails; never silently
                // report a scheduled reminder when the server has not accepted it.
              }
            }
          }
          if (data['error'] != null) syncError = data['error'];
        }
      }
      for (final r in List<ProductivityRecord>.from(records)) {
        final payload = _recordPayload(r);
        final fingerprint = jsonEncode(payload);
        if (_knownRecords[r.id] == fingerprint) continue;
        if (!_knownRecords.containsKey(r.id)) {
          final create = Map<String, dynamic>.from(payload)..remove('status');
          create['client_id'] = r.id;
          await api.request('POST', '/records', create);
          // A previous POST may have succeeded while its response was lost.
          // Apply the latest local fields after the idempotent create as well.
          final latest = Map<String, dynamic>.from(payload)
            ..remove('kind')
            ..remove('source_message_id');
          await api.request('PATCH', '/records/${r.id}', latest);
        } else {
          final baseline = jsonDecode(_knownRecords[r.id]!) as Map;
          final update = <String, dynamic>{
            for (final field in payload.entries)
              if (field.key != 'kind' &&
                  field.key != 'source_message_id' &&
                  jsonEncode(field.value) != jsonEncode(baseline[field.key]))
                field.key: field.value,
          };
          if (update.isNotEmpty) {
            await api.request('PATCH', '/records/${r.id}', update);
          }
        }
        _knownRecords[r.id] = fingerprint;
      }
      for (final id in _knownRecords.keys.toList()) {
        if (!records.any((r) => r.id == id)) {
          try {
            await api.request('DELETE', '/records/$id');
          } on ApiException catch (e) {
            if (e.statusCode != 404) rethrow;
          }
          _knownRecords.remove(id);
        }
      }
      if (revision == _revision) {
        final data = Map<String, dynamic>.from(
          await api.request('GET', '/export'),
        );
        final interpretations = List<dynamic>.from(
          await api.request('GET', '/interpretations'),
        );
        if (revision == _revision) _applyRemote(data, interpretations);
      }
    } catch (e) {
      syncError = e.toString();
    } finally {
      syncing = false;
      // Persist sync metadata without scheduling an endless refresh loop.
      changed(scheduleSync: false);
      _syncCompletion?.complete();
      _syncCompletion = null;
      if (revision + 1 != _revision && syncError == null) {
        _syncTimer = Timer(const Duration(milliseconds: 600), sync);
      }
    }
  }

  static bool canAutoSaveReminder(Map<String, dynamic> proposal, String text) {
    if (!RegExp(
      r'remind|alarm|notify|یاد|yaad|yad',
      caseSensitive: false,
    ).hasMatch(text)) {
      return false;
    }
    if (proposal['status'] != 'pending' ||
        proposal['structured_output']?['intent'] == 'plan') {
      return false;
    }
    final actions = proposal['structured_output']?['actions'] as List? ?? [];
    if (actions.isEmpty || actions.length > 10) return false;
    return actions.every((a) {
      if (!['reminder', 'task'].contains(a['kind']) ||
          (a['ambiguities'] as List? ?? []).isNotEmpty ||
          (a['confidence'] as num? ?? 0) < 0.7) {
        return false;
      }
      final times = a['reminders'] as List? ?? [];
      return times.isNotEmpty &&
          times.every(
            (t) => DateTime.tryParse('$t')?.isAfter(DateTime.now()) == true,
          );
    });
  }

  Future<void> acceptProposal(
    Map<String, dynamic> proposal,
    List<Map<String, dynamic>> actions,
  ) async {
    await sync();
    if (syncError != null) throw ApiException(syncError!);
    await api.request('POST', '/interpretations/${proposal['id']}/accept', {
      'actions': actions
          .map(
            (a) => a['kind'] == 'note'
                ? {...a, 'space_kind': 'note', 'space_title': null}
                : a,
          )
          .toList(),
    });
    await sync();
  }

  final Set<String> retryingCaptures = {};
  Future<void> retryCapture(Entry entry) async {
    if (!signedIn) throw ApiException('Sign in to retry interpretation.');
    if (syncing) throw ApiException('Wait for sync to finish before retrying.');
    if (!retryingCaptures.add(entry.id)) return;
    final workspace = userId;
    notifyListeners();
    try {
      final result = await api
          .request('POST', '/chats/${entry.chatId}/messages', {
            'content': entry.text,
            'client_id': entry.id,
            'created_at': entry.createdAt.toUtc().toIso8601String(),
            'revised_from': entry.revisedFrom,
          });
      if (userId != workspace) return;
      entry.aiStatus = result['message']?['ai_status'] ?? 'failed';
      final proposal = result['interpretation'];
      if (proposal != null &&
          !proposals.any((p) => p['id'] == proposal['id'])) {
        proposals.add(Map<String, dynamic>.from(proposal));
      }
      changed(scheduleSync: false);
      if (result['error'] != null) throw ApiException(result['error']);
    } finally {
      retryingCaptures.remove(entry.id);
      notifyListeners();
    }
  }

  Future<void> rejectProposal(Map<String, dynamic> proposal) async {
    await api.request('POST', '/interpretations/${proposal['id']}/reject');
    await sync();
  }

  Future<Map<String, dynamic>> query(String text, {String? recordId}) async =>
      Map<String, dynamic>.from(
        await api.request('POST', '/ai/query', {
          'query': text,
          'record_id': recordId,
        }),
      );
  Future<void> applyCommand(String id, Map<String, dynamic> update) async {
    await api.request('PATCH', '/records/$id', update);
    await sync();
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    _syncTimer?.cancel();
    api.close();
    notifications.dispose();
    super.dispose();
  }

  // Sync is event-driven: launch, resume, user changes, notification actions,
  // push events and explicit refresh. An idle app must not keep cloud SQL awake.

  Future<void> _restoreNotifications({bool requestPermission = false}) async {
    if (!signedIn || !notifications.supported) return;
    try {
      await localReminders.enable(
        _openLocal,
        handleReminderAction,
        requestExactPermission: true,
        requestOnlyOnce: true,
      );
      await _scheduleLocal();
      await notifications.enable(api, sync, (id) {
        notificationRecordId = id;
        notifyListeners();
      }, requestPermission: requestPermission);
      notificationError = localReminders.precise
          ? null
          : 'Allow Alarms & reminders for on-time alerts.';
    } catch (e) {
      notificationError = e.toString();
    }
    notifyListeners();
  }

  void finishOnboarding() {
    onboarded = true;
    changed();
  }

  Chat createChat(String title, {String kind = 'chat'}) {
    final chat = Chat(newId(), title.trim(), kind: kind);
    chats.add(chat);
    changed();
    return chat;
  }

  Entry capture(String chatId, String text) {
    final entry = Entry(
      id: newId(),
      chatId: chatId,
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    messages.add(entry);
    final quick = autoSaveReminders
        ? QuickReminder.parse(entry.text, entry.createdAt)
        : null;
    if (quick != null) {
      records.add(
        ProductivityRecord(
          id: newId(),
          title: quick.title,
          kind: RecordKind.task,
          chatId: chatId,
          sourceId: entry.id,
          dueAt: quick.dueAt,
          reminderTimes: [quick.dueAt],
        ),
      );
      entry.aiStatus = 'local';
      if (localReminders.supported && !localReminders.enabled) {
        unawaited(
          enableLocalReminders().catchError((Object error) {
            notificationError = error.toString();
            notifyListeners();
          }),
        );
      }
    }
    changed();
    return entry;
  }

  Entry reviseCapture(Entry original, String text) {
    if (!messages.any((entry) => entry.id == original.id) ||
        text.trim().isEmpty) {
      throw ApiException(
        'Choose an existing message and enter its revised text.',
      );
    }
    final revision = Entry(
      id: newId(),
      chatId: original.chatId,
      text: text.trim(),
      createdAt: original.createdAt,
      revisedFrom: original.id,
    );
    messages.add(revision);
    changed();
    return revision;
  }

  ProductivityRecord createRecord({
    required String title,
    required RecordKind kind,
    required String chatId,
    String? sourceId,
    DateTime? dueAt,
    DateTime? endAt,
    DateTime? startAt,
    bool allDay = false,
    String location = '',
    String priority = 'Normal',
    String body = '',
    String status = 'planned',
    String? recurrence,
    List<String>? tags,
    List<Map<String, dynamic>>? subtasks,
    List<DateTime>? reminderTimes,
  }) {
    final record = ProductivityRecord(
      id: newId(),
      title: title.trim(),
      kind: kind,
      chatId: chatId,
      sourceId: sourceId,
      dueAt: dueAt,
      endAt: endAt,
      startAt: startAt,
      allDay: allDay,
      location: location,
      priority: priority,
      body: body,
      status: status,
      done: status == 'done' || status == 'cancelled',
      recurrence: recurrence,
      tags: tags,
      subtasks: subtasks,
      reminderTimes: reminderTimes,
    );
    records.add(record);
    completeOfflineRecurrence(record);
    changed();
    return record;
  }

  void toggle(ProductivityRecord record) {
    record.done = !record.done;
    record.status = record.done ? 'done' : 'planned';
    completeOfflineRecurrence(record);
    changed();
  }

  void rescheduleRecord(ProductivityRecord record, DateTime due) {
    if (record.dueAt == null || record.done || record.status == 'cancelled') {
      throw ApiException('Choose an active scheduled item.');
    }
    final delta = due.difference(record.dueAt!);
    final upcoming = record.reminderTimes
        .where((t) => t.isAfter(DateTime.now()))
        .map((t) => t.add(delta))
        .toList();
    if (upcoming.any((t) => !t.isAfter(DateTime.now()))) {
      throw ApiException(
        'This move puts a reminder in the past. Edit its reminders first.',
      );
    }
    record.dueAt = due;
    record.endAt = record.endAt?.add(delta);
    record.startAt = record.startAt?.add(delta);
    record.reminderTimes = [
      ...record.reminderTimes.where((t) => !t.isAfter(DateTime.now())),
      ...upcoming,
    ];
    changed();
  }

  void completeOfflineRecurrence(ProductivityRecord record) {
    final template = record.recurrenceTemplate;
    final base = template == null
        ? record
        : ProductivityRecord(
            id: record.id,
            title: template['title'],
            kind: record.kind,
            chatId: record.chatId,
            sourceId: record.sourceId,
            dueAt: DateTime.tryParse(template['due_at'] ?? ''),
            endAt: DateTime.tryParse(template['end_at'] ?? ''),
            startAt: DateTime.tryParse(template['start_at'] ?? ''),
            allDay: template['all_day'] ?? false,
            location: template['location'] ?? '',
            body: template['body'] ?? '',
            priority: template['priority'] ?? 'Normal',
            recurrence: template['recurrence'],
            tags: List<String>.from(template['tags'] ?? []),
            subtasks: record.subtasks,
            reminderTimes: (template['reminders'] as List? ?? [])
                .map((value) => DateTime.parse(value))
                .toList(),
          );
    if (signedIn ||
        !record.done ||
        record.status != 'done' ||
        base.recurrence == null ||
        base.dueAt == null ||
        record.recurrenceSuccessorId != null) {
      return;
    }
    var next = displayTime(base.dueAt!);
    final current = DateTime.now();
    for (var attempts = 0; attempts < 5000; attempts++) {
      if (base.recurrence == 'monthly') {
        final lastDay = DateTime(next.year, next.month + 2, 0).day;
        next = calendarTime(
          next.year,
          next.month + 1,
          next.day > lastDay ? lastDay : next.day,
          next.hour,
          next.minute,
          next.second,
        );
      } else {
        next = calendarTime(
          next.year,
          next.month,
          next.day + (base.recurrence == 'weekly' ? 7 : 1),
          next.hour,
          next.minute,
          next.second,
        );
      }
      if (base.recurrence == 'weekdays' && next.weekday >= DateTime.saturday) {
        continue;
      }
      if (next.isAfter(current)) break;
    }
    if (!next.isAfter(current)) {
      syncError = 'Repeating item is too far in the past. Reschedule it first.';
      return;
    }
    final successor = ProductivityRecord(
      id: newId(),
      title: base.title,
      kind: base.kind,
      chatId: base.chatId,
      sourceId: base.sourceId,
      dueAt: next,
      startAt: base.startAt == null
          ? null
          : next.add(base.startAt!.difference(base.dueAt!)),
      allDay: base.allDay,
      location: base.location,
      endAt: base.endAt == null
          ? null
          : next.add(base.endAt!.difference(base.dueAt!)),
      priority: base.priority,
      body: base.body,
      recurrence: base.recurrence,
      tags: List.of(base.tags),
      subtasks: base.subtasks.map((item) => {...item, 'done': false}).toList(),
      reminderTimes: base.reminderTimes
          .map((t) => next.add(t.difference(base.dueAt!)))
          .where((t) => t.isAfter(current))
          .toList(),
    );
    record.recurrenceSuccessorId = successor.id;
    records.add(successor);
  }

  void prepareRecurringEdit(ProductivityRecord record, String scope) {
    if (record.recurrence != null && record.recurrenceTemplate == null) {
      record.recurrenceTemplate =
          Map<String, dynamic>.from(_recordPayload(record))
            ..remove('recurrence_template')
            ..remove('recurrence_scope');
    }
    record.recurrenceScope = scope;
  }

  void finishRecurringEdit(ProductivityRecord record) {
    if (record.recurrenceScope != 'series') return;
    final oldDue = DateTime.tryParse(
      record.recurrenceTemplate?['due_at'] ?? '',
    );
    record.recurrenceTemplate = record.recurrence == null
        ? null
        : (Map<String, dynamic>.from(_recordPayload(record))
            ..remove('recurrence_template')
            ..remove('recurrence_scope'));
    if (signedIn) return;
    var id = record.recurrenceSuccessorId;
    final seen = <String>{record.id};
    while (id != null && seen.add(id)) {
      final child = records.where((item) => item.id == id).firstOrNull;
      if (child == null) break;
      if (!child.done && child.status != 'cancelled') {
        child.title = record.title;
        child.body = record.body;
        child.priority = record.priority;
        child.tags = List.of(record.tags);
        child.recurrence = record.recurrence;
        child.location = record.location;
        child.allDay = record.allDay;
        child.chatId = record.chatId;
        if (oldDue != null && record.dueAt != null && child.dueAt != null) {
          final delta = record.dueAt!.difference(oldDue);
          child.dueAt = child.dueAt!.add(delta);
          child.endAt = child.endAt?.add(delta);
          child.startAt = child.startAt?.add(delta);
          child.reminderTimes = child.reminderTimes
              .map((time) => time.add(delta))
              .toList();
        }
        child.recurrenceTemplate = null;
        child.recurrenceScope = 'series';
      }
      id = child.recurrenceSuccessorId;
    }
  }

  String chatTitle(String id) =>
      chats.where((c) => c.id == id).firstOrNull?.displayTitle ?? 'Inbox';
  List<Entry> history(String id) =>
      messages.where((m) => m.chatId == id).toList();
  List<ProductivityRecord> get tasks =>
      records.where((r) => r.kind == RecordKind.task).toList();
  List<ProductivityRecord> get notes =>
      records.where((r) => r.kind == RecordKind.note).toList()..sort(
        (a, b) => a.pinned == b.pinned
            ? 0
            : a.pinned
            ? -1
            : 1,
      );
  List<ProductivityRecord> onDay(DateTime day) =>
      records
          .where(
            (r) =>
                r.dueAt != null &&
                r.kind != RecordKind.note &&
                (sameDay(r.dueAt!, day) ||
                    (r.kind == RecordKind.event &&
                        r.endAt != null &&
                        r.dueAt!.isBefore(
                          calendarTime(day.year, day.month, day.day + 1),
                        ) &&
                        r.endAt!.isAfter(
                          calendarTime(day.year, day.month, day.day),
                        ))),
          )
          .toList()
        ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
