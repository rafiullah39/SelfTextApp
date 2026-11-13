import 'legal_links.dart';
import 'package:flutter/material.dart';
import 'store.dart';
import 'suggestion_widgets.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.store});
  final SelfTextStore store;
  @override
  State<AccountScreen> createState() => _AccountState();
}

class _AccountState extends State<AccountScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool register = false, busy = false;
  String? error;
  String? notice;
  DateTime? lastVerification;
  @override
  void initState() {
    super.initState();
    if (widget.store.signedIn) email.text = widget.store.email ?? '';
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await widget.store.signIn(
        email.text.trim(),
        password.text,
        register: register,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your SelfText email and password first.');
      return;
    }
    if (lastVerification != null &&
        DateTime.now().difference(lastVerification!) <
            const Duration(seconds: 60)) {
      setState(
        () => error = 'Wait one minute before requesting another email.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await widget.store.api.resendVerification(
        email.text.trim(),
        password.text,
      );
      lastVerification = DateTime.now();
      if (mounted) {
        setState(
          () => notice =
              'Firebase accepted the verification email request. Check your inbox and Spam/Junk, then sign in after verifying.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(register ? 'Create account' : 'Sign in')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Sign in to sync your account. Your existing device-only workspace remains separate.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: busy ? null : (_) => submit(),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'For ages 18 and above. Review the privacy policy before creating an account.',
            ),
            const LegalLinks(),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(notice!),
              ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(
                busy
                    ? 'Please wait…'
                    : register
                    ? 'Create account'
                    : 'Sign in',
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() => register = !register),
              child: Text(
                register
                    ? 'Already registered? Sign in'
                    : 'Create a new account',
              ),
            ),
            if (!register)
              TextButton(
                onPressed: busy ? null : resend,
                child: const Text('Resend verification email'),
              ),
            if (!register)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (email.text.trim().isEmpty) {
                          setState(() => error = 'Enter your email first.');
                          return;
                        }
                        setState(() {
                          busy = true;
                          error = null;
                          notice = null;
                        });
                        try {
                          await widget.store.api.resetPassword(
                            email.text.trim(),
                          );
                          if (mounted) {
                            setState(
                              () => notice =
                                  'Password reset requested. Check your inbox and Spam/Junk.',
                            );
                          }
                        } catch (e) {
                          if (mounted) setState(() => error = e.toString());
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Forgot password?'),
              ),
          ],
        ),
      ),
    ),
  );
}

class ConnectedScreen extends StatefulWidget {
  const ConnectedScreen({super.key, required this.store});
  final SelfTextStore store;
  @override
  State<ConnectedScreen> createState() => _ConnectedState();
}

class _ConnectedState extends State<ConnectedScreen> {
  final query = TextEditingController();
  Map<String, dynamic>? response;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final s = widget.store;
      final pending = s.proposals
          .where((p) => p['status'] == 'pending')
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Review & reminders'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: s.syncing || busy ? null : () => run(s.sync),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (s.syncing) const LinearProgressIndicator(),
                if (error ?? s.syncError case final String problem)
                  Text(
                    problem,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const Text(
                  'Review suggestions before creating records. The current fallback uses date and keyword rules; it can make mistakes.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: query,
                  decoration: const InputDecoration(
                    labelText: 'Ask about your saved records',
                    hintText: 'What is planned tomorrow?',
                  ),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          response = await s.query(query.text);
                        }),
                  child: const Text('Ask'),
                ),
                if (response != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(response!['answer'] ?? ''),
                          if (response!['record'] != null)
                            Text(response!['record']['title']),
                          if (response!['update'] != null) ...[
                            Text(
                              response!['update']['status'] != null
                                  ? 'Set status: ${response!['update']['status']}'
                                  : 'Move to ${response!['update']['due_at']}',
                            ),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => run(() async {
                                      await s.applyCommand(
                                        response!['record']['id'],
                                        Map<String, dynamic>.from(
                                          response!['update'],
                                        ),
                                      );
                                      response = null;
                                    }),
                              child: const Text('Apply reviewed change'),
                            ),
                          ],
                          for (final r
                              in (response!['records'] ??
                                      response!['candidates'] ??
                                      [])
                                  as List)
                            ListTile(
                              title: Text(r['title']),
                              subtitle: Text(r['due_at'] ?? 'Unscheduled'),
                            ),
                          if (response!['data'] != null)
                            for (final group in [
                              'overdue',
                              'scheduled',
                              'unscheduled',
                              'completed',
                              'unfinished',
                              'upcoming',
                            ])
                              if (response!['data'][group] is List) ...[
                                Text(
                                  group[0].toUpperCase() + group.substring(1),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                for (final r in response!['data'][group])
                                  ListTile(
                                    title: Text(r['title']),
                                    subtitle: Text(
                                      r['due_at'] == null
                                          ? 'Unscheduled'
                                          : DateTime.parse(
                                              r['due_at'],
                                            ).toLocal().toString(),
                                    ),
                                  ),
                                if ((response!['data'][group] as List).isEmpty)
                                  const Text('No items'),
                              ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Suggestions (${pending.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Capture a message in a chat to receive a suggestion.',
                    ),
                  ),
                for (final p in pending)
                  Card(
                    child: ListTile(
                      title: Text(
                        ((p['structured_output']?['actions'] ?? []) as List)
                            .map((a) => a['title'])
                            .join(' • '),
                      ),
                      subtitle: Text(
                        'Provider: ${p['structured_output']?['provider'] ?? p['model_version']}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy || s.syncing
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProposalScreen(store: s, proposal: p),
                              ),
                            ),
                    ),
                  ),
                const SizedBox(height: 24),
                for (final p in s.proposals.where(
                  (p) => p['status'] == 'accepted',
                ))
                  Card(
                    child: ListTile(
                      title: const Text('Accepted suggestion'),
                      subtitle: Text(
                        ((p['structured_output']['actions'] ?? []) as List)
                            .map((a) => a['title'])
                            .join(' • '),
                      ),
                      trailing: TextButton(
                        onPressed: busy || s.syncing
                            ? null
                            : () => run(() async {
                                await s.sync();
                                await s.api.request(
                                  'POST',
                                  '/interpretations/${p['id']}/undo',
                                );
                                await s.sync();
                              }),
                        child: const Text('Undo'),
                      ),
                    ),
                  ),
                Text(
                  'Reminders',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (s.reminders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No reminders yet. Add a future reminder while reviewing a suggestion.',
                    ),
                  ),
                for (final r in s.reminders)
                  Card(
                    child: ListTile(
                      title: Text(
                        s.records
                                .where((item) => item.id == r['record_id'])
                                .firstOrNull
                                ?.title ??
                            'Reminder',
                      ),
                      subtitle: Text(
                        '${friendlyMoment(context, s.displayTime(DateTime.parse(r['trigger_at'])))} · ${r['status']}',
                      ),
                      trailing: ['due', 'delivered'].contains(r['status'])
                          ? TextButton(
                              onPressed: busy
                                  ? null
                                  : () => run(() async {
                                      await s.api.request(
                                        'POST',
                                        '/reminders/${r['id']}/snooze',
                                        {'minutes': 10},
                                      );
                                      await s.sync();
                                    }),
                              child: const Text('Snooze 10m'),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ProposalScreen extends StatefulWidget {
  const ProposalScreen({
    super.key,
    required this.store,
    required this.proposal,
  });
  final SelfTextStore store;
  final Map<String, dynamic> proposal;
  @override
  State<ProposalScreen> createState() => _ProposalState();
}

class _ProposalState extends State<ProposalScreen> {
  late List<Map<String, dynamic>> actions;
  late List<TextEditingController> titles, starts, ends, reminders;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    actions = ((widget.proposal['structured_output']['actions'] ?? []) as List)
        .map((a) => Map<String, dynamic>.from(a))
        .toList();
    titles = actions
        .map((a) => TextEditingController(text: a['title']))
        .toList();
    starts = actions
        .map(
          (a) => TextEditingController(
            text: a['due_at'] == null
                ? ''
                : widget.store
                      .displayTime(DateTime.parse(a['due_at']))
                      .toIso8601String(),
          ),
        )
        .toList();
    ends = actions
        .map(
          (a) => TextEditingController(
            text: a['end_at'] == null
                ? ''
                : widget.store
                      .displayTime(DateTime.parse(a['end_at']))
                      .toIso8601String(),
          ),
        )
        .toList();
    reminders = actions
        .map(
          (a) => TextEditingController(
            text: (a['reminders'] as List? ?? [])
                .map(
                  (d) => widget.store
                      .displayTime(DateTime.parse(d))
                      .toIso8601String(),
                )
                .join(', '),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final c in [...titles, ...starts, ...ends, ...reminders]) {
      c.dispose();
    }
    super.dispose();
  }

  String? timestamp(String value) {
    if (value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) {
      throw const FormatException('Use YYYY-MM-DDTHH:mm for dates.');
    }
    final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value.trim());
    final instant = hasZone
        ? parsed
        : widget.store.calendarTime(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
          );
    return instant.toUtc().toIso8601String();
  }

  Future<void> finish(bool accept) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (accept) {
        for (var i = 0; i < actions.length; i++) {
          actions[i]['title'] = titles[i].text.trim();
          actions[i]['due_at'] = timestamp(starts[i].text);
          actions[i]['end_at'] = timestamp(ends[i].text);
          actions[i]['reminders'] = reminders[i].text.trim().isEmpty
              ? []
              : reminders[i].text.split(',').map(timestamp).toList();
          actions[i]['ambiguities'] = [];
        }
        await widget.store.acceptProposal(widget.proposal, actions);
      } else {
        await widget.store.rejectProposal(widget.proposal);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Make it yours')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'We filled in the details. Tap any date or time to change it, then save.',
            ),
            for (var i = 0; i < actions.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actions[i]['kind'] == 'note'
                            ? 'NOTE'
                            : 'TASK / REMINDER',
                      ),
                      if ((actions[i]['ambiguities'] as List? ?? []).isNotEmpty)
                        Text(
                          'Needs review: ${(actions[i]['ambiguities'] as List).join('; ')}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titles[i],
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      FriendlyDateField(
                        store: widget.store,
                        controller: starts[i],
                        label: actions[i]['kind'] == 'event'
                            ? 'Starts'
                            : 'When',
                        onChanged: () {
                          if (actions[i]['kind'] == 'reminder') {
                            reminders[i].text = starts[i].text;
                          }
                          setState(() {});
                        },
                      ),
                      if (actions[i]['kind'] == 'event')
                        FriendlyDateField(
                          store: widget.store,
                          controller: ends[i],
                          label: 'Ends',
                          onChanged: () => setState(() {}),
                        ),
                      FriendlyDateField(
                        store: widget.store,
                        controller: reminders[i],
                        label: 'Notification',
                        multiple: true,
                        onChanged: () => setState(() {}),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final minutes in [5, 15, 60])
                            ActionChip(
                              label: Text(
                                minutes == 60 ? 'In 1 hour' : 'In $minutes min',
                              ),
                              onPressed: () {
                                final instant = widget.store.calendarNow
                                    .add(Duration(minutes: minutes))
                                    .toIso8601String();
                                setState(() {
                                  starts[i].text = instant;
                                  reminders[i].text = instant;
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: busy || actions.isEmpty ? null : () => finish(true),
              child: Text(
                busy
                    ? 'Saving…'
                    : actions.length > 1
                    ? 'Save plan'
                    : 'Save reminder',
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => finish(false),
              child: const Text('Dismiss suggestion'),
            ),
          ],
        ),
      ),
    ),
  );
}
