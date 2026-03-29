import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class FilterUi {
  static ThemeData whiteTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
      splashColor: WorkaColors.hoverBlue,
      hoverColor: WorkaColors.hoverBlue,
      highlightColor: WorkaColors.hoverBlue,
      colorScheme: base.colorScheme.copyWith(
        surface: Colors.white,
        onSurface: WorkaColors.textGreyDark,
        primary: WorkaColors.blue,
      ),
    );
  }

  static InputDecoration fieldDeco({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: WorkaColors.textGrey, fontWeight: FontWeight.w800),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.blue, width: 2), // ✅ синий контур
      ),
    );
  }

  static Widget dropRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final isAll = value == 'Все';
    final valueColor = isAll ? WorkaColors.textGrey : WorkaColors.textGreyDark;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      hoverColor: WorkaColors.hoverBlue,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WorkaColors.fieldBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  children: [
                    TextSpan(text: '$label: ', style: const TextStyle(color: WorkaColors.textGreyDark)),
                    TextSpan(text: value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: WorkaColors.textGreyDark),
          ],
        ),
      ),
    );
  }

  static Widget inlineDropdown<T>({
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: Colors.white,
          iconEnabledColor: WorkaColors.textGreyDark,
          style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w900),
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(e.toString(), style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w900)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  static Widget switchRow({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
      ),
      contentPadding: EdgeInsets.zero,
      activeTrackColor: WorkaColors.orange,
      inactiveTrackColor: const Color(0xFFE0E0E0),
    );
  }
}
