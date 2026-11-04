import 'package:flutter/material.dart';

import 'appearance.dart';

/// A controlled reveal that grows from its top edge. Keep the mounted reader
/// through collapse so selectable Markdown never gets reparented mid-animation.
class MukaiExpansion extends StatefulWidget {
  const MukaiExpansion({
    super.key,
    required this.expanded,
    required this.child,
  });
  final bool expanded;
  final Widget child;
  @override
  State<MukaiExpansion> createState() => _MukaiExpansionState();
}

class _MukaiExpansionState extends State<MukaiExpansion>
    with SingleTickerProviderStateMixin {
  final GlobalKey _childKey = GlobalKey();
  late final AnimationController _motion;
  late final CurvedAnimation _curve;

  /// Visual height already accounted for by the scroll anchoring below.
  double _anchoredVisual = 0;
  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 210),
      value: widget.expanded ? 1 : 0,
    );
    _curve = CurvedAnimation(
      parent: _motion,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _motion.addListener(_anchorHeader);
  }

  double _naturalHeight() {
    final box = _childKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 0;
  }

  /// Chat threads are bottom-anchored (`reverse: true`), where growing
  /// content pushes the tapped header up off the screen. Scroll by the same
  /// animated delta so the header stays under the finger and the content
  /// discloses downward, the way a desktop `<details>` does.
  void _anchorHeader() {
    final visual = _naturalHeight() * _curve.value;
    final delta = visual - _anchoredVisual;
    _anchoredVisual = visual;
    if (delta.abs() < 0.5) return;
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null || position.axisDirection != AxisDirection.up) {
      return;
    }
    position.jumpTo(position.pixels + delta);
  }

  late bool _mountedOnce = widget.expanded;
  @override
  void didUpdateWidget(covariant MukaiExpansion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) return;
    _anchoredVisual = oldWidget.expanded ? _naturalHeight() : 0;
    if (widget.expanded) _mountedOnce = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = widget.expanded ? 1 : 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _anchorHeader();
      });
    } else if (widget.expanded) {
      _motion.forward();
    } else {
      _motion.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_mountedOnce
      ? const SizedBox.shrink()
      : AnimatedBuilder(
          animation: _motion,
          child: widget.child,
          builder: (context, child) => Offstage(
            offstage: !widget.expanded && _motion.isDismissed,
            child: ExcludeFocus(
              excluding: !widget.expanded,
              child: ExcludeSemantics(
                excluding: !widget.expanded,
                child: IgnorePointer(
                  ignoring: !widget.expanded,
                  child: ClipRect(
                    child: SizeTransition(
                      alignment: Alignment.topCenter,
                      sizeFactor: _curve,
                      child: FadeTransition(
                        key: _childKey,
                        opacity: _motion,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
}

class MukaiDisclosure extends StatefulWidget {
  const MukaiDisclosure({
    super.key,
    required this.title,
    required this.builder,
    this.preview,
  });
  final Widget title;
  final WidgetBuilder builder;
  final Widget? preview;
  @override
  State<MukaiDisclosure> createState() => _MukaiDisclosureState();
}

class _MukaiDisclosureState extends State<MukaiDisclosure> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        button: true,
        expanded: _expanded,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Row(
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.title,
                        if (!_expanded && widget.preview != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: widget.preview!,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? .5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: MukaiColors.of(context).textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      MukaiExpansion(
        expanded: _expanded,
        child: Builder(builder: widget.builder),
      ),
    ],
  );
}
