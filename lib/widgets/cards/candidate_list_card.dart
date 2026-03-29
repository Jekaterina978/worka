import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/candidate_age.dart';
import '../../theme/worka_colors.dart';
import '../../screens/cv/widgets/cv_card_formatters.dart';
import '../../screens/employer/search/widgets/offer_job_picker_sheet.dart';
import 'candidate_cv_card.dart';
import '../card_more_menu_button.dart';
import '../status_pill_badge.dart';
import '../../features/payments/contact_access_controller.dart';

class CandidateListCard extends StatelessWidget {
  const CandidateListCard({
    super.key,
    required this.onTap,
    required this.name,
    this.ageText = '',
    required this.profession,
    required this.location,
    this.category = '',
    this.language = '',
    this.experience = '',
    this.salaryExpectation = '',
    this.birthDate,
    this.citizenshipCountry = '',
    this.topRight,
    this.statusBadge,
    this.footer,
    this.onContactTap,
    this.readyToWork = false,
    this.hasWorkDocuments = false,
    this.profileViews = 0,
    this.isNewCandidate = false,
    this.hasDriverLicense = false,
    this.hasCar = false,
    this.hasTools = false,
    this.hasWorkwear = false,
    this.hasComputerSkills = false,
    this.drivingLicenseCategories = const <String>[],
    this.languagesData = const <Map<String, dynamic>>[],
    this.readyToRelocate = false,
    this.contactsOpened = false,
    this.hasOfferSent = false,
    this.candidateId = '',
    this.candidateUid = '',
    this.candidateData,
    this.testMode = true,
    this.margin = EdgeInsets.zero,
    this.modeOverride,
  });

  final VoidCallback? onTap;
  final String name;
  final String ageText;
  final String profession;
  final String location;
  final String category;
  final String language;
  final String experience;
  final String salaryExpectation;
  final dynamic birthDate;
  final String citizenshipCountry;
  final Widget? topRight;
  final Widget? statusBadge;
  final Widget? footer;
  final VoidCallback? onContactTap;
  final bool readyToWork;
  final bool hasWorkDocuments;
  final int profileViews;
  final bool isNewCandidate;
  final bool hasDriverLicense;
  final bool hasCar;
  final bool hasTools;
  final bool hasWorkwear;
  final bool hasComputerSkills;
  final List<String> drivingLicenseCategories;
  final List<Map<String, dynamic>> languagesData;
  final bool readyToRelocate;
  final bool contactsOpened;
  final bool hasOfferSent;
  final String candidateId;
  final String candidateUid;
  final Map<String, dynamic>? candidateData;
  final bool testMode;
  final EdgeInsets margin;
  final CandidateCvCardMode? modeOverride;

  Widget? _footerLeading(Widget? effectiveStatusBadge) {
    if (effectiveStatusBadge == null && footer == null && profileViews <= 0) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (effectiveStatusBadge != null) effectiveStatusBadge,
        if (profileViews > 0) ...[
          if (effectiveStatusBadge != null) const SizedBox(height: 8),
          Text(
            '🔥 $profileViews просмотров профиля',
            style: const TextStyle(
              color: WorkaColors.orange,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
        if (footer != null) ...[
          if (statusBadge != null || profileViews > 0)
            const SizedBox(height: 8),
          footer!,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ContactAccessController>();
    final hasAccess = ctrl.hasAccess(candidateId);
    debugPrint(
      '[CANDIDATE_CARD_RENDER] candidateId=$candidateId hasAccess=$hasAccess ctrlHash=${identityHashCode(ctrl)}',
    );
    final Widget? effectiveStatusBadge =
        statusBadge ?? (hasAccess ? _contactUnlockedBadge() : null);
    final data = candidateData ?? const <String, dynamic>{};
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    if ((data['isDeleted'] ?? false) == true) {
      return const SizedBox.shrink();
    }
    final contacts = (data['contacts'] is Map)
        ? Map<String, dynamic>.from(data['contacts'] as Map)
        : const <String, dynamic>{};
    final desired = (data['desired'] is Map)
        ? Map<String, dynamic>.from(data['desired'] as Map)
        : const <String, dynamic>{};
    final cvCountries = (desired['countries'] is List)
        ? (desired['countries'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];
    bool isPlaceholder(String v) {
      final lower = v.toLowerCase();
      return lower == 'не указано' || lower == 'не указан' || lower == 'n/a';
    }

    String clean(String v) => isPlaceholder(v) ? '' : v;

    final cvName = [
      clean((contacts['name'] ?? '').toString().trim()),
      clean(
        [
          (contacts['firstName'] ?? '').toString().trim(),
          (contacts['lastName'] ?? '').toString().trim(),
        ].where((e) => e.isNotEmpty).join(' ').trim(),
      ),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final canUseSensitiveContacts = hasAccess || contactsOpened;
    final cvProfession = [
      clean((desired['position'] ?? '').toString().trim()),
      clean((data['title'] ?? '').toString().trim()),
      clean((data['profession'] ?? '').toString().trim()),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final cvCity = [
      (desired['citiesText'] ?? '').toString().trim(),
      (contacts['city'] ?? '').toString().trim(),
      (data['city'] ?? '').toString().trim(),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final cvCountry = cvCountries.isNotEmpty
        ? cvCountries.first
        : ([
            (data['country'] ?? '').toString().trim(),
            (contacts['country'] ?? '').toString().trim(),
          ].firstWhere((e) => e.isNotEmpty, orElse: () => ''));
    if (cvName.isEmpty || cvProfession.isEmpty) {
      return const SizedBox.shrink();
    }
    final effectiveName = cvName;
    final effectiveProfession = cvProfession;
    final effectiveLocation = [
      cvCity,
      cvCountry,
    ].where((e) => e.isNotEmpty).join(', ');
    final locationParts = effectiveLocation.isNotEmpty
        ? (() {
            final parts = effectiveLocation
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            if (parts.length < 2) {
              return (city: parts.isEmpty ? '' : parts.first, country: '');
            }
            return (city: parts.first, country: parts.last);
          })()
        : (city: '', country: '');
    final ageFromProp = ageText.trim();
    final ageFromCv = CandidateAge.fromMap(data);
    final ageRaw = ageFromProp.isNotEmpty ? ageFromProp : ageFromCv;
    final age = ageRaw.isNotEmpty ? int.tryParse(ageRaw) : null;
    final avatarUrl = [
      (data['avatarUrl'] ?? '').toString().trim(),
      (data['photoUrl'] ?? '').toString().trim(),
      (contacts['avatarUrl'] ?? '').toString().trim(),
      (contacts['photoUrl'] ?? '').toString().trim(),
      (contacts['imageUrl'] ?? '').toString().trim(),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final gender = [
      (data['gender'] ?? '').toString().trim(),
      (contacts['gender'] ?? '').toString().trim(),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final salary = (desired['salaryText'] ?? '').toString().trim();
    final readiness = [
      (desired['availabilityText'] ?? '').toString().trim(),
      (desired['readiness'] ?? '').toString().trim(),
      (data['availabilityText'] ?? '').toString().trim(),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final cvLanguages = (data['languages'] is List)
        ? (data['languages'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];
    final cvDrivingCategories =
        (data['drivingLicense'] is Map &&
            (data['drivingLicense'] as Map)['categories'] is List)
        ? ((data['drivingLicense'] as Map)['categories'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : ((data['drivingCategories'] is List)
              ? (data['drivingCategories'] as List)
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : const <String>[]);
    final cvHasComputerSkills =
        data['hasComputerSkills'] == true ||
        (data['skills'] is Map &&
            ((data['skills'] as Map)['computer'] ?? '')
                .toString()
                .trim()
                .isNotEmpty);
    final cvHasCar =
        data['hasCar'] == true ||
        (data['drivingLicense'] is Map &&
            (data['drivingLicense'] as Map)['hasCar'] == true);
    final cvHasTools = data['hasTools'] == true;
    final cvHasWorkwear = data['hasWorkwear'] == true;
    final cvBadges = buildCandidateBadges(
      languages: cvLanguages,
      drivingLicenseCategories: cvDrivingCategories,
      hasCar: cvHasCar,
      hasTools: cvHasTools,
      hasWorkwear: cvHasWorkwear,
      hasComputerSkills: cvHasComputerSkills,
    );
    final effectiveBadges = cvBadges;
    final ownerMenuItems = <CardMenuItem>[
      CardMenuItem(label: 'Изменить', onTap: onTap ?? () {}),
      CardMenuItem(label: 'Копировать', onTap: onTap ?? () {}),
      CardMenuItem(label: 'Удалить', onTap: onTap ?? () {}),
    ];
    final statusPill = effectiveStatusBadge is StatusPillBadge
        ? effectiveStatusBadge as StatusPillBadge
        : null;
    final cardMode =
        modeOverride ??
        (hasOfferSent || onContactTap != null
            ? CandidateCvCardMode.search
            : (statusPill != null
                  ? CandidateCvCardMode.offerStatus
                  : CandidateCvCardMode.viewer));
    final phone = canUseSensitiveContacts
        ? [
            (data['phone'] ?? '').toString().trim(),
            (contacts['phone'] ?? '').toString().trim(),
            (data['phoneNumber'] ?? '').toString().trim(),
          ].firstWhere((e) => e.isNotEmpty, orElse: () => '')
        : '';
    final email = canUseSensitiveContacts
        ? [
            (data['email'] ?? '').toString().trim(),
            (contacts['email'] ?? '').toString().trim(),
          ].firstWhere((e) => e.isNotEmpty, orElse: () => '')
        : '';
    final telegram = canUseSensitiveContacts
        ? [
            (data['telegram'] ?? '').toString().trim(),
            (contacts['telegram'] ?? '').toString().trim(),
            (contacts['tg'] ?? '').toString().trim(),
          ].firstWhere((e) => e.isNotEmpty, orElse: () => '')
        : '';
    final rawWorkType =
        desired['employmentType'] ??
        data['workType'] ??
        data['employmentType'] ??
        data['type'];
    final workType = rawWorkType is List
        ? rawWorkType
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .join(', ')
        : rawWorkType.toString().trim();
    final cvUserId = [
      (data['userId'] ?? '').toString().trim(),
      (contacts['userId'] ?? '').toString().trim(),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final cvOwnerId = [
      (data['ownerId'] ?? '').toString().trim(),
      (data['ownerUid'] ?? '').toString().trim(),
      (data['candidateUid'] ?? '').toString().trim(),
      candidateUid.trim(),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
    return Padding(
      padding: margin,
      child: Column(
        children: [
          CandidateCvCard(
            mode: cardMode,
            fullName: effectiveName.isEmpty ? 'Кандидат' : effectiveName,
            age: age,
            citizenshipCountry: [
              (data['citizenshipCountry'] ?? '').toString().trim(),
              (data['citizenshipName'] ?? '').toString().trim(),
            ].firstWhere((e) => e.isNotEmpty, orElse: () => ''),
            profession: effectiveProfession,
            city: locationParts.city,
            country: locationParts.country,
            countries: cvCountries,
            badges: effectiveBadges,
            salary: salary,
            readiness: readiness,
            avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
            gender: gender,
            onTap: onTap ?? () {},
            topRight: topRight,
            menuItems: topRight == null
                ? ownerMenuItems
                : const <CardMenuItem>[],
            onPrimaryAction: null,
            primaryActionLabel: statusPill?.label,
            primaryActionColor: statusPill?.backgroundColor,
            hasOfferSent: hasOfferSent,
            phone: phone,
            email: email,
            telegram: telegram,
            cvUserId: cvUserId,
            cvOwnerId: cvOwnerId,
            candidateId: candidateId,
            category: (desired['categoryGroup'] ?? desired['category'] ?? '')
                .toString()
                .trim(),
            workType: workType,
            experience: (desired['experience'] ?? data['experienceLabel'] ?? '')
                .toString()
                .trim(),
            languages: cvLanguages
                .map(
                  (l) =>
                      formatLanguageBadge(
                        (l['language'] ?? l['name'] ?? '').toString(),
                        (l['level'] ?? '').toString(),
                      ) ??
                      '',
                )
                .where((e) => e.trim().isNotEmpty)
                .toList(),
            tools: cvHasTools ? 'Есть' : '',
            workClothes: cvHasWorkwear ? 'Есть' : '',
            availability: readiness,
            aboutSnippet: (data['about'] ?? data['aboutMe'] ?? '')
                .toString()
                .trim(),
            onShowContacts: null,
            onOfferJob:
                (candidateUid.trim().isEmpty || candidateId.trim().isEmpty)
                ? null
                : () async {
                    final sent = await OfferJobPickerSheet.open(
                      context,
                      candidateUid: candidateUid.trim(),
                      candidateCvId: candidateId.trim(),
                      candidateData: candidateData,
                      testMode: testMode,
                    );
                    if (sent == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Предложение отправлено')),
                      );
                    }
                  },
          ),
          if ((statusPill == null) &&
              (effectiveStatusBadge != null ||
                  footer != null ||
                  profileViews > 0))
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: _footerLeading(effectiveStatusBadge) ??
                  const SizedBox.shrink(),
            ),
          if (isNewCandidate)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Новый кандидат',
                style: TextStyle(
                  color: WorkaColors.orange,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _contactUnlockedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Контакты открыты',
        style: TextStyle(
          color: Color(0xFF15803D),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
