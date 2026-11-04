/// Workspace switcher sheet — the mobile equivalent of the sidebar's workspace
/// menu (`Choose workspace`, "Your workspaces", folder/personal kind).
library;

import 'package:flutter/material.dart';

import '../../../design/appearance.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../../../domain/models.dart';

class WorkspaceSheet extends StatelessWidget {
  const WorkspaceSheet({
    super.key,
    required this.current,
    required this.others,
    required this.onSelect,
    required this.onCreate,
  });

  final MukaiWorkspace current;
  final List<MukaiWorkspace> others;
  final ValueChanged<MukaiWorkspace> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SheetGrabber(label: 'Your workspaces'),
          const SizedBox(height: MukaiSpace.md),
          for (final MukaiWorkspace workspace in <MukaiWorkspace>[
            current,
            ...others,
          ])
            _WorkspaceRow(
              workspace: workspace,
              selected: workspace.name == current.name,
              onTap: workspace.name == current.name
                  ? null
                  : () {
                      Haptics.select();
                      onSelect(workspace);
                      Navigator.of(context).pop();
                    },
            ),
          const SoftDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MukaiSpace.screen,
              0,
              MukaiSpace.screen,
              MukaiSpace.md,
            ),
            child: Text(
              'Manage your workspaces in the Mukai desktop app.',
              style: text.bodySmall?.copyWith(
                color: colors.textMuted,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.workspace,
    required this.selected,
    this.onTap,
  });

  final MukaiWorkspace workspace;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return PressableScale(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MukaiSpace.screen,
          vertical: 13,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(workspace.name, style: text.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    workspace.kind,
                    style: text.bodySmall?.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 19, color: colors.accentColor),
          ],
        ),
      ),
    );
  }
}
