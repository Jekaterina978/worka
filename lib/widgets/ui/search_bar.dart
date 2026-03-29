import 'package:flutter/material.dart';

import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';

class SearchBar extends StatelessWidget {
  const SearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.hintText = 'Кем?',
    this.height = 56,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: WorkaUiShadows.card,
      ),
      child: SizedBox(
        height: height,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(
            color: WorkaColors.textDark,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: WorkaColors.textGreyDark,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 24,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 14,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
