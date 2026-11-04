/// Auth-flow widgets: step chrome and the "hosted by you" reassurance panel.
///
/// Ports `.auth-steps`, `.auth-aside-footer` and the eyebrow/progress treatment
/// from `styles/auth.css` into touch-sized equivalents.
library;

import 'package:flutter/material.dart';

import '../../../design/appearance.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../../../domain/models.dart';

/// The little ghost, breathing. Used above the fold on both auth steps.
class FloatingGhost extends StatefulWidget {
  const FloatingGhost({
    super.key,
    this.size = 68,
    this.identity = BotIdentity.mukai,
    this.mascot = Mascot.logo,
  });

  final double size;
  final BotIdentity identity;
  final String mascot;

  @override
  State<FloatingGhost> createState() => _FloatingGhostState();
}

class _FloatingGhostState extends State<FloatingGhost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _float,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeInOut.transform(_float.value);
        return Transform.translate(offset: Offset(0, -5 * t), child: child);
      },
      child: GhostAvatar(
        mascot: widget.mascot,
        identity: widget.identity,
        size: widget.size,
      ),
    );
  }
}

/// Two-segment progress bar paired with the eyebrow label.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.step,
    required this.total,
    required this.label,
  });

  final int step;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < total; i++)
              Padding(
                padding: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
                child: AnimatedContainer(
                  duration: MukaiMotion.normal,
                  curve: MukaiMotion.curve,
                  width: i < step ? 26 : 14,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < step
                        ? colors.accentColor
                        : colors.hairlineStrong,
                    borderRadius: BorderRadius.circular(MukaiRadii.pill),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Eyebrow('$label · $step of $total'),
      ],
    );
  }
}

class OnboardingStepData {
  const OnboardingStepData({
    required this.title,
    required this.body,
    this.done = false,
    this.current = false,
  });

  final String title;
  final String body;
  final bool done;
  final bool current;
}

/// Numbered steps with a connector rail — `.auth-steps`.
class StepList extends StatelessWidget {
  const StepList({super.key, required this.steps});
  final List<OnboardingStepData> steps;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          _StepRow(
            index: i + 1,
            step: steps[i],
            isLast: i == steps.length - 1,
            connector: colors.hairlineStrong,
            titleStyle: text.titleSmall!,
            bodyStyle: text.bodySmall!.copyWith(
              color: colors.textSecondary,
              height: 1.55,
            ),
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.step,
    required this.isLast,
    required this.connector,
    required this.titleStyle,
    required this.bodyStyle,
  });

  final int index;
  final OnboardingStepData step;
  final bool isLast;
  final Color connector;
  final TextStyle titleStyle;
  final TextStyle bodyStyle;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final Color markerFill = step.done
        ? colors.accentColor
        : (step.current ? colors.accentSoft : Colors.transparent);
    final Color markerBorder = step.done || step.current
        ? colors.accentColor
        : colors.hairlineStrong;
    final Color markerText = step.done
        ? colors.textOnAccent
        : (step.current ? colors.accentInk : colors.textMuted);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              AnimatedContainer(
                duration: MukaiMotion.fast,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: markerFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: markerBorder, width: 1),
                ),
                child: Center(
                  child: step.done
                      ? Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: colors.textOnAccent,
                        )
                      : Text(
                          '$index',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: markerText,
                          ),
                        ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: connector,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 26, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    step.title,
                    style: titleStyle.copyWith(
                      color: step.done || step.current
                          ? colors.ink
                          : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(step.body, style: bodyStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Hosted by you." — the trust panel pinned to the bottom of the auth screen.
class HostedFooter extends StatelessWidget {
  const HostedFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MukaiSpace.xl),
      decoration: BoxDecoration(
        color: colors.cardMuted,
        borderRadius: BorderRadius.circular(MukaiRadii.card),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.shield_outlined, size: 20, color: colors.accentInk),
          const SizedBox(height: 12),
          Text(
            'Hosted by you.',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            'Your login protects access to the Mukai running on your machine.',
            style: text.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}
