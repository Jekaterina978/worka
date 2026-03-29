import 'package:flutter/material.dart';
import '../theme/worka_colors.dart';

class WorkaBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;
  final ValueChanged<int>? onTabSelected;

  const WorkaBottomNav({
    super.key,
    required this.currentIndex,
    this.onTap,
    this.onTabSelected,
  }) : assert(onTap != null || onTabSelected != null);

  ValueChanged<int> get _onSelect => onTabSelected ?? onTap!;

  @override
  Widget build(BuildContext context) {
    final activeColor = WorkaColors.orange;
    final inactiveColor = const Color(0xFF5F6F90);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
        child: SizedBox(
          key: const Key('worka_bottom_nav'),
          height: 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Item(
                active: currentIndex == 0,
                label: 'Домой',
                icon: Icons.home_rounded,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onSelect(0),
              ),
              _Item(
                active: currentIndex == 1,
                label: 'Избранное',
                icon: Icons.star_outline_rounded,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onSelect(1),
              ),
              _Item(
                active: currentIndex == 2,
                label: 'Профиль',
                icon: Icons.person_outline_rounded,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onSelect(2),
              ),
              _Item(
                active: currentIndex == 3,
                label: 'Связь',
                icon: Icons.mail_outline_rounded,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onSelect(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatefulWidget {
  final bool active;
  final String label;
  final IconData icon;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _Item({
    required this.active,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? widget.activeColor : widget.inactiveColor;
    final labelStyle = Theme.of(context).textTheme.labelSmall;

    return Expanded(
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: _pressed ? 0.96 : 1.0,
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 20, color: color),
              const SizedBox(height: 1),
              Text(
                widget.label,
                style: (labelStyle ?? const TextStyle(fontSize: 11.5)).copyWith(
                  fontSize: 11.5,
                  color: color,
                  fontWeight: widget.active ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
