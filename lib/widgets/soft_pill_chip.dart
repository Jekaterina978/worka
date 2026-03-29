import 'package:flutter/material.dart';
import '../theme/worka_colors.dart';

class SoftPillChip extends StatelessWidget {
  const SoftPillChip({
    super.key,
    required this.label,
    this.leading,
  });

  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WorkaColors.hoverBlue.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: WorkaColors.blue.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: WorkaColors.subtitle,
            ),
          ),
        ],
      ),
    );
  }
}
