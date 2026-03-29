import 'package:flutter/material.dart';

/// Unified app background based on Home screen gradient.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF4F6EDB), Color(0xFF3F63D0)],
  );

  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF4A6FDB), Color(0xFF5B7FE8)],
  );

  @override
  Widget build(BuildContext context) {
    if (_AppBackgroundScope.maybeOf(context) != null) {
      return child;
    }
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: gradient),
      child: _AppBackgroundScope(child: child),
    );
  }
}

class _AppBackgroundScope extends InheritedWidget {
  const _AppBackgroundScope({required super.child});

  static _AppBackgroundScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_AppBackgroundScope>();
  }

  @override
  bool updateShouldNotify(_AppBackgroundScope oldWidget) => false;
}
