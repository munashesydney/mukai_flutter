/// The iOS tab bar.
///
/// Written by hand rather than using `NavigationBar` (Android-shaped) or
/// `CupertinoTabBar` (fixes its own colours): this keeps the bar on Mukai's
/// tokens, and the sliding capsule behind the active icon is the one piece of
/// motion the app leans on for navigation.
library;

import 'package:flutter/material.dart';

import '../design/appearance.dart';
import '../design/theme.dart';
import '../design/widgets.dart';

class MukaiTabItem {
  const MukaiTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class MukaiTabBar extends StatelessWidget {
  const MukaiTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<MukaiTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  double get _indicatorX =>
      items.length <= 1 ? 0 : -1 + (2 * index) / (items.length - 1);

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);

    return Material(
      color: colors.card,
      child: SafeArea(
        top: false,
        bottom: true,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.hairline)),
            boxShadow: MukaiShadows.sheet(colors.brightness),
          ),
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Stack(
            children: <Widget>[
              // The capsule slides instead of popping, so tab changes read as
              // one movement. Positioned.fill keeps it sized against the bar
              // (which the Row defines) — unpositioned, the Align would expand
              // to the Scaffold slot's full height and starve the body.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedAlign(
                    duration: MukaiMotion.normal,
                    curve: MukaiMotion.springy,
                    alignment: Alignment(_indicatorX, -0.46),
                    child: FractionallySizedBox(
                      widthFactor: 0.74 / items.length,
                      heightFactor: 0.40,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: BorderRadius.circular(MukaiRadii.pill),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: _TabButton(
                        item: items[i],
                        selected: i == index,
                        onTap: () {
                          if (i == index) return;
                          Haptics.select();
                          onChanged(i);
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final MukaiTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: PressableScale(
        scale: 0.9,
        enableHaptics: false,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedSwitcher(
              duration: MukaiMotion.fast,
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                key: ValueKey<bool>(selected),
                size: 22,
                color: selected ? colors.accentColor : colors.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: MukaiMotion.fast,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: selected ? colors.accentInk : colors.textMuted,
                letterSpacing: 0.1,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
