import 'package:flutter/material.dart';

import '../../theme/worka_colors.dart';

class FilterChipRowItem {
  const FilterChipRowItem({
    required this.label,
    required this.icon,
    this.iconWidget,
    this.iconColor,
    this.labelColor,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final Widget? iconWidget;
  final Color? iconColor;
  final Color? labelColor;
  final bool selected;
  final ValueChanged<bool> onSelected;
}

class FilterChipRow extends StatelessWidget {
  const FilterChipRow({super.key, required this.items});

  final List<FilterChipRowItem> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
              ),
              child: FilterChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(
                  horizontal: -2,
                  vertical: -2,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    items[i].iconWidget ??
                        Icon(
                          items[i].icon,
                          size: 16,
                          color: items[i].iconColor ?? WorkaColors.blue,
                        ),
                    const SizedBox(width: 6),
                    Text(
                      items[i].label,
                      style: TextStyle(
                        color: items[i].labelColor ?? WorkaColors.blue,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                selected: items[i].selected,
                onSelected: items[i].onSelected,
                selectedColor: WorkaColors.blue.withValues(alpha: 0.14),
                backgroundColor: Colors.white,
                checkmarkColor: WorkaColors.blue,
                side: BorderSide(
                  color: WorkaColors.divider.withValues(alpha: 0.60),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
