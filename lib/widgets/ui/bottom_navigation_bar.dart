import 'package:flutter/material.dart';

import '../worka_bottom_nav.dart';

class WorkaBottomNavigationBar extends StatelessWidget {
  const WorkaBottomNavigationBar({
    super.key,
    required this.currentIndex,
    this.onTap,
    this.onTabSelected,
  });

  final int currentIndex;
  final ValueChanged<int>? onTap;
  final ValueChanged<int>? onTabSelected;

  @override
  Widget build(BuildContext context) {
    return WorkaBottomNav(
      currentIndex: currentIndex,
      onTap: onTap,
      onTabSelected: onTabSelected,
    );
  }
}
