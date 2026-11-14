/// The minimalist home: the chat itself, and nothing else. The companion and
/// workspace are switched from quiet picker rows just above the composer,
/// and the sidebar opens from the chat header like anywhere else in the app.
library;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../design/appearance.dart';
import '../../design/theme.dart';
import '../../design/widgets.dart';
import '../../domain/models.dart';
import '../chat/chat_screen.dart';

class MinimalChatHome extends StatefulWidget {
  const MinimalChatHome({
    super.key,
    required this.onOpenSidebar,
    this.onSwitchWorkspace,
  });

  final VoidCallback onOpenSidebar;
  final VoidCallback? onSwitchWorkspace;

  @override
  State<MinimalChatHome> createState() => _MinimalChatHomeState();
}

class _MinimalChatHomeState extends State<MinimalChatHome> {
  /// The companion picked on this home; `null` follows the session's own.
  String? _botId;

  @override
  Widget build(BuildContext context) {
    final session = MukaiScope.sessionOf(context);
    return ListenableBuilder(
      listenable: session,
      builder: (BuildContext context, Widget? _) {
        MukaiBot bot = session.bot;
        if (_botId != null) {
          for (final MukaiBot candidate in session.bots) {
            if (candidate.id == _botId) {
              bot = candidate;
              break;
            }
          }
        }
        return ChatScreen(
          // Remount per workspace/companion so the chat opens fresh.
          key: ValueKey('${session.workspace.id}:${bot.id}'),
          bot: bot,
          fresh: true,
          onMenu: widget.onOpenSidebar,
          slotAboveComposer: _Pickers(
            bot: bot,
            bots: session.bots,
            workspaceName: session.workspace.name,
            onSelectBot: (String id) => setState(() => _botId = id),
            onSwitchWorkspace: widget.onSwitchWorkspace,
          ),
        );
      },
    );
  }
}

class _Pickers extends StatefulWidget {
  const _Pickers({
    required this.bot,
    required this.bots,
    required this.workspaceName,
    required this.onSelectBot,
    required this.onSwitchWorkspace,
  });

  final MukaiBot bot;
  final List<MukaiBot> bots;
  final String workspaceName;
  final ValueChanged<String> onSelectBot;
  final VoidCallback? onSwitchWorkspace;

  @override
  State<_Pickers> createState() => _PickersState();
}

class _PickersState extends State<_Pickers> {
  bool _botMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final MukaiBot bot = widget.bot;
    const label = TextStyle(fontSize: 12.5, color: null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                MukaiGlassMenuButton(
              tooltip: 'Choose a companion',
              up: true,
              // Cover the row that was tapped: the panel matches its width and
              // pins to its leading edge, like the composer's pickers.
              alignStart: true,
              expandWidth: true,
              width: constraints.maxWidth,
              size: 30,
              onOpenChanged: (open) {
                if (mounted) setState(() => _botMenuOpen = open);
              },
              icon: IgnorePointer(
                ignoring: _botMenuOpen,
                // The panel unfurls over the row, so the row steps aside.
                child: AnimatedScale(
                  scale: _botMenuOpen ? .8 : 1,
                  duration: MukaiMotion.fast,
                  curve: MukaiMotion.curve,
                  child: AnimatedOpacity(
                    opacity: _botMenuOpen ? 0 : 1,
                    duration: MukaiMotion.fast,
                    curve: MukaiMotion.curve,
                    child: Row(
                      children: [
                        GhostAvatar(
                          mascot: bot.mascot,
                          identity: bot.identity,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            bot.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: label.copyWith(color: colors.textMuted),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.swap_vert_rounded,
                          size: 15,
                          color: colors.textMuted,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
              items: [
                for (final candidate in widget.bots)
                  MukaiGlassMenuItem(
                    label: candidate.name,
                    leading: GhostAvatar(
                      mascot: candidate.mascot,
                      identity: candidate.identity,
                      size: 22,
                    ),
                    selected: candidate.id == bot.id,
                    onTap: () => widget.onSelectBot(candidate.id),
                  ),
              ],
            ),
          ),
          PressableScale(
            onTap: widget.onSwitchWorkspace,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 15,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.workspaceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: label.copyWith(color: colors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.swap_vert_rounded,
                    size: 15,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
