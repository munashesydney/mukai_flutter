import 'package:flutter/material.dart';

import '../../design/widgets.dart';
import '../../state/pursuit_sidebar_state.dart';
import 'connected_features_screen.dart' show OpenPursuitRun;
import 'connected_widgets.dart';

class PursuitSidebar extends StatefulWidget {
  const PursuitSidebar({
    super.key,
    this.selectedPursuitId,
    this.selectedRunId,
    required this.onOpenRun,
    required this.state,
  });

  final String? selectedPursuitId, selectedRunId;
  final OpenPursuitRun onOpenRun;
  final PursuitSidebarState state;

  @override
  State<PursuitSidebar> createState() => _PursuitSidebarState();
}

class _PursuitSidebarState extends State<PursuitSidebar> {
  String? _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.selectedPursuitId;
    if (_expanded != null) widget.state.ensureRuns(_expanded!);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      if (state.error != null && state.pursuits.isEmpty) {
        return TextButton(
          onPressed: () => state.refresh(state.workspaceId, force: true),
          child: const Text('Reload pursuits'),
        );
      }
      if (state.loading && !state.loaded) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Loading pursuits…'),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Column(
          children: [
            for (final (index, pursuit) in state.pursuits.indexed)
              if (index < state.visibleCount ||
                  pursuit['id'] == widget.selectedPursuitId) ...[
                ListTile(
                  dense: true,
                  minTileHeight: 40,
                  title: Text(
                    words(pursuit['name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    _expanded == pursuit['id']
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  onTap: () {
                    final id = words(pursuit['id']);
                    setState(() => _expanded = _expanded == id ? null : id);
                    if (_expanded != null) state.ensureRuns(id);
                  },
                ),
                if (_expanded == pursuit['id']) _runs(words(pursuit['id'])),
              ],
            if (state.pursuits.length > state.visibleCount)
              TextButton(
                onPressed: state.loadingMore ? null : state.loadMorePursuits,
                child: Text(
                  state.loadingMore ? 'Loading more…' : 'Load more pursuits',
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _runs(String id) {
    final state = widget.state;
    final detail = state.details[id];
    if (detail == null) {
      if (state.runErrors.containsKey(id)) {
        return TextButton(
          onPressed: () => state.ensureRuns(id),
          child: const Text('Reload runs'),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Loading runs…'),
      );
    }
    final runs = objects(detail['runs']);
    final count = detail['runCount'] as int? ?? runs.length;
    if (runs.isEmpty) return const Text('No runs yet');
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        children: [
          for (final (index, run) in runs.indexed)
            ListTile(
              key: ValueKey('sidebar-run-${run['id']}'),
              dense: true,
              minTileHeight: 38,
              title: Text('Run ${count - index}'),
              selected: run['id'] == widget.selectedRunId,
              trailing: run['status'] == 'running'
                  ? const BouncingDots()
                  : Text(label(run['status'])),
              onTap: () => widget.onOpenRun(id, words(run['id'])),
            ),
          if (count > runs.length)
            TextButton(
              onPressed: state.runsLoadingMore(id)
                  ? null
                  : () => state.loadMoreRuns(id),
              child: Text(
                state.runsLoadingMore(id)
                    ? 'Loading more…'
                    : state.runErrors.containsKey(id)
                    ? 'Retry loading more runs'
                    : 'Load more runs',
              ),
            ),
        ],
      ),
    );
  }
}
