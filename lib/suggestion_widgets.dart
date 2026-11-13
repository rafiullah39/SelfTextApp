import 'package:flutter/material.dart';
import 'store.dart';
import 'connected_screens.dart';
import 'feedback_dialog.dart';

String friendlyMoment(BuildContext context, DateTime date) {
  final now = DateTime.now();
  final day =
      date.year == now.year && date.month == now.month && date.day == now.day
      ? 'Today'
      : '${date.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]}${date.year == now.year ? '' : ' ${date.year}'}';
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$day · $hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'}';
}

class FriendlyDateField extends StatelessWidget {
  const FriendlyDateField({
    super.key,
    required this.store,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.multiple = false,
  });
  final SelfTextStore store;
  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final bool multiple;
  Future<void> pick(BuildContext context) async {
    final current = store.calendarNow;
    final initial = DateTime.tryParse(controller.text.split(',').first.trim());
    final local = initial == null ? current : store.displayTime(initial);
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(local.year, local.month, local.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(current.year + 20),
      helpText: 'Choose a date',
    );
    if (selected == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(local),
      helpText: 'Choose a time',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (time == null || !context.mounted) return;
    final value = store
        .calendarTime(
          selected.year,
          selected.month,
          selected.day,
          time.hour,
          time.minute,
        )
        .toIso8601String();
    controller.text = multiple && controller.text.isNotEmpty
        ? '${controller.text}, $value'
        : value;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final values = controller.text
        .split(',')
        .map((s) => DateTime.tryParse(s.trim()))
        .whereType<DateTime>()
        .toList();
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: Icon(
          label == 'Notification'
              ? Icons.notifications_outlined
              : Icons.schedule,
        ),
        title: Text(label),
        subtitle: Text(
          values.isEmpty
              ? 'Choose date & time'
              : values
                    .map((d) => friendlyMoment(context, store.displayTime(d)))
                    .join('\n'),
        ),
        onTap: () => pick(context),
        trailing: values.isEmpty
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: 'Clear $label',
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
      ),
    );
  }
}

class InlineSuggestionCard extends StatefulWidget {
  const InlineSuggestionCard({
    super.key,
    required this.store,
    required this.proposal,
  });
  final SelfTextStore store;
  final Map<String, dynamic> proposal;
  @override
  State<InlineSuggestionCard> createState() => _InlineSuggestionState();
}

class _InlineSuggestionState extends State<InlineSuggestionCard> {
  bool busy = false;
  Future<void> act(bool save) async {
    setState(() => busy = true);
    try {
      if (save) {
        await widget.store.acceptProposal(
          widget.proposal,
          ((widget.proposal['structured_output']['actions'] ?? []) as List)
              .map((a) => Map<String, dynamic>.from(a))
              .toList(),
        );
      } else {
        await widget.store.rejectProposal(widget.proposal);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions =
        (widget.proposal['structured_output']['actions'] ?? []) as List;
    if (actions.isEmpty) {
      return widget.proposal['structured_output']['query'] == null
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'I could not make a task from this message. Tell me what you want to do and when, or tap your message to organize it.',
              ),
            )
          : ConversationReplyCard(
              store: widget.store,
              proposal: widget.proposal,
            );
    }
    final isPlan = widget.proposal['structured_output']['intent'] == 'plan';
    final explanation =
        widget.proposal['structured_output']['explanation'] as String? ?? '';
    final needsReview = actions.any(
      (a) =>
          (a['ambiguities'] as List? ?? []).isNotEmpty ||
          (a['reminders'] as List? ?? []).any(
            (s) => DateTime.parse(s).isBefore(DateTime.now()),
          ),
    );
    void edit() => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProposalScreen(store: widget.store, proposal: widget.proposal),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  needsReview
                      ? 'Let’s confirm a detail'
                      : isPlan
                      ? 'Your suggested plan'
                      : 'Ready to remind you',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Report suggestion',
                icon: const Icon(Icons.flag_outlined, size: 20),
                onPressed: () => reportProblem(
                  context,
                  widget.store,
                  interpretationId: widget.proposal['id'] as String?,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(explanation),
            ),
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action['kind'] == 'note'
                        ? 'NOTE'
                        : isPlan
                        ? 'TASK'
                        : 'REMINDER',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    action['title'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (action['due_at'] != null)
                    Text(
                      friendlyMoment(
                        context,
                        widget.store.displayTime(
                          DateTime.parse(action['due_at']),
                        ),
                      ),
                    ),
                  for (final question in action['ambiguities'] as List? ?? [])
                    Text(
                      question,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : needsReview
                    ? edit
                    : () => act(true),
                icon: Icon(needsReview ? Icons.schedule : Icons.check),
                label: Text(
                  busy
                      ? 'Saving…'
                      : needsReview
                      ? 'Review details'
                      : actions.length == 1
                      ? 'Save'
                      : isPlan
                      ? 'Save plan'
                      : 'Save all',
                ),
              ),
              TextButton(
                onPressed: busy ? null : edit,
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: busy ? null : () => act(false),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ConversationReplyCard extends StatefulWidget {
  const ConversationReplyCard({
    super.key,
    required this.store,
    required this.proposal,
  });
  final SelfTextStore store;
  final Map<String, dynamic> proposal;
  @override
  State<ConversationReplyCard> createState() => _ConversationReplyState();
}

class _ConversationReplyState extends State<ConversationReplyCard> {
  Map<String, dynamic>? reply;
  String? error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    reply = widget.proposal['chat_reply'] as Map<String, dynamic>?;
    if (reply != null) {
      busy = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => load());
    }
  }

  Future<void> load({String? recordId}) async {
    final workspace = widget.store.activeStorageKey;
    try {
      final result = Map<String, dynamic>.from(
        await widget.store.api.request('POST', '/ai/query', {
          'query': widget.proposal['structured_output']['query'],
          if (recordId != null) 'record_id': recordId,
        }),
      );
      if (!mounted || widget.store.activeStorageKey != workspace) return;
      widget.proposal['chat_reply'] = result;
      widget.store.changed(scheduleSync: false);
      setState(() {
        reply = result;
        error = null;
        busy = false;
      });
    } catch (e) {
      if (mounted && workspace == widget.store.activeStorageKey) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
    }
  }

  Future<void> apply() async {
    final workspace = widget.store.activeStorageKey;
    setState(() => busy = true);
    try {
      await widget.store.api.request(
        'PATCH',
        '/records/${reply!['record']['id']}',
        Map<String, dynamic>.from(reply!['update']),
      );
      if (!mounted || workspace != widget.store.activeStorageKey) return;
      reply!['applied'] = true;
      widget.proposal['chat_reply'] = reply;
      await widget.store.sync();
      if (mounted && workspace == widget.store.activeStorageKey) {
        setState(() => busy = false);
      }
    } catch (e) {
      if (mounted && workspace == widget.store.activeStorageKey) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = <dynamic>[
      ...?reply?['records'] as List?,
      ...?reply?['candidates'] as List?,
    ];
    final data = reply?['data'] as Map?;
    if (data != null) {
      for (final group in [
        'overdue',
        'due_today',
        'events',
        'tasks',
        'upcoming',
      ]) {
        if (data[group] is List) records.addAll(data[group]);
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 18),
                SizedBox(width: 8),
                Text('Your assistant'),
              ],
            ),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(error!),
              TextButton(
                onPressed: () {
                  setState(() => busy = true);
                  load();
                },
                child: const Text('Try again'),
              ),
            ],
            if (reply != null) ...[
              Text(
                reply!['applied'] == true
                    ? 'Updated your reminders.'
                    : reply!['answer'] ?? 'Here is your saved plan.',
              ),
              for (final record in records)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(record['title']),
                  onTap: busy || reply?['candidates'] == null
                      ? null
                      : () {
                          setState(() => busy = true);
                          load(recordId: record['id']);
                        },
                  subtitle: record['due_at'] == null
                      ? null
                      : Text(
                          friendlyMoment(
                            context,
                            widget.store.displayTime(
                              DateTime.parse(record['due_at']),
                            ),
                          ),
                        ),
                ),
              if (reply!['record'] != null &&
                  reply!['update'] != null &&
                  reply!['applied'] != true) ...[
                const SizedBox(height: 12),
                Text(
                  reply!['record']['title'],
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (reply!['update']['due_at'] != null)
                  Text(
                    friendlyMoment(
                      context,
                      widget.store.displayTime(
                        DateTime.parse(reply!['update']['due_at']),
                      ),
                    ),
                  ),
                if (reply!['update']['status'] != null)
                  Text('Mark as ${reply!['update']['status']}'),
                FilledButton(
                  onPressed: busy ? null : apply,
                  child: const Text('Confirm change'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
