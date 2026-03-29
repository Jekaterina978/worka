import 'package:flutter/material.dart';

import '../screens/favorites_screen.dart';

class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab>
    with AutomaticKeepAliveClientMixin<FavoritesTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const KeyedSubtree(
      key: Key('favorites_content'),
      child: FavoritesScreen(embeddedInShell: true),
    );
  }
}
