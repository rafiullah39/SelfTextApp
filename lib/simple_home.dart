import 'legal_links.dart';
import 'feedback_dialog.dart';
import 'dashboard.dart';
import 'package:flutter/material.dart';
import 'app.dart' show ChatScreen, RecordTile;
import 'store.dart';
import 'connected_screens.dart' show AccountScreen;
import 'account_tools.dart' show AccountTools;
import 'suggestion_widgets.dart' show friendlyMoment;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final SelfTextStore store;
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> with WidgetsBindingObserver {
  int tab = 0;
  String? chatId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(openNotification);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(openNotification);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.resumeNotificationActions();
    }
  }

  void openNotification() {
    final id = widget.store.notificationRecordId;
    if (id == null) return;
    widget.store.notificationRecordId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.store.sync();
      if (!mounted) return;
      final record = widget.store.records.where((r) => r.id == id).firstOrNull;
      if (record != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReminderEditor(store: widget.store, record: record),
          ),
        );
      }
    });
  }

  Future<void> conversations() async {
    final chats = widget.store.chats.where((c) => c.kind == 'chat').toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Your conversations')),
            for (final chat in chats)
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(chat.displayTitle),
                onTap: () => Navigator.pop(context, chat.id),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New conversation'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    setState(
      () => chatId = choice == 'new'
          ? widget.store.createChat('Chat ${chats.length + 1}').id
          : choice,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final chat =
          widget.store.chats
              .where((c) => c.id == chatId && c.kind == 'chat')
              .firstOrNull ??
          widget.store.chats.where((c) => c.kind == 'chat').firstOrNull;
      return PopScope(
        canPop: tab == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && tab != 0) setState(() => tab = 0);
        },
        child: Scaffold(
          body: Column(
            children: [
              if (widget.store.storageError != null)
                SafeArea(
                  bottom: false,
                  child: MaterialBanner(
                    content: Text(widget.store.storageError!),
                    actions: const [SizedBox.shrink()],
                  ),
                ),
              Expanded(
                child: switch (tab) {
                  0 => DashboardScreen(
                    store: widget.store,
                    onChat: (id) => setState(() {
                      chatId = id;
                      tab = 1;
                    }),
                    onTasks: () => setState(() => tab = 2),
                  ),
                  1 =>
                    chat == null
                        ? const Center(child: CircularProgressIndicator())
                        : ChatScreen(
                            key: ValueKey(chat.id),
                            store: widget.store,
                            chat: chat,
                            onConversations: conversations,
                            onSelectChat: (id) => setState(() => chatId = id),
                            onDashboard: () => setState(() => tab = 0),
                          ),
                  2 => TaskOverview(
                    store: widget.store,
                    onDashboard: () => setState(() => tab = 0),
                  ),
                  3 => CalendarOverview(
                    store: widget.store,
                    onDashboard: () => setState(() => tab = 0),
                  ),
                  _ => ProfileScreen(
                    store: widget.store,
                    onDashboard: () => setState(() => tab = 0),
                  ),
                },
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                label: 'Tasks',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                label: 'Calendar',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      );
    },
  );
}

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key, required this.store});
  final SelfTextStore store;
  DateTime next(ProductivityRecord r) =>
      r.reminderTimes.where((t) => t.isAfter(DateTime.now())).firstOrNull ??
      r.reminderTimes.last;
  @override
  Widget build(BuildContext context) {
    final reminders = store.records
        .where(
          (r) =>
              !r.done && r.status != 'cancelled' && r.reminderTimes.isNotEmpty,
        )
        .toList();
    for (final r in reminders) {
      r.reminderTimes.sort();
    }
    reminders.sort((a, b) => next(a).compareTo(next(b)));
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReminderEditor(store: store)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
      ),
      body: RefreshIndicator(
        onRefresh: store.sync,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            if (store.notificationError != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: const Text('Check notification permissions'),
                  subtitle: const Text(
                    'Open Profile → Notification permissions to enable on-time alerts.',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(store: store),
                    ),
                  ),
                ),
              ),
            if (reminders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 64),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nothing to remember yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Say or type a reminder in Remind me.\nYou can also choose a time yourself.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final record in reminders)
              RecordTile(
                record: record,
                store: store,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ReminderEditor(store: store, record: record),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReminderEditor extends StatefulWidget {
  const ReminderEditor({
    super.key,
    required this.store,
    this.record,
    this.source,
  });
  final SelfTextStore store;
  final ProductivityRecord? record;
  final Entry? source;
  @override
  State<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<ReminderEditor> {
  late final title = TextEditingController(
    text: widget.record?.title ?? widget.source?.text ?? '',
  );
  late final times = List<DateTime>.from(widget.record?.reminderTimes ?? [])
    ..sort();
  late String? recurrence = widget.record?.recurrence;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> pick([int? index]) async {
    final now = widget.store.calendarNow;
    final base = index == null || times[index].isBefore(now)
        ? now.add(const Duration(minutes: 5))
        : widget.store.displayTime(times[index]);
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 20),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    final selected = widget.store.calendarTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (index == null) {
        times.add(selected);
      } else {
        times[index] = selected;
      }
      times.sort();
    });
  }

  void save() {
    if (title.text.trim().isEmpty ||
        times.isEmpty ||
        times.any((t) => !t.isAfter(DateTime.now()))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a title and future reminder time. Remove any past times before saving.',
          ),
        ),
      );
      return;
    }
    final r = widget.record;
    if (r == null) {
      widget.store.createRecord(
        title: title.text.trim(),
        kind: RecordKind.task,
        chatId:
            widget.source?.chatId ??
            widget.store.chats.where((c) => c.kind == 'chat').first.id,
        sourceId: widget.source?.id,
        dueAt: times.last,
        reminderTimes: times.toSet().toList(),
        recurrence: recurrence,
      );
    } else {
      r.title = title.text.trim();
      r.reminderTimes = times.toSet().toList();
      r.recurrence = recurrence;
      if (r.kind == RecordKind.task) {
        r.dueAt = times.last;
        if (r.startAt != null) r.startAt = times.first;
      }
      widget.store.changed();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.record == null ? 'New reminder' : 'Edit reminder'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: title,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Remind me to',
            hintText: 'Call Ali',
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < times.length; i++)
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(
                friendlyMoment(context, widget.store.displayTime(times[i])),
              ),
              onTap: () => pick(i),
              trailing: IconButton(
                tooltip: 'Remove time',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => times.removeAt(i)),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: times.length >= 10 ? null : () => pick(),
          icon: const Icon(Icons.add),
          label: Text(
            times.isEmpty ? 'Choose date & time' : 'Add another alert',
          ),
        ),
        if (times.isEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final m in [5, 15, 60])
                ActionChip(
                  label: Text(m == 60 ? 'In 1 hour' : 'In $m min'),
                  onPressed: () => setState(
                    () => times.add(DateTime.now().add(Duration(minutes: m))),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: recurrence ?? 'none',
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Once')),
            DropdownMenuItem(value: 'daily', child: Text('Every day')),
            DropdownMenuItem(value: 'weekdays', child: Text('Weekdays')),
            DropdownMenuItem(value: 'weekly', child: Text('Every week')),
            DropdownMenuItem(value: 'monthly', child: Text('Every month')),
          ],
          onChanged: (v) => setState(() => recurrence = v == 'none' ? null : v),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: save, child: const Text('Save reminder')),
        if (widget.record != null)
          TextButton(
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Dismiss this reminder?'),
                  content: const Text(
                    'This removes it and cancels all its remaining alerts.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              );
              if (yes == true && context.mounted) {
                widget.store.handleReminderAction(widget.record!.id, 'dismiss');
                Navigator.pop(context);
              }
            },
            child: const Text('Dismiss reminder'),
          ),
      ],
    ),
  );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.store, this.onDashboard});
  final VoidCallback? onDashboard;
  final SelfTextStore store;
  Future<void> run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: onDashboard == null
            ? null
            : BackButton(onPressed: onDashboard),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_outline,
                      size: 30,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    store.signedIn
                        ? 'Your SelfText account'
                        : 'Welcome to SelfText',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    store.email ?? 'Sign in for AI reminders and account sync.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    store.syncing
                        ? 'Syncing…'
                        : store.syncError != null
                        ? 'Waiting to sync. Your saved items stay on this device.'
                        : store.signedIn
                        ? 'Your reminders and notes sync securely.'
                        : 'Your notepad is ready on this device.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (store.signedIn && store.syncError != null)
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountScreen(store: store),
                        ),
                      ),
                      child: const Text('Reconnect account'),
                    ),
                  if (!store.signedIn)
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountScreen(store: store),
                        ),
                      ),
                      child: const Text('Sign in or create account'),
                    )
                  else
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: store.syncing
                              ? null
                              : () => run(context, store.sync),
                          child: const Text('Sync now'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => run(context, store.signOut),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          heading(context, 'Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('System')),
                  ButtonSegment(value: 'light', label: Text('Light')),
                  ButtonSegment(value: 'dark', label: Text('Dark')),
                ],
                selected: {store.appearance},
                onSelectionChanged: (v) =>
                    run(context, () => store.setAppearance(v.single)),
              ),
            ),
          ),
          heading(context, 'Reminders & alarms'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.alarm),
                  title: const Text('Ringing alarm'),
                  subtitle: const Text(
                    'Use alarm sound until Snooze or Dismiss.',
                  ),
                  value: store.alarmSound,
                  onChanged: (v) => run(context, () => store.setAlarmSound(v)),
                ),
                ListTile(
                  leading: const Icon(Icons.snooze),
                  title: const Text('Snooze for'),
                  trailing: DropdownButton<int>(
                    value: store.snoozeMinutes,
                    items:
                        ({5, 10, 15, 30, 60, store.snoozeMinutes}.toList()
                              ..sort())
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text('$m min'),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        run(context, () => store.setSnoozeMinutes(v));
                      }
                    },
                  ),
                ),
                if (store.localReminders.supported)
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Notification permissions'),
                    subtitle: Text(
                      store.notificationError != null
                          ? 'Tap to fix reminder delivery'
                          : 'Allow notifications and precise alarm timing.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => run(context, () async {
                      await store.enableLocalReminders();
                      if (store.signedIn) await store.enableNotifications();
                    }),
                  ),
              ],
            ),
          ),
          heading(context, 'AI reminders'),
          Card(
            child: Column(
              children: [
                if (store.signedIn)
                  SwitchListTile(
                    secondary: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Understand my messages with AI'),
                    subtitle: const Text(
                      'Send reminder messages to the AI provider. Turn off to use basic date rules.',
                    ),
                    value: store.accountPreferences['ai_enabled'] == true,
                    onChanged: (v) => run(context, () async {
                      if (v && !await confirmAiConsent(context)) return;
                      await store.api.request('PATCH', '/me', {
                        'preferences': {
                          ...store.accountPreferences,
                          'ai_enabled': v,
                          if (v) 'ai_consent_version': '2026-10-22',
                          if (v) 'ai_adult_confirmed': true,
                        },
                      });
                      await store.sync();
                    }),
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.bolt_outlined),
                  title: const Text('Automatically save clear reminders'),
                  subtitle: const Text(
                    'If the time is unclear, I’ll ask you first.',
                  ),
                  value: store.autoSaveReminders,
                  onChanged: (v) =>
                      run(context, () => store.setAutoSaveReminders(v)),
                ),
              ],
            ),
          ),
          if (store.signedIn) ...[
            heading(context, 'Privacy & account'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Manage my data'),
                subtitle: const Text(
                  'Privacy, quiet hours, export or delete account.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AccountTools(store: store)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Report a problem'),
            subtitle: const Text(
              'Incorrect suggestions, safety or other issues.',
            ),
            onTap: () => reportProblem(context, store),
          ),
          const LegalLinks(),
          const Text('SelfText · 1.0.0 RC4', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
