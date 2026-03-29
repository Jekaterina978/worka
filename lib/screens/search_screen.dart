import 'package:flutter/material.dart';
import 'search/search_screen.dart' as v2;

class SearchScreen extends StatelessWidget {
  final bool testMode;

  const SearchScreen({super.key, this.testMode = true});

  @override
  Widget build(BuildContext context) {
    return v2.SearchScreen(testMode: testMode);
  }
}
