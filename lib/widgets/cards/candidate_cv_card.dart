import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:worka/controllers/paid_entitlements_controller.dart';
import 'package:worka/features/payments/contact_access_controller.dart';
import 'package:worka/features/payments/models/employer_payment_models.dart';
import 'package:worka/features/monetization/worker/cv_highlight_paywall_sheet.dart';
import 'package:worka/services/runtime_flow_logger.dart';

import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';
import '../../utils/country_display_formatter.dart';
import '../../services/ownership_resolver.dart';
import '../candidate_offer_sent_badge.dart';
import '../card_more_menu_button.dart';
import '../vacancy_cta_button.dart';

part 'candidate_cv_card_formatters.dart';
part 'candidate_cv_card_header.dart';
part 'candidate_cv_card_body.dart';

final Set<String> _cvCardContactBadgeHiddenMarkerDedupe = <String>{};

enum CandidateCvCardMode {
  owner,
  search,
  viewer,
  employer,
  offerStatus,
  applicationStatus,
  incomingApplicationStatus,
}

class _CvCardOwnership {
  const _CvCardOwnership({
    required this.ownerUid,
    required this.known,
    required this.isOwner,
  });

  final String ownerUid;
  final bool known;
  final bool isOwner;
}

_CvCardOwnership _resolveCvCardOwnership({
  required bool ownerMode,
  required String cvOwnerId,
  required String cvUserId,
}) {
  var ownerUid = cvOwnerId.trim().isNotEmpty
      ? cvOwnerId.trim()
      : cvUserId.trim();
  if (ownerMode && ownerUid.isEmpty) {
    ownerUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }
  if (ownerMode) {
    return _CvCardOwnership(ownerUid: ownerUid, known: true, isOwner: true);
  }
  final synthetic = <String, dynamic>{
    if (cvOwnerId.trim().isNotEmpty) 'candidateOwnerId': cvOwnerId.trim(),
    if (cvUserId.trim().isNotEmpty) 'ownerUid': cvUserId.trim(),
    if (ownerUid.isNotEmpty) 'ownerId': ownerUid,
  };
  final r = OwnershipResolver.cvViewerOwnership(synthetic);
  return _CvCardOwnership(
    ownerUid: ownerUid,
    known: r.known,
    isOwner: r.isOwner,
  );
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
    this.offerSentSummaryLine,
    this.onShowContacts,
    this.onOfferJob,
    this.phone = '',
    this.email = '',
    this.telegram = '',
    this.cvId = '',
    this.cvUserId = '',
    this.cvOwnerId = '',
    this.candidateId = '',
    this.canonicalCandidateId = '',
    this.candidateKey = '',
    this.hasAccess = false,
    this.isBootstrapped = true,
    this.contact,
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
    this.resolvedContactKey = '',
    this.hasResolvedAccess = false,
    this.resolvedContact,
    this.showUnlockedBadge = false,
    this.showUnlockedLoader = false,
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
  /// When set with [hasOfferSent], replaces primary CTA (Patch B).
  final String? offerSentSummaryLine;
  final VoidCallback? onShowContacts;
  final VoidCallback? onOfferJob;
  final String phone;
  final String email;
  final String telegram;
  final String cvId;
  final String cvUserId;
  final String cvOwnerId;
  final String candidateId;
  final String canonicalCandidateId;
  final String candidateKey;
  final bool hasAccess;
  final bool isBootstrapped;
  final CandidateContact? contact;
  final String resolvedContactKey;
  final bool hasResolvedAccess;
  final CandidateContact? resolvedContact;
  final bool showUnlockedBadge;
  final bool showUnlockedLoader;
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
    final hasBoost = paid.hasCvFeature(cvId, 'boost');
    final hasHighlight = paid.hasCvFeature(cvId, 'highlight');
    final hasPriority = paid.hasCvFeature(cvId, 'priority');

    return Container(
        margin: margin,
        padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasBoost
            ? const Color(0xFFEAF3FF)
            : hasHighlight
            ? const Color(0xFFFFF4CC)
            : Colors.white,
        border: Border.all(
          color: hasBoost
              ? const Color(0xFF2D5BCA).withValues(alpha: 0.75)
              : hasHighlight
              ? const Color(0xFFF59E0B)
              : WorkaColors.border,
          width: (hasBoost || hasHighlight) ? 1.8 : 0.8,
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
            if (hasHighlight && !hasBoost) ...[
              Container(
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
            _CandidateCvCardHeader(
              avatarInitials: _avatarInitials(),
              avatarUrl: avatarUrl,
              gender: gender,
              titleLine: _titleLine(),
              profession: _safeProfession(),
              locationLine: _locationLine(),
              citizenshipBadge: _citizenshipBadge(),
              entitlementBadges: _entitlementBadges(
                hasBoost,
                hasHighlight,
                hasPriority,
              ),
              showEntitlements: hasBoost || hasHighlight || hasPriority,
              topRight: topRight ?? _defaultTopRight(),
            ),
            _CandidateCvCardBody(
              visibleBadges: _visibleBadges(badges),
              buildBadge: _buildBadge,
              salaryText: _salaryText(),
              readiness: readiness,
              primaryAction: _buildOfferOrPrimaryAction(context),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildOfferOrPrimaryAction(BuildContext context) {
    final ownership = _resolveCvCardOwnership(
      ownerMode: mode == CandidateCvCardMode.owner,
      cvOwnerId: cvOwnerId,
      cvUserId: cvUserId,
    );
    final isOwner = ownership.isOwner;
    if (!isOwner &&
        hasOfferSent &&
        mode != CandidateCvCardMode.offerStatus &&
        mode != CandidateCvCardMode.applicationStatus &&
        mode != CandidateCvCardMode.incomingApplicationStatus) {
      final raw = (offerSentSummaryLine ?? '').trim();
      final text = raw.isEmpty ? 'Вакансия отправлена кандидату' : raw;
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: OfferSentFilledBadge(
          label: text,
          candidateUid: cvOwnerId.trim(),
          cvId: cvId.trim(),
          rawCandidateId: candidateId.trim(),
          offerId: '',
          jobTitle: '',
        ),
      );
    }
    return _buildPrimaryAction(context);
  }

  Widget _buildPrimaryAction(BuildContext context) {
    final contactCtrl = context.watch<ContactAccessController>();
    final resolvedKey = _resolveContactKey(contactCtrl);
    final bool hasAccessNow =
        resolvedKey.isNotEmpty &&
        contactCtrl.hasAccessToCandidateContact(resolvedKey);

    final ownership = _resolveCvCardOwnership(
      ownerMode: mode == CandidateCvCardMode.owner,
      cvOwnerId: cvOwnerId,
      cvUserId: cvUserId,
    );
    final isOwner = ownership.isOwner;
    final isStatusMode =
        mode == CandidateCvCardMode.offerStatus ||
        mode == CandidateCvCardMode.applicationStatus ||
        mode == CandidateCvCardMode.incomingApplicationStatus;
    final bool isOfferSent = !isOwner && hasOfferSent;
    final bool isSentState = isOfferSent || isStatusMode;
    final Color bg =
        primaryActionColor ??
        (isSentState ? WorkaColors.blue : WorkaColors.orange);

    if (!hasAccessNow) {
      // Locked UI only when access is false.
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
              : 'Связаться');
      VoidCallback bypassPreviewToFullFlow() {
        return () {
          RuntimeFlowLogger.mark(
            'CANDIDATE_PREVIEW_SHEET_BYPASSED',
            <String, Object?>{
              'surface': 'cv_card_primary_cta',
              'candidateId': candidateId.trim(),
              'mode': mode.name,
            },
          );
          onTap();
        };
      }

      final VoidCallback? callback = (isOfferSent || isStatusMode)
          ? null
          : (onPrimaryAction ?? (isOwner ? null : bypassPreviewToFullFlow()));
      if (isOwner) {
        return OutlinedButton(
          onPressed: () {
            final id = cvId.trim();
            if (id.isEmpty) {
              debugPrint(
                '[CV PAYWALL] blocked: missing cvId source=owner_card',
              );
              return;
            }
            debugPrint('[CV PAYWALL] source=owner_card cvId=$id');
            CvHighlightPaywallSheet.open(
              context,
              cvId: id,
              originSource: 'owner_card',
              cvOwnerType: 'personal',
              cvOwnerId: ownership.ownerUid,
            );
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: WorkaColors.orange,
            side: const BorderSide(color: WorkaColors.orange, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkaUiRadius.control),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      if (isOfferSent || isStatusMode) {
        return VacancyCtaButton(kind: VacancyCtaKind.sent, label: text);
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

    if (isSentState) {
      final String text =
          primaryActionLabel ??
          (isStatusMode
              ? (mode == CandidateCvCardMode.offerStatus
                    ? 'Предложение отправлено'
                    : (mode == CandidateCvCardMode.applicationStatus
                          ? 'Отклик отправлен'
                          : 'Новый отклик'))
              : 'Предложение отправлено');
      return VacancyCtaButton(kind: VacancyCtaKind.sent, label: text);
    }

    final contactLoadedNow =
        resolvedKey.isNotEmpty &&
        contactCtrl.contactForCandidate(resolvedKey) != null;
    final hydrationState =
        contactCtrl.stateForCandidateKey(resolvedKey);

    if (contactLoadedNow && resolvedKey.isNotEmpty) {
      _cvCardContactBadgeHiddenMarkerDedupe.remove(resolvedKey);
    }

    if (!isOwner && hasAccessNow && !contactLoadedNow) {
      if (!_cvCardContactBadgeHiddenMarkerDedupe.contains(resolvedKey)) {
        _cvCardContactBadgeHiddenMarkerDedupe.add(resolvedKey);
        RuntimeFlowLogger.mark(
          'CONTACT_BADGE_RENDER',
          <String, Object?>{
            'visible': false,
            'reason': 'contact_not_loaded',
            'resolvedKey': resolvedKey,
          },
        );
      }
      if (hydrationState.isLoadingContact || showUnlockedLoader) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Загрузка контактов…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: WorkaColors.textGreyDark,
                ),
              ),
            ),
          ],
        );
      }
      if (hydrationState.error != null) {
        return OutlinedButton(
          onPressed: () {
            unawaited(
              contactCtrl.ensureLoadedContactForCandidate(resolvedKey),
            );
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: WorkaColors.blue,
            side: const BorderSide(color: WorkaColors.blue, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkaUiRadius.control),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: const Text(
            'Повторить загрузку контактов',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
          ),
        );
      }
      return ElevatedButton(
        onPressed: () {
          unawaited(
            contactCtrl.ensureLoadedContactForCandidate(resolvedKey),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: WorkaColors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkaUiRadius.control),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text(
          'Открыть контакты',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      );
    }

    final bool showContactsOpenedBadge =
        !isOwner &&
        contactLoadedNow &&
        (showUnlockedBadge || hasAccessNow);

    if (showContactsOpenedBadge) {
      return _UnlockedBadgeInline();
    }

    if (isOwner) {
      final String text = primaryActionLabel ?? 'Выделить CV';
      return OutlinedButton(
        onPressed: () {
          final id = cvId.trim();
          if (id.isEmpty) {
            debugPrint(
              '[CV PAYWALL] blocked: missing cvId source=owner_card_unlocked',
            );
            return;
          }
          debugPrint('[CV PAYWALL] source=owner_card_unlocked cvId=$id');
          CvHighlightPaywallSheet.open(
            context,
            cvId: id,
            originSource: 'owner_card',
            cvOwnerType: 'personal',
            cvOwnerId: ownership.ownerUid,
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: WorkaColors.orange,
          side: const BorderSide(color: WorkaColors.orange, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkaUiRadius.control),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      onPressed: () {
        RuntimeFlowLogger.mark(
          'CANDIDATE_PREVIEW_SHEET_BYPASSED',
          <String, Object?>{
            'surface': 'cv_card_primary_cta_fallback',
            'candidateId': candidateId.trim(),
            'mode': mode.name,
          },
        );
        onTap();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkaUiRadius.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: const Text(
        'Связаться',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  String _resolveContactKey(ContactAccessController contactCtrl) {
    final keyOverride = resolvedContactKey.trim();
    if (keyOverride.isNotEmpty) return keyOverride;
    return contactCtrl.resolveCandidateContactKey(
      candidateId: candidateId.trim(),
      candidateKey: candidateKey.trim(),
      canonicalCandidateId: canonicalCandidateId.trim(),
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
}

class _UnlockedBadgeInline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7EE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF1E7B3A).withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.verified_outlined, size: 16, color: Color(0xFF1E7B3A)),
            SizedBox(width: 6),
            Text(
              'Контакты открыты',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF1E7B3A),
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
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
