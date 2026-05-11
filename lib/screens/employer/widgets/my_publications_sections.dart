import 'package:flutter/material.dart';

import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:worka/theme/worka_ui_tokens.dart';
import 'package:worka/widgets/card_more_menu_button.dart';
import 'package:worka/widgets/cards/vacancy_list_card.dart';
import 'package:worka/widgets/worka_job_card.dart';

enum JobCardAction { edit, promote, copy, moveProfile, delete }

class StatsInfoBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const StatsInfoBanner({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: WorkaColors.textDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: onRetry,
                child: const Text(
                  'Повторить',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DraftJobCard extends StatelessWidget {
  final String title;
  final String city;
  final String country;
  final VoidCallback onContinue;

  const DraftJobCard({
    super.key,
    required this.title,
    required this.city,
    required this.country,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final location = [
      city.trim(),
      country.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WorkaColors.fieldBorder),
        boxShadow: WorkaUiShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.edit_outlined,
                color: WorkaColors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Не закончено',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: WorkaColors.orange,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onContinue,
                child: const Text(
                  'Дополнить',
                  style: TextStyle(
                    color: WorkaColors.blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: WorkaColors.textDark,
            ),
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              location,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: WorkaColors.textGreyDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  final String jobId;
  final String title;
  final String vacancyNumber;
  final String ownerUid;
  final String ownerEmail;
  final String currentUserUid;
  final Map<String, dynamic> vacancySnapshot;
  final String city;
  final String country;
  final String salary;
  final double? salaryFrom;
  final double? salaryTo;
  final String salaryType;
  final String employmentLabel;
  final bool housingProvided;
  final bool transportProvided;
  final bool forTeenagers;
  final bool forDisabled;
  final bool isUrgent;
  final VoidCallback onOpen;
  final VoidCallback onHighlight;
  final String promotionLabel;
  final ValueChanged<JobCardAction> onAction;

  const JobCard({
    super.key,
    required this.jobId,
    required this.title,
    required this.vacancyNumber,
    required this.ownerUid,
    required this.ownerEmail,
    required this.currentUserUid,
    required this.vacancySnapshot,
    required this.city,
    required this.country,
    required this.salary,
    required this.salaryFrom,
    required this.salaryTo,
    required this.salaryType,
    required this.employmentLabel,
    required this.housingProvided,
    required this.transportProvided,
    required this.forTeenagers,
    required this.forDisabled,
    required this.isUrgent,
    required this.onOpen,
    required this.onHighlight,
    required this.promotionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final ownership = OwnershipResolver.vacancyViewerOwnership(
      vacancySnapshot,
      viewerUid: currentUserUid.trim(),
    );
    final isOwner = ownership.known && ownership.isOwner;
    return VacancyListCard(
      mode: WorkaJobCardMode.owner,
      title: title,
      vacancyNumber: vacancyNumber,
      showVacancyNumberInOwnerView: true,
      city: city,
      country: country,
      salaryFrom: salaryFrom,
      salaryTo: salaryTo,
      salaryType: salaryType,
      salaryTextFallback: salary,
      employmentLabel: employmentLabel,
      housingProvided: housingProvided,
      transportProvided: transportProvided,
      forTeenagers: forTeenagers,
      forDisabled: forDisabled,
      isUrgent: isUrgent,
      jobId: jobId,
      ownerUid: ownerUid,
      ownerEmail: ownerEmail,
      vacancyOwnershipData: Map<String, dynamic>.from(vacancySnapshot),
      vacancyOwnerType:
          (vacancySnapshot['ownerType'] ?? vacancySnapshot['vacancyOwnerType'])
              ?.toString(),
      vacancyOwnerId: ownerUid.isNotEmpty ? ownerUid : null,
      onTap: onOpen,
      showApply: false,
      salaryTrailing: isOwner
          ? SizedBox(
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.17),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: OutlinedButton(
                  onPressed: onHighlight,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: WorkaColors.orange,
                    side: const BorderSide(
                      color: WorkaColors.orange,
                      width: 1.2,
                    ),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'Продвижение вакансии',
                    style: TextStyle(
                      color: WorkaColors.orange,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            )
          : null,
      footerLeading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (promotionLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: WorkaColors.hoverBlueSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: WorkaColors.fieldBorder),
              ),
              child: Text(
                promotionLabel,
                style: const TextStyle(
                  color: WorkaColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      topRight: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CardMoreMenuButton(
            items: [
              CardMenuItem(
                label: 'Изменить',
                onTap: () => onAction(JobCardAction.edit),
              ),
              CardMenuItem(
                label: 'Продвинуть',
                onTap: () => onAction(JobCardAction.promote),
              ),
              CardMenuItem(
                label: 'Копировать',
                onTap: () => onAction(JobCardAction.copy),
              ),
              CardMenuItem(
                label: 'Перенести в другой профиль',
                onTap: () => onAction(JobCardAction.moveProfile),
              ),
              CardMenuItem(
                label: 'Удалить',
                onTap: () => onAction(JobCardAction.delete),
              ),
            ],
          ),
        ],
      ),
      topRightReservedWidth: 92,
    );
  }
}
