import 'simple_home.dart';
import 'notes_workspace.dart';
import 'voice_capture.dart';
import 'package:flutter/material.dart';
import 'store.dart';
import 'account_tools.dart';
import 'suggestion_widgets.dart';

const accent = Color(0xff46f0d2);
const months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String dateLabel(DateTime d) => '${months[d.month - 1]} ${d.day}';
String timeLabel(BuildContext context, DateTime d) =>
    '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';

class SelfTextApp extends StatelessWidget {
  const SelfTextApp({super.key, required this.store});
  final SelfTextStore store;
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xff051e22) : const Color(0xfff7f9f3);
    final surface = dark ? const Color(0xff132e30) : Colors.white;
    final primary = dark ? accent : const Color(0xff0d795f);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: dark ? const Color(0xff051e22) : Colors.white,
          primaryContainer: dark
              ? const Color(0xff1f574f)
              : const Color(0xffc9f7e8),
          onPrimaryContainer: dark
              ? const Color(0xffdcfff5)
              : const Color(0xff073b32),
          surface: surface,
          onSurface: dark ? const Color(0xfff4f6fa) : const Color(0xff162b27),
          secondaryContainer: dark
              ? const Color(0xff303344)
              : const Color(0xffe7f1ed),
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff29293c) : const Color(0xffedf4f1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: background,
        indicatorColor: dark ? accent : const Color(0xffc9f7e8),
        iconTheme: WidgetStateProperty.fromMap({
          WidgetState.selected: const IconThemeData(color: Color(0xff073b32)),
          WidgetState.any: IconThemeData(color: scheme.onSurfaceVariant),
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      title: 'SelfText',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: switch (store.appearance) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
      home: store.onboarded
          ? HomeScreen(store: store)
          : WelcomeScreen(store: store),
    ),
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.store});
  final SelfTextStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(32),
            children: [
              const Icon(Icons.forum_outlined, size: 64, color: accent),
              const SizedBox(height: 32),
              Text(
                'Say it.\nRemember it.',
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text(
                'Reminders, alarms, and a notepad. Nothing in your way.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              const InfoCard(
                title: 'A reminder in your own words',
                body:
                    'Type or speak in English or Urdu. Clear times are scheduled automatically.',
              ),
              const InfoCard(
                title: 'Your notes stay with you',
                body:
                    'Write notes right away. Sign in from Profile to use AI and account sync.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: store.finishOnboarding,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Get started'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.store,
    required this.chat,
    this.sourceId,
    this.onConversations,
    this.onSelectChat,
    this.onDashboard,
  });
  final SelfTextStore store;
  final Chat chat;
  final String? sourceId;
  final VoidCallback? onConversations;
  final ValueChanged<String>? onSelectChat;
  final VoidCallback? onDashboard;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final composer = TextEditingController();
  final scroll = ScrollController();
  final sourceKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (sourceKey.currentContext != null) {
        Scrollable.ensureVisible(sourceKey.currentContext!, alignment: 0.2);
      } else if (scroll.hasClients) {
        scroll.jumpTo(
          widget.sourceId == null ? 0 : scroll.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  void dispose() {
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  void send() async {
    if (composer.text.trim().isEmpty) return;
    widget.store.capture(widget.chat.id, composer.text);
    composer.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          widget.sourceId == null ? 0 : scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
    if (widget.store.signedIn) {
      await widget.store.sync();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.animateTo(
            widget.sourceId == null ? 0 : scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  bool capturingVoice = false;
  Future<void> voice() async {
    if (capturingVoice) return;
    final workspace = widget.store.activeStorageKey;
    setState(() => capturingVoice = true);
    final text = await VoiceCapture.capture(context);
    if (!mounted) return;
    setState(() => capturingVoice = false);
    if (text == null ||
        text.trim().isEmpty ||
        workspace != widget.store.activeStorageKey) {
      return;
    }
    composer.text = text;
    send();
  }

  Future<void> reviseMessage(Entry original) async {
    final editor = TextEditingController(text: original.text);
    final workspace = widget.store.activeStorageKey;
    final revised = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit and re-interpret message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'A revision keeps the original message and capture date. Existing tasks stay as saved; review the new suggestion before accepting it.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: editor,
              minLines: 2,
              maxLines: 6,
              maxLength: 10000,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editor.text.trim()),
            child: const Text('Save revision'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (!mounted ||
        revised == null ||
        revised.isEmpty ||
        workspace != widget.store.activeStorageKey) {
      return;
    }
    widget.store.reviseCapture(original, revised);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final messages = widget.store.history(widget.chat.id);
      Widget messageTile(Entry m) {
        final linked = widget.store.records
            .where((r) => r.sourceId == m.id)
            .toList();
        final suggestions = widget.store.proposals
            .where(
              (p) =>
                  linked.isEmpty &&
                  p['message_id'] == m.id &&
                  p['status'] == 'pending',
            )
            .toList();
        return Column(
          key: m.id == widget.sourceId ? sourceKey : null,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 12),
              child: Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: m.id == widget.sourceId
                      ? BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : BorderSide.none,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onLongPress: () => reviseMessage(m),
                  onTap: () => organize(m),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(m.text),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                '${dateLabel(m.createdAt)} · ${timeLabel(context, m.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (widget.store.signedIn &&
                m.aiStatus == 'pending' &&
                linked.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  widget.store.syncing
                      ? 'Setting your reminder…'
                      : 'Waiting to connect…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ...linked.map(
              (r) => RecordTile(
                record: r,
                store: widget.store,
                onTap: () =>
                    editRecord(context, widget.store, record: r, kind: r.kind),
              ),
            ),
            ...suggestions.map(
              (p) => InlineSuggestionCard(
                key: ValueKey(p['id']),
                store: widget.store,
                proposal: p,
              ),
            ),
            if (widget.store.signedIn &&
                suggestions.isEmpty &&
                linked.isEmpty &&
                m.aiStatus == 'pending')
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  widget.store.syncError != null
                      ? 'Message saved on this phone. Sync failed: ${widget.store.syncError}'
                      : 'Preparing your suggestion…',
                ),
              ),
            if (widget.store.signedIn &&
                suggestions.isEmpty &&
                linked.isEmpty &&
                m.aiStatus == 'proposed')
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  captureFeedback(
                    widget.store.proposals
                        .where((p) => p['message_id'] == m.id)
                        .firstOrNull,
                  ),
                ),
              ),
            if (m.aiStatus == 'failed' && widget.store.signedIn)
              TextButton.icon(
                onPressed: widget.store.retryingCaptures.contains(m.id)
                    ? null
                    : () async {
                        try {
                          await widget.store.retryCapture(m);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Your suggestion is ready below the message.',
                                ),
                              ),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.refresh),
                label: Text(
                  widget.store.retryingCaptures.contains(m.id)
                      ? 'Retrying…'
                      : 'Retry failed interpretation',
                ),
              ),
            if (linked.isEmpty &&
                suggestions.isEmpty &&
                (!widget.store.signedIn || m.aiStatus == 'failed'))
              if (RegExp(
                r'remind|alarm|notify|yaad|yad|یاد',
                caseSensitive: false,
              ).hasMatch(m.text))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No reminder scheduled yet. Choose a time below, or sign in for AI.',
                  ),
                ),
            if (linked.isEmpty &&
                suggestions.isEmpty &&
                (!widget.store.signedIn || m.aiStatus == 'failed'))
              TextButton.icon(
                onPressed: () => organize(m),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Set reminder or save note'),
              ),
          ],
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(widget.chat.displayTitle),
          leading: widget.onDashboard == null
              ? null
              : BackButton(onPressed: widget.onDashboard),
          bottom: widget.onSelectChat == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final c in widget.store.chats.where(
                          (c) => c.kind == 'chat',
                        ))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(c.displayTitle),
                              selected: c.id == widget.chat.id,
                              onSelected: (_) => widget.onSelectChat!(c.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
          actions: [
            if (widget.onConversations != null)
              IconButton(
                tooltip: 'Conversations',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: widget.onConversations,
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Text(
                      widget.store.signedIn
                          ? 'Type or speak. I’ll set your reminder.'
                          : 'Quick reminders work on this phone. Sign in for AI and cloud sync.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (widget.store.signedIn && widget.store.quietHoursActive)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bedtime_outlined, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Quiet hours are active. Cloud alerts wait until they end.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AccountTools(store: widget.store),
                              ),
                            ),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                  if (widget.store.notificationError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.store.notificationError!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              try {
                                await widget.store.enableLocalReminders();
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error.toString())),
                                  );
                                }
                              }
                            },
                            child: const Text('Set up alerts'),
                          ),
                        ],
                      ),
                    ),
                  if (widget.store.signedIn &&
                      widget.store.accountPreferences['ai_enabled'] != true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'AI is off. Basic date rules are active.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SettingsScreen(store: widget.store),
                              ),
                            ),
                            child: const Text('Enable AI'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: messages.isEmpty
                        ? const SingleChildScrollView(
                            padding: EdgeInsets.all(20),
                            child: EmptyView(
                              icon: Icons.forum_outlined,
                              title: 'What should I remind you about?',
                              body: 'Try “Remind me in 5 minutes to call Ali.”',
                            ),
                          )
                        : widget.sourceId != null
                        ? SingleChildScrollView(
                            controller: scroll,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: messages.map(messageTile).toList(),
                            ),
                          )
                        : ListView.builder(
                            controller: scroll,
                            reverse: true,
                            padding: const EdgeInsets.all(20),
                            itemCount: messages.length,
                            itemBuilder: (_, index) => messageTile(
                              messages[messages.length - 1 - index],
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: composer,
                            minLines: 1,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Remind me to…',
                            ),
                            onSubmitted: (_) => send(),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Speak a message',
                          onPressed: capturingVoice ? null : voice,
                          icon: Icon(
                            capturingVoice
                                ? Icons.hourglass_top
                                : Icons.mic_none,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filled(
                          onPressed: send,
                          tooltip: 'Save message',
                          icon: const Icon(Icons.arrow_upward),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  Future<void> organize(Entry m) async {
    final kind = await showModalBottomSheet<RecordKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Turn this message into…'),
            ),
            ...[RecordKind.task, RecordKind.note].map(
              (k) => ListTile(
                leading: Icon(kindIcon(k)),
                title: Text(kindName(k)),
                onTap: () => Navigator.pop(ctx, k),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (kind != null && mounted) {
      await editRecord(context, widget.store, kind: kind, source: m);
    }
  }
}

String kindName(RecordKind k) => switch (k) {
  RecordKind.task => 'Reminder',
  RecordKind.event => 'Reminder',
  RecordKind.note => 'Note',
};
IconData kindIcon(RecordKind k) => switch (k) {
  RecordKind.task => Icons.task_alt,
  RecordKind.event => Icons.event_outlined,
  RecordKind.note => Icons.notes,
};
Future<void> editRecord(
  BuildContext context,
  SelfTextStore store, {
  required RecordKind kind,
  ProductivityRecord? record,
  ProductivityRecord? seedNote,
  Entry? source,
}) => Navigator.push<void>(
  context,
  MaterialPageRoute(
    builder: (_) => kind == RecordKind.note
        ? QuickNoteEditor(
            store: store,
            chatId: record?.chatId ?? source?.chatId ?? store.chats.first.id,
            record: record,
            initialText: source?.text ?? seedNote?.body,
            sourceId: source?.id ?? seedNote?.sourceId,
          )
        : ReminderEditor(store: store, record: record, source: source),
  ),
);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final SelfTextStore store;
  @override
  Widget build(BuildContext context) => ProfileScreen(store: store);
}

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key, required this.store});
  final SelfTextStore store;
  @override
  Widget build(BuildContext context) => NotesWorkspace(store: store);
}

class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.record,
    required this.store,
    required this.onTap,
  });
  final ProductivityRecord record;
  final SelfTextStore store;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final times = record.reminderTimes..sort();
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(
          record.kind == RecordKind.note
              ? Icons.notes_outlined
              : Icons.notifications_active_outlined,
        ),
        title: Text(record.title),
        subtitle: Text(
          record.kind == RecordKind.note
              ? record.body
              : times
                    .map((t) => friendlyMoment(context, store.displayTime(t)))
                    .join('\n'),
          maxLines: 4,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.title,
    required this.body,
    this.action,
  });
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center),
      ],
    ),
  );
}

String captureFeedback(
  Map<String, dynamic>? proposal,
) => switch (proposal?['status']) {
  'accepted' =>
    'This reminder or task was already handled. It is no longer active.',
  'rejected' => 'Suggestion dismissed. Your message is still saved.',
  _ =>
    'No active suggestion is available. Tap your message to set a reminder, or edit it to ask again.',
};
