import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class CvProgressDots extends StatelessWidget {
  final int current;
  final int total;

  /// размер активной точки
  final double activeSize;

  /// размер неактивной точки
  final double idleSize;

  /// расстояние между точками
  final double gap;

  /// когда true — белые точки (для синего фона)
  final bool onBlue;

  const CvProgressDots({
    super.key,
    required this.current,
    required this.total,
    this.activeSize = 10,
    this.idleSize = 8,
    this.gap = 8,
    this.onBlue = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = current.clamp(0, total - 1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i <= c;
        final size = i == c ? activeSize : idleSize;

        final Color color;
        if (onBlue) {
          color = active ? Colors.white : Colors.white.withValues(alpha: 0.4);
        } else {
          color = active ? WorkaColors.blue : Colors.grey.shade300;
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.symmetric(horizontal: gap / 2),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}
