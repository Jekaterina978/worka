import 'package:flutter/material.dart';

import '../screens/favorites_screen.dart';

class SavedTab extends StatelessWidget {
  const SavedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const FavoritesScreen(embeddedInShell: true);
  }
}
