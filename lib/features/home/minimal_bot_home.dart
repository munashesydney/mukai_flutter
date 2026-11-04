/// A quiet landing page: bots, with their recent conversations on demand.
library;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../design/appearance.dart';
import '../../design/widgets.dart';
import '../../domain/models.dart';
import '../settings/appearance_sheet.dart';
import 'widgets/bot_conversation_list.dart';

class MinimalBotHome extends StatelessWidget {
  const MinimalBotHome({
    super.key,
    required this.onOpenBot,
    required this.onOpenConversation,
    this.onSwitchWorkspace,
  });

  final ValueChanged<MukaiBot> onOpenBot;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback? onSwitchWorkspace;

  @override
  Widget build(BuildContext context) {
    final session = MukaiScope.sessionOf(context);
    final colors = MukaiColors.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => RefreshIndicator.adaptive(
        onRefresh: session.loadRecents,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: onSwitchWorkspace != null,
                      child: InkWell(
                        onTap: onSwitchWorkspace,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  session.workspace.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: colors.textMuted),
                                ),
                              ),
                              if (onSwitchWorkspace != null) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: colors.textSoft,
                                ),
                              ],
                            ],
                          ),
                        ),
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
            if (session.hasError)
              MukaiErrorBanner(
                message: session.error!,
                onRetry: session.loadRecents,
              ),
            BotConversationList(
              key: ValueKey(session.workspace.id),
              bots: session.bots,
              conversations: session.botConversations,
              onOpenConversation: onOpenConversation,
              onNewConversation: onOpenBot,
            ),
          ],
        ),
      ),
    );
  }
}
