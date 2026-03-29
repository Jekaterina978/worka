import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';

class StatusPillBadge extends StatelessWidget {
  const StatusPillBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor = Colors.white,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.fontSize = 12,
  });

  final String label;
  final Color? backgroundColor;
  final Color textColor;
  final EdgeInsets padding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? WorkaColors.blue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: fontSize,
        ),
      ),
    );
  }
}
