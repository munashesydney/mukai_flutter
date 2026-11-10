import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../core/workspace_time.dart';
import '../../design/appearance.dart';
import '../../design/glass.dart';
import '../../design/widgets.dart';

typedef JsonMap = Map<String, dynamic>;
JsonMap object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<JsonMap> objects(dynamic value) =>
    value is List ? value.map(object).toList() : <JsonMap>[];
String words(dynamic value, [String fallback = '']) =>
    value == null ? fallback : value.toString();
String label(dynamic value) => words(value).replaceAll('_', ' ');
String dateLabel(BuildContext context, dynamic value) {
  final instant = DateTime.tryParse(words(value));
  if (instant == null) return 'Not scheduled';
  final date = WorkspaceTime.local(
    instant,
    MukaiScope.sessionOf(context).workspace.timeZone,
  );
  return '${date.month}/${date.day}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

Future<dynamic> connectedRequest(
  BuildContext context,
  String path, {
  String method = 'GET',
  Object? body,
}) {
  final api = MukaiScope.sessionOf(context).api;
  if (api == null) throw StateError('Connect to your Mukai to continue.');
  return api.request(path, method: method, body: body);
}

String workspaceQuery(BuildContext context) =>
    'workspaceId=${Uri.encodeComponent(MukaiScope.sessionOf(context).workspace.id)}';
String encoded(dynamic value) => Uri.encodeComponent(words(value));

Future<bool> confirmRemoval(
  BuildContext context,
  String title,
  String description, {
  String confirmLabel = 'Delete',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

void connectionNotice(BuildContext context, Object message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message.toString())));
}

/// Loads server state again after refresh or returning from the background.
class ConnectedAsync extends StatefulWidget {
  const ConnectedAsync({
    super.key,
    required this.load,
    required this.builder,
    this.refreshInterval,
  });
  final Duration? refreshInterval;
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext, dynamic, Future<void> Function()) builder;
  @override
  State<ConnectedAsync> createState() => _ConnectedAsyncState();
}

class _ConnectedAsyncState extends State<ConnectedAsync>
    with WidgetsBindingObserver {
  dynamic _data;
  String? _snapshot;
  Object? _error;
  bool _loading = true;
  bool _started = false;
  int _version = 0;
  Timer? _timer;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.refreshInterval != null) {
      _timer = Timer.periodic(widget.refreshInterval!, (_) {
        if (mounted &&
            !_loading &&
            _foreground &&
            (ModalRoute.of(context)?.isCurrent ?? true) &&
            TickerMode.valuesOf(context).enabled) {
          _reload(background: true);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _reload();
    }
  }

  @override
  void dispose() {
    _version++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && !_loading) {
      _reload(background: true);
    }
  }

  Future<void> _reload({bool background = false}) async {
    final version = ++_version;
    final initial = _data == null;
    _loading = true;
    if (initial) setState(() => _error = null);
    try {
      final data = await widget.load();
      if (!mounted || version != _version) return;
      final snapshot = jsonEncode(data);
      if (!background || snapshot != _snapshot || _error != null) {
        setState(() {
          _data = data;
          _snapshot = snapshot;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && version == _version && (!background || initial)) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && version == _version) {
        _loading = false;
        if (initial) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_outlined, size: 36),
              const SizedBox(height: 16),
              Text(
                words(_error, 'No data returned.'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              MukaiButton(label: 'Try again', onPressed: _reload),
            ],
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: MukaiErrorBanner(
              message: _error.toString(),
              onRetry: _reload,
            ),
          ),
        Expanded(child: widget.builder(context, _data, _reload)),
      ],
    );
  }
}

class ConnectedAction extends StatefulWidget {
  const ConnectedAction({
    super.key,
    required this.label,
    required this.action,
    this.icon,
    this.tonal = false,
  });
  final String label;
  final Future<void> Function()? action;
  final IconData? icon;
  final bool tonal;
  @override
  State<ConnectedAction> createState() => _ConnectedActionState();
}

class _ConnectedActionState extends State<ConnectedAction> {
  bool _busy = false;
  Future<void> _act() async {
    if (_busy || widget.action == null) return;
    setState(() => _busy = true);
    try {
      await widget.action!();
    } catch (error) {
      if (mounted) connectionNotice(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MukaiButton(
    label: widget.label,
    icon: widget.icon,
    compact: true,
    busy: _busy,
    variant: widget.tonal
        ? MukaiButtonVariant.tonal
        : MukaiButtonVariant.filled,
    onPressed: widget.action == null ? null : _act,
  );
}

class ConnectedHeading extends StatelessWidget {
  const ConnectedHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class ConnectedEmpty extends StatelessWidget {
  const ConnectedEmpty({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
  });
  final String title, body;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: MukaiColors.of(context).accentInk),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

class ConnectedSection extends StatelessWidget {
  const ConnectedSection(this.title, {super.key, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Eyebrow(title),
        ),
        MukaiCard(
          elevated: false,
          padding: EdgeInsets.zero,
          child: Column(
            children: children
                .map(
                  (child) => Material(color: Colors.transparent, child: child),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );
}

class ConnectedDocument extends StatelessWidget {
  const ConnectedDocument({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
  });
  final String title, body;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), leading: const MukaiGlassBackButton()),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (subtitle != null) ...<Widget>[
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),
            ],
            SelectableText(body, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    ),
  );
}
