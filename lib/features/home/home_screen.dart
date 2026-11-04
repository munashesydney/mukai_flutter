/// Routes the landing page according to the local appearance preference.
library;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../domain/models.dart';
import 'minimal_bot_home.dart';
import 'workspace_home.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenBot,
    required this.onOpenSettings,
    required this.onOpenConversation,
    this.onSwitchWorkspace,
    this.onNewConversation,
  });

  final ValueChanged<MukaiBot> onOpenBot;
  final ValueChanged<MukaiBot>? onNewConversation;
  final VoidCallback onOpenSettings;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback? onSwitchWorkspace;

  @override
  Widget build(BuildContext context) {
    final appearance = MukaiScope.appearanceOf(context);
    final session = MukaiScope.sessionOf(context);
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => appearance.preferences.minimalism
          ? MinimalBotHome(
              key: ValueKey(session.workspace.id),
              onOpenBot: onNewConversation ?? onOpenBot,
              onOpenConversation: onOpenConversation,
              onSwitchWorkspace: onSwitchWorkspace,
            )
          : WorkspaceHome(
              onOpenBot: onOpenBot,
              onOpenSettings: onOpenSettings,
              onOpenConversation: onOpenConversation,
              onSwitchWorkspace: onSwitchWorkspace,
            ),
    );
  }
}
