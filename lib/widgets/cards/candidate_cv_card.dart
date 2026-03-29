import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:worka/controllers/paid_entitlements_controller.dart';
import 'package:worka/features/payments/models/employer_payment_models.dart';
import 'package:worka/features/payments/usecases/unlock_candidate_contact_use_case.dart';
import 'package:worka/features/payments/screens/contact_unlock_paywall_sheet.dart';
import 'package:worka/features/monetization/worker/cv_highlight_paywall_sheet.dart';

import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';
import '../../utils/country_display_formatter.dart';
import '../card_more_menu_button.dart';

enum CandidateCvCardMode {
  owner,
  search,
  viewer,
  employer,
  offerStatus,
  applicationStatus,
  incomingApplicationStatus,
}

class CandidateCvCard extends StatelessWidget {
  const CandidateCvCard({
    super.key,
    required this.mode,
    required this.fullName,
    required this.profession,
    required this.onTap,
    this.age,
    this.citizenshipCountry = '',
    this.city = '',
    this.country = '',
    this.countries = const <String>[],
    this.badges = const <String>[],
    this.salary = '',
    this.readiness = '',
    this.avatarUrl,
    this.initials,
    this.menuItems = const <CardMenuItem>[],
    this.topRight,
    this.primaryActionLabel,
    this.primaryActionColor,
    this.onPrimaryAction,
    this.onFavoriteToggle,
    this.isFavorite = false,
    this.hasOfferSent = false,
    this.onShowContacts,
    this.onOfferJob,
    this.phone = '',
    this.email = '',
    this.telegram = '',
    this.cvId = '',
    this.cvUserId = '',
    this.cvOwnerId = '',
    this.candidateId = '',
    this.category = '',
    this.workType = '',
    this.experience = '',
    this.languages = const <String>[],
    this.tools = '',
    this.workClothes = '',
    this.availability = '',
    this.aboutSnippet = '',
    this.gender = '',
    this.margin = EdgeInsets.zero,
  });

  final CandidateCvCardMode mode;
  final String fullName;
  final String profession;
  final int? age;
  final String citizenshipCountry;
  final String city;
  final String country;
  final List<String> countries;
  final List<String> badges;
  final String salary;
  final String readiness;
  final VoidCallback onTap;
  final String? avatarUrl;
  final String? initials;
  final List<CardMenuItem> menuItems;
  final Widget? topRight;
  final String? primaryActionLabel;
  final Color? primaryActionColor;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onFavoriteToggle;
  final bool isFavorite;
  final bool hasOfferSent;
  final VoidCallback? onShowContacts;
  final VoidCallback? onOfferJob;
  final String phone;
  final String email;
  final String telegram;
  final String cvId;
  final String cvUserId;
  final String cvOwnerId;
  final String candidateId;
  final String category;
  final String workType;
  final String experience;
  final List<String> languages;
  final String tools;
  final String workClothes;
  final String availability;
  final String aboutSnippet;
  final String gender;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final paid = context.watch<PaidEntitlementsController>();
    final hasHighlight = paid.hasCvFeature(cvId, 'highlight');
    final hasPriority = paid.hasCvFeature(cvId, 'priority');
    final hasBump = paid.hasCvFeature(cvId, 'bump');
    if (cvId.trim().isNotEmpty &&
        paid.cvEntitlementsById[cvId.trim()] == null) {
      // Fire and forget refresh; avoids tight loop because map will populate.
      Future.microtask(() => paid.refreshCvEntitlements(cvId.trim()));
    }

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasHighlight ? Colors.yellow.withOpacity(0.14) : Colors.white,
        border: Border.all(
          color: hasHighlight
              ? Colors.orange.withOpacity(0.55)
              : Colors.transparent,
          width: hasHighlight ? 1.4 : 0.8,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: WorkaUiShadows.card,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(
                  initials: _avatarInitials(),
                  avatarUrl: avatarUrl,
                  gender: gender,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _titleLine(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: WorkaColors.blue,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _citizenshipBadge(),
                          if (hasPriority || hasBump) ...[
                            const SizedBox(width: 8),
                            _entitlementBadges(hasPriority, hasBump),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _safeProfession(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: WorkaColors.textGreyDark,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _locationLine(),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                topRight ?? _defaultTopRight(),
              ],
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: badges
                    .where((e) => e.trim().isNotEmpty)
                    .map(_buildBadge)
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _salaryText(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WorkaColors.orange,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          height: 1.0,
                        ),
                      ),
                      if (readiness.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          readiness.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WorkaColors.textGreyDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(height: 36, child: _buildPrimaryAction(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _safeProfession() {
    final value = profession.trim();
    if (value.isEmpty) return 'Профессия не указана';
    return value;
  }

  String _titleLine() {
    final base = fullName.trim().isEmpty ? 'Кандидат' : fullName.trim();
    if (age != null && age! > 0) {
      return '$base, $age';
    }
    return base;
  }

  Widget _defaultTopRight() {
    if (mode == CandidateCvCardMode.owner) {
      if (menuItems.isNotEmpty) return CardMoreMenuButton(items: menuItems);
      return const SizedBox.shrink();
    }
    if (mode == CandidateCvCardMode.offerStatus ||
        mode == CandidateCvCardMode.applicationStatus ||
        mode == CandidateCvCardMode.incomingApplicationStatus) {
      return const SizedBox.shrink();
    }
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      onPressed: onFavoriteToggle,
      icon: Icon(
        isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
        color: isFavorite ? WorkaColors.orange : WorkaColors.textGreyDark,
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context) {
    final paid = context.read<PaidEntitlementsController>();
    final hasHighlight = paid.hasCvFeature(cvId, 'highlight');
    final hasPriority = paid.hasCvFeature(cvId, 'priority');
    final hasBump = paid.hasCvFeature(cvId, 'bump');

    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final normalizedUserId = cvUserId.trim();
    final isOwnCv =
        currentUid.isNotEmpty &&
        (normalizedUserId == currentUid || cvOwnerId.trim() == currentUid);
    final isOwner = mode == CandidateCvCardMode.owner || isOwnCv;
    final isStatusMode =
        mode == CandidateCvCardMode.offerStatus ||
        mode == CandidateCvCardMode.applicationStatus ||
        mode == CandidateCvCardMode.incomingApplicationStatus;
    final bool isOfferSent = !isOwner && hasOfferSent;
    final bool isSentState = isOfferSent || isStatusMode;
    final Color bg =
        primaryActionColor ??
        (isSentState ? WorkaColors.blue : WorkaColors.orange);
    final String text =
        primaryActionLabel ??
        (isStatusMode
            ? (mode == CandidateCvCardMode.offerStatus
                  ? 'Предложение отправлено'
                  : (mode == CandidateCvCardMode.applicationStatus
                        ? 'Отклик отправлен'
                        : 'Новый отклик'))
            : isOwner
            ? 'Выделить CV'
            : (isOfferSent ? 'Предложение отправлено' : 'Связаться'));
    final VoidCallback? callback = (isOfferSent || isStatusMode)
        ? null
        : (onPrimaryAction ??
              (isOwner ? null : () => _openExpandedCardSheet(context)));
    if (isOwner && (hasHighlight || hasPriority || hasBump)) {
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (hasHighlight)
            _statusChip('Выделение активно', WorkaColors.orange),
          if (hasPriority)
            _statusChip('Приоритет активен', WorkaColors.blueDark),
          if (hasBump) _statusChip('Поднято', Colors.blueGrey),
        ],
      );
    }

    if (isOwner) {
      return OutlinedButton(
        onPressed: () {
          final id = cvId.trim();
          if (id.isEmpty) {
            debugPrint('[CV PAYWALL] blocked: missing cvId source=owner_card');
            return;
          }
          debugPrint('[CV PAYWALL] source=owner_card cvId=$id');
          CvHighlightPaywallSheet.open(context, cvId: id);
          if (callback != null) callback();
        },
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll<Color>(Colors.white),
          foregroundColor: const WidgetStatePropertyAll<Color>(
            WorkaColors.orange,
          ),
          side: const WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: WorkaColors.orange, width: 1.2),
          ),
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkaUiRadius.control),
            ),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle>(
            TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          overlayColor: WidgetStatePropertyAll<Color>(
            WorkaColors.orange.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: WorkaColors.orange,
          ),
        ),
      );
    }
    return ElevatedButton(
      onPressed: callback,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        elevation: 0,
        disabledBackgroundColor: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkaUiRadius.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  void _openExpandedCardSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExpandedCandidateCard(
        fullName: fullName,
        age: age,
        citizenshipCountry: citizenshipCountry,
        profession: profession,
        city: city,
        country: country,
        countries: countries,
        badges: badges,
        salary: salary,
        readiness: readiness,
        avatarUrl: avatarUrl,
        initials: initials,
        onShowContacts: onShowContacts,
        onOfferJob: onOfferJob,
        phone: phone,
        email: email,
        telegram: telegram,
        cvUserId: cvUserId,
        cvOwnerId: cvOwnerId,
        candidateId: candidateId,
        category: category,
        workType: workType,
        experience: experience,
        languages: languages,
        tools: tools,
        workClothes: workClothes,
        availability: availability,
        aboutSnippet: aboutSnippet,
        gender: gender,
      ),
    );
  }

  Widget _citizenshipBadge() {
    final clean = citizenshipCountry.trim();
    if (clean.isEmpty) return const SizedBox.shrink();
    final isEu = CountryDisplayFormatter.isEu(clean);
    final flag = CountryDisplayFormatter.countryFlagToken(clean);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: isEu ? const Color(0xFFE9EEFF) : const Color(0xFFF2F4F7),
        shape: BoxShape.circle,
        border: Border.all(
          color: isEu
              ? WorkaColors.blue.withValues(alpha: 0.35)
              : WorkaColors.divider,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        flag,
        style: TextStyle(
          fontSize: isEu ? 10 : 13,
          color: isEu ? WorkaColors.blue : null,
          fontWeight: isEu ? FontWeight.w900 : FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  Widget _locationLine() {
    final all = _locationCountries();
    final String primary = all.isNotEmpty ? all.first : country.trim();
    final bool hasMore = all.length > 1;
    final String normalizedCountry = _normalizeCountryForLocation(primary);
    final String prefixedCountry = _countryWithFlag(normalizedCountry);
    final String cityPart = city.trim();
    String text;
    if (normalizedCountry.isEmpty && cityPart.isNotEmpty) {
      text = cityPart;
    } else if (cityPart.isNotEmpty && normalizedCountry.isNotEmpty) {
      final sameCityCountry =
          cityPart.toLowerCase() == normalizedCountry.toLowerCase();
      text = sameCityCountry ? prefixedCountry : '$cityPart, $prefixedCountry';
    } else {
      text = prefixedCountry;
    }
    if (hasMore) text = '$text, ...';
    return Row(
      children: [
        const Icon(
          Icons.location_on_outlined,
          size: 16,
          color: WorkaColors.blue,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  String _countryWithFlag(String rawCountry) {
    final clean = rawCountry.trim();
    if (clean.isEmpty) return '';
    final flag = CountryDisplayFormatter.countryFlagOnly(
      clean,
      euAsToken: false,
    );
    if (flag.trim().isEmpty) return clean;
    return '$flag $clean';
  }

  String _normalizeCountryForLocation(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (value.contains(',')) {
      final segments = value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (segments.isNotEmpty) {
        value = segments.last;
      }
    }
    final parts = value.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      final first = parts.first;
      final maybeFlagToken =
          first.contains('🇪') ||
          first.contains('🇷') ||
          first.contains('🇺') ||
          first.contains('🇰') ||
          first.contains('🇫') ||
          first.contains('🇸') ||
          first.contains('🇱') ||
          first.contains('🇵') ||
          first.contains('🇩') ||
          first.contains('🇳') ||
          first.contains('🇮');
      if (maybeFlagToken) {
        value = parts.skip(1).join(' ').trim();
      }
    }
    value = value.replaceFirst(
      RegExp(r'^(EU|ЕС)\s+', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(
      RegExp(r'^(EU|ЕС)\s+', caseSensitive: false),
      '',
    );
    return value.trim();
  }

  List<String> _locationCountries() {
    final values = <String>{};
    for (final c in countries) {
      final v = c.trim();
      if (v.isNotEmpty) values.add(v);
    }
    return values.toList();
  }

  String _salaryText() {
    final clean = salary.trim();
    if (clean.isEmpty || clean == '-') return '€ -';
    final normalized = clean.replaceAll('\$', '').replaceAll('€', '').trim();
    if (normalized.isEmpty) return '€ -';
    return '€ $normalized';
  }

  Widget _buildBadge(String raw) {
    final token = raw.trim();
    IconData? icon;
    _BadgeKind kind = _BadgeKind.experience;
    String text = token;
    if (token == 'icon:computer') {
      icon = Icons.computer_outlined;
      kind = _BadgeKind.experience;
      text = '';
    } else if (token == 'icon:car') {
      icon = Icons.directions_car_outlined;
      kind = _BadgeKind.driver;
      text = '';
    } else if (token == 'icon:tools') {
      icon = Icons.handyman_outlined;
      kind = _BadgeKind.tools;
      text = '';
    } else if (token == 'icon:workwear') {
      icon = Icons.checkroom_outlined;
      kind = _BadgeKind.workwear;
      text = '';
    } else if (_isLanguageBadge(token)) {
      kind = _BadgeKind.language;
    } else if (_isDrivingLicenseBadge(token)) {
      kind = _BadgeKind.driver;
    } else if (token.contains('опыт')) {
      kind = _BadgeKind.experience;
    }

    final style = _badgeStyle(kind);
    return Container(
      padding: icon == null
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
          : const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: icon == null
          ? Text(
              text,
              style: TextStyle(
                color: style.fg,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            )
          : Icon(icon, size: 16, color: style.fg),
    );
  }

  _BadgeStyle _badgeStyle(_BadgeKind kind) {
    switch (kind) {
      case _BadgeKind.language:
        return const _BadgeStyle(Color(0xFFFFF4CC), Color(0xFF8A6A00));
      case _BadgeKind.driver:
        return const _BadgeStyle(Color(0xFFE9F8EC), Color(0xFF1E7B3A));
      case _BadgeKind.tools:
        return const _BadgeStyle(Color(0xFFFFEFE2), Color(0xFFB85A00));
      case _BadgeKind.workwear:
        return const _BadgeStyle(Color(0xFFF2EBFF), Color(0xFF6E42C1));
      case _BadgeKind.experience:
        return const _BadgeStyle(Color(0xFFE9F1FF), Color(0xFF2D5BCA));
    }
  }

  bool _isLanguageBadge(String value) {
    final v = value.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2,4}(?:\s+[ABC][12])?$').hasMatch(v);
  }

  bool _isDrivingLicenseBadge(String value) {
    final v = value.trim().toUpperCase();
    return RegExp(r'^[A-Z]{1,3}[0-9]?$').hasMatch(v);
  }

  String _avatarInitials() {
    if (initials != null && initials!.trim().isNotEmpty) {
      return initials!.trim();
    }
    final parts = fullName
        .replaceAll(',', ' ')
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'U';
    return parts.map((e) => e.substring(0, 1).toUpperCase()).join();
  }

  Widget _entitlementBadges(bool priority, bool bump) {
    final chips = <Widget>[];
    if (priority) {
      chips.add(_pillBadge('PRIORITY', Colors.deepOrange));
    }
    if (bump) {
      chips.add(_pillBadge('BUMP', Colors.blueGrey));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: chips
          .expand((w) => [w, const SizedBox(width: 4)])
          .take(chips.isEmpty ? 0 : chips.length * 2 - 1)
          .toList(),
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
}

class ExpandedCandidateCard extends StatelessWidget {
  const ExpandedCandidateCard({
    super.key,
    required this.fullName,
    required this.profession,
    required this.city,
    required this.country,
    required this.countries,
    required this.badges,
    required this.salary,
    required this.readiness,
    this.age,
    this.citizenshipCountry = '',
    this.avatarUrl,
    this.initials,
    this.category = '',
    this.workType = '',
    this.experience = '',
    this.languages = const <String>[],
    this.tools = '',
    this.workClothes = '',
    this.availability = '',
    this.aboutSnippet = '',
    this.gender = '',
    this.phone = '',
    this.email = '',
    this.telegram = '',
    this.cvUserId = '',
    this.cvOwnerId = '',
    this.candidateId = '',
    this.onShowContacts,
    this.onOfferJob,
  });

  final String fullName;
  final int? age;
  final String citizenshipCountry;
  final String profession;
  final String city;
  final String country;
  final List<String> countries;
  final List<String> badges;
  final String salary;
  final String readiness;
  final String? avatarUrl;
  final String? initials;
  final String category;
  final String workType;
  final String experience;
  final List<String> languages;
  final String tools;
  final String workClothes;
  final String availability;
  final String aboutSnippet;
  final String gender;
  final String phone;
  final String email;
  final String telegram;
  final String cvUserId;
  final String cvOwnerId;
  final String candidateId;
  final VoidCallback? onShowContacts;
  final VoidCallback? onOfferJob;
  static final UnlockCandidateContactUseCase _unlockCandidateContact =
      UnlockCandidateContactUseCase();

  Future<void> _handleContactsTap(BuildContext context) async {
    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final isOwnCv =
        currentUid.isNotEmpty &&
        (cvUserId.trim() == currentUid || cvOwnerId.trim() == currentUid);
    if (isOwnCv) {
      (onShowContacts ?? () {})();
      return;
    }
    if (candidateId.trim().isEmpty) {
      // No candidateId available — open credits purchase only (cannot unlock specific candidate).
      await ContactUnlockPaywallSheet.open(
        context,
        candidateName: fullName.trim().isEmpty ? null : fullName.trim(),
        entryPoint: 'expanded_candidate_card_missing_id',
        mode: PaywallMode.creditsOnly,
      );
      return;
    }
    final result = await _unlockCandidateContact(
      context,
      candidateId: candidateId.trim(),
      candidateName: fullName.trim().isEmpty ? null : fullName.trim(),
      entryPoint: 'expanded_candidate_card',
    );
    if (!result.isSuccess || !context.mounted) return;
    if (onShowContacts != null) {
      onShowContacts!.call();
      return;
    }
    _showContactsSheet(context, unlockedContact: result.contact);
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final isOwnCv = currentUid.isNotEmpty && cvUserId.trim() == currentUid;
    final allCountries = countries
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final location = [
      if (city.trim().isNotEmpty) city.trim(),
      if (country.trim().isNotEmpty) country.trim(),
    ].join(', ');
    final driverCategories = badges
        .where(
          (b) => RegExp(r'^[A-Z]{1,3}[0-9]?$').hasMatch(b.trim().toUpperCase()),
        )
        .toList();
    final hasCar = badges.any((b) => b.trim() == 'icon:car');
    final hasTools =
        badges.any((b) => b.trim() == 'icon:tools') || tools.trim().isNotEmpty;
    final hasWorkwear =
        badges.any((b) => b.trim() == 'icon:workwear') ||
        workClothes.trim().isNotEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: WorkaUiShadows.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Avatar(
                          initials: (initials ?? '').trim().isEmpty
                              ? _shortInitials(fullName)
                              : initials!.trim(),
                          avatarUrl: avatarUrl,
                          gender: gender,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _titleText(),
                                      style: const TextStyle(
                                        color: WorkaColors.blue,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  _smallCitizenshipBadge(citizenshipCountry),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                profession.trim().isEmpty
                                    ? 'Профессия не указана'
                                    : profession.trim(),
                                style: const TextStyle(
                                  color: WorkaColors.textGreyDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _locationSummary(location, allCountries),
                              const SizedBox(height: 6),
                              Text(
                                _salaryWithEuro(salary),
                                style: const TextStyle(
                                  color: WorkaColors.orange,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: badges
                            .where((e) => e.trim().isNotEmpty)
                            .map(_compactBadge)
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ExpandedInfoRow(label: 'Категория', value: category),
              _ExpandedInfoRow(label: 'Тип работы', value: workType),
              _ExpandedInfoRow(label: 'Опыт', value: experience),
              _ExpandedInfoRow(
                label: 'Языки',
                value: languages.where((e) => e.trim().isNotEmpty).join(', '),
              ),
              _ExpandedInfoRow(
                label: 'Водительские права',
                value: driverCategories.join(', '),
              ),
              _ExpandedInfoRow(
                label: 'Автомобиль',
                value: hasCar ? 'Есть' : '',
              ),
              _ExpandedInfoRow(
                label: 'Инструменты',
                value: hasTools ? 'Есть' : '',
              ),
              _ExpandedInfoRow(
                label: 'Рабочая одежда',
                value: hasWorkwear ? 'Есть' : '',
              ),
              _ExpandedInfoRow(
                label: 'Готовность',
                value: availability.isEmpty ? readiness : availability,
              ),
              _ExpandedInfoRow(
                label: 'О себе',
                value: aboutSnippet.trim().isEmpty
                    ? ''
                    : aboutSnippet.trim().split('\n').first,
              ),
              if (allCountries.isNotEmpty)
                _ExpandedInfoRow(
                  label: 'Страны',
                  value: allCountries.join(', '),
                ),
              if (location.isNotEmpty)
                _ExpandedInfoRow(label: 'Локация', value: location),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleContactsTap(context),
                      style:
                          (isOwnCv
                                  ? OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: WorkaColors.orange,
                                      side: const BorderSide(
                                        color: WorkaColors.orange,
                                        width: 1.2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                    )
                                  : WorkaButtonStyles.outlineBlue())
                              .copyWith(
                                minimumSize: const WidgetStatePropertyAll<Size>(
                                  Size.fromHeight(46),
                                ),
                              ),
                      child: Text(
                        isOwnCv ? 'Выделить CV' : 'Показать контакты',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isOwnCv ? WorkaColors.orange : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onOfferJob,
                      style: WorkaButtonStyles.primaryOrange().copyWith(
                        minimumSize: const WidgetStatePropertyAll<Size>(
                          Size.fromHeight(46),
                        ),
                      ),
                      child: const Text(
                        'Предложить работу',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _titleText() {
    final name = fullName.trim().isEmpty ? 'Кандидат' : fullName.trim();
    if (age != null && age! > 0) return '$name, $age';
    return name;
  }

  String _shortInitials(String value) {
    final parts = value
        .replaceAll(',', ' ')
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'U';
    return parts.map((e) => e.substring(0, 1).toUpperCase()).join();
  }

  Widget _smallCitizenshipBadge(String value) {
    final clean = value.trim();
    final label = CountryDisplayFormatter.countryFlagToken(clean);
    final isEu = CountryDisplayFormatter.isEu(clean);
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        shape: BoxShape.circle,
        border: Border.all(color: WorkaColors.divider),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isEu ? 10 : 13,
          fontWeight: FontWeight.w800,
          color: isEu ? WorkaColors.blue : null,
        ),
      ),
    );
  }

  Widget _locationSummary(String location, List<String> allCountries) {
    final value = allCountries.isNotEmpty
        ? CountryDisplayFormatter.formatCountriesWithFlags(
            allCountries,
          ).join(', ')
        : location;
    return Row(
      children: [
        const Icon(
          Icons.location_on_outlined,
          size: 16,
          color: WorkaColors.blue,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value.trim(),
            style: const TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  String _salaryWithEuro(String value) {
    final v = value.trim();
    if (v.isEmpty || v == '-') return '€ -';
    if (v.startsWith('€')) return v;
    return '€ ${v.replaceAll('\$', '').trim()}';
  }

  Widget _compactBadge(String text) {
    final token = text.trim();
    if (token.isEmpty || token.toLowerCase() == 'null') {
      return const SizedBox.shrink();
    }
    if (token == 'icon:computer') {
      return _iconBadge(
        icon: Icons.computer_outlined,
        bg: const Color(0xFFE9F1FF),
        fg: const Color(0xFF2D5BCA),
      );
    }
    if (token == 'icon:car') {
      return _iconBadge(
        icon: Icons.directions_car_outlined,
        bg: const Color(0xFFE9F8EC),
        fg: const Color(0xFF1E7B3A),
      );
    }
    if (token == 'icon:tools') {
      return _iconBadge(
        icon: Icons.handyman_outlined,
        bg: const Color(0xFFFFEFE2),
        fg: const Color(0xFFB85A00),
      );
    }
    if (token == 'icon:workwear') {
      return _iconBadge(
        icon: Icons.checkroom_outlined,
        bg: const Color(0xFFF2EBFF),
        fg: const Color(0xFF6E42C1),
      );
    }
    final isLanguage = RegExp(
      r'^[A-Z]{2,4}(?:\s+[ABC][12])?$',
    ).hasMatch(token.toUpperCase());
    final isDriver = RegExp(
      r'^[A-Z]{1,3}[0-9]?$',
    ).hasMatch(token.toUpperCase());
    final Color bg = isLanguage
        ? const Color(0xFFFFF4CC)
        : (isDriver ? const Color(0xFFE9F8EC) : const Color(0xFFE9F1FF));
    final Color fg = isLanguage
        ? const Color(0xFF8A6A00)
        : (isDriver ? const Color(0xFF1E7B3A) : WorkaColors.blue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        token,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Widget _iconBadge({
    required IconData icon,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(icon, size: 15, color: fg),
    );
  }

  void _showContactsSheet(
    BuildContext context, {
    CandidateContact? unlockedContact,
  }) {
    final displayPhone = (unlockedContact?.phone ?? '').isNotEmpty
        ? unlockedContact!.phone
        : phone;
    final displayEmail = (unlockedContact?.email ?? '').isNotEmpty
        ? unlockedContact!.email
        : email;
    final displayTelegram = (unlockedContact?.telegram ?? '').isNotEmpty
        ? unlockedContact!.telegram
        : telegram;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Контакты',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: WorkaColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            _ExpandedInfoRow(label: 'Телефон', value: displayPhone),
            _ExpandedInfoRow(label: 'Email', value: displayEmail),
            _ExpandedInfoRow(label: 'Telegram', value: displayTelegram),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.avatarUrl,
    required this.gender,
  });

  final String initials;
  final String? avatarUrl;
  final String gender;

  String? sanitizeAvatarUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final normalized = value.toLowerCase();
    const invalid = <String>{
      '',
      '-',
      'null',
      'undefined',
      'n/a',
      'placeholder',
    };
    if (invalid.contains(normalized)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    if (!isHttp) return null;
    if (uri.host.trim().isEmpty) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = sanitizeAvatarUrl(avatarUrl);
    final hasImage = imageUrl != null;
    final normalizedGender = gender.trim().toLowerCase();
    final bool isMale =
        normalizedGender == 'male' ||
        normalizedGender == 'мужской' ||
        normalizedGender == 'муж' ||
        normalizedGender == 'm';
    final bool isFemale =
        normalizedGender == 'female' ||
        normalizedGender == 'женский' ||
        normalizedGender == 'жен' ||
        normalizedGender == 'f';
    final String? genderAsset = isMale
        ? 'assets/avatars/male.png'
        : (isFemale ? 'assets/avatars/female.png' : null);

    Widget initialsFallback() {
      return Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      );
    }

    Widget genderAssetFallback() {
      if (genderAsset == null) return initialsFallback();
      return Image.asset(
        genderAsset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initialsFallback(),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF0FF),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return genderAssetFallback();
                },
              )
            : genderAssetFallback(),
      ),
    );
  }
}

class _ExpandedInfoRow extends StatelessWidget {
  const _ExpandedInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final clean = value.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'null') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              clean,
              style: const TextStyle(
                color: WorkaColors.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _BadgeKind { language, driver, tools, workwear, experience }

class _BadgeStyle {
  final Color bg;
  final Color fg;

  const _BadgeStyle(this.bg, this.fg);
}
