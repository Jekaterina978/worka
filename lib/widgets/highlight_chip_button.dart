import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';

class HighlightChipButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool small;

  const HighlightChipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.small = true,
  });

  @override
  Widget build(BuildContext context) {
    final vertical = small ? 7.0 : 10.0;
    final horizontal = small ? 14.0 : 18.0;
    final fontSize = small ? 12.0 : 14.0;

    return SizedBox(
      height: small ? 34 : 40,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: WorkaColors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: vertical,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}
