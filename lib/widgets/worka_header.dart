import 'package:flutter/material.dart';

import 'profile_avatar_button.dart';

class WorkaHeader extends StatelessWidget {
  final String title;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget>? bottom;
  final bool showProfileAvatar;
  final bool testMode;

  const WorkaHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.bottom,
    this.showProfileAvatar = true,
    this.testMode = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (leading != null) leading!
                  else const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (trailing != null)
                    trailing!
                  else if (showProfileAvatar)
                    ProfileAvatarButton(testMode: testMode)
                  else
                    const SizedBox(width: 40),
                ],
              ),
            ),
            if (bottom != null) ...bottom!,
          ],
        ),
      );
  }
}
