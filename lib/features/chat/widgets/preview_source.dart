import 'dart:async';
import 'dart:collection';

import '../../../core/response_reference.dart';
import '../../../data/api/api_client.dart';

class PreviewSource {
  const PreviewSource({
    required this.href,
    required this.conversationId,
    this.messageId,
    this.name = 'File',
    this.image = false,
  });
  final String href, conversationId, name;
  final String? messageId;
  final bool image;
  String get key => '$conversationId|$messageId|$image|$href';
}

/// Bound preview work and cache only this authenticated API session's bytes.
class PreviewLoader {
  PreviewLoader(this.api);
  final MukaiApiClient api;
  static final _sessions = Expando<PreviewLoader>();
  static PreviewLoader forApi(MukaiApiClient api) =>
      _sessions[api] ??= PreviewLoader(api);
  final _cache = <String, DownloadedContent>{};
  final _pending = <String, Future<DownloadedContent>>{};
  final _queue = Queue<Completer<void>>();
  int _active = 0, _cachedBytes = 0;

  Future<DownloadedContent> load(PreviewSource source) {
    final cached = _cache.remove(source.key);
    if (cached != null) {
      _cache[source.key] = cached;
      return Future.value(cached);
    }
    if (_pending.length >= 256 && !_pending.containsKey(source.key)) {
      return Future.error(
        const ApiException('Too many previews are loading. Try again shortly.'),
      );
    }
    return _pending.putIfAbsent(source.key, () => _load(source));
  }

  Future<DownloadedContent> _load(PreviewSource source) async {
    await Future<void>.value();
    if (_active >= 3) {
      final ready = Completer<void>();
      _queue.add(ready);
      try {
        await ready.future.timeout(const Duration(seconds: 45));
      } catch (_) {
        _queue.remove(ready);
        _pending.remove(source.key);
        rethrow;
      }
    } else {
      _active++;
    }
    try {
      final reference = parseResponseReference(source.href);
      DownloadedContent result;
      if (source.href.startsWith('mukai-activity:') &&
          source.messageId != null) {
        result = await api.downloadContent(
          '/conversations/${Uri.encodeComponent(source.conversationId)}/activity-image',
          method: 'POST',
          body: {
            'messageId': source.messageId,
            'activityId': source.href.substring('mukai-activity:'.length),
          },
        );
      } else if (reference == null) {
        throw const ApiException('This reference cannot be previewed.');
      } else if (reference.type == 'attachment' ||
          reference.type == 'artifact') {
        result = await api.downloadContent(
          '/${reference.type == 'artifact' ? 'artifacts' : 'attachments'}/${Uri.encodeComponent(reference.value)}',
        );
      } else {
        result = await api.downloadContent(
          '/conversations/${Uri.encodeComponent(source.conversationId)}/reference',
          method: 'POST',
          body: {'href': source.href, 'image': source.image},
        );
      }
      if (result.name == 'File' && source.name != 'File') {
        result = DownloadedContent(
          result.bytes,
          name: source.name,
          mediaType: result.mediaType,
        );
      }
      // Keep a small LRU; large media are held only by their current viewer.
      if (result.bytes.length <= 8 * 1024 * 1024) {
        while (_cache.isNotEmpty &&
            (_cache.length >= 12 ||
                _cachedBytes + result.bytes.length > 32 * 1024 * 1024)) {
          _cachedBytes -= _cache.remove(_cache.keys.first)!.bytes.length;
        }
        _cache[source.key] = result;
        _cachedBytes += result.bytes.length;
      }
      return result;
    } finally {
      _pending.remove(source.key);
      if (_queue.isNotEmpty) {
        _queue.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
