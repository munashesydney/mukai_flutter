import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/scope.dart';
import '../../../core/response_reference.dart';
import '../../../data/api/api_client.dart';
import '../../../design/appearance.dart';
import '../../../design/widgets.dart';
import 'open_content.dart';
import 'preview_source.dart';

bool _isImage(DownloadedContent content) {
  final bytes = content.bytes;
  return content.mediaType.startsWith('image/') ||
      RegExp(
        r'\.(png|jpe?g|gif|webp|bmp|heic|avif)$',
        caseSensitive: false,
      ).hasMatch(content.name) ||
      (bytes.length > 8 &&
          (bytes[0] == 0x89 && bytes[1] == 0x50 ||
              bytes[0] == 0xff && bytes[1] == 0xd8 ||
              ascii.decode(bytes.take(3).toList(), allowInvalid: true) ==
                  'GIF'));
}

bool _isText(DownloadedContent content) =>
    content.mediaType.startsWith('text/') ||
    RegExp(r'(json|xml|javascript|yaml)').hasMatch(content.mediaType) ||
    RegExp(
      r'\.(md|txt|json|csv|log|yaml|yml|xml|html|css|js|ts|tsx|jsx|py|sh|toml|rs|swift|dart|sql|svg)$',
      caseSensitive: false,
    ).hasMatch(content.name);

class FilePreviewPage extends StatefulWidget {
  const FilePreviewPage({super.key, required this.source, this.initialContent});
  final PreviewSource source;
  final DownloadedContent? initialContent;
  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  DownloadedContent? _content;
  String? _error;
  bool _loading = true, _nativeBusy = false;
  int _generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_generation == 0) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = MukaiScope.sessionOf(context).api;
      if (api == null && widget.initialContent == null) {
        throw Exception('Connect to Mukai to preview this file.');
      }
      final content =
          widget.initialContent ??
          await PreviewLoader.forApi(api!).load(widget.source);
      if (!mounted || generation != _generation) return;
      setState(() {
        _content = content;
        _loading = false;
      });
      if (!_isImage(content) &&
          !_isText(content) &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openNative();
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openNative() async {
    if (_nativeBusy || _content == null) return;
    setState(() => _nativeBusy = true);
    try {
      await const MethodChannel('com.mukai.mobile/preview').invokeMethod<void>(
        'open',
        {'bytes': _content!.bytes, 'name': _content!.name},
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'This format could not be previewed here. Use Share to open it in another app.',
        );
      }
    } finally {
      if (mounted) setState(() => _nativeBusy = false);
    }
  }

  Future<void> _share() async {
    final content = _content;
    if (content == null) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            content.bytes,
            name: content.name,
            mimeType: content.mediaType,
          ),
        ],
        fileNameOverrides: [content.name],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final colors = MukaiColors.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close preview',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          content?.name ?? widget.source.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Share file',
            onPressed: content == null ? null : _share,
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator.adaptive())
            : _error != null && content == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      MukaiButton(label: 'Try again', onPressed: _load),
                    ],
                  ),
                ),
              )
            : content == null
            ? const SizedBox.shrink()
            : _isImage(content)
            ? InteractiveViewer(
                minScale: .5,
                maxScale: 6,
                child: Center(
                  child: Image.memory(
                    content.bytes,
                    fit: BoxFit.contain,
                    cacheWidth: 2560,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'This image could not be displayed. Use Share to open the original.',
                      ),
                    ),
                  ),
                ),
              )
            : _isText(content)
            ? _TextPreview(
                content: content,
                line: parseResponseReference(widget.source.href)?.line,
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 44,
                        color: colors.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error ??
                            'Preview this file with the iPhone’s native viewer.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (defaultTargetPlatform == TargetPlatform.iOS)
                        MukaiButton(
                          label: 'Open preview',
                          busy: _nativeBusy,
                          onPressed: _nativeBusy ? null : _openNative,
                        ),
                      TextButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Share or save original'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.content, this.line});
  final DownloadedContent content;
  final int? line;
  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  late final _text = utf8.decode(
    widget.content.bytes.take(512 * 1024).toList(),
    allowMalformed: true,
  );
  late final _lines = _text.split('\n');
  late final _scroll = ScrollController(
    initialScrollOffset:
        (math.min(widget.line ?? 1, _lines.length) - 1).clamp(
          0,
          _lines.length,
        ) *
        22.0,
  );
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    return Column(
      children: [
        if (widget.content.bytes.length > 512 * 1024)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Showing the first 512 KB. Share the original for the full file.',
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(
                  constraints.maxWidth,
                  math.min(
                    16000,
                    _lines.fold<int>(
                              0,
                              (max, line) => math.max(max, line.length),
                            ) *
                            7.8 +
                        80,
                  ),
                ),
                height: constraints.maxHeight,
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    itemExtent: 22,
                    itemCount: _lines.length,
                    itemBuilder: (_, index) => ColoredBox(
                      color: widget.line == index + 1
                          ? colors.accentSoft
                          : Colors.transparent,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 54,
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: 'Menlo',
                                fontSize: 11,
                                color: colors.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _lines[index],
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                fontFamily: 'Menlo',
                                fontSize: 12,
                                height: 1.6,
                                color: colors.textBody,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline authenticated image. Loading begins only once its transcript is built.
class ChatImagePreview extends StatefulWidget {
  const ChatImagePreview({super.key, required this.href, this.name = 'Image'});
  final String href, name;
  @override
  State<ChatImagePreview> createState() => _ChatImagePreviewState();
}

class _ChatImagePreviewState extends State<ChatImagePreview> {
  Future<DownloadedContent>? _load;
  PreviewSource? _source;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = previewSource(
      context,
      widget.href,
      name: widget.name,
      image: true,
    );
    if (source.key != _source?.key) {
      _source = source;
      final api = MukaiScope.sessionOf(context).api;
      _load = api == null
          ? Future.error(Exception('Connect to preview this image.'))
          : PreviewLoader.forApi(api).load(source);
    }
  }

  @override
  void didUpdateWidget(covariant ChatImagePreview old) {
    super.didUpdateWidget(old);
    if (old.href != widget.href) {
      _source = null;
      didChangeDependencies();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DownloadedContent>(
    future: _load,
    builder: (context, snapshot) {
      final content = snapshot.data;
      return Semantics(
        button: true,
        label: 'View image: ${widget.name}',
        child: InkWell(
          onTap: () => openChatContent(
            context,
            widget.href,
            name: widget.name,
            image: true,
            initialContent: content,
          ),
          borderRadius: BorderRadius.circular(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: content != null
                ? ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                      maxHeight: 220,
                    ),
                    child: Image.memory(
                      content.bytes,
                      fit: BoxFit.contain,
                      cacheWidth: 1000,
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('View image'),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.image_outlined, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            snapshot.hasError
                                ? 'Open ${widget.name}'
                                : 'Loading ${widget.name}…',
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
