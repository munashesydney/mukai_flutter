/// Settings — the mobile read of the desktop settings window.
///
/// iOS grouped-list grammar: cards of chevron rows, section labels above,
/// hairline insets. Rows that do something real (Appearance) are wired; rows
/// that describe backend state are honest placeholders with the real copy.
library;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../design/appearance.dart';
import '../../design/theme.dart';
import '../../design/widgets.dart';
import 'appearance_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _approvals = true;
  bool _notifications = true;
  bool _checkOnLaunch = true;

  Future<void> _openAppearance() => showMukaiSheet<void>(
    context: context,
    builder: (BuildContext _) => const AppearanceSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final AppearanceController appearance = MukaiScope.appearanceOf(context);
    final session = MukaiScope.sessionOf(context);
    final MukaiThemeDefinition theme = mukaiThemeOf(
      appearance.preferences.theme,
    );

    return ListenableBuilder(
      listenable: appearance,
      builder: (BuildContext context, Widget? _) {
        return CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text('Settings', style: text.headlineMedium),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                MukaiSpace.screen,
                0,
                MukaiSpace.screen,
                MukaiSpace.xxxl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  _Group(
                    label: 'Appearance',
                    children: <Widget>[
                      MukaiRow(
                        title: 'Theme',
                        subtitle: theme.description,
                        leading: _ThemeDot(
                          palette: theme.palette(colors.brightness),
                        ),
                        trailing: Text(
                          '${theme.label} · ${appearance.preferences.mode.label}',
                          style: text.bodySmall?.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        onTap: _openAppearance,
                      ),
                      const SoftDivider(indent: 52),
                      MukaiRow(
                        title: 'Match the system',
                        subtitle: 'Follow iOS light and dark automatically',
                        leading: Icon(
                          Icons.brightness_auto_outlined,
                          size: 19,
                          color: colors.accentInk,
                        ),
                        showChevron: false,
                        trailing: Switch(
                          value:
                              appearance.preferences.mode == ColorMode.system,
                          onChanged: (bool value) => appearance.setMode(
                            value ? ColorMode.system : ColorMode.light,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Group(
                    label: 'Workspace',
                    children: <Widget>[
                      MukaiRow(
                        title: session.workspace.name,
                        subtitle: session.workspace.kind,
                        leading: Icon(
                          Icons.folder_rounded,
                          size: 19,
                          color: colors.accentInk,
                        ),
                        trailing: Text(
                          '${session.bots.length} bots',
                          style: text.bodySmall?.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        onTap: Haptics.select,
                      ),
                      const SoftDivider(indent: 52),
                      MukaiRow(
                        title: 'Bot Hierarchy',
                        subtitle: 'Who reports to whom',
                        leading: Icon(
                          Icons.account_tree_outlined,
                          size: 19,
                          color: colors.accentInk,
                        ),
                        onTap: Haptics.select,
                      ),
                      const SoftDivider(indent: 52),
                      MukaiRow(
                        title: 'Shared backend',
                        subtitle: '127.0.0.1:47831',
                        leading: Icon(
                          Icons.dns_outlined,
                          size: 19,
                          color: colors.accentInk,
                        ),
                        onTap: Haptics.select,
                      ),
                    ],
                  ),
                  _Group(
                    label: 'Access',
                    children: <Widget>[
                      MukaiRow(
                        title: 'Request approvals',
                        subtitle: 'Pause before a bot changes a file',
                        leading: Icon(
                          Icons.verified_user_outlined,
                          size: 19,
                          color: colors.accentInk,
                        ),
                        showChevron: false,
                        trailing: Switch(
                          value: _approvals,
                          onChanged: (bool value) {
                            Haptics.select();
                            setState(() => _approvals = value);
                          },
                        ),
                      ),
                      const SoftDivider(indent: 52),
                      MukaiRow(
                        title: 'Providers',
                        subtitle: 'Set up a provider to send messages',
                        leading: Icon(
                          Icons.hub_outlined,
                          size: 19,
                          color: colors.accentInk,
                        ),
                        onTap: Haptics.select,
                      ),
                    ],
                  ),
                  _Group(
                    label: 'Device',
                    children: <Widget>[
                      MukaiRow(
                        title: 'Notifications',
                        subtitle: 'Pursuits, failures and updates',
                        leading: Icon(
                          Icons.notifications_none_rounded,
                          size: 19,
                          color: colors.accentInk,
                        ),
                        showChevron: false,
                        trailing: Switch(
                          value: _notifications,
                          onChanged: (bool value) {
                            Haptics.select();
                            setState(() => _notifications = value);
                          },
                        ),
                      ),
                      const SoftDivider(indent: 52),
                      MukaiRow(
                        title: 'Check for updates',
                        subtitle: 'Ask the local server on launch',
                        leading: Icon(
                          Icons.system_update_alt_rounded,
                          size: 19,
                          color: colors.accentInk,
                        ),
                        showChevron: false,
                        trailing: Switch(
                          value: _checkOnLaunch,
                          onChanged: (bool value) {
                            Haptics.select();
                            setState(() => _checkOnLaunch = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MukaiSpace.xl),
                  const _About(),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Section label + a grouped card of rows.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final MukaiColors colors = MukaiColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: MukaiSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: MukaiSpace.sm),
            child: Text(
              label.toUpperCase(),
              style: text.labelSmall?.copyWith(color: colors.textMuted),
            ),
          ),
          MukaiCard(
            padding: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({required this.palette});
  final AccentPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[palette.accent, palette.glow],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.border),
      ),
    );
  }
}

/// Version block plus the Shona footnote — the app's own sign-off.
class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Center(
          child: Column(
            children: <Widget>[
              const MukaiWordmark(size: 22),
              const SizedBox(height: MukaiSpace.sm),
              Text(
                'UI preview · demo data · v0.1.0',
                style: text.bodySmall?.copyWith(color: colors.textSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: MukaiSpace.lg),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.translate_rounded, size: 13, color: colors.textSoft),
              const SizedBox(width: 6),
              Text(
                'Mukai means “wake up” in Shona.',
                style: text.bodySmall?.copyWith(color: colors.textSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
