import 'package:flutter/material.dart';
import 'package:worka/services/favorites_bus.dart';
import '../theme/worka_colors.dart';
import '../widgets/worka_bottom_nav.dart';

import 'start_screen.dart';
import 'favorites_screen.dart';
import 'profile_screen.dart';
import 'contact_screen.dart';

// worker/employer roots (для определения режима)
import 'search/search_screen.dart';
import 'employer/candidate_search_screen.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;
  final Widget homeRoot;

  const AppShell({
    super.key,
    this.initialIndex = 0,
    required this.homeRoot,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;
  final _navKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  bool get _isEmployerMode => widget.homeRoot is CandidateSearchScreen;
  FavoritesEntry get _entry => _isEmployerMode ? FavoritesEntry.employer : FavoritesEntry.worker;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 3);
  }

  void _exitToStart() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const StartScreen()),
      (route) => false,
    );
  }

  void _onTap(int i) {
    // ✅ "Домой" = выйти в StartScreen
    if (i == 0) {
      _exitToStart();
      return;
    }

    // ✅ ВАЖНО: при открытии "Избранное" форсим перечитку локальных данных,
    // чтобы ⭐ отображались сразу (IndexedStack держит таб живым).
    if (i == 1) {
      FavoritesBus.notify();
    }

    if (i == _index) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _index = i);
  }

  Future<bool> _onWillPop() async {
    final nav = _navKeys[_index].currentState;
    if (nav == null) return true;

    if (nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  Widget _tabNavigator({required int tabIndex, required Widget root}) {
    return Navigator(
      key: _navKeys[tabIndex],
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: WorkaColors.bg,
        bottomNavigationBar: WorkaBottomNav(currentIndex: _index, onTap: _onTap),
        body: IndexedStack(
          index: _index,
          children: [
            _tabNavigator(tabIndex: 0, root: widget.homeRoot),
            _tabNavigator(tabIndex: 1, root: FavoritesScreen(entry: _entry)),
            _tabNavigator(tabIndex: 2, root: const ProfileScreen()),
            _tabNavigator(tabIndex: 3, root: const ContactScreen()),
          ],
        ),
      ),
    );
  }
}
