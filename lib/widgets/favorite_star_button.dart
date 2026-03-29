import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';

class FavoriteStarButton extends StatelessWidget {
  const FavoriteStarButton({
    super.key,
    required this.isFavorite,
    this.onTap,
    this.tooltip,
    this.size = 30,
  });

  final bool isFavorite;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconColor = const Color(0xFFF59E0B);
    final icon = Icon(
      isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
      size: size,
      color: isFavorite
          ? iconColor
          : const Color(0xFFD3A157).withValues(alpha: 0.82),
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
    );

    final button = InkResponse(
      onTap: onTap,
      radius: 22,
      splashColor: WorkaColors.hoverBlue,
      highlightShape: BoxShape.circle,
      child: SizedBox(width: 40, height: 40, child: Center(child: icon)),
    );

    if ((tooltip ?? '').trim().isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
