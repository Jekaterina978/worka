import 'package:flutter/material.dart';
import 'package:worka/theme/worka_colors.dart';

import '../models/payment_product.dart';

class PaymentPackageTile extends StatelessWidget {
  const PaymentPackageTile({
    super.key,
    required this.product,
    required this.selected,
    required this.onTap,
    this.badgeText,
    this.badgeIcon,
    this.subtitleOverride,
  });

  final PaymentProduct product;
  final bool selected;
  final VoidCallback onTap;
  final String? badgeText;
  final IconData? badgeIcon;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final hasBadge = badgeText != null;
    final effectiveSubtitle = subtitleOverride ?? product.subtitle;

    final tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7EF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasBadge || selected
                ? WorkaColors.orange
                : WorkaColors.divider,
            width: hasBadge || selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: WorkaColors.orange.withValues(alpha: 0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (effectiveSubtitle.trim().isNotEmpty)
                    Text(
                      effectiveSubtitle,
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              product.priceLabel,
              style: const TextStyle(
                color: WorkaColors.orange,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );

    if (!hasBadge) return tile;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          top: -10,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: WorkaColors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badgeIcon != null) ...[
                  Icon(badgeIcon, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                ],
                Text(
                  badgeText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
