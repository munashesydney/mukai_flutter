/// Appearance — switch mode and accent theme live.
///
/// Mirrors Settings → Appearance in the desktop app: the same six themes with
/// their one-line descriptions, and System/Light/Dark. Everything routes
/// through [AppearanceController], so a change repaints the whole client from
/// [MukaiColors] without any screen knowing a theme was picked.
library;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../design/appearance.dart';
import '../../design/glass.dart';
import '../../design/theme.dart';
import '../../design/widgets.dart';

class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final AppearanceController appearance = MukaiScope.appearanceOf(context);

    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => DraggableScrollableSheet(
        initialChildSize: .85,
        minChildSize: .35,
        maxChildSize: 1,
        expand: false,
        snap: true,
        snapSizes: const [.35, .85, 1],
        builder: (context, scrollController) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: MukaiSpace.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Stack(
                  children: [
                    const SheetGrabber(label: 'Appearance'),
                    Positioned(
                      right: 8,
                      top: 14,
                      child: MukaiGlassPill.circle(
                        child: MukaiIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Close appearance',
                          border: false,
                          onTap: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: MukaiSpace.screen,
                  ),
                  title: Text('Minimalism', style: text.titleSmall),
                  subtitle: const Text('A simple bot list with recent chats.'),
                  value: appearance.preferences.minimalism,
                  onChanged: (value) {
                    Haptics.select();
                    appearance.setMinimalism(value);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MukaiSpace.screen,
                    MukaiSpace.xl,
                    MukaiSpace.screen,
                    MukaiSpace.sm,
                  ),
                  child: Text('Mode', style: text.titleSmall),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MukaiSpace.screen,
                  ),
                  child: _ModeSelector(
                    mode: appearance.preferences.mode,
                    onChanged: appearance.setMode,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MukaiSpace.screen,
                    MukaiSpace.xl,
                    MukaiSpace.screen,
                    MukaiSpace.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text('Theme', style: text.titleSmall),
                      const Spacer(),
                      Text(
                        colors.themeId.label,
                        style: text.labelMedium?.copyWith(
                          color: colors.textSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MukaiSpace.screen,
                  ),
                  child: _ThemeGrid(
                    selected: appearance.preferences.theme,
                    brightness: colors.brightness,
                    onSelect: (MukaiThemeId id) {
                      Haptics.select();
                      appearance.setTheme(id);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented System / Light / Dark control.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});
  final ColorMode mode;
  final ValueChanged<ColorMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.cardMuted,
        borderRadius: BorderRadius.circular(MukaiRadii.control),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: <Widget>[
          for (final ColorMode option in ColorMode.values)
            Expanded(
              child: _ModeChip(
                option: option,
                selected: option == mode,
                onTap: () {
                  Haptics.select();
                  onChanged(option);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ColorMode option;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (option) {
    ColorMode.system => Icons.brightness_auto_outlined,
    ColorMode.light => Icons.light_mode_outlined,
    ColorMode.dark => Icons.dark_mode_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return PressableScale(
      scale: 0.96,
      onTap: onTap,
      child: AnimatedContainer(
        duration: MukaiMotion.fast,
        curve: MukaiMotion.curve,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(MukaiRadii.control - 3),
          boxShadow: selected ? MukaiShadows.card(colors.brightness) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              _icon,
              size: 15,
              color: selected ? colors.accentInk : colors.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? colors.ink : colors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two columns of theme cards, each showing its own accent rather than the
/// currently active one, so the choice reads before it is made.
class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({
    required this.selected,
    required this.brightness,
    required this.onSelect,
  });

  final MukaiThemeId selected;
  final Brightness brightness;
  final ValueChanged<MukaiThemeId> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      for (final MukaiThemeDefinition theme in kMukaiThemes)
        _ThemeCard(
          theme: theme,
          palette: theme.palette(brightness),
          selected: theme.id == selected,
          onTap: () => onSelect(theme.id),
        ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = MukaiSpace.md;
        final bool twoColumns =
            constraints.maxWidth >= 340 &&
            MediaQuery.textScalerOf(context).scale(14) <= 16;
        final double width = twoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final Widget card in cards)
              SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final MukaiThemeDefinition theme;
  final AccentPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return PressableScale(
      scale: 0.97,
      onTap: onTap,
      child: AnimatedContainer(
        duration: MukaiMotion.fast,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? palette.soft : colors.card,
          borderRadius: BorderRadius.circular(MukaiRadii.card),
          border: Border.all(
            color: selected ? palette.accent : colors.hairline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[palette.accent, palette.glow],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(theme.label, style: text.titleSmall)),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: palette.accent,
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              theme.description,
              style: text.bodySmall?.copyWith(
                color: colors.textMuted,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 9),
            Row(
              children: <Widget>[
                _Swatch(color: palette.accent),
                const SizedBox(width: 4),
                _Swatch(color: palette.text),
                const SizedBox(width: 4),
                _Swatch(color: palette.border),
                const SizedBox(width: 4),
                _Swatch(color: palette.rail),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
    );
  }
}
