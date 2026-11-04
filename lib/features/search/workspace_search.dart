import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../data/api/api_repository.dart' show objects, string, encoded;
import '../../design/appearance.dart';
import '../../design/widgets.dart';
import '../../domain/models.dart';

enum WorkspaceSearchKind { companion, conversation, space, pursuit }

class WorkspaceSearchResult {
  const WorkspaceSearchResult({
    required this.id,
    required this.title,
    required this.detail,
    required this.kind,
    this.bot,
    this.conversation,
  });
  final String id, title, detail;
  final WorkspaceSearchKind kind;
  final MukaiBot? bot;
  final Conversation? conversation;
}

/// Search names and descriptions in the current workspace. Like the desktop
/// search, it uses the normal workspace APIs, never another workspace's index.
class WorkspaceSearchPage extends StatefulWidget {
  const WorkspaceSearchPage({super.key});
  @override
  State<WorkspaceSearchPage> createState() => _WorkspaceSearchPageState();
}

class _WorkspaceSearchPageState extends State<WorkspaceSearchPage> {
  final _input = TextEditingController();
  Timer? _debounce;
  List<WorkspaceSearchResult> _items = [];
  String _query = '';
  WorkspaceSearchKind? _filter;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final session = MukaiScope.sessionOf(context);
    final workspace = session.workspace.id;
    final bots = session.bots;
    final initial = <WorkspaceSearchResult>[
      for (final bot in bots)
        WorkspaceSearchResult(
          id: bot.id,
          title: bot.name,
          detail: bot.role,
          kind: WorkspaceSearchKind.companion,
          bot: bot,
        ),
      for (final conversation
          in session.remote?.allConversations ?? session.recents)
        _conversation(conversation, bots),
    ];
    setState(() {
      _items = initial;
      _loading = session.api != null;
      _error = null;
    });
    if (session.api == null) return;
    final query = 'workspaceId=${encoded(workspace)}';
    // Keep partial results usable if one endpoint is temporarily unavailable.
    final requests = [
      '/conversations?$query',
      '/conversations?$query&kind=private',
      '/conversations?$query&kind=bot',
      '/pursuits?$query',
    ];
    final values = await Future.wait(
      requests.map((path) async {
        try {
          return (value: await session.api!.request(path), failed: false);
        } catch (_) {
          return (value: null, failed: true);
        }
      }),
    );
    if (!mounted ||
        generation != _generation ||
        session.workspace.id != workspace) {
      return;
    }
    final conversations = <String, Conversation>{
      for (final conversation in session.remote!.allConversations)
        conversation.id: conversation,
    };
    for (final response in values.take(3)) {
      for (final row in objects(response.value)) {
        final conversation = session.remote!.conversationFromJson(row);
        conversations[conversation.id] = conversation;
      }
    }
    final sorted = conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    setState(() {
      _loading = false;
      _error = values.any((v) => v.failed)
          ? 'Some results couldn’t load. You can retry without losing your search.'
          : null;
      _items = [
        ...initial.where((r) => r.kind == WorkspaceSearchKind.companion),
        for (final c in sorted) _conversation(c, bots),
        for (final p in objects(values.last.value))
          WorkspaceSearchResult(
            id: string(p['id']),
            title: string(p['name'], 'Untitled pursuit'),
            detail: string(p['objective']),
            kind: WorkspaceSearchKind.pursuit,
          ),
      ];
    });
  }

  WorkspaceSearchResult _conversation(Conversation c, List<MukaiBot> bots) =>
      WorkspaceSearchResult(
        id: c.id,
        title: c.title,
        detail: c.description.isEmpty ? c.preview : c.description,
        kind: c.kind == 'space'
            ? WorkspaceSearchKind.space
            : WorkspaceSearchKind.conversation,
        conversation: c,
        bot: bots.where((b) => b.id == c.botId).firstOrNull,
      );

  List<WorkspaceSearchResult> _results(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final matches = _items
        .where(
          (r) =>
              (_filter == null || r.kind == _filter) &&
              terms.every(
                (term) => '${r.title} ${r.detail}'.toLowerCase().contains(term),
              ),
        )
        .toList();
    if (terms.isNotEmpty) {
      int score(WorkspaceSearchResult r) =>
          r.title.toLowerCase() == query.trim().toLowerCase()
          ? 0
          : r.title.toLowerCase().startsWith(terms.first)
          ? 1
          : 2;
      // Preserve recency within equally relevant results.
      final positions = {for (var i = 0; i < _items.length; i++) _items[i]: i};
      matches.sort(
        (a, b) => score(a) == score(b)
            ? positions[a]!.compareTo(positions[b]!)
            : score(a).compareTo(score(b)),
      );
    }
    return matches;
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final results = _results(_query);
    const labels = {
      WorkspaceSearchKind.companion: 'Companions',
      WorkspaceSearchKind.conversation: 'Chats',
      WorkspaceSearchKind.space: 'Spaces',
      WorkspaceSearchKind.pursuit: 'Pursuits',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                key: const ValueKey('workspace-search-input'),
                controller: _input,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _changed,
                onSubmitted: (value) {
                  final matches = _results(value);
                  if (matches.isNotEmpty) Navigator.pop(context, matches.first);
                },
                decoration: InputDecoration(
                  hintText: 'Search your workspace',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _debounce?.cancel();
                      _input.clear();
                      setState(() => _query = '');
                    },
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                  ),
                  for (final kind in WorkspaceSearchKind.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(labels[kind]!),
                        selected: _filter == kind,
                        onSelected: (_) => setState(() => _filter = kind),
                      ),
                    ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: MukaiErrorBanner(message: _error!, onRetry: _load),
              ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _loading
                              ? 'Finding your workspace…'
                              : 'No matches. Try another name or word.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final result = results[index];
                        return ListTile(
                          key: ValueKey(
                            'search-${result.kind.name}-${result.id}',
                          ),
                          leading: result.bot != null
                              ? GhostAvatar(
                                  mascot: result.bot!.mascot,
                                  identity: result.bot!.identity,
                                  size: 30,
                                )
                              : Icon(
                                  result.kind == WorkspaceSearchKind.pursuit
                                      ? Icons.track_changes_rounded
                                      : result.kind == WorkspaceSearchKind.space
                                      ? Icons.layers_outlined
                                      : Icons.chat_bubble_outline_rounded,
                                  color: colors.textSecondary,
                                ),
                          title: Text(
                            result.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${labels[result.kind]}${result.detail.isEmpty ? '' : ' · ${result.detail}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(
                            Icons.north_east_rounded,
                            size: 16,
                            color: colors.textMuted,
                          ),
                          onTap: () => Navigator.pop(context, result),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
