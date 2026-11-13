import 'package:flutter/material.dart';
import 'store.dart';

class MessageSummaryScreen extends StatefulWidget {
  const MessageSummaryScreen({
    super.key,
    required this.store,
    required this.chat,
  });
  final SelfTextStore store;
  final Chat chat;
  @override
  State<MessageSummaryScreen> createState() => _MessageSummaryState();
}

class _MessageSummaryState extends State<MessageSummaryScreen> {
  final selected = <String>{};
  final title = TextEditingController(), body = TextEditingController();
  List<Entry> sources = [];
  bool busy = false;
  String? error;
  String? draftWorkspace;
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    final workspace = widget.store.userId;
    final ids = List<String>.of(selected);
    setState(() {
      busy = true;
      error = null;
      sources = [];
    });
    try {
      await widget.store.sync();
      if (widget.store.syncError != null) {
        throw StateError(widget.store.syncError!);
      }
      if (workspace != widget.store.userId || !widget.store.signedIn) {
        throw StateError('Account changed. Open this screen again.');
      }
      final result = await widget.store.api.request(
        'POST',
        '/chats/${widget.chat.id}/summary',
        {'message_ids': ids},
      );
      if (!mounted || workspace != widget.store.userId) return;
      setState(() {
        title.text = result['title'];
        body.text = result['body'];
        draftWorkspace = workspace;
        sources = widget.store
            .history(widget.chat.id)
            .where((m) => ids.contains(m.id))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void save() {
    if (sources.isEmpty ||
        draftWorkspace != widget.store.userId ||
        !widget.store.signedIn) {
      setState(() => error = 'Account changed. Generate a new draft first.');
      return;
    }
    if (title.text.trim().isEmpty ||
        title.text.length > 500 ||
        body.text.trim().isEmpty ||
        body.text.length > 10000) {
      setState(
        () => error =
            'Use a title up to 500 characters and a summary up to 10,000 characters.',
      );
      return;
    }
    // Keep the selected originals in the saved note so every source is retained.
    final content =
        '${body.text.trim()}\n\nOriginal messages:\n${sources.map((m) => '• ${m.text}').join('\n')}';
    if (content.length > 10000) {
      setState(
        () => error =
            'Summary and original messages exceed 10,000 characters. Shorten the draft or select fewer messages.',
      );
      return;
    }
    widget.store.createRecord(
      title: title.text.trim(),
      kind: RecordKind.note,
      chatId: widget.chat.id,
      sourceId: sources.first.id,
      body: content,
      tags: ['summary'],
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Summarize selected messages')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Select the messages to send to AI. Review the draft before saving a note. Original messages remain unchanged.',
        ),
        if (!widget.store.signedIn) const Text('Sign in to use AI summaries.'),
        ...widget.store
            .history(widget.chat.id)
            .map(
              (m) => CheckboxListTile(
                value: selected.contains(m.id),
                title: Text(m.text),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        sources = [];
                        if (value == true) {
                          if (selected.length < 50) selected.add(m.id);
                        } else {
                          selected.remove(m.id);
                        }
                      }),
              ),
            ),
        FilledButton(
          onPressed: busy || selected.isEmpty || !widget.store.signedIn
              ? null
              : generate,
          child: Text(busy ? 'Generating draft…' : 'Generate summary draft'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Review and edit the AI draft'),
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Note title'),
          ),
          TextField(
            controller: body,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(labelText: 'Summary'),
          ),
          const Text(
            'The saved note also retains copies of all selected original messages.',
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('Save reviewed summary as note'),
          ),
        ],
      ],
    ),
  );
}
