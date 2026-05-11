import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_guard.dart';
import '../services/firestore_paths.dart';
import '../services/ownership_context.dart';
import '../services/ownership_resolver.dart';
import '../services/vacancy_owner_scope_resolver.dart';
import '../theme/worka_colors.dart';
import '../utils/country_display_formatter.dart';
import '../features/payments/payments_routes.dart';
import 'favorite_star_button.dart';
import 'vacancy_cta_button.dart';

enum WorkaJobCardMode {
  search,
  readonlyStatus,
  owner,
  marketplace,
  status,
}

class WorkaJobCard extends StatelessWidget {
  const WorkaJobCard({
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
    this.highlight = false,
    this.priority = false,
    this.bump = false,
    this.contacts = false,
    this.paidUrgent = false,
    this.vacancyOwnerType,
    this.vacancyOwnerId,
    this.onTap,
    this.onApply,
    this.topRight,
    this.showApply = true,
    this.topRightReservedWidth = 56,
    this.footerLeading,
    this.salaryTrailing,
    this.employmentLabel = 'Полная занятость',
    this.applyLabel = 'ОТКЛИКНУТЬСЯ',
    this.bottomRight,
    this.salaryMainColor = WorkaColors.salaryAccent,
    this.verifiedEmployer = false,
    this.mode = WorkaJobCardMode.search,
    this.ownerAvatarUrl = '',
    this.ownerCompanyLogoUrl = '',
    this.ownerBusinessHint = false,
    this.vacancyOwnershipData,
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
  final bool highlight;
  final bool priority;
  final bool bump;
  final bool contacts;
  final bool paidUrgent;
  final String? vacancyOwnerType;
  final String? vacancyOwnerId;

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
  final String ownerAvatarUrl;
  final String ownerCompanyLogoUrl;
  final bool ownerBusinessHint;

  /// When set (marketplace cards), ownership uses explicit vacancy scope fields.
  final Map<String, dynamic>? vacancyOwnershipData;

  static const double _radius = 20;
  static const EdgeInsets _pad = EdgeInsets.all(16);

  bool get _isMarketplaceMode =>
      mode == WorkaJobCardMode.marketplace || mode == WorkaJobCardMode.search;
  bool get _isStatusMode =>
      mode == WorkaJobCardMode.status ||
      mode == WorkaJobCardMode.readonlyStatus;

  bool _viewerOwnsVacancy() {
    if (mode == WorkaJobCardMode.owner) return true;
    final snap = vacancyOwnershipData;
    if (snap != null && snap.isNotEmpty) {
      return OwnershipResolver.vacancyIsOwnedByCurrentViewer(snap);
    }
    final ot = (vacancyOwnerType ?? '').trim();
    if (ot.isEmpty) {
      return false;
    }
    final oid = (vacancyOwnerId ?? '').trim();
    final ouid = (ownerUid ?? '').trim();
    final r = OwnershipResolver.resolveVacancyViewerOwnership(
      ownerType: ot,
      ownerId: oid,
      ownerUid: ouid.isEmpty ? null : ouid,
      createdByUserId: null,
      companyId: null,
    );
    return r.known && r.isOwner;
  }

  Widget _paidPromotionBadge({
    required String label,
    required Color bg,
    required Color border,
    required Color fg,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 1.05,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  ({String entityOwnerType, String entityOwnerId}) _promotionEntityScope() {
    final snap = vacancyOwnershipData;
    if (snap != null && snap.isNotEmpty) {
      final resolved = VacancyOwnerScopeResolver.resolveVacancyOwnerScope(snap);
      if (resolved.isResolved) {
        if (resolved.ownerType == 'business') {
          final id = resolved.companyId.trim().isNotEmpty
              ? resolved.companyId.trim()
              : resolved.ownerId.trim();
          return (entityOwnerType: 'business', entityOwnerId: id);
        }
        return (
          entityOwnerType: 'personal',
          entityOwnerId: resolved.ownerId.trim(),
        );
      }
    }
    var ot = (vacancyOwnerType ?? '').trim().toLowerCase();
    final oid = (vacancyOwnerId ?? ownerUid ?? '').trim();
    if (ot == 'company') ot = 'business';
    if (ot == 'user') ot = 'personal';
    if (ot.isEmpty) ot = 'personal';
    return (entityOwnerType: ot, entityOwnerId: oid);
  }

  String _normalizeSalaryFallback(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    final hasCurrency =
        text.contains('€') ||
        text.contains(r'$') ||
        text.contains('₽') ||
        text.contains('£') ||
        text.toLowerCase().contains('eur');
    if (hasCurrency) return text;
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    final rangeMatch = RegExp(
      r'^(\d+[.,]?\d*)\s*[-–]\s*(\d+[.,]?\d*)$',
    ).firstMatch(text);
    if (rangeMatch != null) {
      return '€ ${rangeMatch.group(1)} – ${rangeMatch.group(2)}';
    }
    if (RegExp(r'^(от)\s+\d', caseSensitive: false).hasMatch(text)) {
      return text.replaceFirst(
        RegExp(r'^(от)\s+', caseSensitive: false),
        'от € ',
      );
    }
    if (RegExp(r'^(до)\s+\d', caseSensitive: false).hasMatch(text)) {
      return text.replaceFirst(
        RegExp(r'^(до)\s+', caseSensitive: false),
        'до € ',
      );
    }
    if (RegExp(r'^\d').hasMatch(text)) return '€ $text';
    return '€ —';
  }

  String _moneyCompact(double v) => '€${v.round()}';

  String _salaryDisplayShort() {
    final from = salaryFrom;
    final to = salaryTo;
    if (from != null && to != null && from > 0 && to > 0) {
      if (from == to) return _moneyCompact(from);
      return '${_moneyCompact(from)}–${_moneyCompact(to)}';
    }
    if (from != null && from > 0) return _moneyCompact(from);
    if (salaryTextFallback.trim().isNotEmpty) {
      final n = _normalizeSalaryFallback(salaryTextFallback);
      var s = n.replaceAll(' ', '');
      s = s.replaceFirst(RegExp(r'^от', caseSensitive: false), '');
      s = s.replaceFirst(RegExp(r'^до', caseSensitive: false), '');
      s = s.replaceAll('/мес', '').replaceAll('/час', '').trim();
      if (s.isEmpty || s == '€—') return '—';
      return s;
    }
    return '—';
  }

  String _salaryPeriodSecondary() {
    final t = salaryType.trim().toLowerCase();
    if (t.contains('hour') || t.contains('час')) return 'в час';
    return 'в месяц';
  }

  String _locationText() {
    final cityPart = city.trim();
    final countryPart = country.trim();

    if (cityPart.isEmpty && countryPart.isEmpty) {
      return 'Не указано';
    }
    final countryWithFlag = countryPart.isNotEmpty
        ? CountryDisplayFormatter.formatCountryWithLeadingEmoji(countryPart)
        : '';
    if (countryPart.isEmpty) {
      return cityPart;
    }
    if (cityPart.isEmpty) {
      return countryWithFlag;
    }
    return '$cityPart, $countryWithFlag';
  }

  static const int _maxVacancyConditionIconBadges = 4;

  Widget _iconOnlyConditionBadge({
    required IconData icon,
    required Color fill,
    required Color borderColor,
    required Color iconColor,
  }) {
    return Container(
      width: 30,
      height: 30,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: iconColor),
    );
  }

  Widget _iconOnlyOverflowBadge(int extraCount) {
    final n = extraCount.clamp(1, 99);
    return Container(
      width: 30,
      height: 30,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$n',
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          height: 1.0,
        ),
      ),
    );
  }

  List<Widget> _conditions() {
    final icons = <Widget>[];

    final schedule = employmentLabel.trim();
    if (schedule.isNotEmpty) {
      icons.add(
        _iconOnlyConditionBadge(
          icon: Icons.access_time_outlined,
          fill: const Color(0xFFEEF5FF),
          borderColor: const Color(0xFFD6E4FF),
          iconColor: const Color(0xFF2F6BFF),
        ),
      );
    }

    if (housingProvided) {
      icons.add(
        _iconOnlyConditionBadge(
          icon: Icons.home_outlined,
          fill: const Color(0xFFEAF8EE),
          borderColor: const Color(0xFFD5F0DC),
          iconColor: const Color(0xFF1A8F45),
        ),
      );
    }
    if (noExperienceRequired) {
      icons.add(
        _iconOnlyConditionBadge(
          icon: Icons.business_center_outlined,
          fill: const Color(0xFFFFF4E5),
          borderColor: const Color(0xFFFFE2B8),
          iconColor: const Color(0xFFF59E0B),
        ),
      );
    }
    if (noLanguageRequired) {
      icons.add(
        _iconOnlyConditionBadge(
          icon: Icons.translate_outlined,
          fill: const Color(0xFFF3EEFF),
          borderColor: const Color(0xFFE4D8FF),
          iconColor: const Color(0xFF7C3AED),
        ),
      );
    }
    if (transportProvided) {
      icons.add(
        _iconOnlyConditionBadge(
          icon: Icons.directions_car_outlined,
          fill: const Color(0xFFF3EEFF),
          borderColor: const Color(0xFFE4D8FF),
          iconColor: const Color(0xFF7C3AED),
        ),
      );
    }
    if (forTeenagers) {
      icons.add(
        _iconOnlyConditionBadge(
          icon: Icons.cake_outlined,
          fill: const Color(0xFFFFF7ED),
          borderColor: const Color(0xFFFFD8A8),
          iconColor: const Color(0xFFB45309),
        ),
      );
    }
    if (forDisabled) {
      icons.add(
        _iconOnlyConditionBadge(
          icon: Icons.accessible_outlined,
          fill: const Color(0xFFEFF6FF),
          borderColor: const Color(0xFFC7E2F5),
          iconColor: const Color(0xFF0369A1),
        ),
      );
    }
    if (kDebugMode) {
      debugPrint(
        '[JOB_BADGE_ROW_RENDER] '
        'jobId=${jobId.trim()} rawIcons=${icons.length} '
        'noLang=$noLanguageRequired noExp=$noExperienceRequired '
        'housing=$housingProvided transport=$transportProvided '
        'teens=$forTeenagers disabled=$forDisabled',
      );
    }
    if (icons.length <= _maxVacancyConditionIconBadges) {
      return icons;
    }
    final extra = icons.length - _maxVacancyConditionIconBadges;
    return <Widget>[
      ...icons.take(_maxVacancyConditionIconBadges),
      _iconOnlyOverflowBadge(extra),
    ];
  }

  bool get _isBusinessVacancy {
    if (ownerBusinessHint) return true;
    final ownerType = (vacancyOwnerType ?? '').trim().toLowerCase();
    if (ownerType == 'company' || ownerType == 'business') return true;
    return companyName.trim().isNotEmpty;
  }

  Widget _vacancyOwnerAvatar() {
    final logo = ownerCompanyLogoUrl.trim();
    final photo = ownerAvatarUrl.trim();
    final showBusiness = _isBusinessVacancy;
    final imageUrl = showBusiness
        ? (logo.isNotEmpty ? logo : photo)
        : (photo.isNotEmpty ? photo : logo);
    final fallbackIcon = showBusiness
        ? Icons.business_outlined
        : Icons.account_circle_outlined;
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD7E3FF), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                fallbackIcon,
                size: 34,
                color: WorkaColors.blue,
              ),
            )
          : Icon(
              fallbackIcon,
              size: 34,
              color: WorkaColors.blue,
            ),
    );
  }

  Widget _titleLocationSalaryBlock(
    BuildContext context, {
    required Widget rightAction,
    required bool viewerOwnsVacancy,
    required bool paidUrgent,
    required bool organicUrgent,
    bool priorityPromoActive = false,
    bool showContactsPromoActive = false,
    bool bumpPromoActive = false,
    required List<Widget> conditionChips,
    required List<Widget> paidPromotionBadges,
    required bool showViewerOwnVacancyBadge,
    required bool suppressSalaryPromoteButton,
    required bool highlightCard,
  }) {
    final hasActivePromotion =
        paidUrgent ||
        priorityPromoActive ||
        showContactsPromoActive ||
        bumpPromoActive ||
        organicUrgent ||
        highlightCard;
    final Widget? trailing = salaryTrailing ??
        (suppressSalaryPromoteButton
            ? null
            : _promoteButton(context, compact: hasActivePromotion));
    final hasTitle = title.trim().isNotEmpty;
    final showVacancyNumber =
        showVacancyNumberInOwnerView &&
        viewerOwnsVacancy &&
        vacancyNumber.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _vacancyOwnerAvatar(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  hasTitle
                      ? Text(
                          title.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                            letterSpacing: -0.2,
                          ),
                        )
                      : Container(
                          height: 16,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: WorkaColors.divider,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                  if (showViewerOwnVacancyBadge && _isMarketplaceMode) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF5FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF93C5FD)),
                      ),
                      child: const Text(
                        'Ваша вакансия',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                  ],
                  if (showVacancyNumber) ...[
                    const SizedBox(height: 6),
                    Text(
                      '№ ${vacancyNumber.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: WorkaColors.textGreyDark,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: WorkaColors.blue,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _locationText(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (paidPromotionBadges.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: paidPromotionBadges,
                    ),
                  ],
                  if (conditionChips.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < conditionChips.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          conditionChips[i],
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Align(alignment: Alignment.topRight, child: rightAction),
          ],
        ),
        if (trailing != null) ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ],
    );
  }

  Widget? _promoteButton(BuildContext context, {required bool compact}) {
    if (jobId.trim().isEmpty) return null;
    if (!_viewerOwnsVacancy()) return null;
    final scope = _promotionEntityScope();
    final ownerType = scope.entityOwnerType;
    final ownerId = scope.entityOwnerId;
    final scopeDecision = CanonicalOwnershipResolver.resolvePromotionAccess(
      entityOwnerType: ownerType,
      entityOwnerId: ownerId,
    );
    if (!scopeDecision.allowed) {
      void showBlocked() {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(PromotionOwnershipDecision.mismatchMessage),
          ),
        );
      }
      if (compact) {
        return Tooltip(
          message: PromotionOwnershipDecision.mismatchMessage,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: showBlocked,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: WorkaColors.textGreyDark.withValues(alpha: 0.35),
                  width: 1.1,
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.apartment_outlined,
                size: 16,
                color: WorkaColors.textGreyDark,
              ),
            ),
          ),
        );
      }
      return OutlinedButton(
        onPressed: showBlocked,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: WorkaColors.textGreyDark,
          side: BorderSide(
            color: WorkaColors.textGreyDark.withValues(alpha: 0.35),
            width: 1.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: const StadiumBorder(),
        ),
        child: const Text(
          'Продвижение',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: WorkaColors.textGreyDark,
          ),
        ),
      );
    }
    if (compact) {
      return Tooltip(
        message: 'Продвижение',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pushNamed(
              PaymentsRoutes.promoteJob,
              arguments: <String, dynamic>{
                'jobId': jobId.trim(),
                'ownerType': ownerType,
                'ownerId': ownerId,
              },
            );
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: WorkaColors.orange.withValues(alpha: 0.55),
                width: 1.1,
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.apartment_outlined,
              size: 16,
              color: WorkaColors.orange,
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.008),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: OutlinedButton(
        onPressed: () {
          Navigator.of(context, rootNavigator: true).pushNamed(
            PaymentsRoutes.promoteJob,
            arguments: <String, dynamic>{
              'jobId': jobId.trim(),
              'ownerType': ownerType,
              'ownerId': ownerId,
            },
          );
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: WorkaColors.orange,
          side: const BorderSide(color: WorkaColors.orange, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: const StadiumBorder(),
        ),
        child: const Text(
          'Продвижение',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: WorkaColors.orange,
          ),
        ),
      ),
    );
  }

  Widget _applyButton() {
    return VacancyCtaButton(
      kind: VacancyCtaKind.apply,
      label: applyLabel,
      onTap: onApply ?? onTap,
      showArrow: false,
    );
  }

  Widget _appliedBadge() {
    return const VacancyCtaButton(
      kind: VacancyCtaKind.sent,
      label: 'Отклик отправлен',
    );
  }

  Widget _bottomEmploymentBar({required bool hasApplied}) {
    final viewerOwns = _viewerOwnsVacancy();
    final canShowWorkerCta = showApply && !viewerOwns;
    final actionVisible = _isStatusMode
        ? false
        : (_isMarketplaceMode
              ? (bottomRight != null || canShowWorkerCta)
              : bottomRight != null);
    final Widget? action = _isStatusMode
        ? null
        : (bottomRight ??
              (canShowWorkerCta
                  ? (hasApplied ? _appliedBadge() : _applyButton())
                  : null));
    final hasSalary =
        ((salaryFrom ?? 0) > 0) ||
        ((salaryTo ?? 0) > 0) ||
        salaryTextFallback.trim().isNotEmpty;
    final salaryPrimary = _salaryDisplayShort();
    final salarySecondary = _salaryPeriodSecondary();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: hasSalary
              ? RichText(
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: salaryPrimary,
                        style: const TextStyle(
                          fontSize: 31,
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          color: WorkaColors.orange,
                          letterSpacing: -0.3,
                        ),
                      ),
                      TextSpan(
                        text: ' $salarySecondary',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: WorkaColors.divider,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
        ),
        if (actionVisible && action != null) ...[
          const SizedBox(width: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: Alignment.centerRight,
              child: bottomRight != null
                  ? action
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 38,
                          minWidth: 128,
                          maxWidth: 140,
                        ),
                        child: action,
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _shell(BuildContext context, {required bool hasApplied}) {
    final bool organicUrgent = isUrgent;
    final bumpEffective = bump;
    final priorityEffective = priority;
    final showContactsEffective = contacts;

    final viewerOwns = _viewerOwnsVacancy();
    final rightAction =
        topRight ??
        (_isMarketplaceMode
            ? const FavoriteStarButton(isFavorite: false, size: 30)
            : const SizedBox.shrink());
    final conditionChips = _isMarketplaceMode ? _conditions() : const <Widget>[];

    final entitlementPaidBadges = <Widget>[];
    if (highlight) {
      entitlementPaidBadges.add(
        _paidPromotionBadge(
          label: 'Выделено',
          bg: const Color(0xFFFFF7E8),
          border: const Color(0xFFF59E0B),
          fg: const Color(0xFFB45309),
          icon: Icons.auto_awesome_rounded,
        ),
      );
    }
    if (paidUrgent) {
      entitlementPaidBadges.add(
        _paidPromotionBadge(
          label: 'Срочно',
          bg: const Color(0xFFFFF1F2),
          border: const Color(0xFFF87171),
          fg: const Color(0xFFB91C1C),
          icon: Icons.flash_on_rounded,
        ),
      );
    }
    if (priorityEffective) {
      entitlementPaidBadges.add(
        _paidPromotionBadge(
          label: 'Приоритет',
          bg: const Color(0xFFF5F3FF),
          border: const Color(0xFFA78BFA),
          fg: const Color(0xFF5B21B6),
          icon: Icons.vertical_align_top_rounded,
        ),
      );
    }
    if (bumpEffective) {
      entitlementPaidBadges.add(
        _paidPromotionBadge(
          label: 'Поднято',
          bg: const Color(0xFFEFF6FF),
          border: const Color(0xFF60A5FA),
          fg: const Color(0xFF1D4ED8),
          icon: Icons.trending_up_rounded,
        ),
      );
    }
    if (showContactsEffective) {
      entitlementPaidBadges.add(
        _paidPromotionBadge(
          label: 'Контакты открыты',
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFF34D399),
          fg: const Color(0xFF047857),
          icon: Icons.contact_phone_outlined,
        ),
      );
    }

    final paidRowWidgets = <Widget>[...entitlementPaidBadges];
    if (organicUrgent && !paidUrgent) {
      paidRowWidgets.add(
        _paidPromotionBadge(
          label: 'Срочно',
          bg: const Color(0xFFF9FAFB),
          border: const Color(0xFFD1D5DB),
          fg: const Color(0xFF4B5563),
          icon: Icons.schedule_rounded,
        ),
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[JOB_PAID_BADGE_ROW_RENDER] '
        'jobId=${jobId.trim()} '
        'highlight=$highlight '
        'paidUrgent=$paidUrgent '
        'priority=$priorityEffective '
        'bump=$bumpEffective '
        'contacts=$showContactsEffective '
        'paidBadgeCount=${entitlementPaidBadges.length} '
        'organicUrgent=${organicUrgent && !paidUrgent}',
      );
    }

    final hl = highlight;
    final cardBorderColor =
        hl ? const Color(0xFFF59E0B) : const Color(0xFFEEF1F6);
    final cardBorderWidth = hl ? 2.0 : 1.0;

    return _PressScaleCard(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(
            color: cardBorderColor,
            width: cardBorderWidth,
          ),
          gradient: hl
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFFFFDF6),
                    Color(0xFFFFFFFF),
                  ],
                )
              : null,
          color: hl ? null : const Color(0xFFFFFFFF),
          boxShadow: [
            BoxShadow(
              color: hl
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.07),
              blurRadius: hl ? 16 : 12,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap ?? onApply,
              borderRadius: BorderRadius.circular(_radius),
              child: Padding(
                padding: _pad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _titleLocationSalaryBlock(
                      context,
                      rightAction: rightAction,
                      viewerOwnsVacancy: viewerOwns,
                      paidUrgent: paidUrgent,
                      organicUrgent: organicUrgent,
                      priorityPromoActive: priorityEffective,
                      showContactsPromoActive: showContactsEffective,
                      bumpPromoActive: bumpEffective,
                      conditionChips: conditionChips,
                      paidPromotionBadges: paidRowWidgets,
                      showViewerOwnVacancyBadge: viewerOwns,
                      suppressSalaryPromoteButton:
                          viewerOwns && bottomRight != null,
                      highlightCard: highlight,
                    ),
                    const SizedBox(height: 16),
                    _bottomEmploymentBar(hasApplied: hasApplied),
                    if (footerLeading != null) ...[
                      const SizedBox(height: 10),
                      footerLeading!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewerOwns = _viewerOwnsVacancy();
    final highlightFlag = highlight;
    final organicUrgentFlag = isUrgent;

    if (kDebugMode) {
      debugPrint(
        '[JOB_PROMO_RENDER] '
        'jobId=${jobId.trim()} highlight=$highlightFlag '
        'paidUrgent=$paidUrgent organicUrgent=$organicUrgentFlag '
        'combinedUrgent=${paidUrgent || organicUrgentFlag} '
        'priority=$priority bump=$bump contacts=$contacts',
      );
    }

    if (_isStatusMode || (!showApply && bottomRight == null)) {
      return _shell(context, hasApplied: false);
    }

    if (viewerOwns) {
      return _shell(context, hasApplied: false);
    }

    final uid = (candidateOwnerId?.trim().isNotEmpty ?? false)
        ? candidateOwnerId!.trim()
        : (AuthGuard.effectiveUidOrNull() ??
                  FirebaseAuth.instance.currentUser?.uid ??
                  '')
              .trim();
    final canCheck = jobId.trim().isNotEmpty && uid.isNotEmpty;

    if (!canCheck) {
      return _shell(context, hasApplied: false);
    }

    final stream = FirebaseFirestore.instance
        .collection(FirestorePaths.applications)
        .where('type', isEqualTo: 'apply')
        .where('applicantId', isEqualTo: uid)
        .where('vacancyId', isEqualTo: jobId.trim())
        .where(
          'status',
          whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
        )
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final hasApplied = (snap.data?.docs ?? const []).isNotEmpty;
        if (kDebugMode) {
          debugPrint(
            'WorkaJobCard badge query uid=$uid vacancyId=${jobId.trim()} count=${snap.data?.docs.length ?? 0}',
          );
        }
        return _shell(context, hasApplied: hasApplied);
      },
    );
  }
}

class _PressScaleCard extends StatefulWidget {
  const _PressScaleCard({required this.child});

  final Widget child;

  @override
  State<_PressScaleCard> createState() => _PressScaleCardState();
}

class _PressScaleCardState extends State<_PressScaleCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

