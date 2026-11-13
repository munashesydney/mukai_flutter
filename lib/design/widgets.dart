/// Mukai's iOS component kit. Small, opinionated, token-driven.
///
/// Two conventions worth knowing:
///   * Colour always comes from `MukaiColors.of(context)`, never a literal.
///   * Anything tappable gets a subtle press-scale plus haptics — the part that
///     makes a ported UI feel like it belongs on the device.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import 'appearance.dart';
import 'glass.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Feel
// ---------------------------------------------------------------------------

/// One place for touch feedback, so "how Mukai feels" is a single decision.
abstract final class Haptics {
  static Future<void> tap() => HapticFeedback.lightImpact();
  static Future<void> select() => HapticFeedback.selectionClick();
  static Future<void> success() => HapticFeedback.mediumImpact();
}

/// Scales its child down while pressed. The whole app's tactile signature.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.borderRadius,
    this.enableHaptics = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final BorderRadius? borderRadius;
  final bool enableHaptics;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setDown(bool value) {
    if (!_enabled || _down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) {
        _setDown(true);
        if (widget.enableHaptics) Haptics.select();
      },
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: MukaiMotion.instant,
        curve: MukaiMotion.curve,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

class MukaiCard extends StatelessWidget {
  const MukaiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MukaiSpace.lg),
    this.radius = MukaiRadii.card,
    this.muted = false,
    this.elevated = true,
    this.border = true,
    this.onTap,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool muted;
  final bool elevated;
  final bool border;
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final BorderRadius shape = BorderRadius.circular(radius);
    return PressableScale(
      onTap: onTap,
      scale: onTap == null ? 1 : 0.985,
      child: AnimatedContainer(
        duration: MukaiMotion.fast,
        padding: padding,
        decoration: BoxDecoration(
          color: gradient == null
              ? (muted ? colors.cardMuted : colors.card)
              : null,
          gradient: gradient,
          borderRadius: shape,
          border: border ? Border.all(color: colors.hairline, width: 1) : null,
          boxShadow: elevated ? MukaiShadows.card(colors.brightness) : null,
        ),
        child: child,
      ),
    );
  }
}

class SoftDivider extends StatelessWidget {
  const SoftDivider({super.key, this.indent = 0, this.color});
  final double indent;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return Container(
      height: 1,
      margin: EdgeInsets.only(left: indent),
      color: color ?? colors.hairline,
    );
  }
}

// ---------------------------------------------------------------------------
// Type helpers
// ---------------------------------------------------------------------------

/// The small uppercase label above a section — the app's `auth-eyebrow`.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.tracking = 1.2});
  final String text;
  final Color? color;
  final double tracking;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color ?? colors.accentInk,
        letterSpacing: tracking,
      ),
    );
  }
}

/// "Bots  2" — a section label with an optional count and trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    this.count,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      MukaiSpace.screen,
      MukaiSpace.xl,
      MukaiSpace.md,
      MukaiSpace.sm,
    ),
  });

  final String label;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(child: Text(label, style: text.titleMedium, maxLines: 2)),
          if (count != null) ...<Widget>[
            const SizedBox(width: 7),
            Text(
              '$count',
              style: text.labelMedium?.copyWith(
                color: colors.textMuted,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

enum MukaiButtonVariant { filled, tonal, quiet, plain }

class MukaiButton extends StatelessWidget {
  const MukaiButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = MukaiButtonVariant.filled,
    this.expand = false,
    this.busy = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final MukaiButtonVariant variant;
  final bool expand;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool enabled = onPressed != null && !busy;

    final (Color fill, Color foreground, Color? outline) = switch (variant) {
      MukaiButtonVariant.filled => (
        enabled
            ? colors.accentColor
            : colors.accentColor.withValues(alpha: 0.45),
        colors.textOnAccent,
        null,
      ),
      MukaiButtonVariant.tonal => (
        colors.accentSoft,
        colors.accentInk,
        colors.accentBorder.withValues(alpha: 0.7),
      ),
      MukaiButtonVariant.quiet => (
        colors.cardMuted,
        colors.textBody,
        colors.hairline,
      ),
      MukaiButtonVariant.plain => (Colors.transparent, colors.accentInk, null),
    };

    final List<Widget> content = <Widget>[
      if (busy)
        SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: foreground.withValues(alpha: 0.9),
          ),
        )
      else if (icon != null)
        Icon(icon, size: compact ? 15 : 17, color: foreground),
      if (busy || icon != null) const SizedBox(width: 8),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (compact ? text.labelMedium : text.labelLarge)?.copyWith(
            color: foreground,
          ),
        ),
      ),
      if (trailingIcon != null && !busy) ...<Widget>[
        const SizedBox(width: 6),
        Icon(trailingIcon, size: compact ? 14 : 16, color: foreground),
      ],
    ];

    final Widget body = AnimatedContainer(
      duration: MukaiMotion.fast,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? MukaiSpace.md : MukaiSpace.xl,
        vertical: compact ? 8 : 15,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(
          variant == MukaiButtonVariant.plain
              ? MukaiRadii.chip
              : MukaiRadii.control,
        ),
        border: outline == null ? null : Border.all(color: outline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: content,
      ),
    );

    return PressableScale(
      enableHaptics: false,
      onTap: enabled
          ? () {
              Haptics.tap();
              onPressed?.call();
            }
          : null,
      scale: enabled ? 0.975 : 1,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: expand ? SizedBox(width: double.infinity, child: body) : body,
      ),
    );
  }
}

class MukaiIconButton extends StatelessWidget {
  const MukaiIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.filled = false,
    this.border = true,
    this.size = 44,
    this.iconSize = 18,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool filled;
  final bool border;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final Widget button = PressableScale(
      scale: 0.92,
      enableHaptics: false,
      onTap: onTap == null
          ? null
          : () {
              Haptics.select();
              onTap!.call();
            },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? colors.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(MukaiRadii.control),
          border: border && !filled
              ? Border.all(color: colors.hairline, width: 1)
              : null,
        ),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color:
                color ?? (filled ? colors.textOnAccent : colors.textSecondary),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// One row inside [MukaiGlassMenuButton].
class MukaiGlassMenuItem {
  const MukaiGlassMenuItem({
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
}

/// Dropdown menu on the same native glass as [MukaiGlassPill]: the panel is
/// a [MukaiGlassSurface] (UIKit `UIGlassEffect`) with Flutter-drawn rows, so
/// a header kebab and its menu read as one material family. Where native
/// glass is unavailable the panel falls back to the standard card surface.
class MukaiGlassMenuButton extends StatefulWidget {
  const MukaiGlassMenuButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.items,
    this.width = 190,
    this.size = 44,
  });

  final String tooltip;
  final Widget icon;
  final List<MukaiGlassMenuItem> items;
  final double width;
  final double size;

  @override
  State<MukaiGlassMenuButton> createState() => _MukaiGlassMenuButtonState();
}

class _MukaiGlassMenuButtonState extends State<MukaiGlassMenuButton> {
  final GlobalKey _anchor = GlobalKey();

  void _open() {
    if (widget.items.isEmpty) return;
    final RenderBox? box =
        _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    Navigator.of(context).push(
      _MukaiGlassMenuRoute(
        items: widget.items,
        width: widget.width,
        anchor: box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: PressableScale(
        scale: 0.92,
        onTap: _open,
        child: SizedBox(
          key: _anchor,
          width: widget.size,
          height: widget.size,
          child: Center(child: widget.icon),
        ),
      ),
    );
  }
}

class _MukaiGlassMenuRoute extends PopupRoute<void> {
  _MukaiGlassMenuRoute({
    required this.items,
    required this.width,
    required this.anchor,
  });

  final List<MukaiGlassMenuItem> items;
  final double width;
  final Rect anchor;

  static const double _radius = 18;
  static const double _itemHeight = 44;

  @override
  Color get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => MukaiMotion.fast;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final MukaiColors colors = MukaiColors.of(context);
    final Size screen = MediaQuery.sizeOf(context);
    final double panelHeight = items.length * _itemHeight + 12;
    // Opens under the anchor, right-aligned to it; flips above when the
    // bottom edge runs out of room, then clamps inside the screen.
    double top = anchor.bottom + 6;
    if (top + panelHeight > screen.height - 12) {
      top = anchor.top - 6 - panelHeight;
    }
    top = top.clamp(12.0, math.max(12.0, screen.height - panelHeight - 12));
    double left = anchor.right - width;
    if (left + width > screen.width - 12) left = screen.width - width - 12;
    if (left < 12) left = 12;
    return Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: top,
          width: width,
          child: MukaiGlassProbe(
            builder: (BuildContext context, bool glass, Widget? _) =>
                MukaiGlassSurface(
                  cornerRadius: _radius,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_radius),
                      // On glass the material supplies the surface and edge.
                      color: glass ? null : colors.card,
                      border: glass
                          ? null
                          : Border.all(color: colors.hairlineStrong),
                      boxShadow: glass
                          ? null
                          : MukaiShadows.card(colors.brightness),
                    ),
                    child: Material(
                      // Transparent so ink responds while the native glass (or
                      // the card fallback behind it) paints the surface.
                      type: MaterialType.transparency,
                      borderRadius: BorderRadius.circular(_radius),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (final item in items)
                              SizedBox(
                                height: _itemHeight,
                                child: ListTile(
                                  dense: true,
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    item.onTap?.call();
                                  },
                                  title: Text(
                                    item.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: colors.ink),
                                  ),
                                  trailing: item.selected
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: colors.accentColor,
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: .92, end: 1).animate(
          CurvedAnimation(parent: animation, curve: MukaiMotion.springy),
        ),
        alignment: Alignment.topRight,
        child: child,
      ),
    );
  }
}

/// Labelled field with the accent focus ring.
class MukaiField extends StatelessWidget {
  const MukaiField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.monospace = false,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.maxLines = 1,
    this.autofocus = false,
    this.focusNode,
    this.suffix,
    this.onError,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final bool monospace;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final bool autofocus;
  final FocusNode? focusNode;
  final Widget? suffix;
  final String? onError;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: text.titleSmall),
        const SizedBox(height: 9),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          enabled: enabled,
          autofocus: autofocus,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          maxLines: obscure ? 1 : maxLines,
          style: text.bodyLarge?.copyWith(
            color: colors.ink,
            // Menlo ships with iOS, so codes get real monospace like the web app.
            fontFamily: monospace ? 'Menlo' : null,
            letterSpacing: monospace ? 0.4 : null,
            fontFeatures: monospace
                ? const <FontFeature>[FontFeature.tabularFigures()]
                : null,
          ),
          decoration: InputDecoration(
            hintText: hint,
            errorText: onError,
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
          ),
        ),
        if (helper != null) ...<Widget>[
          const SizedBox(height: 9),
          Text(
            helper!,
            style: text.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.55,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Brand + identity
// ---------------------------------------------------------------------------

/// Mascot asset names shipped in `assets/mascots/`.
abstract final class Mascot {
  static const String logo = 'mukai-logo';
  static const String defaultBot = 'muka-mascot-1-purple';

  static String path(String id) => 'assets/mascots/$id.webp';

  static const List<String> selectable = <String>[
    logo,
    'muka-mascot-1-green',
    'muka-mascot-1-meroon',
    'muka-mascot-1-orange',
    'muka-mascot-1-purple',
    'muka-mascot-2-blue',
    'muka-mascot-2-green',
    'muka-mascot-2-meroon',
    'muka-mascot-2-orange',
    'muka-mascot-2-purple',
    'muka-mascot-3-blue',
    'muka-mascot-3-green',
    'muka-mascot-3-orange',
    'muka-mascot-3-purple',
    'muka-mascot-4-blue',
    'muka-mascot-5-blue',
  ];
}

/// The ghost, drawn — used when an asset is missing and as a loading state.
class GhostPainter extends CustomPainter {
  const GhostPainter({required this.mark, required this.body});
  final Color mark;
  final Color body;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint blob = Paint()
      ..color = body
      ..style = PaintingStyle.fill;
    final Path body1 = Path()
      ..moveTo(w * 0.14, h * 0.72)
      ..quadraticBezierTo(w * 0.04, h * 0.44, w * 0.28, h * 0.33)
      ..quadraticBezierTo(w * 0.32, h * 0.12, w * 0.54, h * 0.17)
      ..quadraticBezierTo(w * 0.82, h * 0.14, w * 0.86, h * 0.44)
      ..quadraticBezierTo(w * 1.0, h * 0.66, w * 0.78, h * 0.76)
      ..quadraticBezierTo(w * 0.62, h * 0.92, w * 0.44, h * 0.84)
      ..quadraticBezierTo(w * 0.24, h * 0.88, w * 0.14, h * 0.72)
      ..close();
    canvas.drawPath(body1, blob);

    final Paint eye = Paint()..color = const Color(0xFF1E2A30);
    canvas.drawCircle(Offset(w * 0.40, h * 0.52), w * 0.058, eye);
    canvas.drawCircle(Offset(w * 0.62, h * 0.52), w * 0.058, eye);
    final Paint glint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w * 0.418, h * 0.50), w * 0.018, glint);
    canvas.drawCircle(Offset(w * 0.638, h * 0.50), w * 0.018, glint);

    final Paint bow = Paint()..color = mark;
    canvas.drawCircle(Offset(w * 0.51, h * 0.68), w * 0.035, bow);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.42, h * 0.68),
        width: w * 0.15,
        height: h * 0.09,
      ),
      bow,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.60, h * 0.68),
        width: w * 0.15,
        height: h * 0.09,
      ),
      bow,
    );
  }

  @override
  bool shouldRepaint(covariant GhostPainter old) =>
      old.mark != mark || old.body != body;
}

/// Circular mascot avatar on a bot-identity gradient, with optional presence.
class GhostAvatar extends StatelessWidget {
  const GhostAvatar({
    super.key,
    this.mascot = Mascot.defaultBot,
    this.identity = BotIdentity.neutral,
    this.size = 40,
    this.presence,
  });

  final String mascot;
  final BotIdentity identity;
  final double size;
  final bool? presence;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final BotIdentityColors skin = colors.identity(identity);
    final double dot = math.max(8, size * 0.24);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Image.asset(
            Mascot.path(mascot),
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => CustomPaint(
              size: Size.square(size),
              painter: GhostPainter(mark: skin.mark, body: colors.canvas),
            ),
          ),
          if (presence != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: presence! ? const Color(0xFF4CB07F) : colors.textSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.canvas, width: dot * 0.22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// mascot + `mukai.` wordmark, with the accent period.
class MukaiWordmark extends StatelessWidget {
  const MukaiWordmark({super.key, this.size = 26, this.compact = false});
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Image.asset(
          Mascot.path(Mascot.logo),
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => CustomPaint(
            size: Size.square(size),
            painter: GhostPainter(
              mark: colors.accentColor,
              body: colors.canvas,
            ),
          ),
        ),
        if (!compact) ...<Widget>[
          const SizedBox(width: 9),
          Text.rich(
            TextSpan(
              text: 'mukai',
              style: TextStyle(
                fontSize: size * 0.82,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: colors.ink,
              ),
              children: <InlineSpan>[
                TextSpan(
                  text: '.',
                  style: TextStyle(color: colors.accentColor),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Small pill for bot roles and source tags.
class IdentityChip extends StatelessWidget {
  const IdentityChip({
    super.key,
    required this.label,
    this.identity,
    this.icon,
    this.color,
    this.dense = false,
  });

  final String label;
  final BotIdentity? identity;
  final IconData? icon;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final BotIdentityColors? skin = identity == null
        ? null
        : colors.identity(identity!);
    final Color tint = color ?? skin?.label ?? colors.textSecondary;
    final Color fill = skin?.labelSurface ?? colors.cardMuted;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 4.5,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(MukaiRadii.chip),
        border: Border.all(
          color: (skin?.border ?? colors.hairline).withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 11 : 12, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tint,
              fontSize: dense ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// "All systems calm" — a breathing glow dot and a short status line.
class SystemStatusPill extends StatefulWidget {
  const SystemStatusPill({super.key, this.label = 'All systems calm'});
  final String label;

  @override
  State<SystemStatusPill> createState() => _SystemStatusPillState();
}

class _SystemStatusPillState extends State<SystemStatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedBuilder(
          animation: _breath,
          builder: (BuildContext context, Widget? child) {
            final double t = Curves.easeInOut.transform(_breath.value);
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.glow,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.glow.withValues(alpha: 0.30 + 0.35 * t),
                    blurRadius: 5 + 6 * t,
                    spreadRadius: 0.5 + 1.2 * t,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// The desktop activity indicator: three 4px dots, a 1.2s pulse and 150ms stagger.
class BouncingDots extends StatefulWidget {
  const BouncingDots({super.key, this.size = 4, this.color});
  final double size;
  final Color? color;

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.color ?? MukaiColors.of(context).accentColor;
    return Semantics(
      label: 'AI is working',
      liveRegion: true,
      child: SizedBox(
        height: math.max(14, widget.size + 4),
        child: Center(
          widthFactor: 1,
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Builder(
                    builder: (context) {
                      final elapsed =
                          (_motion.lastElapsedDuration?.inMilliseconds ?? 0) -
                          i * 150;
                      final phase = (elapsed % 1200) / 1200;
                      final pulse = _reduceMotion || elapsed < 0
                          ? 0.0
                          : Curves.easeInOut.transform(
                              phase <= .5 ? phase * 2 : (1 - phase) * 2,
                            );
                      return Padding(
                        padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
                        child: Transform.translate(
                          offset: Offset(0, -2 * pulse),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tint.withValues(alpha: 1 - .7 * pulse),
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(dimension: widget.size),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

/// Chevron row used across home and settings.
class MukaiRow extends StatelessWidget {
  const MukaiRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.showChevron = true,
    this.onTap,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return PressableScale(
      onTap: onTap,
      scale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: MukaiSpace.lg,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.pressed : null,
          borderRadius: BorderRadius.circular(MukaiRadii.control),
        ),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: text.titleSmall),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(
                        color: colors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              trailing!,
              const SizedBox(width: 8),
            ],
            if (showChevron)
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: colors.textSoft,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheets
// ---------------------------------------------------------------------------

Future<T?> showMukaiSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  final MukaiColors colors = MukaiColors.of(context);
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final route = ModalBottomSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    enableDrag: true,
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .90,
    ),
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MukaiRadii.sheet),
      ),
    ),
    modalBarrierColor: colors.scrim,
    builder: builder,
  );
  // The push future resolves at pop, before the reverse animation ends.
  // completed resolves after the sheet and its barrier leave the overlay.
  MukaiGlass.coverRouteUntil(ModalRoute.of(context), route.completed);
  return navigator.push(route);
}

class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: colors.hairlineStrong,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          if (label != null) ...<Widget>[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                label!,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline failure surface with a retry — used by home and chat alike.
class MukaiErrorBanner extends StatelessWidget {
  const MukaiErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
    this.actionLabel = 'Retry',
  });

  final String message;
  final VoidCallback onRetry;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final bool dark = colors.isDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3C2723) : const Color(0xFFFAEDEA),
        borderRadius: BorderRadius.circular(MukaiRadii.control),
        border: Border.all(
          color: dark ? const Color(0xFF6A443C) : const Color(0xFFF0D3CC),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: dark ? const Color(0xFFE0836F) : const Color(0xFFB3402B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
          MukaiButton(
            label: actionLabel,
            variant: MukaiButtonVariant.plain,
            compact: true,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Empty state used by the tabs that aren't built out yet.
class MukaiEmptyState extends StatelessWidget {
  const MukaiEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.mascot = Mascot.defaultBot,
    this.identity = BotIdentity.mukai,
    this.action,
  });

  final String title;
  final String body;
  final String mascot;
  final BotIdentity identity;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MukaiSpace.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            GhostAvatar(mascot: mascot, identity: identity, size: 66),
            const SizedBox(height: MukaiSpace.lg),
            Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: MukaiSpace.sm),
            Text(
              body,
              style: text.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: MukaiSpace.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
