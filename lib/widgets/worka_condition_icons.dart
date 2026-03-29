import 'package:flutter/material.dart';

class JobConditions {
  const JobConditions({
    required this.housingProvided,
    required this.transportProvided,
    required this.forTeenagers,
    required this.forDisabled,
    this.isUrgent = false,
  });

  final bool housingProvided;
  final bool transportProvided;
  final bool forTeenagers;
  final bool forDisabled;
  final bool isUrgent;
}

class WorkaConditionIcons extends StatelessWidget {
  const WorkaConditionIcons({
    super.key,
    required this.conditions,
    this.size = 36,
    this.iconSize = 20,
    this.spacing = 10,
    this.runSpacing = 10,
    this.wrap = true,
    this.maxItems,
  });

  final JobConditions conditions;
  final double size;
  final double iconSize;
  final double spacing;
  final double runSpacing;
  final bool wrap;
  final int? maxItems;

  Widget _item({
    required String asset,
    required Color bgColor,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Image.asset(
          asset,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  List<Widget> _icons() {
    final out = <Widget>[];
    if (conditions.housingProvided) {
      out.add(
        _item(
          asset: 'assets/icons/icon_housing.png',
          bgColor: const Color(0xFFEAF0FF),
        ),
      );
    }
    if (conditions.transportProvided) {
      out.add(
        _item(
          asset: 'assets/icons/icon_transport.png',
          bgColor: const Color(0xFFE6F4F1),
        ),
      );
    }
    if (conditions.forTeenagers) {
      out.add(
        _item(
          asset: 'assets/icons/icon_teens.png',
          bgColor: const Color(0xFFF2ECFF),
        ),
      );
    }
    if (conditions.forDisabled) {
      out.add(
        _item(
          asset: 'assets/icons/icon_disabled.png',
          bgColor: const Color(0xFFEAF4FF),
        ),
      );
    }
    if (maxItems != null && maxItems! >= 0 && out.length > maxItems!) {
      return out.take(maxItems!).toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final icons = _icons();
    if (icons.isEmpty) return const SizedBox.shrink();

    if (wrap) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: icons,
      );
    }

    return Row(
      children: [
        for (var i = 0; i < icons.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          icons[i],
        ],
      ],
    );
  }
}
