import 'dart:async';
import 'package:flutter/material.dart';
import 'store.dart';

class NotesWorkspace extends StatefulWidget {
  const NotesWorkspace({super.key, required this.store});
  final SelfTextStore store;
  @override
  State<NotesWorkspace> createState() => _NotesWorkspaceState();
}

class _NotesWorkspaceState extends State<NotesWorkspace> {
  String query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final notes = widget.store.notes
          .where(
            (n) => '${n.title} ${n.body}'.toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('Notepad')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuickNoteEditor(
                store: widget.store,
                chatId: widget.store.chats.first.id,
              ),
            ),
          ),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Write a note'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            if (widget.store.notes.isNotEmpty) ...[
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  hintText: 'Search your notes',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (notes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 64),
                child: Column(
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      query.isEmpty
                          ? 'Your own little notepad'
                          : 'No matching notes',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Write it down. Your notes save as you go.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final note in notes)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: const Icon(Icons.description_outlined),
                  title: Text(note.title),
                  subtitle: Text(
                    note.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuickNoteEditor(
                        store: widget.store,
                        chatId: note.chatId,
                        record: note,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class QuickNoteEditor extends StatefulWidget {
  const QuickNoteEditor({
    super.key,
    required this.store,
    required this.chatId,
    this.record,
    this.initialText,
    this.sourceId,
  });
  final SelfTextStore store;
  final String chatId;
  final ProductivityRecord? record;
  final String? initialText, sourceId;
  @override
  State<QuickNoteEditor> createState() => _QuickNoteState();
}

class _QuickNoteState extends State<QuickNoteEditor> {
  late final title = TextEditingController(text: widget.record?.title ?? '');
  late final body = TextEditingController(
    text: widget.record?.body ?? widget.initialText ?? '',
  );
  late final workspace = widget.store.activeStorageKey;
  ProductivityRecord? saved;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    saved = widget.record;
  }

  void save([String? draftTitle, String? draftBody]) {
    final titleText = draftTitle ?? title.text;
    final bodyText = draftBody ?? body.text;
    debounce?.cancel();
    if (workspace != widget.store.activeStorageKey ||
        widget.store.storageError != null) {
      return;
    }
    if (saved != null && !widget.store.records.any((r) => r.id == saved!.id)) {
      return;
    }
    if (!widget.store.chats.any((c) => c.id == widget.chatId)) return;
    if (saved == null && bodyText.trim().isEmpty && titleText.trim().isEmpty) {
      return;
    }
    final name = titleText.trim().isNotEmpty
        ? titleText.trim()
        : bodyText.trim().split('\n').first;
    final safe = name.isEmpty
        ? 'Untitled note'
        : name.length > 120
        ? name.substring(0, 120)
        : name;
    if (saved == null) {
      saved = widget.store.createRecord(
        title: safe,
        kind: RecordKind.note,
        chatId: widget.chatId,
        sourceId: widget.sourceId,
        body: bodyText,
      );
    } else {
      saved = widget.store.records.firstWhere((r) => r.id == saved!.id);
      if (saved!.title == safe && saved!.body == bodyText) return;
      saved!.title = safe;
      saved!.body = bodyText;
      widget.store.changed();
    }
  }

  void queue() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 700), save);
  }

  @override
  void dispose() {
    debounce?.cancel();
    final t = title.text, b = body.text;
    scheduleMicrotask(() => save(t, b));
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notepad'),
      actions: [
        if (saved != null)
          IconButton(
            tooltip: 'Delete note',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete this note?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (yes == true && context.mounted) {
                widget.store.records.removeWhere((r) => r.id == saved!.id);
                widget.store.changed();
                Navigator.pop(context);
              }
            },
          ),
        IconButton(
          tooltip: 'Save note',
          onPressed: () {
            save();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            controller: title,
            maxLength: 120,
            onChanged: (_) => queue(),
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              hintText: 'Title (optional)',
              border: InputBorder.none,
              filled: false,
            ),
          ),
          Expanded(
            child: TextField(
              controller: body,
              maxLength: 10000,
              onChanged: (_) => queue(),
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 17, height: 1.7),
              decoration: const InputDecoration(
                hintText: 'Start writing…',
                border: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const Text(
            'Saved on this device as you write. Syncs when connected.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
