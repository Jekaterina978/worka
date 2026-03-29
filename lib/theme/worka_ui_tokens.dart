import 'package:flutter/material.dart';
import 'worka_colors.dart';

class WorkaUiRadius {
  static const double header = 32;
  static const double container = 24;
  static const double card = 20;
  static const double floatingCard = 18;
  static const double button = 20;
  static const double control = 20;
  static const double segmented = 20;
  static const double chip = 12;
}

class WorkaUiShadows {
  static const BoxShadow single = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 14,
    offset: Offset(0, 6),
  );

  static const BoxShadow navbarSingle = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.05), // rgba(0,0,0,0.05)
    blurRadius: 8,
    offset: Offset(0, -2),
  );

  static const List<BoxShadow> card = [single];
  static const List<BoxShadow> button = [single];
  static const List<BoxShadow> tabs = [single];
  static const List<BoxShadow> navbar = [navbarSingle];
}

class WorkaButtonStyles {
  static final RoundedRectangleBorder _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(WorkaUiRadius.control),
  );

  static ButtonStyle primaryBlue({
    bool enabled = true,
    EdgeInsetsGeometry? padding,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: WorkaColors.blue,
      disabledBackgroundColor: WorkaColors.blue.withValues(alpha: 0.35),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: _shape,
      padding: padding,
    );
  }

  static ButtonStyle primaryOrange({
    bool enabled = true,
    EdgeInsetsGeometry? padding,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: WorkaColors.orange,
      disabledBackgroundColor: WorkaColors.orange.withValues(alpha: 0.35),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: _shape,
      padding: padding,
    );
  }

  static ButtonStyle outlineBlue({EdgeInsetsGeometry? padding}) {
    return OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      side: const BorderSide(color: WorkaColors.blue, width: 1.2),
      shape: _shape,
      padding: padding,
    );
  }

  static ButtonStyle outlineNeutral({EdgeInsetsGeometry? padding}) {
    return OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      side: const BorderSide(color: WorkaColors.fieldBorder, width: 1.2),
      shape: _shape,
      padding: padding,
    );
  }
}

class WorkaSegmentedStyles {
  static BoxDecoration container({
    Color color = Colors.white,
    BorderSide? borderSide,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(WorkaUiRadius.segmented),
      border: borderSide == null ? null : Border.fromBorderSide(borderSide),
      boxShadow: WorkaUiShadows.tabs,
    );
  }

  static BoxDecoration segment({
    required bool selected,
    Color selectedColor = WorkaColors.orange,
  }) {
    return BoxDecoration(
      color: selected ? selectedColor : Colors.transparent,
      borderRadius: BorderRadius.circular(WorkaUiRadius.segmented),
      boxShadow: selected ? WorkaUiShadows.button : null,
    );
  }
}
