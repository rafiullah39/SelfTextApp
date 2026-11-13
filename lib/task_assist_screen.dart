import 'package:flutter/material.dart';
import 'store.dart';

class TaskAssistScreen extends StatefulWidget {
  const TaskAssistScreen({
    super.key,
    required this.store,
    this.record,
    this.chatId,
    this.initialGoal,
  });
  final SelfTextStore store;
  final ProductivityRecord? record;
  final String? chatId, initialGoal;
  @override
  State<TaskAssistScreen> createState() => _TaskAssistState();
}

class _TaskAssistState extends State<TaskAssistScreen> {
  final goal = TextEditingController();
  bool busy = false;
  String? error, explanation, draftWorkspace;
  List<Map<String, dynamic>> tasks = [];
  final Set<int> selected = {};
  @override
  void initState() {
    super.initState();
    goal.text = widget.record?.title ?? widget.initialGoal ?? '';
  }

  @override
  void dispose() {
    goal.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    if (goal.text.trim().isEmpty) return;
    final workspace = widget.store.activeStorageKey;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.store.api.request('POST', '/ai/task-plan', {
        'goal': goal.text.trim(),
        if (widget.record != null) 'record_id': widget.record!.id,
      });
      if (!mounted || workspace != widget.store.activeStorageKey) return;
      setState(() {
        draftWorkspace = workspace;
        explanation = result['explanation'];
        tasks = (result['tasks'] as List)
            .map((t) => Map<String, dynamic>.from(t))
            .toList();
        selected
          ..clear()
          ..addAll(List.generate(tasks.length, (i) => i));
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void save() {
    if (selected.isEmpty) return;
    if (draftWorkspace != widget.store.activeStorageKey) {
      setState(() => error = 'Account changed. Generate a new plan first.');
      return;
    }
    final record = widget.record;
    if (record != null) {
      if (!widget.store.records.contains(record)) {
        setState(() => error = 'This task is no longer available.');
        return;
      }
      if (record.subtasks.length + (tasks.first['steps'] as List).length > 50) {
        setState(
          () => error =
              'This task already has too many steps. Remove some first.',
        );
        return;
      }
      record.subtasks = [
        ...record.subtasks,
        ...(tasks.first['steps'] as List).map(
          (s) => <String, dynamic>{'title': s, 'done': false},
        ),
      ];
      widget.store.changed();
    } else {
      for (final i in selected) {
        widget.store.createRecord(
          title: tasks[i]['title'],
          kind: RecordKind.task,
          chatId: widget.chatId ?? widget.store.chats.first.id,
          subtasks: (tasks[i]['steps'] as List)
              .map((s) => <String, dynamic>{'title': s, 'done': false})
              .toList(),
        );
      }
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.record == null
            ? 'Turn a goal into a plan'
            : 'Find your next steps',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Big ideas. Small, doable steps.',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'Describe what you want to achieve. AI drafts the tasks; you choose what to keep.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: goal,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Prepare for my exams next week…',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : generate,
          icon: const Icon(Icons.auto_awesome),
          label: Text(busy ? 'Thinking through your plan…' : 'Build my plan'),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (explanation != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(explanation!),
          ),
        for (var i = 0; i < tasks.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(i),
                    title: Text(tasks[i]['title']),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected.add(i);
                      } else {
                        selected.remove(i);
                      }
                    }),
                  ),
                  for (final step in tasks[i]['steps'] as List)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text('• $step'),
                    ),
                ],
              ),
            ),
          ),
        if (tasks.isNotEmpty)
          FilledButton(
            onPressed: selected.isEmpty ? null : save,
            child: Text(
              widget.record == null
                  ? 'Add selected tasks'
                  : 'Add checklist steps',
            ),
          ),
        const SizedBox(height: 30),
      ],
    ),
  );
}
