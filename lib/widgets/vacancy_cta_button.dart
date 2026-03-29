import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';
import '../theme/worka_ui_tokens.dart';

enum VacancyCtaKind { apply, sent }

class VacancyCtaButton extends StatefulWidget {
  const VacancyCtaButton({
    super.key,
    required this.kind,
    required this.label,
    this.onTap,
    this.showArrow = false,
  });

  final VacancyCtaKind kind;
  final String label;
  final VoidCallback? onTap;
  final bool showArrow;

  @override
  State<VacancyCtaButton> createState() => _VacancyCtaButtonState();
}

class _VacancyCtaButtonState extends State<VacancyCtaButton> {
  bool _pressed = false;

  bool get _interactive =>
      widget.onTap != null && widget.kind == VacancyCtaKind.apply;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isApply = widget.kind == VacancyCtaKind.apply;
    final color = isApply ? WorkaColors.orange : WorkaColors.blue;
    final borderRadius = BorderRadius.circular(WorkaUiRadius.control);

    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Transform.translate(
        offset: const Offset(0, -1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.25,
                ),
              ),
            ),
            if (isApply && widget.showArrow) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );

    final applyDecoratedChild = Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: _pressed
                ? [
                    WorkaColors.orange.withValues(alpha: 0.95),
                    WorkaColors.orange.withValues(alpha: 0.90),
                    WorkaColors.orange.withValues(alpha: 0.85),
                  ]
                : [
                    WorkaColors.orange.withValues(alpha: 1.0),
                    WorkaColors.orange.withValues(alpha: 0.95),
                    WorkaColors.orange.withValues(alpha: 0.90),
                  ],
          ),
          borderRadius: borderRadius,
          boxShadow: WorkaUiShadows.button,
        ),
        child: child,
      ),
    );

    if (!isApply) {
      return Material(color: color, borderRadius: borderRadius, child: child);
    }

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: _interactive
          ? InkWell(
              borderRadius: borderRadius,
              onTap: widget.onTap,
              splashColor: Colors.black.withValues(alpha: 0.08),
              highlightColor: Colors.black.withValues(alpha: 0.12),
              child: applyDecoratedChild,
            )
          : applyDecoratedChild,
    );
  }
}
