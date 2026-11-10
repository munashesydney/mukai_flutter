import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/api/api_client.dart';
import '../data/api/api_repository.dart' show encoded, object, objects, string;

/// Keeps the first run pages ready before the navigation drawer opens.
class PursuitSidebarState extends ChangeNotifier {
  PursuitSidebarState(this.api);
  final MukaiApiClient api;
  static const pageSize = 6;

  String workspaceId = '';
  List<Map<String, dynamic>> pursuits = [];
  final Map<String, Map<String, dynamic>> details = {};
  final Map<String, String> runErrors = {};
  final Map<String, Future<void>> _requests = {};
  final Set<String> _moreRequests = {};
  int visibleCount = pageSize;
  bool loading = false, loadingMore = false;
  String? error;
  int _generation = 0;
  bool _disposed = false, _loaded = false;
  bool get loaded => _loaded;

  Future<void> refresh(String workspace, {bool force = false}) async {
    if (_disposed || workspace.isEmpty) return;
    if (workspaceId != workspace) {
      _generation++;
      workspaceId = workspace;
      pursuits = [];
      details.clear();
      runErrors.clear();
      _requests.clear();
      _moreRequests.clear();
      visibleCount = pageSize;
      loading = false;
      loadingMore = false;
      _loaded = false;
      error = null;
    }
    if (loading || (_loaded && !force)) return;
    final generation = _generation;
    loading = true;
    try {
      final next = objects(
        await api.request('/pursuits?workspaceId=${encoded(workspace)}'),
      );
      if (!_current(generation)) return;
      final changed =
          jsonEncode(next) != jsonEncode(pursuits) || error != null || !_loaded;
      pursuits = next;
      error = null;
      await Future.wait([
        for (final pursuit in next.take(visibleCount))
          _loadRuns(string(pursuit['id']), refresh: true),
      ]);
      if (!_current(generation)) return;
      _loaded = true;
      loading = false;
      if (changed) notifyListeners();
    } catch (failure) {
      if (_current(generation) && !_loaded) {
        loading = false;
        error = failure.toString();
        notifyListeners();
      }
    } finally {
      if (_current(generation)) loading = false;
    }
  }

  Future<void> ensureRuns(String id) =>
      details.containsKey(id) ? Future<void>.value() : _loadRuns(id);

  Future<void> loadMoreRuns(String id) async {
    if (_disposed || _moreRequests.contains(id)) return;
    final generation = _generation;
    _moreRequests.add(id);
    notifyListeners();
    try {
      await _requests[id];
      if (_current(generation)) await _loadRuns(id, more: true);
    } finally {
      if (_current(generation)) {
        _moreRequests.remove(id);
        notifyListeners();
      }
    }
  }

  Future<void> _loadRuns(String id, {bool refresh = false, bool more = false}) {
    if (_disposed) return Future<void>.value();
    if (_requests[id] case final pending?) return pending;
    final generation = _generation;
    final current = details[id];
    final offset = more ? objects(current?['runs']).length : 0;
    if (!refresh && !more && current != null) return Future<void>.value();
    final request = () async {
      try {
        final next = object(
          await api.request(
            '/pursuits/${encoded(id)}?runLimit=$pageSize&runOffset=$offset',
          ),
        );
        if (!_current(generation)) return;
        final runs = <String, Map<String, dynamic>>{};
        for (final run in [
          if (more) ...objects(current?['runs']),
          ...objects(next['runs']),
          if (!more) ...objects(details[id]?['runs']),
        ]) {
          runs.putIfAbsent(string(run['id']), () => run);
        }
        final value = {...next, 'runs': runs.values.toList()};
        final changed =
            jsonEncode(value) != jsonEncode(details[id]) ||
            runErrors.containsKey(id);
        details[id] = value;
        runErrors.remove(id);
        if (changed) notifyListeners();
      } catch (failure) {
        if (_current(generation) && (more || !details.containsKey(id))) {
          runErrors[id] = failure.toString();
          notifyListeners();
        }
      } finally {
        if (_current(generation)) {
          _requests.remove(id);
        }
      }
    }();
    _requests[id] = request;
    return request;
  }

  bool runsLoadingMore(String id) => _moreRequests.contains(id);

  Future<void> loadMorePursuits() async {
    if (_disposed || loadingMore) return;
    final generation = _generation;
    loadingMore = true;
    notifyListeners();
    try {
      await Future.wait([
        for (final pursuit in pursuits.skip(visibleCount).take(pageSize))
          ensureRuns(string(pursuit['id'])),
      ]);
      if (_current(generation)) visibleCount += pageSize;
    } finally {
      if (_current(generation)) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
