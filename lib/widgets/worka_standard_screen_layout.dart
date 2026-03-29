import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_background_layout.dart';

/// Standard non-Home/Favorites screen composition:
/// 1) full-screen gradient background
/// 2) header overlay
/// 3) gray content container
class WorkaStandardScreenLayout extends StatelessWidget {
  const WorkaStandardScreenLayout({
    super.key,
    required this.header,
    required this.body,
    this.headerPadding = EdgeInsets.zero,
    this.bodyTopRadius = 24,
    this.bodyColor = Colors.white,
    this.bodyTopSpacing = 0,
  });

  final Widget header;
  final Widget body;
  final EdgeInsetsGeometry headerPadding;
  final double bodyTopRadius;
  final Color bodyColor;
  final double bodyTopSpacing;

  @override
  Widget build(BuildContext context) {
    final Widget bodyChild = bodyTopSpacing > 0
        ? Padding(
            padding: EdgeInsets.only(top: bodyTopSpacing),
            child: body,
          )
        : body;

    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: AppBackground.gradient),
          ),
        ),
        Positioned.fill(
          child: AppBackgroundLayout(
            headerPadding: headerPadding.resolve(Directionality.of(context)),
            header: header,
            body: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: bodyColor,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(bodyTopRadius),
                ),
              ),
              child: bodyChild,
            ),
          ),
        ),
      ],
    );
  }
}
