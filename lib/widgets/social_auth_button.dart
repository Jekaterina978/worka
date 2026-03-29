import 'package:flutter/material.dart';
import '../theme/worka_ui_tokens.dart';

class SocialAuthButton extends StatelessWidget {
  const SocialAuthButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WorkaUiRadius.button),
        border: Border.all(
          color: const Color(0xFFDCE1EB).withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: WorkaUiShadows.button,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: OutlinedButton(
          onPressed: onPressed,
          style:
              OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WorkaUiRadius.button),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 0,
                ),
              ).copyWith(
                elevation: const WidgetStatePropertyAll<double>(0),
                overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return const Color(0xFFEAF1FF);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return const Color(0xFFF4F7FC);
                  }
                  return null;
                }),
              ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: IconTheme(
                    data: const IconThemeData(size: 30),
                    child: icon,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: Color(0xFF1F2430),
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
