import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'home_screen.dart';

/// ⚠️ Deprecated: EmployerShell больше не используется как отдельный контейнер.
/// Чтобы не было 2 разных shell’ов (и двойных панелей),
/// всегда используем AppShell, а работодатель — это просто другой homeRoot.
class EmployerShell extends StatelessWidget {
  final int initialIndex;
  const EmployerShell({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    // Мягкий редирект в AppShell (без второго контейнера)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShell(
            initialIndex: initialIndex,
            homeRoot: const HomeScreen(testMode: true),
          ),
        ),
      );
    });

    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}
