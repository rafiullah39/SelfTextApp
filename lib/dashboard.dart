import 'package:flutter/material.dart';
import 'store.dart';
import 'app.dart' show RecordTile, editRecord;
import 'simple_home.dart' show ReminderEditor;
import 'notes_workspace.dart';

void openNotepad(BuildContext context, SelfTextStore store) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => NotesWorkspace(store: store)),
);

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.store,
    required this.onChat,
    required this.onTasks,
  });
  final SelfTextStore store;
  final ValueChanged<String> onChat;
  final VoidCallback onTasks;
  Future<void> newChat(BuildContext context) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Chat name',
            hintText: 'Personal, University…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(c, controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    // The dialog route may still be animating its exit.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (title != null && context.mounted) onChat(store.createChat(title).id);
  }

  @override
  Widget build(BuildContext context) {
    final chats = store.chats.where((c) => c.kind == 'chat').toList();
    final active = store.records
        .where(
          (r) =>
              r.kind != RecordKind.note && !r.done && r.status != 'cancelled',
        )
        .length;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 86,
        title: const Text(
          'SelfText',
          style: TextStyle(
            fontFamily: 'DancingScript',
            fontSize: 42,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Icon(
              Icons.auto_awesome_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text(
              'YOUR EVERYDAY, SIMPLIFIED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FeatureCard(
                    title: 'Tasks &\nreminders',
                    subtitle: '$active active',
                    icon: Icons.notifications_active_outlined,
                    height: (constraints.maxHeight * .52).clamp(320.0, 370.0),
                    colors: const [
                      Color(0xff051e22),
                      Color(0xff0d795f),
                      Color(0xff5b944d),
                    ],
                    onTap: onTasks,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _FeatureCard(
                    title: 'Notepad',
                    subtitle: '${store.notes.length} saved notes',
                    icon: Icons.edit_note_rounded,
                    height: (constraints.maxHeight * .52).clamp(320.0, 370.0),
                    colors: const [
                      Color(0xff5b944d),
                      Color(0xff0d795f),
                      Color(0xff051e22),
                    ],
                    onTap: () => openNotepad(context, store),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Text(
                  'Your chats',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: 'New chat',
                  onPressed: () => newChat(context),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final chat in chats)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: dark ? const Color(0xff182c2b) : Colors.white,
                  borderRadius: BorderRadius.circular(23),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(23),
                    onTap: () => onChat(chat.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 20,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: dark
                                  ? const Color(0xff294a3c)
                                  : const Color(0xffe9f1e4),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              chat.id == 'university'
                                  ? Icons.school_outlined
                                  : chat.id == 'personal'
                                  ? Icons.person_outline
                                  : Icons.chat_bubble_outline,
                              color: dark
                                  ? const Color(0xffb8d8a9)
                                  : const Color(0xff0d795f),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chat.displayTitle,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  store.history(chat.id).lastOrNull?.text ??
                                      'Type or speak a reminder',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.height,
    required this.colors,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final double height;
  final List<Color> colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: title.replaceAll("\n", " "),
    child: Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: .17),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xffe4efdd),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class TaskOverview extends StatefulWidget {
  const TaskOverview({super.key, required this.store, this.onDashboard});
  final SelfTextStore store;
  final VoidCallback? onDashboard;
  @override
  State<TaskOverview> createState() => _TaskOverviewState();
}

class _TaskOverviewState extends State<TaskOverview> {
  String? chatId;
  bool completed = false;
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final records =
        store.records
            .where(
              (r) =>
                  r.kind != RecordKind.note &&
                  r.status != 'cancelled' &&
                  r.done == completed &&
                  (chatId == null || r.chatId == chatId),
            )
            .toList()
          ..sort(
            (a, b) => (a.dueAt ?? DateTime(2100)).compareTo(
              b.dueAt ?? DateTime(2100),
            ),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & reminders'),
        leading: widget.onDashboard == null
            ? null
            : BackButton(onPressed: widget.onDashboard),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add reminder',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReminderEditor(store: store)),
        ),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: chatId == null,
                  onSelected: (_) => setState(() => chatId = null),
                ),
                for (final chat in store.chats.where((c) => c.kind == 'chat'))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(chat.displayTitle),
                      selected: chatId == chat.id,
                      onSelected: (_) => setState(() => chatId = chat.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Active')),
              ButtonSegment(value: true, label: Text('Completed')),
            ],
            selected: {completed},
            onSelectionChanged: (v) => setState(() => completed = v.first),
          ),
          const SizedBox(height: 16),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No tasks here yet. Create one in your chat.'),
            ),
          for (final record in records)
            Card(
              child: ListTile(
                leading: Checkbox(
                  value: record.done,
                  onChanged: (_) => store.toggle(record),
                ),
                title: Text(record.title),
                subtitle: Text(
                  '${store.chatTitle(record.chatId)}${record.dueAt == null ? '' : ' · ${MaterialLocalizations.of(context).formatShortDate(store.displayTime(record.dueAt!))} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(store.displayTime(record.dueAt!)), alwaysUse24HourFormat: false)}'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => editRecord(
                  context,
                  store,
                  kind: record.kind,
                  record: record,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CalendarOverview extends StatefulWidget {
  const CalendarOverview({super.key, required this.store, this.onDashboard});
  final SelfTextStore store;
  final VoidCallback? onDashboard;
  @override
  State<CalendarOverview> createState() => _CalendarOverviewState();
}

class _CalendarOverviewState extends State<CalendarOverview> {
  DateTime? selected;
  @override
  Widget build(BuildContext context) {
    final day = selected ?? widget.store.calendarNow;
    final items = widget.store
        .onDay(day)
        .where((r) => r.status != 'cancelled')
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        leading: widget.onDashboard == null
            ? null
            : BackButton(onPressed: widget.onDashboard),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: CalendarDatePicker(
              initialDate: day,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              onDateChanged: (v) => setState(() => selected = v),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            MaterialLocalizations.of(context).formatFullDate(day),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No tasks or reminders on this day.'),
            ),
          for (final r in items)
            RecordTile(
              store: widget.store,
              record: r,
              onTap: () =>
                  editRecord(context, widget.store, kind: r.kind, record: r),
            ),
        ],
      ),
    );
  }
}
