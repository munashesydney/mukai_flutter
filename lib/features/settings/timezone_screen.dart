import 'dart:async';
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../core/format.dart';
import '../../core/workspace_time.dart';
import '../../design/glass.dart';
import '../../design/widgets.dart';
import '../../domain/models.dart';

class TimezoneScreen extends StatefulWidget {
  const TimezoneScreen({super.key, required this.workspace});
  final MukaiWorkspace workspace;

  @override
  State<TimezoneScreen> createState() => _TimezoneScreenState();
}

class _TimezoneScreenState extends State<TimezoneScreen> {
  late String? _selected = widget.workspace.timeZone;
  final _search = TextEditingController();
  final _zones = WorkspaceTime.names;
  DateTime _now = DateTime.now();
  Timer? _timer;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final zone = _selected;
    if (_saving || zone == null || !WorkspaceTime.isValid(zone)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await MukaiScope.sessionOf(
        context,
      ).setWorkspaceTimeZone(widget.workspace.id, zone);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final query = _search.text.trim().toLowerCase().replaceAll(' ', '_');
    final zones = _zones
        .where((zone) => zone.toLowerCase().contains(query))
        .toList();
    final valid = selected != null && WorkspaceTime.isValid(selected);
    final local = valid ? WorkspaceTime.local(_now, selected) : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timezone'),
        leading: const MukaiGlassBackButton(),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.workspace.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Shared with your workspace and its bots. Travelling with this iPhone does not change the selection. Existing scheduled runs keep their instant.',
                          ),
                          const SizedBox(height: 16),
                          if (local != null) ...[
                            Text(
                              selected!,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${MaterialLocalizations.of(context).formatMediumDate(local)} · ${Format.clock(_now, timeZone: selected)} · ${WorkspaceTime.offset(_now, selected)}',
                              key: const ValueKey('timezone-preview'),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextField(
                            controller: _search,
                            enabled: !_saving,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Search timezones',
                              hintText: 'City or America/Vancouver',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (zones.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No matching timezones. Try a city or region.',
                        ),
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: zones.length,
                      itemBuilder: (context, index) {
                        final zone = zones[index];
                        return ListTile(
                          title: Text(WorkspaceTime.city(zone)),
                          subtitle: Text(zone),
                          selected: zone == selected,
                          enabled: !_saving,
                          trailing: zone == selected
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => setState(() {
                            _selected = zone;
                            _error = null;
                          }),
                        );
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  MukaiButton(
                    label: 'Save timezone',
                    busy: _saving,
                    expand: true,
                    onPressed: valid && selected != widget.workspace.timeZone
                        ? _save
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
