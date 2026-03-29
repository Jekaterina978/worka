import 'package:flutter/material.dart';

import '../../../widgets/cards/candidate_cv_card.dart';
import '../../../widgets/card_more_menu_button.dart';
import 'cv_card_formatters.dart';

enum CvCardAction { edit, copy, delete }

@Deprecated('Use CandidateCvCard from widgets/cards/candidate_cv_card.dart')
class CvCard extends StatelessWidget {
  final String fullName;
  final int? age;
  final dynamic birthDate;
  final String citizenshipCountry;
  final String profession;
  final String city;
  final String country;
  final String? countryFlag;
  final String salary;
  final String readiness;
  final List<String> badges;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? topRight;
  final List<CardMenuItem> menuItems;
  final String primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final bool selected;
  final String? avatarUrl;

  const CvCard({
    super.key,
    required this.fullName,
    required this.age,
    this.birthDate,
    this.citizenshipCountry = '',
    required this.profession,
    required this.city,
    required this.country,
    required this.salary,
    required this.readiness,
    required this.badges,
    required this.onTap,
    this.leading,
    this.topRight,
    this.menuItems = const <CardMenuItem>[],
    this.primaryActionLabel = 'Выделить CV',
    this.onPrimaryAction,
    this.selected = false,
    this.countryFlag,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedCitizenship =
        mapCitizenshipToDisplayValue(citizenshipCountry) ?? '';
    final salaryText = salary.trim().isEmpty ? '€ -' : salary.trim();
    final int? resolvedAge = age ?? calculateAgeFromBirthDate(birthDate);

    return CandidateCvCard(
      mode: CandidateCvCardMode.owner,
      fullName: fullName.trim().isEmpty ? 'Кандидат' : fullName.trim(),
      age: resolvedAge,
      citizenshipCountry: normalizedCitizenship,
      profession: profession.trim(),
      city: city.trim(),
      country: country.trim(),
      badges: badges,
      salary: salaryText,
      readiness: readiness.trim(),
      onTap: onTap,
      avatarUrl: avatarUrl,
      topRight:
          topRight ??
          (menuItems.isEmpty
              ? const SizedBox.shrink()
              : CardMoreMenuButton(items: menuItems)),
      menuItems: menuItems,
      primaryActionLabel: primaryActionLabel,
      onPrimaryAction: onPrimaryAction,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }
}
