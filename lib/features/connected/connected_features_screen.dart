import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../core/format.dart';
import '../../core/workspace_time.dart';

import '../../app/scope.dart';
import '../../design/appearance.dart';
import '../../design/glass.dart';
import '../../design/widgets.dart';
import '../../design/disclosure.dart';
import '../../domain/models.dart';
import '../chat/chat_screen.dart';
import '../chat/widgets/open_content.dart';
import '../chat/widgets/file_preview.dart';
import '../../core/response_reference.dart';
import '../../core/message_reference.dart';
import 'connected_widgets.dart';

part 'pursuit_views.dart';
part 'updates_screen.dart';

typedef OpenPursuitRun = void Function(String pursuitId, String runId);

Future<void> openPursuit(
  BuildContext context,
  String id,
  OpenPursuitRun onOpenRun, {
  bool animate = true,
}) => Navigator.of(context).push<void>(
  animate
      ? MaterialPageRoute(
          builder: (_) => _PursuitPage(id: id, onOpenRun: onOpenRun),
        )
      : PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => _PursuitPage(id: id, onOpenRun: onOpenRun),
        ),
);

class ConnectedFeaturesScreen extends StatelessWidget {
  const ConnectedFeaturesScreen({
    super.key,
    required this.kind,
    required this.onOpenConversation,
    this.onOpenRun,
  }) : assert(kind != 'pursuits' || onOpenRun != null);
  final String kind;
  final ValueChanged<Conversation> onOpenConversation;
  final OpenPursuitRun? onOpenRun;

  @override
  Widget build(BuildContext context) {
    if (kind == 'pursuits') {
      return _PursuitsScreen(onOpenRun: onOpenRun!);
    }
    final workspaceId = MukaiScope.sessionOf(context).workspace.id;
    final title = switch (kind) {
      'pursuits' => 'Pursuits',
      'spaces' => 'Spaces',
      _ => 'Tools',
    };
    return ConnectedAsync(
      key: ValueKey('$kind:$workspaceId'),
      refreshInterval: kind == 'pursuits' ? const Duration(seconds: 5) : null,
      load: () async {
        final query = workspaceQuery(context);
        if (kind == 'spaces') {
          return connectedRequest(context, '/conversations?$query&kind=space');
        }
        if (kind == 'tools') {
          final values = await Future.wait<dynamic>(<Future<dynamic>>[
            connectedRequest(context, '/tools?$query'),
            connectedRequest(context, '/tools/assignments?$query'),
          ]);
          return <String, dynamic>{
            'tools': values[0],
            'assignments': values[1],
          };
        }
        return connectedRequest(context, '/pursuits?$query');
      },
      builder: (context, data, reload) {
        final rows = kind == 'tools'
            ? objects(object(data)['tools'])
            : objects(data);
        return RefreshIndicator.adaptive(
          onRefresh: reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: ConnectedHeading(
                  title,
                  subtitle: switch (kind) {
                    'pursuits' => 'Goals your companions keep moving forward.',
                    'spaces' => 'A shared place to think and work together.',
                    _ => 'What your companions can do.',
                  },
                  trailing: kind == 'spaces'
                      ? MukaiIconButton(
                          icon: Icons.add_rounded,
                          tooltip: 'New space',
                          border: false,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _SpaceEditor(onCreated: onOpenConversation),
                              ),
                            );
                            if (context.mounted) await reload();
                          },
                        )
                      : null,
                ),
              ),
              if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom + 24,
                    ),
                    child: ConnectedEmpty(
                      title:
                          'No ${kind == 'tools' ? 'tools available' : '$kind yet'}',
                      body: switch (kind) {
                        'pursuits' =>
                          'Ask a companion to pursue a goal. It will appear here, along with its progress and workpad.',
                        'spaces' =>
                          'Create a space to bring conversations and companions together.',
                        _ => 'Tools from your workspace will appear here.',
                      },
                      icon: kind == 'pursuits'
                          ? Icons.track_changes_rounded
                          : kind == 'spaces'
                          ? Icons.layers_outlined
                          : Icons.extension_outlined,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 24,
                  ),
                  sliver: SliverList.list(
                    children: [
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: MukaiCard(
                            elevated: false,
                            padding: EdgeInsets.zero,
                            child: MukaiRow(
                              title: words(row['name'], 'Untitled'),
                              subtitle: kind == 'pursuits'
                                  ? '${label(row['status'])} · ${words(row['objective'])}'
                                  : words(row['description']),
                              leading: Icon(
                                kind == 'pursuits'
                                    ? Icons.track_changes_rounded
                                    : kind == 'spaces'
                                    ? Icons.forum_outlined
                                    : Icons.extension_outlined,
                                color: MukaiColors.of(context).accentInk,
                              ),
                              onTap: () async {
                                if (kind == 'spaces') {
                                  onOpenConversation(_space(row));
                                  return;
                                }
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => _ToolPage(
                                      tool: row,
                                      assignments: objects(
                                        object(data)['assignments'],
                                      ),
                                      onChanged: reload,
                                    ),
                                  ),
                                );
                                if (context.mounted) await reload();
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Conversation _space(JsonMap value) {
  final ids = (value['botIds'] as List? ?? <dynamic>[])
      .map((id) => id.toString())
      .toList();
  return Conversation(
    id: words(value['id']),
    title: words(value['name'], 'Space'),
    botId: words(value['ownerBotId'], ids.isEmpty ? '' : ids.first),
    updatedAt: DateTime.tryParse(words(value['updatedAt'])) ?? DateTime.now(),
    kind: words(value['kind'], 'space'),
    description: words(value['description']),
    botIds: ids,
  );
}

class _WorkpadPage extends StatefulWidget {
  const _WorkpadPage({required this.pursuitId});
  final String pursuitId;
  @override
  State<_WorkpadPage> createState() => _WorkpadPageState();
}

class _WorkpadPageState extends State<_WorkpadPage> {
  int _offset = 0;
  String _type = '';
  bool _archived = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Workpad'),
      leading: MukaiGlassPill.circle(child: const BackButton()),
    ),
    body: Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DropdownButton<String>(
                  value: _type,
                  isExpanded: true,
                  items:
                      <String>[
                            '',
                            'work_item',
                            'decision',
                            'blocker',
                            'reference',
                            'note',
                          ]
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(
                                type.isEmpty ? 'All entries' : label(type),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() {
                    _type = value ?? '';
                    _offset = 0;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Include archived',
                child: Switch.adaptive(
                  value: _archived,
                  onChanged: (value) => setState(() {
                    _archived = value;
                    _offset = 0;
                  }),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ConnectedAsync(
            key: ValueKey('$_offset:$_type:$_archived'),
            load: () => connectedRequest(
              context,
              '/pursuits/${encoded(widget.pursuitId)}/workpad?offset=$_offset&limit=30&includeArchived=$_archived${_type.isEmpty ? '' : '&type=$_type'}',
            ),
            builder: (context, data, reload) {
              final page = object(data),
                  entries = objects(object(data)['entries']);
              return ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: MukaiCard(
                        elevated: false,
                        padding: EdgeInsets.zero,
                        child: MukaiRow(
                          title: words(entry['title']),
                          subtitle:
                              '${label(entry['type'])} · ${label(entry['status'])}',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _WorkpadEntry(
                                pursuitId: widget.pursuitId,
                                entryId: words(entry['id']),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (entries.isEmpty)
                    const Text('No workpad entries match this view.'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    children: <Widget>[
                      if (_offset > 0)
                        MukaiButton(
                          label: 'Previous',
                          compact: true,
                          variant: MukaiButtonVariant.tonal,
                          onPressed: () => setState(
                            () => _offset = (_offset - 30).clamp(0, _offset),
                          ),
                        ),
                      if (page['nextOffset'] is num)
                        MukaiButton(
                          label: 'Next',
                          compact: true,
                          onPressed: () => setState(
                            () => _offset = (page['nextOffset'] as num).toInt(),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _WorkpadEntry extends StatelessWidget {
  const _WorkpadEntry({required this.pursuitId, required this.entryId});
  final String pursuitId, entryId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Workpad entry'),
      leading: MukaiGlassPill.circle(child: const BackButton()),
    ),
    body: ConnectedAsync(
      refreshInterval: const Duration(seconds: 5),
      load: () => connectedRequest(
        context,
        '/pursuits/${encoded(pursuitId)}/workpad?entryId=${encoded(entryId)}',
      ),
      builder: (context, data, reload) {
        final entry = object(data);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                words(entry['title']),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${label(entry['type'])} · ${label(entry['status'])}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              SelectableText(
                words(entry['content']),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              for (final link in objects(entry['links']))
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: SelectableText(
                    '${words(link['label'])}\n${words(link['target'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _SpaceEditor extends StatefulWidget {
  const _SpaceEditor({required this.onCreated});
  final ValueChanged<Conversation> onCreated;
  @override
  State<_SpaceEditor> createState() => _SpaceEditorState();
}

class _SpaceEditorState extends State<_SpaceEditor> {
  final _name = TextEditingController(), _description = TextEditingController();
  final Set<String> _bots = <String>{};
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final value = await connectedRequest(
        context,
        '/conversations',
        method: 'POST',
        body: <String, dynamic>{
          'workspaceId': MukaiScope.sessionOf(context).workspace.id,
          'name': _name.text.trim(),
          'description': _description.text.trim(),
          'botIds': _bots.toList(),
        },
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated(_space(object(value)));
    } catch (error) {
      if (context.mounted) connectionNotice(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('New space'),
      leading: MukaiGlassPill.circle(child: const BackButton()),
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
            maxLength: 400,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 24),
          const Eyebrow('Companions'),
          const SizedBox(height: 12),
          for (final bot in MukaiScope.sessionOf(context).bots)
            CheckboxListTile.adaptive(
              title: Text(bot.name),
              subtitle: Text(bot.role),
              value: _bots.contains(bot.id),
              onChanged: (value) => setState(() {
                if (value == true) {
                  _bots.add(bot.id);
                } else {
                  _bots.remove(bot.id);
                }
              }),
            ),
          const SizedBox(height: 24),
          MukaiButton(
            label: 'Create space',
            busy: _busy,
            expand: true,
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
        ],
      ),
    ),
  );
}

class _ToolPage extends StatefulWidget {
  const _ToolPage({
    required this.tool,
    required this.assignments,
    required this.onChanged,
  });
  final JsonMap tool;
  final List<JsonMap> assignments;
  final Future<void> Function() onChanged;
  @override
  State<_ToolPage> createState() => _ToolPageState();
}

class _ToolPageState extends State<_ToolPage> {
  final Set<String> _busy = <String>{};
  late final List<JsonMap> _assignments = widget.assignments
      .map((assignment) => JsonMap.from(assignment))
      .toList();
  bool _enabled(String botId) => _assignments.any(
    (assignment) =>
        assignment['toolId'] == widget.tool['id'] &&
        assignment['botId'] == botId &&
        assignment['enabled'] == true,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(words(widget.tool['name'], 'Tool')),
      leading: MukaiGlassPill.circle(child: const BackButton()),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(
          words(widget.tool['description']),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Text(
          widget.tool['available'] == true
              ? 'Available in this workspace'
              : 'Unavailable in this workspace',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        if (widget.tool['scope'] == 'all-bots')
          const Text('This tool is available to every companion.')
        else ...<Widget>[
          const Eyebrow('Companion access'),
          const SizedBox(height: 12),
          for (final bot in MukaiScope.sessionOf(context).bots)
            SwitchListTile.adaptive(
              title: Text(bot.name),
              subtitle: Text(bot.isMain ? 'Main companion' : bot.role),
              value: _enabled(bot.id),
              onChanged:
                  _busy.contains(bot.id) || widget.tool['available'] != true
                  ? null
                  : (enabled) async {
                      setState(() => _busy.add(bot.id));
                      try {
                        final result = object(
                          await connectedRequest(
                            context,
                            '/tools/assignments?${workspaceQuery(context)}',
                            method: 'PUT',
                            body: <String, dynamic>{
                              'botId': bot.id,
                              'toolId': widget.tool['id'],
                              'enabled': enabled,
                            },
                          ),
                        );
                        if (!mounted) return;
                        setState(() {
                          _assignments.removeWhere(
                            (assignment) =>
                                assignment['botId'] == bot.id &&
                                assignment['toolId'] == widget.tool['id'],
                          );
                          _assignments.add(result);
                        });
                        await widget.onChanged();
                      } catch (error) {
                        if (context.mounted) {
                          connectionNotice(context, error);
                        }
                      } finally {
                        if (mounted) setState(() => _busy.remove(bot.id));
                      }
                    },
            ),
        ],
        const SizedBox(height: 24),
        if ((widget.tool['actions'] as List? ?? <dynamic>[])
            .isNotEmpty) ...<Widget>[
          const Eyebrow('Actions'),
          const SizedBox(height: 8),
          SelectableText((widget.tool['actions'] as List).join(' · ')),
        ],
      ],
    ),
  );
}
