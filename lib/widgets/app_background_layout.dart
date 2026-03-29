import 'package:flutter/material.dart';

import 'app_background.dart';

class AppBackgroundLayout extends StatelessWidget {
  const AppBackgroundLayout({
    super.key,
    required this.header,
    required this.body,
    this.headerPadding = EdgeInsets.zero,
    this.bodyTopSpacing = 0,
    this.expandBody = true,
    this.showHeader = true,
  });

  final Widget header;
  final Widget body;
  final EdgeInsets headerPadding;
  final double bodyTopSpacing;
  final bool expandBody;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    if (!showHeader) {
      return AppBackground(child: body);
    }
    final bodyWidget = expandBody ? Expanded(child: body) : body;
    return AppBackground(
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(padding: headerPadding, child: header),
          ),
          if (bodyTopSpacing > 0) SizedBox(height: bodyTopSpacing),
          bodyWidget,
        ],
      ),
    );
  }
}
