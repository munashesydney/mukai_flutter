/// Routes the landing page according to the local appearance preference.
library;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../domain/models.dart';
import 'minimal_bot_home.dart';
import 'minimal_chat_home.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenBot,
    required this.onOpenSidebar,
    required this.onOpenConversation,
    this.onSwitchWorkspace,
    this.onNewConversation,
  });

  final ValueChanged<MukaiBot> onOpenBot;
  final ValueChanged<MukaiBot>? onNewConversation;
  final VoidCallback onOpenSidebar;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback? onSwitchWorkspace;

  @override
  Widget build(BuildContext context) {
    final appearance = MukaiScope.appearanceOf(context);
    final session = MukaiScope.sessionOf(context);
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => appearance.preferences.minimalism
          ? MinimalChatHome(
              key: ValueKey(session.workspace.id),
              onOpenSidebar: onOpenSidebar,
              onSwitchWorkspace: onSwitchWorkspace,
            )
          : MinimalBotHome(
              key: ValueKey(session.workspace.id),
              onOpenBot: onNewConversation ?? onOpenBot,
              onOpenConversation: onOpenConversation,
              onSwitchWorkspace: onSwitchWorkspace,
            ),
    );
  }
}
