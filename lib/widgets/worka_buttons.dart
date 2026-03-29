import 'package:flutter/material.dart';
import '../theme/worka_colors.dart';
import '../theme/worka_ui_tokens.dart';

class WorkaOutlineOrangeButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  const WorkaOutlineOrangeButton({
    super.key,
    required this.text,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: WorkaColors.orange, width: 1.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkaUiRadius.control),
        ),
        padding: padding,
      ),
      child: const _WorkaLoginLikeText(''),
    ).copyWithChild(
      Text(
        text,
        style: const TextStyle(
          fontSize: 17, // как linkStyle на StartScreen (у тебя 17*s)
          fontWeight: FontWeight.w500,
          color: WorkaColors.orange,
        ),
      ),
    );
  }
}

/// маленький хак, чтобы не плодить дублирующий стиль через const (можно удалить, если не нравится)
extension _BtnChild on OutlinedButton {
  Widget copyWithChild(Widget child) {
    return Builder(
      builder: (context) {
        final b = this;
        return OutlinedButton(
          onPressed: b.onPressed,
          style: b.style,
          child: child,
        );
      },
    );
  }
}

class _WorkaLoginLikeText extends StatelessWidget {
  final String t;
  const _WorkaLoginLikeText(this.t);

  @override
  Widget build(BuildContext context) {
    return Text(
      t,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: WorkaColors.orange,
      ),
    );
  }
}
