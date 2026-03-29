import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class CvProgress extends StatelessWidget {
  final int step; // 0-based
  final int total;

  const CvProgress({super.key, required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final s = step.clamp(0, total - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(total, (i) {
                final active = i <= s;
                final isCurrent = i == s;
                final size = isCurrent ? 10.0 : 8.0;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: active ? WorkaColors.blue : WorkaColors.fieldBorder,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${s + 1}/$total',
            style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
          ),
        ],
      ),
    );
  }
}
