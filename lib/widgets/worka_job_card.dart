import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_guard.dart';
import '../services/firestore_paths.dart';
import '../services/ownership_resolver.dart';
import '../theme/worka_colors.dart';
import '../theme/worka_ui_tokens.dart';
import '../features/payments/payments_routes.dart';
import 'favorite_star_button.dart';
import 'vacancy_cta_button.dart';

enum WorkaJobCardMode {
  search, // legacy alias of marketplace
  readonlyStatus, // legacy alias of status
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
    this.salaryMainColor = WorkaColors.salaryAccent,
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
  final bool highlight;

  final VoidCallback? onTap;
  final VoidCallback? onApply;
  final Widget? topRight;
  final bool showApply;

  // Kept for backward-compatible API.
  final double topRightReservedWidth;
  final Widget? footerLeading;
  final Widget? salaryTrailing;
  final String employmentLabel;
  final String applyLabel;
  final Widget? bottomRight;
  final Color salaryMainColor;
  final bool verifiedEmployer;
  final WorkaJobCardMode mode;

  static const double _mH = 10;
  static const double _mV = 2;
  static const double _radius = WorkaUiRadius.card;
  static const EdgeInsets _pad = EdgeInsets.fromLTRB(18, 16, 18, 16);

  bool get _isMarketplaceMode =>
      mode == WorkaJobCardMode.marketplace || mode == WorkaJobCardMode.search;
  bool get _isStatusMode =>
      mode == WorkaJobCardMode.status ||
      mode == WorkaJobCardMode.readonlyStatus;

  static const Map<String, String> _countryFlags = <String, String>{
    'Австрия': '🇦🇹',
    'Азербайджан': '🇦🇿',
    'Армения': '🇦🇲',
    'Беларусь': '🇧🇾',
    'Бельгия': '🇧🇪',
    'Болгария': '🇧🇬',
    'Венгрия': '🇭🇺',
    'Германия': '🇩🇪',
    'Греция': '🇬🇷',
    'Грузия': '🇬🇪',
    'Дания': '🇩🇰',
    'Ирландия': '🇮🇪',
    'Исландия': '🇮🇸',
    'Испания': '🇪🇸',
    'Италия': '🇮🇹',
    'Казахстан': '🇰🇿',
    'Кипр': '🇨🇾',
    'Кыргызстан': '🇰🇬',
    'Латвия': '🇱🇻',
    'Литва': '🇱🇹',
    'Люксембург': '🇱🇺',
    'Мальта': '🇲🇹',
    'Молдова': '🇲🇩',
    'Нидерланды': '🇳🇱',
    'Норвегия': '🇳🇴',
    'Польша': '🇵🇱',
    'Португалия': '🇵🇹',
    'Румыния': '🇷🇴',
    'Словакия': '🇸🇰',
    'Словения': '🇸🇮',
    'Таджикистан': '🇹🇯',
    'Туркменистан': '🇹🇲',
    'Украина': '🇺🇦',
    'Узбекистан': '🇺🇿',
    'Финляндия': '🇫🇮',
    'Франция': '🇫🇷',
    'Хорватия': '🇭🇷',
    'Чехия': '🇨🇿',
    'Швеция': '🇸🇪',
    'Эстония': '🇪🇪',
    'Austria': '🇦🇹',
    'Azerbaijan': '🇦🇿',
    'Armenia': '🇦🇲',
    'Belarus': '🇧🇾',
    'Belgium': '🇧🇪',
    'Bulgaria': '🇧🇬',
    'Hungary': '🇭🇺',
    'Germany': '🇩🇪',
    'Greece': '🇬🇷',
    'Georgia': '🇬🇪',
    'Denmark': '🇩🇰',
    'Ireland': '🇮🇪',
    'Iceland': '🇮🇸',
    'Spain': '🇪🇸',
    'Italy': '🇮🇹',
    'Kazakhstan': '🇰🇿',
    'Cyprus': '🇨🇾',
    'Kyrgyzstan': '🇰🇬',
    'Latvia': '🇱🇻',
    'Lithuania': '🇱🇹',
    'Luxembourg': '🇱🇺',
    'Malta': '🇲🇹',
    'Moldova': '🇲🇩',
    'Netherlands': '🇳🇱',
    'Norway': '🇳🇴',
    'Poland': '🇵🇱',
    'Portugal': '🇵🇹',
    'Romania': '🇷🇴',
    'Slovakia': '🇸🇰',
    'Slovenia': '🇸🇮',
    'Tajikistan': '🇹🇯',
    'Turkmenistan': '🇹🇲',
    'Ukraine': '🇺🇦',
    'Uzbekistan': '🇺🇿',
    'Finland': '🇫🇮',
    'France': '🇫🇷',
    'Croatia': '🇭🇷',
    'Czechia': '🇨🇿',
    'Sweden': '🇸🇪',
    'Estonia': '🇪🇪',
  };

  String _flagForCountry(String name) {
    final t = name.trim();
    if (t.isEmpty) return '';
    final exact = _countryFlags[t];
    if (exact != null) return exact;
    final lower = t.toLowerCase();
    for (final e in _countryFlags.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return '';
  }

  String _salaryPeriod() {
    final t = salaryType.trim().toLowerCase();
    if (t.contains('hour') || t.contains('час')) return '/ час';
    return '/ мес';
  }

  String _money(double v) => '€ ${v.round()}';

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

  String _salaryMain() {
    final from = salaryFrom;
    final to = salaryTo;
    if (from != null && to != null && from > 0 && to > 0) {
      if (from == to) return 'от ${_money(from)}';
      return '${_money(from)} – ${_money(to)}';
    }
    if (from != null && from > 0) return 'от ${_money(from)}';
    if (salaryTextFallback.trim().isNotEmpty) {
      return _normalizeSalaryFallback(salaryTextFallback);
    }
    return '€ —';
  }

  String _locationText() {
    final cityPart = city.trim();
    final countryPart = country.trim();

    if (cityPart.isEmpty && countryPart.isEmpty) {
      return 'Локация не указана';
    }
    if (countryPart.isEmpty) {
      return cityPart;
    }
    if (cityPart.isEmpty) {
      return countryPart;
    }
    return '$countryPart • $cityPart';
  }

  Widget _flagBadge(String flag, double fontSize) {
    return SizedBox(
      width: 20,
      height: 14,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: ColoredBox(
          color: Colors.transparent,
          child: Center(
            child: Text(
              flag,
              style: TextStyle(fontSize: fontSize, height: 1.0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBadge({
    required IconData icon,
    required Color iconColor,
    Color background = const Color(0xFFF2F6FF),
    Color border = const Color(0xFFDCE5FA),
  }) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Icon(icon, size: 16, color: iconColor),
    );
  }

  Widget _compoundNoBadge({required IconData icon, required Color iconColor}) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF8D3D3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.close_rounded, size: 16, color: Color(0xFFD32F2F)),
          const SizedBox(width: 4),
          Icon(icon, size: 16, color: iconColor),
        ],
      ),
    );
  }

  List<Widget> _conditions() {
    final out = <Widget>[];

    if (housingProvided) {
      out.add(
        _iconBadge(icon: Icons.home_outlined, iconColor: WorkaColors.blue),
      );
    }
    if (transportProvided) {
      out.add(
        _iconBadge(
          icon: Icons.airport_shuttle_outlined,
          iconColor: const Color(0xFF2E7D32),
          background: const Color(0xFFE8F5E9),
          border: const Color(0xFFB7DDBB),
        ),
      );
    }
    if (forTeenagers) {
      out.add(
        _iconBadge(
          icon: Icons.verified_user_outlined,
          iconColor: WorkaColors.blue,
        ),
      );
    }
    if (forDisabled) {
      out.add(
        _iconBadge(
          icon: Icons.accessible_outlined,
          iconColor: WorkaColors.orange,
        ),
      );
    }
    if (noLanguageRequired) {
      out.add(
        _compoundNoBadge(
          icon: Icons.translate_rounded,
          iconColor: WorkaColors.blueDark,
        ),
      );
    }
    if (noExperienceRequired) {
      out.add(
        _compoundNoBadge(
          icon: Icons.work_outline_rounded,
          iconColor: WorkaColors.orange,
        ),
      );
    }
    return out;
  }

  Widget _urgentBadge() {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF4D4F), Color(0xFFFF7A18)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [WorkaUiShadows.single],
      ),
      child: const Icon(Icons.flash_on_rounded, size: 16, color: Colors.white),
    );
  }

  Widget _pillBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _reliableEmployerBadge() {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE5FA), width: 1),
      ),
      child: const _VerifiedEmployerGoldBadge(size: 14),
    );
  }

  Widget _titleLocationSalaryBlock(
    BuildContext context, {
    required Widget rightAction,
    required bool isOwnerCard,
    required bool highlightActive,
    required bool urgentActive,
    bool bumpActive = false,
    bool showContactsActive = false,
  }) {
    final trailing = salaryTrailing ?? _promoteButton(context);
    final hasTitle = title.trim().isNotEmpty;
    final hasCompany = companyName.trim().isNotEmpty;
    final showVacancyNumber =
        showVacancyNumberInOwnerView &&
        isOwnerCard &&
        vacancyNumber.trim().isNotEmpty;
    final cond = _isMarketplaceMode ? _conditions() : const <Widget>[];
    final countryPart = country.trim();
    final flag = _flagForCountry(countryPart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: hasTitle
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (urgentActive) ...[
                          _urgentBadge(),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            title.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2F58CC),
                              letterSpacing: -0.2,
                              backgroundColor: highlightActive
                                  ? Colors.yellow.withOpacity(0.25)
                                  : null,
                            ),
                          ),
                        ),
                        if (_isMarketplaceMode && verifiedEmployer) ...[
                          const SizedBox(width: 8),
                          _reliableEmployerBadge(),
                        ],
                        if (bumpActive || showContactsActive) ...[
                          const SizedBox(width: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              if (bumpActive) _pillBadge('BUMP', Colors.blue),
                              if (showContactsActive)
                                _pillBadge('CONTACTS', Colors.green),
                            ],
                          ),
                        ],
                      ],
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
            const SizedBox(width: 8),
            Align(alignment: Alignment.center, child: rightAction),
          ],
        ),
        if (hasCompany) ...[
          const SizedBox(height: 6),
          Text(
            companyName.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF7B88A4),
            ),
          ),
        ],
        if (showVacancyNumber) ...[
          const SizedBox(height: 6),
          Text(
            'Номер вакансии: ${vacancyNumber.trim()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: WorkaColors.textGreyDark,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 16,
              color: WorkaColors.blue,
            ),
            if (flag.isNotEmpty) ...[
              const SizedBox(width: 6),
              _flagBadge(flag, 12),
            ],
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _locationText(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.4,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7D8CA8),
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ],
        ),
        if (cond.isNotEmpty) ...[
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < cond.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  cond[i],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget? _promoteButton(BuildContext context) {
    if (jobId.trim().isEmpty) return null;
    final ownership = OwnershipResolver.byOwnerId(ownerUid ?? '');
    final uidMatch = ownership.known && ownership.isOwner;
    if (!uidMatch) {
      return null;
    }
    return DecoratedBox(
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
        onPressed: () {
          Navigator.of(context, rootNavigator: true).pushNamed(
            PaymentsRoutes.promoteJob,
            arguments: <String, dynamic>{'jobId': jobId.trim()},
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
          'Продвижение вакансии',
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
      showArrow: true,
    );
  }

  Widget _appliedBadge() {
    return const VacancyCtaButton(
      kind: VacancyCtaKind.sent,
      label: 'Отклик отправлен',
    );
  }

  Widget _bottomEmploymentBar({required bool hasApplied}) {
    final ownership = OwnershipResolver.byOwnerId(ownerUid ?? '');
    final isOwnerCard = ownership.known && ownership.isOwner;
    final canShowWorkerCta = showApply && !isOwnerCard;
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
    final salaryMain = _salaryMain();
    final salaryPeriod = _salaryPeriod();
    final salaryAccent = salaryMainColor;

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
                        text: salaryMain,
                        style: TextStyle(
                          fontSize: 28,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          color: salaryAccent,
                          letterSpacing: -0.2,
                        ),
                      ),
                      TextSpan(
                        text: ' $salaryPeriod',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8693AD),
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
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 34,
                    maxWidth: 152,
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
    final bool highlight = this.highlight;
    final bool isUrgent = this.isUrgent;
    final bumpEffective = false;
    final showContactsEffective = false;

    final ownership = OwnershipResolver.byOwnerId(ownerUid ?? '');
    final isOwnerCard = ownership.known && ownership.isOwner;
    final rightAction =
        topRight ??
        (_isMarketplaceMode
            ? const FavoriteStarButton(isFavorite: false, size: 30)
            : const SizedBox.shrink());
    final hasConditions =
        housingProvided || transportProvided || forTeenagers || forDisabled;

    return _PressScaleCard(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: _mH, vertical: _mV),
        decoration: BoxDecoration(
          color: highlight ? const Color(0xFFFFF9E6) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.04),
            width: 1,
          ),
          boxShadow: [...WorkaUiShadows.card],
        ),
        child: Material(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(_radius),
          child: InkWell(
            onTap: onTap ?? onApply,
            borderRadius: BorderRadius.circular(_radius),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius),
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: _pad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _titleLocationSalaryBlock(
                        context,
                        rightAction: rightAction,
                        isOwnerCard: isOwnerCard,
                        highlightActive: highlight,
                        urgentActive: isUrgent,
                        bumpActive: bumpEffective,
                        showContactsActive: showContactsEffective,
                      ),
                      SizedBox(height: hasConditions ? 18 : 14),
                      _bottomEmploymentBar(hasApplied: hasApplied),
                      if (footerLeading != null) ...[
                        const SizedBox(height: 10),
                        footerLeading!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownership = OwnershipResolver.byOwnerId(ownerUid ?? '');
    final isOwnerCard = ownership.known && ownership.isOwner;

    if (_isStatusMode || (!showApply && bottomRight == null)) {
      return _shell(context, hasApplied: false);
    }

    if (isOwnerCard && bottomRight == null) {
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

class _VerifiedEmployerGoldBadge extends StatelessWidget {
  const _VerifiedEmployerGoldBadge({this.size = 17});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
              ).createShader(rect),
              blendMode: BlendMode.srcIn,
              child: Icon(
                Icons.shield_rounded,
                size: size,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: size * 0.42,
              height: size * 0.42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC22C),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 0.8),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.check_rounded,
                size: size * 0.26,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
