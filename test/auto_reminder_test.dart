import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show FakeApi, MemorySessionStorage;

class AutoApi extends FakeApi {
  bool ambiguous = false;
  int accepts = 0;
  final alerts = <Map<String, dynamic>>[];
  final proposals = <Map<String, dynamic>>[];
  @override
  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'POST' && path == '/records') {
      final record = await super.request(method, path, body);
      for (final trigger in body!['reminders'] as List? ?? []) {
        if (!alerts.any(
          (alert) =>
              alert['record_id'] == record['id'] &&
              alert['trigger_at'] == trigger,
        )) {
          alerts.add({
            'id': 'alert-${alerts.length}',
            'record_id': record['id'],
            'trigger_at': trigger,
            'status': 'scheduled',
          });
        }
      }
      return record;
    }
    if (method == 'POST' && path.endsWith('/messages')) {
      await super.request(method, path, body);
      messages.last['ai_status'] = 'proposed';
      final due = DateTime.now()
          .add(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String();
      final proposal = <String, dynamic>{
        'id': 'proposal-${body!['client_id']}',
        'message_id': body['client_id'],
        'status': 'pending',
        'structured_output': {
          'actions': [
            {
              'kind': 'reminder',
              'title': 'Call Ali',
              'due_at': due,
              'reminders': [due],
              'confidence': 0.95,
              'ambiguities': ambiguous ? ['Confirm time'] : [],
            },
          ],
        },
      };
      proposals.add(proposal);
      return {'message': messages.last, 'interpretation': proposal};
    }
    if (method == 'POST' && path.endsWith('/accept')) {
      accepts++;
      final proposal = proposals.firstWhere((p) => path.contains(p['id']));
      final a = proposal['structured_output']['actions'][0];
      final id = 'record-$accepts';
      records[id] = {
        'id': id,
        'kind': 'task',
        'title': a['title'],
        'body': '',
        'priority': 'Normal',
        'chat_id': 'cloud-inbox',
        'source_message_id': proposal['message_id'],
        'due_at': a['due_at'],
        'status': 'planned',
      };
      alerts.add({
        'id': 'alert-$accepts',
        'record_id': id,
        'trigger_at': a['reminders'][0],
        'status': 'scheduled',
      });
      proposal['status'] = 'accepted';
      return {
        'records': [records[id]],
      };
    }
    if (path == '/interpretations') return proposals;
    if (path == '/export') {
      final data = await super.request(method, path, body);
      data['reminders'] = alerts;
      return data;
    }
    return super.request(method, path, body);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'clear countdown saves automatically once and delivered reminders remain visible',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = AutoApi();
      final store = SelfTextStore(
        api: api,
        sessionStorage: MemorySessionStorage(),
      );
      addTearDown(store.dispose);
      await store.load();
      await store.signIn('test@example.com', 'test');
      store.capture('cloud-inbox', 'Remind me in 5 minutes to call Ali');
      await store.sync();
      expect(
        api.accepts,
        0,
        reason: 'Local-first countdown must not also accept the server draft',
      );
      expect(store.records.single.reminderTimes, hasLength(1));
      await store.sync();
      expect(api.accepts, 0);
      api.alerts.single['status'] = 'delivered';
      await store.sync();
      expect(store.records.single.reminderTimes, hasLength(1));
    },
  );
  test(
    'ambiguous reminders stay pending and auto-save can be disabled',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = AutoApi()..ambiguous = true;
      final storage = MemorySessionStorage();
      final store = SelfTextStore(api: api, sessionStorage: storage);
      addTearDown(store.dispose);
      await store.load();
      await store.signIn('test@example.com', 'test');
      store.capture('cloud-inbox', 'Remind me later to call Ali');
      await store.sync();
      expect(api.accepts, 0);
      expect(store.proposals.single['status'], 'pending');
      api.ambiguous = false;
      await store.setAutoSaveReminders(false);
      store.capture('cloud-inbox', 'Remind me in 5 minutes to call Ali');
      await store.sync();
      expect(api.accepts, 0);
      expect(storage.values['selftext.auto-save-reminders'], 'false');
      await store.setAppearance('dark');
      expect(storage.values['selftext.appearance'], 'dark');
    },
  );
  test('expired low-confidence and non-reminder captures never auto-save', () {
    Map<String, dynamic> p(String kind, String time, double confidence) => {
      'status': 'pending',
      'structured_output': {
        'actions': [
          {
            'kind': kind,
            'reminders': [time],
            'confidence': confidence,
            'ambiguities': [],
          },
        ],
      },
    };
    final future = DateTime.now()
        .add(const Duration(hours: 1))
        .toIso8601String();
    expect(
      SelfTextStore.canAutoSaveReminder(p('note', future, 0.9), 'Remind me'),
      false,
    );
    expect(
      SelfTextStore.canAutoSaveReminder(
        p('reminder', future, 0.5),
        'Remind me',
      ),
      false,
    );
    expect(
      SelfTextStore.canAutoSaveReminder(
        p(
          'reminder',
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
          0.9,
        ),
        'Remind me',
      ),
      false,
    );
    expect(
      SelfTextStore.canAutoSaveReminder(
        p('reminder', future, 0.9),
        'Buy some milk',
      ),
      false,
    );
  });
}
