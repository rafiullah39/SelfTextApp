import 'package:flutter/material.dart';
import 'store.dart';

class SearchWorkspace extends StatefulWidget {
  const SearchWorkspace({
    super.key,
    required this.store,
    required this.openRecord,
    required this.openMessage,
  });
  final SelfTextStore store;
  final void Function(ProductivityRecord) openRecord;
  final void Function(Entry) openMessage;
  @override
  State<SearchWorkspace> createState() => _SearchWorkspaceState();
}

class _SearchWorkspaceState extends State<SearchWorkspace> {
  final query = TextEditingController();
  final tag = TextEditingController();
  String kind = 'all', status = 'all';
  String? chat;
  DateTimeRange? dates;
  bool busy = false;
  String? error, scope;
  List<Map<String, dynamic>> semantic = [];
  String? workspace;
  @override
  void dispose() {
    query.dispose();
    tag.dispose();
    super.dispose();
  }

  bool inDates(DateTime? time) =>
      dates == null ||
      (time != null &&
          !time.isBefore(dates!.start) &&
          time.isBefore(dates!.end.add(const Duration(days: 1))));
  bool recordMatches(ProductivityRecord r) =>
      (chat == null || r.chatId == chat) &&
      (kind == 'all' || kind == r.kind.name) &&
      (status == 'all' || status == r.status) &&
      (tag.text.trim().isEmpty ||
          r.tags.any(
            (t) => t.toLowerCase() == tag.text.trim().toLowerCase(),
          )) &&
      inDates(r.dueAt);
  bool messageMatches(Entry m) =>
      (chat == null || m.chatId == chat) &&
      (kind == 'all' || kind == 'message') &&
      status == 'all' &&
      tag.text.trim().isEmpty &&
      inDates(m.createdAt);
  Future<void> searchSemantic() async {
    if (query.text.trim().isEmpty || busy) return;
    final submitted = query.text.trim();
    final submittedWorkspace = widget.store.activeStorageKey;
    widget.store.rememberSearch(submitted);
    setState(() {
      busy = true;
      error = null;
      semantic = [];
      scope = null;
    });
    try {
      await widget.store.sync();
      if (widget.store.activeStorageKey != submittedWorkspace) return;
      final result = await widget.store.api.request(
        'POST',
        '/search/semantic',
        {'query': submitted},
      );
      if (!mounted ||
          query.text.trim() != submitted ||
          widget.store.activeStorageKey != submittedWorkspace) {
        return;
      }
      setState(() {
        semantic = (result['matches'] as List)
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        scope = result['scope'];
      });
    } catch (e) {
      if (mounted &&
          query.text.trim() == submitted &&
          widget.store.activeStorageKey == submittedWorkspace) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && widget.store.activeStorageKey == submittedWorkspace) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (workspace != store.activeStorageKey) {
      if (workspace != null) {
        query.clear();
        tag.clear();
        semantic = [];
        error = null;
        scope = null;
        chat = null;
        dates = null;
        kind = 'all';
        status = 'all';
        busy = false;
      }
      workspace = store.activeStorageKey;
    }
    final q = query.text.trim().toLowerCase();
    final records = store.records
        .where(
          (r) =>
              recordMatches(r) &&
              '${r.title} ${r.body} ${r.tags.join(' ')}'.toLowerCase().contains(
                q,
              ),
        )
        .toList();
    final messages = store.messages
        .where((m) => messageMatches(m) && m.text.toLowerCase().contains(q))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        TextField(
          controller: query,
          decoration: const InputDecoration(
            hintText: 'Search messages, tasks, ideas…',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {
            semantic = [];
            error = null;
            scope = null;
          }),
          onSubmitted: store.rememberSearch,
        ),
        if (q.isEmpty && store.recentSearches.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(child: Text('Recent searches')),
              TextButton(
                onPressed: () => setState(store.clearRecentSearches),
                child: const Text('Clear history'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: store.recentSearches
                .map(
                  (term) => ActionChip(
                    label: Text(term),
                    onPressed: () => setState(() {
                      query.text = term;
                    }),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: ['all', 'message', 'task', 'event', 'note']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => kind = v!),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items:
                    [
                          'all',
                          'inbox',
                          'planned',
                          'in_progress',
                          'done',
                          'cancelled',
                        ]
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(v.replaceAll('_', ' ')),
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() => status = v!),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: chat ?? 'all',
                decoration: const InputDecoration(labelText: 'Chat'),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All chats'),
                  ),
                  ...store.chats.map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.title, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => chat = v == 'all' ? null : v),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: tag,
                decoration: const InputDecoration(labelText: 'Tag'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(dates == null ? 'Date range' : 'Clear date range'),
              onPressed: () async {
                if (dates != null) {
                  setState(() => dates = null);
                  return;
                }
                final selected = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (mounted && selected != null) {
                  setState(() => dates = selected);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Dates filter record due times and message capture times.'),
        if (store.signedIn) ...[
          const SizedBox(height: 12),
          const Text(
            'AI search sends your query and recent saved content to the configured AI provider. Use it only for content you want processed there.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy ? null : searchSemantic,
              icon: const Icon(Icons.auto_awesome),
              label: Text(busy ? 'Searching…' : 'Search by meaning'),
            ),
          ),
        ],
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (scope != null) ...[
          Text('AI matches · $scope'),
          if (semantic.isEmpty) const Text('No semantic matches.'),
          ...semantic.map((match) {
            final r = store.records
                .where((r) => r.id == match['id'])
                .firstOrNull;
            final m = store.messages
                .where((m) => m.id == match['id'])
                .firstOrNull;
            if (r != null && recordMatches(r)) {
              return ListTile(
                title: Text(r.title),
                subtitle: Text('AI match · ${store.chatTitle(r.chatId)}'),
                onTap: () => widget.openRecord(r),
              );
            }
            if (m != null && messageMatches(m)) {
              return ListTile(
                title: Text(m.text),
                subtitle: Text('AI match · ${store.chatTitle(m.chatId)}'),
                onTap: () => widget.openMessage(m),
              );
            }
            return const SizedBox.shrink();
          }),
        ],
        const SizedBox(height: 16),
        const Text('Keyword matches'),
        if (records.isEmpty && messages.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No matches. Try a different word or filter.'),
          ),
        ...records.map(
          (r) => Card(
            child: ListTile(
              title: Text(r.title),
              subtitle: Text(
                '${r.kind.name} · ${store.chatTitle(r.chatId)} · ${r.status}',
              ),
              onTap: () => widget.openRecord(r),
            ),
          ),
        ),
        ...messages.map(
          (m) => Card(
            child: ListTile(
              title: Text(m.text),
              subtitle: Text(store.chatTitle(m.chatId)),
              onTap: () => widget.openMessage(m),
            ),
          ),
        ),
      ],
    );
  }
}
