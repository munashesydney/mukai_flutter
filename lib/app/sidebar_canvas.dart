import 'package:flutter/material.dart';

import '../design/appearance.dart';
import '../design/glass.dart';

/// A full-size page that follows a horizontal swipe above the navigation.
class SidebarCanvas extends StatefulWidget {
  const SidebarCanvas({super.key, required this.child, required this.sidebar});
  final Widget child;
  final Widget sidebar;
  @override
  State<SidebarCanvas> createState() => SidebarCanvasState();
}

class SidebarCanvasState extends State<SidebarCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  bool _open = false;
  bool _dragging = false;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    // Fast path: return the material the instant the settle animation ends.
    // _syncGlassHidden (below) is the safety net that keeps the flag honest
    // even if a status event is ever missed.
    _motion.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (MukaiGlass.hidden.value) MukaiGlass.hidden.value = false;
      }
    });
  }

  /// Glass is native iOS platform views composited above the Flutter layer.
  /// The hole cut for them in that layer lags a moving ClipRRect and tears
  /// as a bright band along the page edge, so the material steps out while
  /// the page moves. Deriving it from live state (drag or running animation)
  /// each frame — instead of trusting lifecycle callbacks alone — means it
  /// can never strand hidden and take the material app-wide.
  void _syncGlassHidden() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bool moving = _dragging || _motion.isAnimating;
      if (MukaiGlass.hidden.value != moving) MukaiGlass.hidden.value = moving;
    });
  }

  void open() => _settle(true);
  void close() => _settle(false);

  void _settle(bool open) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _open = open);
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = open ? 1 : 0;
    } else {
      _motion.animateTo(open ? 1 : 0, curve: Curves.easeOutCubic);
    }
    _syncGlassHidden();
  }

  void _drag(DragUpdateDetails details) {
    if (_width == 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _dragging = true;
    _motion.value = (_motion.value + details.delta.dx / _width).clamp(0, 1);
  }

  void _finish(DragEndDetails details) {
    _dragging = false;
    final speed = details.primaryVelocity ?? 0;
    _settle(speed.abs() > 400 ? speed > 0 : _motion.value > .45);
  }

  @override
  void dispose() {
    // Never leave the app stranded without material because this canvas is
    // gone while its page was mid motion.
    if (MukaiGlass.hidden.value) MukaiGlass.hidden.value = false;
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: colors.cardMuted,
        body: LayoutBuilder(
          builder: (context, constraints) {
            _width = (constraints.maxWidth * .80).clamp(0, 360);
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: _drag,
              onHorizontalDragEnd: _finish,
              onHorizontalDragCancel: () => _settle(_open),
              child: AnimatedBuilder(
                animation: _motion,
                child: RepaintBoundary(child: widget.child),
                builder: (context, page) {
                  final progress = _motion.value;
                  _syncGlassHidden();
                  final radius = BorderRadius.horizontal(
                    left: Radius.circular(42 * progress),
                  );
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      if (progress > 0)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: _width,
                          child: ExcludeSemantics(
                            excluding: !_open,
                            child: IgnorePointer(
                              ignoring: !_open,
                              child: widget.sidebar,
                            ),
                          ),
                        ),
                      Transform.translate(
                        offset: Offset(_width * progress, 0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.canvas,
                            borderRadius: radius,
                            boxShadow: progress > 0
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha:
                                            (colors.isDark ? .12 : .035) *
                                            progress,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(-4, 0),
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            key: const ValueKey('main-page-canvas'),
                            borderRadius: radius,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ExcludeSemantics(
                                  excluding: _open,
                                  child: IgnorePointer(
                                    ignoring: progress > 0,
                                    child: page,
                                  ),
                                ),
                                if (progress > 0) ...[
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onTap: close,
                                      behavior: HitTestBehavior.opaque,
                                      child: Semantics(
                                        button: true,
                                        label: 'Close navigation',
                                        child: ColoredBox(
                                          color: Colors.black.withValues(
                                            alpha:
                                                (colors.isDark ? .12 : .035) *
                                                progress,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        key: const ValueKey(
                                          'sidebar-page-outline',
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: radius,
                                          border: Border.all(
                                            width: .5,
                                            color: colors.hairlineStrong
                                                .withValues(
                                                  alpha: .35 * progress,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
