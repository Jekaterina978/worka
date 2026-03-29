import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';

class CardMenuItem {
  final String label;
  final VoidCallback onTap;

  const CardMenuItem({required this.label, required this.onTap});
}

class CardMoreMenuButton extends StatelessWidget {
  final List<CardMenuItem> items;

  const CardMoreMenuButton({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CardMenuItem>(
      icon: const Icon(Icons.more_vert, color: WorkaColors.textGreyDark),
      elevation: 8,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (item) => item.onTap(),
      itemBuilder: (_) => items
          .map(
            (item) => PopupMenuItem<CardMenuItem>(
              value: item,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                item.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: WorkaColors.textDark,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
