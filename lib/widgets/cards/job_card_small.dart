import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/paid_entitlements_controller.dart';
import '../worka_job_card.dart';

class JobCardSmall extends StatelessWidget {
  const JobCardSmall({
    super.key,
    required this.title,
    this.companyName = '',
    this.vacancyNumber = '',
    this.showVacancyNumberInOwnerView = false,
    required this.city,
    required this.country,
    required this.salaryFrom,
    required this.salaryTo,
    required this.salaryType,
    required this.salaryTextFallback,
    required this.housingProvided,
    required this.transportProvided,
    required this.forTeenagers,
    required this.forDisabled,
    required this.isUrgent,
    this.noLanguageRequired = false,
    this.noExperienceRequired = false,
    required this.jobId,
    this.candidateOwnerId,
    this.ownerUid,
    this.ownerEmail,
    this.onTap,
    this.onApply,
    this.topRight,
    this.showApply = true,
    this.topRightReservedWidth = 56,
    this.footerLeading,
    this.salaryTrailing,
    this.employmentLabel = 'Полная занятость',
    this.applyLabel = 'Взять работу',
    this.bottomRight,
    this.salaryMainColor = const Color(0xFF1D3475),
    this.verifiedEmployer = false,
    this.mode = WorkaJobCardMode.search,
  });

  final String title;
  final String companyName;
  final String vacancyNumber;
  final bool showVacancyNumberInOwnerView;
  final String city;
  final String country;
  final double? salaryFrom;
  final double? salaryTo;
  final String salaryType;
  final String salaryTextFallback;
  final bool housingProvided;
  final bool transportProvided;
  final bool forTeenagers;
  final bool forDisabled;
  final bool isUrgent;
  final bool noLanguageRequired;
  final bool noExperienceRequired;
  final String jobId;
  final String? candidateOwnerId;
  final String? ownerUid;
  final String? ownerEmail;
  final VoidCallback? onTap;
  final VoidCallback? onApply;
  final Widget? topRight;
  final bool showApply;
  final double topRightReservedWidth;
  final Widget? footerLeading;
  final Widget? salaryTrailing;
  final String employmentLabel;
  final String applyLabel;
  final Widget? bottomRight;
  final Color salaryMainColor;
  final bool verifiedEmployer;
  final WorkaJobCardMode mode;

  @override
  Widget build(BuildContext context) {
    final safeJobId = jobId.trim();
    final paid = context.watch<PaidEntitlementsController>();
    if (safeJobId.isNotEmpty && paid.jobEntitlementsById[safeJobId] == null) {
      Future.microtask(() => paid.refreshJobEntitlements(safeJobId));
    }
    final highlight = paid.hasJobFeature(safeJobId, 'highlight');
    final urgentFlag = paid.hasJobFeature(safeJobId, 'urgent') || isUrgent;
    final hasContacts = paid.hasJobFeature(safeJobId, 'show_contacts');

    return WorkaJobCard(
      title: title,
      companyName: companyName,
      vacancyNumber: vacancyNumber,
      showVacancyNumberInOwnerView: showVacancyNumberInOwnerView,
      city: city,
      country: country,
      salaryFrom: salaryFrom,
      salaryTo: salaryTo,
      salaryType: salaryType,
      salaryTextFallback: salaryTextFallback,
      housingProvided: housingProvided,
      transportProvided: transportProvided,
      forTeenagers: forTeenagers,
      forDisabled: forDisabled,
      isUrgent: urgentFlag,
      noLanguageRequired: noLanguageRequired,
      noExperienceRequired: noExperienceRequired,
      jobId: jobId,
      candidateOwnerId: candidateOwnerId,
      ownerUid: ownerUid,
      ownerEmail: ownerEmail,
      onTap: onTap,
      onApply: onApply,
      topRight:
          topRight ??
          (hasContacts
              ? const Chip(
                  label: Text('Контакты доступны'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                )
              : null),
      showApply: showApply,
      topRightReservedWidth: topRightReservedWidth,
      footerLeading: footerLeading,
      salaryTrailing: salaryTrailing,
      employmentLabel: employmentLabel,
      applyLabel: applyLabel,
      bottomRight: bottomRight,
      salaryMainColor: salaryMainColor,
      verifiedEmployer: verifiedEmployer,
      mode: mode,
      highlight: highlight,
    );
  }
}
