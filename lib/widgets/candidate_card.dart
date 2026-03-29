import 'package:flutter/material.dart';
import '../theme/worka_colors.dart';
import '../theme/worka_ui_tokens.dart';

@Deprecated('Use CandidateCvCard from widgets/cards/candidate_cv_card.dart')
class CandidateCard extends StatelessWidget {
  const CandidateCard({
    super.key,
    required this.onTap,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.badge,
  });

  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsets margin;
  final Widget? badge;

  static const double _radius = 22;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: WorkaUiShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Material(
          color: const Color(0xFFFFFFFF),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(
                color: WorkaColors.divider.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(_radius),
              splashColor: WorkaColors.blue.withValues(alpha: 0.08),
              highlightColor: WorkaColors.blue.withValues(alpha: 0.03),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: child,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_radius),
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ),
                  if (badge != null)
                    Positioned(top: 12, right: 12, child: badge!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
