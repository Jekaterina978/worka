import 'package:flutter/material.dart';

import '../../theme/worka_colors.dart';

class HeaderBar extends StatelessWidget {
  const HeaderBar({
    super.key,
    required this.onMenuTap,
    required this.avatar,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  final VoidCallback onMenuTap;
  final Widget avatar;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Row(
        children: [
          IconButton(
            onPressed: onMenuTap,
            icon: const Icon(
              Icons.menu_rounded,
              size: 28,
              color: WorkaColors.textDark,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: WorkaColors.fieldBorder),
            ),
          ),
          const Spacer(),
          avatar,
        ],
      ),
    );
  }
}
