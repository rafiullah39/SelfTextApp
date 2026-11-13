import 'package:flutter/material.dart';
import 'store.dart';
import 'suggestion_widgets.dart';

class BulkRescheduleScreen extends StatefulWidget {
  const BulkRescheduleScreen({super.key, required this.store});
  final SelfTextStore store;
  @override
  State<BulkRescheduleScreen> createState() => _BulkRescheduleState();
}

class _BulkRescheduleState extends State<BulkRescheduleScreen> {
  final selected = <String>{};
  DateTime? due;
  bool busy = false;
  String? error;
  Future<void> apply() async {
    final workspace = widget.store.userId;
    final rows = widget.store.tasks
        .where((r) => selected.contains(r.id))
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${rows.length} tasks?'),
        content: Text(
          'Move these tasks to ${friendlyMoment(context, due!)}? Their reminders move with them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move tasks'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (workspace != widget.store.userId) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.store.signedIn) {
        await widget.store.sync();
        if (widget.store.syncError != null) {
          throw StateError(widget.store.syncError!);
        }
        if (workspace != widget.store.userId || !widget.store.signedIn) {
          throw StateError('Account changed. Open this screen again.');
        }
        await widget.store.api.request('POST', '/tasks/bulk-reschedule', {
          'record_ids': rows.map((r) => r.id).toList(),
          'due_at': due!.toUtc().toIso8601String(),
        });
        await widget.store.sync();
        if (widget.store.syncError != null) {
          throw StateError(
            'Tasks were rescheduled on the server. Sync again to load them.',
          );
        }
        if (mounted) Navigator.pop(context);
        return;
      }
      final adjusted = <String, List<DateTime>>{};
      for (final r in rows) {
        final delta = r.dueAt == null ? null : due!.difference(r.dueAt!);
        if (delta == null && r.reminderTimes.isNotEmpty) {
          throw StateError('Edit reminders on undated tasks individually.');
        }
        final times = r.reminderTimes.map((t) => t.add(delta!)).toList();
        if (times.any((t) => !t.isAfter(DateTime.now()))) {
          throw StateError(
            'This move puts a reminder in the past. Edit that reminder first.',
          );
        }
        adjusted[r.id] = times;
      }
      for (final r in rows) {
        r.dueAt = due;
        r.reminderTimes = adjusted[r.id]!;
      }
      widget.store.changed();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reschedule tasks')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Select up to 50 active tasks. Review the new due time before applying.',
        ),
        ...widget.store.tasks
            .where((r) => !r.done && r.status != 'cancelled')
            .map(
              (r) => CheckboxListTile(
                value: selected.contains(r.id),
                title: Text(r.title),
                subtitle: Text(
                  r.dueAt == null
                      ? 'No due time'
                      : friendlyMoment(context, r.dueAt!),
                ),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          if (selected.length < 50) selected.add(r.id);
                        } else {
                          selected.remove(r.id);
                        }
                      }),
              ),
            ),
        ListTile(
          title: const Text('New due date and time'),
          subtitle: Text(
            due == null ? 'Choose date & time' : friendlyMoment(context, due!),
          ),
          onTap: busy
              ? null
              : () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time == null || !mounted) return;
                  final value = widget.store.calendarTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                  setState(() {
                    if (value.isAfter(DateTime.now())) {
                      due = value;
                      error = null;
                    } else {
                      error = 'Choose a future time.';
                    }
                  });
                },
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: busy || selected.isEmpty || due == null ? null : apply,
          child: Text(busy ? 'Applying…' : 'Review reschedule'),
        ),
      ],
    ),
  );
}
