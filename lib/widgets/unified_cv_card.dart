import 'package:flutter/material.dart';

import '../screens/cv/widgets/cv_card_formatters.dart';
import '../theme/worka_colors.dart';

@Deprecated('Use CandidateCvCard from widgets/cards/candidate_cv_card.dart')
class UnifiedCvCard extends StatelessWidget {
  final String fullName;
  final DateTime? birthDate;
  final String? citizenshipCountry;
  final String profession;
  final String? city;
  final String? country;
  final List<String> languageBadges;
  final bool hasComputerSkills;
  final List<String> drivingLicenseCategories;
  final bool hasCar;
  final bool hasTools;
  final bool hasWorkwear;
  final String? salaryText;
  final String? availabilityText;
  final String? initials;
  final String? avatarUrl;
  final VoidCallback? onHighlightTap;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;
  final String? cvId;

  const UnifiedCvCard({
    super.key,
    required this.fullName,
    required this.birthDate,
    required this.citizenshipCountry,
    required this.profession,
    required this.city,
    required this.country,
    required this.languageBadges,
    required this.hasComputerSkills,
    required this.drivingLicenseCategories,
    required this.hasCar,
    required this.hasTools,
    required this.hasWorkwear,
    required this.salaryText,
    required this.availabilityText,
    this.initials,
    this.avatarUrl,
    this.onHighlightTap,
    this.onEdit,
    this.onCopy,
    this.onDelete,
    this.cvId,
  });

  @override
  Widget build(BuildContext context) {
    final age = birthDate == null
        ? null
        : calculateAgeFromBirthDate(birthDate!);
    final citizenship = mapCitizenshipToDisplayValue(citizenshipCountry);

    final topLineParts = <String>[
      fullName,
      if (age != null) age.toString(),
      if (citizenship != null && citizenship.isNotEmpty) citizenship,
    ];

    final locationParts = <String>[
      if (city != null && city!.trim().isNotEmpty) city!.trim(),
      if (country != null && country!.trim().isNotEmpty) country!.trim(),
    ];

    final locationText = locationParts.isEmpty
        ? null
        : locationParts.join(', ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 8),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(initials: initials, avatarUrl: avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topLineParts.join(' • '),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2F5BFF),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profession,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667085),
                      ),
                    ),
                    if (locationText != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Color(0xFF98A2B3),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              locationText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF667085),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFF667085)),
                onSelected: (value) {
                  if (value == 'edit') onEdit?.call();
                  if (value == 'copy') onCopy?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Изменить')),
                  PopupMenuItem(value: 'copy', child: Text('Копировать')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final badge in languageBadges) _TextBadge(text: badge),
              if (hasComputerSkills)
                const _IconBadge(icon: Icons.computer_outlined),
              for (final license in drivingLicenseCategories.where(
                (e) => e.trim().isNotEmpty,
              ))
                _TextBadge(text: license.trim().toUpperCase()),
              if (hasCar) const _IconBadge(icon: Icons.directions_car_outlined),
              if (hasTools) const _IconBadge(icon: Icons.handyman_outlined),
              if (hasWorkwear) const _IconBadge(icon: Icons.checkroom_outlined),
            ],
          ),
          if (salaryText != null && salaryText!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              salaryText!.trim(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFFFF8A00),
              ),
            ),
          ],
          if (availabilityText != null &&
              availabilityText!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              availabilityText!.trim(),
              style: const TextStyle(fontSize: 14, color: Color(0xFF667085)),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                final id = cvId?.trim() ?? '';
                if (id.isEmpty) {
                  debugPrint(
                    '[CV PAYWALL] blocked: missing cvId source=home_card',
                  );
                  return;
                }
                debugPrint('[CV PAYWALL] source=home_card cvId=$id');
                CvHighlightPaywallSheet.open(context, cvId: id);
                if (onHighlightTap != null) onHighlightTap!.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: WorkaColors.orange, width: 1.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Выделить CV',
                  style: TextStyle(
                    color: WorkaColors.orange,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? initials;
  final String? avatarUrl;

  const _Avatar({this.initials, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: NetworkImage(avatarUrl!),
      );
    }

    return CircleAvatar(
      radius: 26,
      backgroundColor: const Color(0xFFE8EEFF),
      child: Text(
        (initials == null || initials!.trim().isEmpty) ? '?' : initials!.trim(),
        style: const TextStyle(
          color: Color(0xFF4A6CF7),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TextBadge extends StatelessWidget {
  final String text;

  const _TextBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF667085),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;

  const _IconBadge({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(icon, size: 18, color: const Color(0xFF667085)),
    );
  }
}
