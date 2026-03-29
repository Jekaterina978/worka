import 'package:flutter/material.dart';
import '../theme/worka_colors.dart';

class UserBadgeWithBell extends StatelessWidget {
  final String initials;
  final bool showBell;
  final double size;
  final VoidCallback? onTap;

  const UserBadgeWithBell({
    super.key,
    required this.initials,
    required this.showBell,
    this.size = 34,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: WorkaColors.blue, width: 1.6),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: WorkaColors.blue,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.38,
          height: 1.0,
        ),
      ),
    );

    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        badge,
        if (showBell)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: size * 0.42,
              height: size * 0.42,
              decoration: const BoxDecoration(
                color: WorkaColors.orange,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications,
                size: size * 0.26,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }
}