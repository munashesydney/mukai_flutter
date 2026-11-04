import 'package:flutter/material.dart';
import '../../app/scope.dart';
import '../settings/notifications_sheet.dart';

import '../../design/widgets.dart';
import '../settings/appearance_sheet.dart';
import 'connected_widgets.dart';

class ConnectedSettingsScreen extends StatelessWidget {
  const ConnectedSettingsScreen({super.key, required this.onDisconnect});
  final VoidCallback onDisconnect;
  @override
  Widget build(BuildContext context) {
    final session = MukaiScope.sessionOf(context);
    return Column(
      children: <Widget>[
        const ConnectedHeading(
          'Settings',
          subtitle: 'Your device. Your shared workspace.',
        ),
        Expanded(
          child: ConnectedAsync(
            key: ValueKey('settings:${session.workspace.id}'),
            load: () async {
              final values = await Future.wait<dynamic>(<Future<dynamic>>[
                connectedRequest(context, '/settings/profile'),
                connectedRequest(
                  context,
                  '/approvals?${workspaceQuery(context)}',
                ),
                connectedRequest(context, '/providers'),
              ]);
              return <String, dynamic>{
                'profile': values[0],
                'approvals': values[1],
                'providers': values[2],
              };
            },
            builder: (context, data, reload) {
              final profile = object(object(data)['profile']);
              final approvals = object(object(data)['approvals']);
              final providers = objects(object(data)['providers']);
              final appearance = MukaiScope.appearanceOf(context);
              return RefreshIndicator.adaptive(
                onRefresh: reload,
                child: ListView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 24,
                  ),
                  children: <Widget>[
                    ConnectedSection(
                      'On this iPhone',
                      children: <Widget>[
                        MukaiRow(
                          title: 'Appearance',
                          subtitle:
                              '${appearance.preferences.theme.label} · ${appearance.preferences.mode.label}',
                          leading: const Icon(Icons.palette_outlined),
                          onTap: () => showMukaiSheet<void>(
                            context: context,
                            builder: (_) => const AppearanceSheet(),
                          ),
                        ),
                      ],
                    ),
                    if (MukaiScope.pushOf(context) case final push?)
                      ConnectedSection(
                        'Notifications',
                        children: [
                          MukaiRow(
                            title: 'Push notifications',
                            leading: const Icon(Icons.notifications_outlined),
                            onTap: () => showMukaiSheet<void>(
                              context: context,
                              builder: (_) => NotificationsSheet(push: push),
                            ),
                          ),
                        ],
                      ),
                    ConnectedSection(
                      'Synced with Mukai',
                      children: <Widget>[
                        MukaiRow(
                          title: 'Profile',
                          subtitle: profile['mode'] == 'letter'
                              ? words(profile['letter'])
                              : label(profile['icon']),
                          leading: const Icon(Icons.person_outline_rounded),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _ProfileEditor(profile: profile),
                              ),
                            );
                            if (context.mounted) await reload();
                          },
                        ),
                        const SoftDivider(indent: 48),
                        _ApprovalModeRow(
                          mode: words(approvals['mode']),
                          onChanged: reload,
                        ),
                      ],
                    ),
                    ConnectedSection(
                      'Providers',
                      children: <Widget>[
                        for (final provider in providers)
                          MukaiRow(
                            title:
                                '${words(provider['name'])}${provider['isDefault'] == true ? ' · Default' : ''}',
                            subtitle:
                                '${words(provider['defaultModel'])} · ${provider['hasKey'] == true || object(provider['account'])['connected'] == true ? 'Connected' : 'No key'}',
                            leading: const Icon(Icons.hub_outlined),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      _ProviderPage(provider: provider),
                                ),
                              );
                              if (context.mounted) await reload();
                            },
                          ),
                        MukaiRow(
                          title: 'Add provider',
                          subtitle:
                              'OpenAI, Anthropic, Google, or a compatible API',
                          leading: const Icon(Icons.add_rounded),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const _ProviderEditor(),
                              ),
                            );
                            if (context.mounted) await reload();
                          },
                        ),
                      ],
                    ),
                    ConnectedSection(
                      'Connection',
                      children: <Widget>[
                        MukaiRow(
                          title: session.workspace.name,
                          subtitle:
                              '${session.bots.length} companions · ${session.workspace.kind}',
                          leading: const Icon(Icons.folder_open_rounded),
                          showChevron: false,
                        ),
                        const SoftDivider(indent: 48),
                        MukaiRow(
                          title: 'Disconnect this iPhone',
                          subtitle:
                              'Remove the saved connection from this device',
                          leading: const Icon(Icons.logout_rounded),
                          onTap: () async {
                            if (await confirmRemoval(
                              context,
                              'Disconnect this iPhone?',
                              'You’ll need to sign in again to reconnect. Your workspace and conversations stay on your Mukai.',
                              confirmLabel: 'Disconnect',
                            )) {
                              if (context.mounted) onDisconnect();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ApprovalModeRow extends StatefulWidget {
  const _ApprovalModeRow({required this.mode, required this.onChanged});
  final String mode;
  final Future<void> Function() onChanged;
  @override
  State<_ApprovalModeRow> createState() => _ApprovalModeRowState();
}

class _ApprovalModeRowState extends State<_ApprovalModeRow> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    title: const Text('Request approvals'),
    subtitle: const Text('Shared workspace access mode'),
    value: widget.mode == 'ask-for-approval',
    onChanged: _busy
        ? null
        : (value) async {
            setState(() => _busy = true);
            try {
              await connectedRequest(
                context,
                '/approvals?${workspaceQuery(context)}',
                method: 'PUT',
                body: <String, dynamic>{
                  'mode': value ? 'ask-for-approval' : 'full-access',
                },
              );
              await widget.onChanged();
            } catch (error) {
              if (context.mounted) connectionNotice(context, error);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.profile});
  final JsonMap profile;
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late String _mode = words(widget.profile['mode'], 'icon');
  late String _icon = words(widget.profile['icon'], 'user');
  late final _letter = TextEditingController(
    text: words(widget.profile['letter'], 'U'),
  );
  late final _color = TextEditingController(
    text: words(widget.profile['background'], '#b28a66'),
  );
  bool _busy = false;
  @override
  void dispose() {
    _letter.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!RegExp(
          r'^[\p{L}\p{N}]{1,2}$',
          unicode: true,
        ).hasMatch(_letter.text.trim()) ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(_color.text.trim())) {
      connectionNotice(
        context,
        'Use one or two letters or numbers and a six-digit hex color.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await connectedRequest(
        context,
        '/settings/profile',
        method: 'PUT',
        body: <String, dynamic>{
          'mode': _mode,
          'letter': _letter.text.trim(),
          'icon': _icon,
          'background': _color.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) connectionNotice(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Avatar style'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'icon', child: Text('Icon')),
              DropdownMenuItem(value: 'letter', child: Text('Letter')),
            ],
            onChanged: (value) => setState(() => _mode = value ?? 'icon'),
          ),
          const SizedBox(height: 20),
          if (_mode == 'letter')
            TextField(
              controller: _letter,
              decoration: const InputDecoration(labelText: 'Initials'),
              maxLength: 2,
              textCapitalization: TextCapitalization.characters,
            )
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _icon,
              decoration: const InputDecoration(labelText: 'Icon'),
              items:
                  <String>[
                        'user',
                        'sparkles',
                        'rocket',
                        'cat',
                        'ghost',
                        'leaf',
                        'coffee',
                        'music',
                        'gamepad',
                        'star',
                        'sun',
                        'smile',
                      ]
                      .map(
                        (icon) => DropdownMenuItem(
                          value: icon,
                          child: Text(label(icon)),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _icon = value ?? 'user'),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _color,
            decoration: const InputDecoration(
              labelText: 'Background color',
              hintText: '#b28a66',
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 28),
          MukaiButton(
            label: 'Save profile',
            busy: _busy,
            onPressed: _save,
            expand: true,
          ),
        ],
      ),
    ),
  );
}

class _ProviderPage extends StatelessWidget {
  const _ProviderPage({required this.provider});
  final JsonMap provider;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(words(provider['name'], 'Provider'))),
    body: ConnectedAsync(
      load: () async {
        final list = objects(await connectedRequest(context, '/providers'));
        return list.firstWhere(
          (item) => item['id'] == provider['id'],
          orElse: () => provider,
        );
      },
      builder: (context, data, reload) {
        final value = object(data);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              words(value['name']),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${label(value['kind'])}${value['isDefault'] == true ? ' · Workspace default' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            const Eyebrow('Default model'),
            const SizedBox(height: 8),
            Text(words(value['defaultModel'])),
            const SizedBox(height: 20),
            const Eyebrow('Endpoint'),
            const SizedBox(height: 8),
            SelectableText(words(value['baseUrl'])),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                ConnectedAction(
                  label: 'Test connection',
                  action: () async {
                    final result = object(
                      await connectedRequest(
                        context,
                        '/providers/${encoded(value['id'])}/test',
                        method: 'POST',
                      ),
                    );
                    if (context.mounted) {
                      connectionNotice(
                        context,
                        words(
                          result['message'],
                          result['ok'] == true
                              ? 'Connected'
                              : 'Connection failed',
                        ),
                      );
                    }
                  },
                ),
                ConnectedAction(
                  label: 'Edit provider',
                  tonal: true,
                  action: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _ProviderEditor(provider: value),
                      ),
                    );
                    if (context.mounted) await reload();
                  },
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Eyebrow('Saved models'),
            const SizedBox(height: 12),
            for (final model in objects(value['models']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(words(model['name'], words(model['id']))),
                subtitle: Text(words(model['id'])),
                trailing: model['id'] == value['defaultModel']
                    ? const Icon(Icons.check_circle_outline_rounded)
                    : null,
                onTap: model['id'] == value['defaultModel']
                    ? null
                    : () async {
                        try {
                          await connectedRequest(
                            context,
                            '/providers/${encoded(value['id'])}/models',
                            method: 'PUT',
                            body: <String, dynamic>{
                              'models': value['models'],
                              'defaultModel': model['id'],
                            },
                          );
                          if (context.mounted) await reload();
                        } catch (error) {
                          if (context.mounted) {
                            connectionNotice(context, error);
                          }
                        }
                      },
              ),
            const SizedBox(height: 28),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete provider'),
              onPressed: () async {
                if (!await confirmRemoval(
                  context,
                  'Delete this provider?',
                  'Bots using this provider may need a different model before they can reply.',
                )) {
                  return;
                }
                if (!context.mounted) return;
                try {
                  await connectedRequest(
                    context,
                    '/providers/${encoded(value['id'])}',
                    method: 'DELETE',
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (context.mounted) connectionNotice(context, error);
                }
              },
            ),
          ],
        );
      },
    ),
  );
}

class _ProviderEditor extends StatefulWidget {
  const _ProviderEditor({this.provider});
  final JsonMap? provider;
  @override
  State<_ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<_ProviderEditor> {
  late final _name = TextEditingController(
    text: words(widget.provider?['name']),
  );
  late final _url = TextEditingController(
    text: words(widget.provider?['baseUrl']),
  );
  late final _model = TextEditingController(
    text: words(widget.provider?['defaultModel']),
  );
  final _key = TextEditingController();
  late String _kind = words(widget.provider?['kind'], 'openai');
  late bool _images = widget.provider?['supportsImages'] == true;
  late bool _default = widget.provider?['isDefault'] == true;
  bool _clearKey = false, _busy = false, _showKey = false;
  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty || _model.text.trim().isEmpty) {
      connectionNotice(context, 'A name and default model are required.');
      return;
    }
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        !<String>['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      connectionNotice(context, 'Enter the provider’s full HTTP or HTTPS URL.');
      return;
    }
    setState(() => _busy = true);
    final existing = widget.provider;
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'kind': _kind,
      'baseUrl': _url.text.trim(),
      'defaultModel': _model.text.trim(),
      'supportsImages': _images,
      'isDefault': _default,
      if (existing?['models'] != null) 'models': existing!['models'],
      if (existing?['contextWindowTokens'] != null)
        'contextWindowTokens': existing!['contextWindowTokens'],
      if (existing?['maxOutputTokens'] != null)
        'maxOutputTokens': existing!['maxOutputTokens'],
      if (existing?['supportsAudio'] != null)
        'supportsAudio': existing!['supportsAudio'],
      if (existing?['supportsVideo'] != null)
        'supportsVideo': existing!['supportsVideo'],
      if (_key.text.isNotEmpty) 'apiKey': _key.text,
      if (_clearKey) 'clearKey': true,
    };
    try {
      await connectedRequest(
        context,
        existing == null
            ? '/providers'
            : '/providers/${encoded(existing['id'])}',
        method: existing == null ? 'POST' : 'PUT',
        body: payload,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) connectionNotice(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.provider == null ? 'Add provider' : 'Edit provider'),
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Provider'),
            items:
                <String>[
                      'openai',
                      'anthropic',
                      'google',
                      'compatible',
                      if (_kind == 'chatgpt') 'chatgpt',
                    ]
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(
                          kind == 'compatible'
                              ? 'OpenAI-compatible'
                              : kind == 'chatgpt'
                              ? 'ChatGPT'
                              : kind,
                        ),
                      ),
                    )
                    .toList(),
            onChanged: widget.provider == null
                ? (value) => setState(() => _kind = value ?? 'openai')
                : null,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: 'Base URL'),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _model,
            decoration: const InputDecoration(labelText: 'Default model'),
            autocorrect: false,
          ),
          if (_kind != 'chatgpt') ...<Widget>[
            const SizedBox(height: 20),
            TextField(
              controller: _key,
              decoration: InputDecoration(
                labelText: widget.provider?['hasKey'] == true
                    ? 'Replace API key (optional)'
                    : 'API key',
                suffixIcon: IconButton(
                  icon: Icon(
                    _showKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  tooltip: _showKey ? 'Hide API key' : 'Show API key',
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
            ),
            if (widget.provider?['hasKey'] == true)
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remove saved key'),
                value: _clearKey,
                onChanged: (value) =>
                    setState(() => _clearKey = value ?? false),
              ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Manage ChatGPT account sign-in from the Mukai desktop app.',
              ),
            ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Image support'),
            value: _images,
            onChanged: (value) => setState(() => _images = value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Workspace default'),
            value: _default,
            onChanged: (value) => setState(() => _default = value),
          ),
          const SizedBox(height: 24),
          MukaiButton(
            label: 'Save provider',
            expand: true,
            busy: _busy,
            onPressed: _save,
          ),
        ],
      ),
    ),
  );
}
