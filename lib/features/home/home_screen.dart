/// The workspace landing: a quiet canvas, expressive companions, real recents.
library;

import 'package:flutter/material.dart';
import '../../app/scope.dart';
import '../../design/appearance.dart';
import '../../design/widgets.dart';
import '../../domain/models.dart';
import '../settings/appearance_sheet.dart';
import 'widgets/bot_tile.dart';
import 'widgets/workspace_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenBot,
    required this.onOpenSettings,
    required this.onOpenConversation,
    this.onSwitchWorkspace,
  });
  final ValueChanged<MukaiBot> onOpenBot;
  final VoidCallback? onSwitchWorkspace;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final text = Theme.of(context).textTheme;
    final session = MukaiScope.sessionOf(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final bots = session.bots;
        return RefreshIndicator.adaptive(
          onRefresh: session.loadRecents,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 16, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        session.workspace.name,
                        style: text.labelMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    MukaiIconButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Appearance',
                      border: false,
                      onTap: () => showMukaiSheet<void>(
                        context: context,
                        builder: (_) => const AppearanceSheet(),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'A little momentum.',
                      style: text.displayLarge?.copyWith(
                        fontSize: 32,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'What shall we make possible today?',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SystemStatusPill(
                        label: session.api == null
                            ? 'All systems calm'
                            : session.hasError
                            ? 'Connection needs attention'
                            : 'Connected to Mukai',
                      ),
                    ),
                    Text('${bots.length} companions', style: text.bodySmall),
                  ],
                ),
              ),
              if (session.hasError)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: MukaiErrorBanner(
                    message: session.error!,
                    onRetry: session.loadRecents,
                  ),
                ),
              if (bots.isNotEmpty) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: _LeadCompanion(
                    bot: bots.first,
                    onTap: () => onOpenBot(bots.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int i = 1; i < bots.length; i++) ...<Widget>[
                        if (i > 1) const SizedBox(width: 12),
                        Expanded(
                          child: _CompanionCard(
                            bot: bots[i],
                            onTap: () => onOpenBot(bots[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Your companions will appear here when you add them to your workspace.',
                    style: text.bodyLarge,
                  ),
                ),
              const SectionHeader(
                label: 'Pick up where you left off',
                padding: EdgeInsets.fromLTRB(24, 30, 24, 10),
              ),
              if (session.recents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Text(
                    'A fresh start. Say hello to a companion above.',
                    style: text.bodySmall,
                  ),
                ),
              for (final conversation in session.recents)
                if (bots.any((bot) => bot.id == conversation.botId))
                  ConversationTile(
                    conversation: conversation,
                    bot: bots.firstWhere((bot) => bot.id == conversation.botId),
                    onTap: () => onOpenConversation(conversation),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: PressableScale(
                  onTap:
                      onSwitchWorkspace ??
                      () => showMukaiSheet<void>(
                        context: context,
                        builder: (_) => WorkspaceSheet(
                          current: session.workspace,
                          others: const [],
                          onSelect: (_) {},
                          onCreate: () {},
                        ),
                      ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.folder_open_rounded,
                        size: 17,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          session.workspace.name,
                          style: text.bodySmall,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: colors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LeadCompanion extends StatelessWidget {
  const _LeadCompanion({required this.bot, required this.onTap});
  final MukaiBot bot;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final text = Theme.of(context).textTheme;
    return MukaiCard(
      onTap: onTap,
      elevated: false,
      radius: 26,
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color.lerp(colors.card, colors.accentSoft, colors.isDark ? 1 : .30)!,
          colors.card,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GhostAvatar(
                mascot: bot.mascot,
                identity: bot.identity,
                size: 62,
                presence: bot.running,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(bot.name, style: text.headlineSmall),
                    const SizedBox(height: 3),
                    Text('Your everyday orchestrator', style: text.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.north_east_rounded, size: 20, color: colors.accentInk),
            ],
          ),
          const SizedBox(height: 18),
          Text('A thought, a plan, a place to start.', style: text.titleMedium),
          const SizedBox(height: 5),
          Text(
            'Bring it to ${bot.name}. Work it out together.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Start a conversation',
                  style: text.labelLarge?.copyWith(color: colors.accentInk),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: colors.accentInk,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({required this.bot, required this.onTap});
  final MukaiBot bot;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MukaiCard(
      onTap: onTap,
      elevated: false,
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GhostAvatar(mascot: bot.mascot, identity: bot.identity, size: 44),
          const SizedBox(height: 12),
          Text(bot.name, style: text.titleMedium),
          const SizedBox(height: 3),
          Text(bot.role, style: text.bodySmall, maxLines: 2),
        ],
      ),
    );
  }
}
