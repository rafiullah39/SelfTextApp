import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_saver/file_saver.dart';
import 'store.dart';
import 'api.dart';

class EvaluationScreen extends StatefulWidget {
  const EvaluationScreen({super.key, required this.store});
  final SelfTextStore store;
  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  late final Future<dynamic> report = widget.store.api.request(
    'GET',
    '/evaluation',
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI evaluation')),
    body: FutureBuilder<dynamic>(
      future: report,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data as Map;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(data['notice']),
            const SizedBox(height: 16),
            for (final item in data['reports'] as List)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['provider'],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('${item['cases']} synthetic examples'),
                      const SizedBox(height: 12),
                      for (final metric in {
                        'Classification accuracy':
                            'exact_action_classification_accuracy',
                        'Action F1': 'action_f1',
                        'Explicit date accuracy':
                            'explicit_due_timestamp_accuracy',
                        'Clarification recall': 'required_clarification_recall',
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${metric.key}: ${((item[metric.value] as num? ?? 0) * 100).toStringAsFixed(1)}%',
                          ),
                        ),
                      Text(
                        'Provider errors: ${(item['provider_errors'] as List? ?? []).length}',
                      ),
                      Text(
                        'Average response: ${((item['mean_latency_ms'] as num) / 1000).toStringAsFixed(2)} seconds',
                      ),
                    ],
                  ),
                ),
              ),
            const Text(
              'Results measure these fixtures only. Review every AI suggestion before accepting it.',
            ),
          ],
        );
      },
    ),
  );
}

class AccountTools extends StatefulWidget {
  const AccountTools({super.key, required this.store});
  final SelfTextStore store;
  @override
  State<AccountTools> createState() => _AccountToolsState();
}

class _AccountToolsState extends State<AccountTools> {
  final zone = TextEditingController(text: 'Asia/Karachi'),
      start = TextEditingController(text: '22:00'),
      end = TextEditingController(text: '07:00');
  bool quiet = false, busy = true;
  Map<String, dynamic> preferences = {};
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await run(() async {
      final data = await widget.store.api.request('GET', '/me');
      zone.text = data['timezone'];
      preferences = Map<String, dynamic>.from(data['preferences']);
      final hours = preferences['quiet_hours'] as Map? ?? {};
      quiet = hours['enabled'] == true;
      start.text = hours['start'] ?? '22:00';
      end.text = hours['end'] ?? '07:00';
    });
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) message = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    await run(() async {
      await widget.store.sync();
      if (widget.store.syncError != null) {
        throw StateError(widget.store.syncError!);
      }
      final data = await widget.store.api.request('GET', '/export');
      final path = await FileSaver.instance.saveFile(
        name: 'selftext-export-${DateTime.now().millisecondsSinceEpoch}',
        bytes: Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
        ),
        fileExtension: 'json',
        mimeType: MimeType.custom,
        customMimeType: 'application/json',
      );
      message =
          'Export saved: $path. The export contains your personal data in readable form.';
    });
  }

  Future<void> remove() async {
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This removes your server data and Firebase account. Export anything you want to keep first. This cannot be undone.',
            ),
            if (SelfTextApi.firebaseKey.isNotEmpty)
              TextField(
                controller: password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'SelfText password',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    final enteredPassword = password.text;
    password.dispose();
    if (confirmed != true) return;
    await run(() async {
      await widget.store.deleteAccount(password: enteredPassword);
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    zone.dispose();
    start.dispose();
    end.dispose();
    super.dispose();
  }

  Widget timeTile(TextEditingController controller, String label) {
    final parts = controller.text.split(':');
    final time = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 22,
      minute: int.tryParse(parts.last) ?? 0,
    );
    return ListTile(
      title: Text(label),
      subtitle: Text(time.format(context)),
      trailing: const Icon(Icons.schedule),
      onTap: busy
          ? null
          : () async {
              final chosen = await showTimePicker(
                context: context,
                initialTime: time,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(alwaysUse24HourFormat: false),
                  child: child!,
                ),
              );
              if (chosen != null && mounted) {
                setState(
                  () => controller.text =
                      '${chosen.hour.toString().padLeft(2, '0')}:${chosen.minute.toString().padLeft(2, '0')}',
                );
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & account')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        Text(
          'You’re in control',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your notes are saved securely on your device. Signed-in data syncs to your account. When AI is enabled, your messages are sent to the AI provider; free Gemini inputs may be used to improve Google products.',
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Quiet hours'),
                subtitle: const Text('Pause cloud alerts during these hours.'),
                value: quiet,
                onChanged: busy ? null : (v) => setState(() => quiet = v),
              ),
              if (quiet) ...[timeTile(start, 'From'), timeTile(end, 'Until')],
              ExpansionTile(
                title: const Text('Account timezone'),
                subtitle: Text(zone.text),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: zone,
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        hintText: 'Asia/Karachi',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  await widget.store.api.request('PATCH', '/me', {
                    'timezone': zone.text.trim(),
                    'preferences': {
                      ...preferences,
                      'snooze_minutes': widget.store.snoozeMinutes,
                      'quiet_hours': {
                        'enabled': quiet,
                        'start': start.text.trim(),
                        'end': end.text.trim(),
                      },
                    },
                  });
                  await widget.store.sync();
                  message = 'Preferences saved.';
                }),
          child: const Text('Save preferences'),
        ),
        if (message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export my data'),
                subtitle: const Text('Download a copy of your saved items.'),
                onTap: busy ? null : export,
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out on all devices'),
                onTap: busy
                    ? null
                    : () => run(() async {
                        await widget.store.revokeSessions();
                        if (context.mounted) Navigator.pop(context);
                      }),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Delete my account'),
                subtitle: const Text(
                  'Permanently remove your account and saved data.',
                ),
                onTap: busy ? null : remove,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
