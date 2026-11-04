import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/auth/cloudflare_access.dart';
import '../../data/api/api_client.dart';

import '../../design/appearance.dart';
import '../../design/widgets.dart';
import 'widgets/auth_widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onAuthenticated,
    this.onPrepare,
    this.onSignIn,
    this.initialUrl = '',
    this.connectionError,
  });
  final VoidCallback onAuthenticated;
  final Future<bool> Function(String url)? onPrepare;
  final Future<void> Function(String username, String password)? onSignIn;
  final String initialUrl;
  final String? connectionError;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _hidePassword = true;
  bool _ready = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url.text = widget.initialUrl;
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _connecting = true;
    });
    try {
      if (!_ready) {
        final entered = await widget.onPrepare?.call(_url.text) ?? false;
        if (mounted && !entered) {
          if (_url.text.trim().isNotEmpty) {
            _url.text = MukaiApiClient.normalizeServerUrl(_url.text);
          }
          setState(() => _ready = true);
        }
      } else {
        if (widget.onSignIn == null) {
          widget.onAuthenticated();
        } else {
          if (_username.text.trim().isEmpty || _password.text.isEmpty) {
            setState(() => _error = 'Enter your Mukai username and password.');
            return;
          }
          await widget.onSignIn!(_username.text, _password.text);
        }
        TextInput.finishAutofillContext();
        _password.clear();
        Haptics.success();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colors.accentSoft.withValues(alpha: .55),
              colors.canvas,
              colors.canvas,
            ],
            stops: const <double>[0, .55, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 64).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const FloatingGhost(size: 96),
                          const SizedBox(height: 20),
                          Text.rich(
                            TextSpan(
                              text: 'mukai',
                              children: <InlineSpan>[
                                TextSpan(
                                  text: '.',
                                  style: TextStyle(color: colors.accentColor),
                                ),
                              ],
                            ),
                            style: text.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 26),
                          Text(
                            _ready
                                ? 'Welcome home.'
                                : 'A little possibility.\nA little Mukai.',
                            textAlign: TextAlign.center,
                            style: text.displayLarge?.copyWith(
                              fontSize: 34,
                              height: 1.13,
                              letterSpacing: -1.3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _ready
                                ? 'Sign in with your Mukai account.'
                                : 'Your ideas. Your companions.\nA little momentum, every day.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (_ready)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: TextButton.icon(
                                onPressed: _connecting
                                    ? null
                                    : () => setState(() {
                                        _ready = false;
                                        _error = null;
                                        _password.clear();
                                      }),
                                icon: const Icon(Icons.link_rounded, size: 16),
                                label: Text(
                                  _url.text.isEmpty
                                      ? 'Change server'
                                      : _url.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          AutofillGroup(
                            child: Container(
                              decoration: BoxDecoration(
                                color: colors.card,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colors.hairlineStrong,
                                ),
                              ),
                              child: Column(
                                children: [
                                  if (!_ready)
                                    _ConnectionField(
                                      label: 'Server URL',
                                      hint: 'https://mukai.example.com',
                                      controller: _url,
                                      icon: Icons.link_rounded,
                                      keyboardType: TextInputType.url,
                                      enabled: !_connecting,
                                      onSubmitted: (_) => _connect(),
                                    )
                                  else ...[
                                    _ConnectionField(
                                      label: 'Username',
                                      hint: 'Your Mukai username',
                                      controller: _username,
                                      icon: Icons.person_outline_rounded,
                                      autofillHints: const [
                                        AutofillHints.username,
                                      ],
                                      enabled: !_connecting,
                                    ),
                                    Divider(
                                      height: 1,
                                      indent: 48,
                                      color: colors.hairline,
                                    ),
                                    _ConnectionField(
                                      label: 'Password',
                                      hint: 'Your Mukai password',
                                      controller: _password,
                                      icon: Icons.lock_outline_rounded,
                                      obscure: _hidePassword,
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      enabled: !_connecting,
                                      suffix: MukaiIconButton(
                                        icon: _hidePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        tooltip: _hidePassword
                                            ? 'Show password'
                                            : 'Hide password',
                                        border: false,
                                        onTap: () => setState(
                                          () => _hidePassword = !_hidePassword,
                                        ),
                                      ),
                                      onSubmitted: (_) => _connect(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_error != null ||
                              (!_ready && widget.connectionError != null))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                _error ?? widget.connectionError!,
                                style: text.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          MukaiButton(
                            label: _connecting
                                ? (_ready ? 'Signing in' : 'Connecting')
                                : (_ready ? 'Sign in' : 'Connect'),
                            busy: _connecting,
                            trailingIcon: Icons.arrow_forward_rounded,
                            expand: true,
                            onPressed: _connecting ? null : _connect,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _ready
                                ? 'Your password stays between you and your Mukai.'
                                : 'Connect to the Mukai you host.',
                            textAlign: TextAlign.center,
                            style: text.bodySmall,
                          ),
                          if (!_ready)
                            TextButton(
                              onPressed: _connecting
                                  ? null
                                  : () => showMukaiSheet<void>(
                                      context: context,
                                      builder: (_) =>
                                          const CloudflareHelpSheet(),
                                    ),
                              child: const Text('Using Cloudflare Zero Trust?'),
                            ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                Icons.home_outlined,
                                size: 15,
                                color: colors.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Your Mukai. Hosted by you.',
                                  textAlign: TextAlign.center,
                                  style: text.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ConnectionField extends StatelessWidget {
  const _ConnectionField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
  });
  final String label, hint;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19, color: colors.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: text.labelMedium?.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 5),
                TextField(
                  controller: controller,
                  enabled: enabled,
                  autofillHints: autofillHints,
                  keyboardType: keyboardType,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: onSubmitted == null
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onSubmitted: onSubmitted,
                  style: text.bodyMedium,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: text.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                    isDense: true,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 5),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          if (suffix != null) suffix! else const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class CloudflareHelpSheet extends StatelessWidget {
  const CloudflareHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MukaiColors.of(context);
    Future<void> open(String url) async {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link. Try again.')),
        );
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: .85,
      minChildSize: .35,
      maxChildSize: 1,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  const SheetGrabber(label: 'Cloudflare Zero Trust'),
                  Positioned(
                    right: 8,
                    top: 14,
                    child: MukaiIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Close Cloudflare help',
                      border: false,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 32,
                      color: colors.accentColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'One browser sign-in.\nThen you’re home.',
                      style: text.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mukai can open your Cloudflare sign-in automatically when your server supports Managed OAuth. Your Mukai username and password still sign you in to the app.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    Text('Set it up once', style: text.titleMedium),
                    const SizedBox(height: 12),
                    Text(
                      '1. Open Cloudflare Zero Trust and find the Access application that protects your Mukai server.\n\n2. In Advanced settings, enable Managed OAuth and Dynamic Client Registration.\n\n3. Add this exact allowed redirect URI:',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                      decoration: BoxDecoration(
                        color: colors.accentSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: SelectableText(
                              CloudflareAccess.redirectUri,
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          MukaiIconButton(
                            icon: Icons.copy_rounded,
                            tooltip: 'Copy callback URL',
                            border: false,
                            onTap: () async {
                              await Clipboard.setData(
                                const ClipboardData(
                                  text: CloudflareAccess.redirectUri,
                                ),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Callback URL copied'),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '4. Save your application settings. Return here, enter your server URL, and tap Connect. Cloudflare opens in your browser if sign-in is needed.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'If you only have the standard Cloudflare login page, ask your server administrator to enable Managed OAuth first.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    MukaiButton(
                      label: 'Open Cloudflare Zero Trust',
                      expand: true,
                      trailingIcon: Icons.open_in_new_rounded,
                      onPressed: () => open('https://one.dash.cloudflare.com/'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => open(
                        'https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/managed-oauth/',
                      ),
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('Read the setup guide'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
