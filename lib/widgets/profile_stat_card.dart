import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';
import '../theme/worka_ui_tokens.dart';

class ProfileStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String trailingValue;
  final double? progress;
  final VoidCallback onTap;
  final Color accent;
  final bool useDualGradient;

  const ProfileStatCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.trailingValue,
    this.progress,
    required this.onTap,
    required this.accent,
    this.useDualGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleText = (subtitle ?? '').trim();
    final progressValue = (progress ?? -1).clamp(0.0, 1.0);
    final showProgress = progress != null;

    return SizedBox(
      height: 126,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: WorkaColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: WorkaColors.border),
            boxShadow: WorkaUiShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: WorkaColors.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    if (subtitleText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleText,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (showProgress) ...[
                      const SizedBox(height: 10),
                      Stack(
                        children: [
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: WorkaColors.fieldBorder,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: progressValue,
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                gradient: useDualGradient
                                    ? const LinearGradient(
                                        colors: [
                                          WorkaColors.primaryBlue,
                                          WorkaColors.accentOrange,
                                        ],
                                      )
                                    : LinearGradient(colors: [accent, accent]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailingValue,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
