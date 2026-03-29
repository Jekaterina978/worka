import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';

enum CvSection {
  header,
  title,
  about,
  desiredJob,
  experience,
  education,
  languages,
  computerSkills,
  driving,
}

enum CvViewerMode { employer, ownerView, ownerEdit }

class CvProfileView extends StatelessWidget {
  final String cvId;
  final Map<String, dynamic> cv;
  final CvViewerMode mode;
  final void Function(CvSection section)? onEditSection;
  final EdgeInsetsGeometry padding;
  final bool showHeaderSection;
  final bool showTitleSection;
  final bool hideEmptySections;
  final bool showSensitiveContacts;

  const CvProfileView({
    super.key,
    required this.cvId,
    required this.cv,
    required this.mode,
    this.onEditSection,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 16),
    this.showHeaderSection = true,
    this.showTitleSection = true,
    this.hideEmptySections = false,
    this.showSensitiveContacts = true,
  });

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  Map<String, dynamic> _map(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _listMap(dynamic v) {
    if (v is! List) return const <Map<String, dynamic>>[];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<String> _listString(dynamic v) {
    if (v is! List) return const <String>[];
    return v
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _firstNonEmpty(
    Map<String, dynamic> m,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final k in keys) {
      final val = _s(m[k]);
      if (val.isNotEmpty) return val;
    }
    return fallback;
  }

  dynamic _firstValue(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k];
    }
    return null;
  }

  List<Map<String, dynamic>> _normalizeRecords(dynamic v) {
    final out = <Map<String, dynamic>>[];
    if (v is! List) return out;
    for (final item in v) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      } else if (item != null && item.toString().trim().isNotEmpty) {
        out.add(<String, dynamic>{'value': item.toString().trim()});
      }
    }
    return out;
  }

  Map<String, int?> _parseMonthYear(dynamic raw) {
    if (raw == null) return const {'month': null, 'year': null};
    if (raw is DateTime) return {'month': raw.month, 'year': raw.year};

    final text = raw.toString().trim();
    if (text.isEmpty) return const {'month': null, 'year': null};

    final iso = RegExp(r'^(\d{4})-(\d{1,2})(?:-\d{1,2})?$').firstMatch(text);
    if (iso != null) {
      return {
        'month': int.tryParse(iso.group(2)!),
        'year': int.tryParse(iso.group(1)!),
      };
    }

    final dot = RegExp(r'^(\d{1,2})[./-](\d{4})$').firstMatch(text);
    if (dot != null) {
      return {
        'month': int.tryParse(dot.group(1)!),
        'year': int.tryParse(dot.group(2)!),
      };
    }

    final yearOnly = int.tryParse(text);
    if (yearOnly != null && yearOnly >= 1900 && yearOnly <= 3000) {
      return {'month': null, 'year': yearOnly};
    }

    return const {'month': null, 'year': null};
  }

  Map<String, dynamic> _normalizePeriodRecord(Map<String, dynamic> row) {
    final out = Map<String, dynamic>.from(row);
    int? startMonth = out['startMonth'] is num
        ? (out['startMonth'] as num).toInt()
        : null;
    int? startYear = out['startYear'] is num
        ? (out['startYear'] as num).toInt()
        : null;
    int? endMonth = out['endMonth'] is num
        ? (out['endMonth'] as num).toInt()
        : null;
    int? endYear = out['endYear'] is num
        ? (out['endYear'] as num).toInt()
        : null;
    bool isCurrent = out['isCurrent'] == true || out['current'] == true;

    if (startMonth == null || startYear == null) {
      final parsedStart = _parseMonthYear(
        _firstValue(out, const ['startDate', 'dateFrom', 'from']),
      );
      startMonth ??= parsedStart['month'];
      startYear ??= parsedStart['year'];
    }
    if (!isCurrent && (endMonth == null || endYear == null)) {
      final parsedEnd = _parseMonthYear(
        _firstValue(out, const ['endDate', 'dateTo', 'to']),
      );
      endMonth ??= parsedEnd['month'];
      endYear ??= parsedEnd['year'];
    }
    if (_s(out['endDate']).toLowerCase().contains('настоя')) {
      isCurrent = true;
    }

    out['startMonth'] = startMonth;
    out['startYear'] = startYear;
    out['endMonth'] = isCurrent ? null : endMonth;
    out['endYear'] = isCurrent ? null : endYear;
    out['isCurrent'] = isCurrent;
    return out;
  }

  Map<String, dynamic> normalizeCv(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);

    final desiredRaw = _map(
      _firstValue(raw, const ['desired', 'desiredJob', 'wantedJob']) ??
          <String, dynamic>{},
    );
    final contactsRaw = _map(
      _firstValue(raw, const ['contacts', 'contact']) ?? <String, dynamic>{},
    );
    if (contactsRaw.isEmpty) {
      contactsRaw.addAll(<String, dynamic>{
        'name': _firstValue(raw, const ['name', 'fullName']) ?? '',
        'email': _firstValue(raw, const ['email']) ?? '',
        'phone': _firstValue(raw, const ['phone', 'phoneNumber']) ?? '',
      });
    }
    if (!contactsRaw.containsKey('city')) {
      contactsRaw['city'] =
          _firstValue(raw, const ['city', 'location', 'address']) ?? '';
    }
    if (!contactsRaw.containsKey('gender')) {
      contactsRaw['gender'] = _firstValue(raw, const ['gender', 'sex']) ?? '';
    }
    if (!contactsRaw.containsKey('birthDate')) {
      contactsRaw['birthDate'] = _firstValue(raw, const ['birthDate']) ?? '';
    }
    if (!contactsRaw.containsKey('citizenshipCountry')) {
      contactsRaw['citizenshipCountry'] =
          _firstValue(raw, const ['citizenshipCountry', 'citizenshipName']) ??
          '';
    }
    if (desiredRaw.isEmpty) {
      desiredRaw.addAll(<String, dynamic>{
        'categoryGroup':
            _firstValue(raw, const ['categoryGroup', 'category']) ?? '',
        'position':
            _firstValue(raw, const [
              'position',
              'jobTitle',
              'desiredPosition',
            ]) ??
            '',
        'employmentType':
            _firstValue(raw, const ['employmentType', 'employment']) ?? '',
        'schedule': _firstValue(raw, const ['schedule', 'shift', 'rate']) ?? '',
        'salaryText': _firstValue(raw, const ['salaryText', 'salary']) ?? '',
        'countries': _firstValue(raw, const ['countries']) ?? const <String>[],
        'locationLabel':
            _firstValue(raw, const ['locationLabel', 'location']) ?? '',
      });
    }

    final rawSkills = raw['skills'];
    final rawComputer = _map(raw['computerSkills']);
    final selected = <String>[
      ..._listString(rawComputer['selected']),
      ..._listString(rawComputer['computerPrograms']),
      if (rawSkills is List) ..._listString(rawSkills),
      if (rawSkills is Map) ..._listString(rawSkills['computerPrograms']),
    ];
    final other = _s(
      rawComputer['other'],
      fallback: rawSkills is Map
          ? _s(rawSkills['computer'])
          : _s(raw['skillsOther']),
    );

    final rawDriving = _map(
      _firstValue(raw, const ['drivingLicense', 'driverLicense', 'driving']),
    );
    final categories = _listString(rawDriving['categories']);
    final legacyLicense = _s(rawDriving['license']);

    final languagesRaw = _firstValue(raw, const [
      'languages',
      'languageSkills',
      'langs',
    ]);
    final normalizedLanguages = _normalizeRecords(languagesRaw).map((m) {
      if (m.containsKey('language') || m.containsKey('level')) return m;
      return <String, dynamic>{
        'language': _s(_firstValue(m, const ['name', 'value', 'title'])),
        'level': _s(_firstValue(m, const ['level', 'proficiency'])),
      };
    }).toList();

    final expRaw = _firstValue(raw, const [
      'experience',
      'experiences',
      'workExperience',
    ]);
    final eduRaw = _firstValue(raw, const ['education', 'educations']);

    out['title'] = _s(
      _firstValue(raw, const ['title', 'position', 'jobTitle', 'profession']),
    );
    out['about'] = _s(
      _firstValue(raw, const [
        'about',
        'summary',
        'description',
        'shortDescription',
      ]),
    );
    out['summary'] = _s(
      _firstValue(raw, const ['summary', 'about', 'description']),
    );
    out['contacts'] = contactsRaw;
    out['desired'] = desiredRaw;
    out['experience'] = _normalizeRecords(
      expRaw,
    ).map(_normalizePeriodRecord).toList();
    out['education'] = _normalizeRecords(
      eduRaw,
    ).map(_normalizePeriodRecord).toList();
    out['languages'] = normalizedLanguages;
    out['computerSkills'] = <String, dynamic>{
      'selected': selected.toSet().toList(),
      'other': other,
    };
    out['drivingLicense'] = <String, dynamic>{
      'hasLicense':
          rawDriving['hasLicense'] == true ||
          categories.isNotEmpty ||
          legacyLicense.isNotEmpty,
      'categories': categories.isNotEmpty
          ? categories
          : (legacyLicense.isEmpty
                ? const <String>[]
                : <String>[legacyLicense]),
      'hasCar': rawDriving['hasCar'] == true,
    };

    final visibility = _map(raw['visibility']);
    if (raw.containsKey('showToEmployers')) {
      visibility['inCandidates'] = raw['showToEmployers'] == true;
    }
    if (raw.containsKey('inCandidates')) {
      visibility['inCandidates'] = raw['inCandidates'] == true;
    }
    out['visibility'] = visibility;

    return out;
  }

  String formatMonthYear(int? month, int? year) {
    if (year == null) return '';
    if (month == null || month < 1 || month > 12) return '$year';
    final mm = month.toString().padLeft(2, '0');
    return '$mm.$year';
  }

  DateTime? _dateFromAny(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw == null) return null;
    try {
      final dynamic value = raw;
      final dynamic converted = value.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  String _birthDateText(dynamic raw) {
    final date = _dateFromAny(raw);
    if (date == null) return '';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd.$mm.${date.year}';
  }

  String formatRange(Map<String, dynamic> m) {
    final startMonth = m['startMonth'] is num
        ? (m['startMonth'] as num).toInt()
        : null;
    final startYear = m['startYear'] is num
        ? (m['startYear'] as num).toInt()
        : null;
    final endMonth = m['endMonth'] is num
        ? (m['endMonth'] as num).toInt()
        : null;
    final endYear = m['endYear'] is num ? (m['endYear'] as num).toInt() : null;
    final isCurrent = m['isCurrent'] == true;

    final startText = formatMonthYear(startMonth, startYear);
    final endText = isCurrent ? 'н.в.' : formatMonthYear(endMonth, endYear);
    if (startText.isEmpty && endText.isEmpty) return '';
    if (startText.isNotEmpty && endText.isEmpty) return startText;
    if (startText.isEmpty && endText.isNotEmpty) return endText;
    return '$startText — $endText';
  }

  List<String> _computerSkills(Map<String, dynamic> root) {
    final out = <String>{};

    final computerSkills = _map(root['computerSkills']);
    out.addAll(_listString(computerSkills['selected']));

    final otherSkills = _s(computerSkills['other']);
    if (otherSkills.isNotEmpty) {
      out.addAll(
        otherSkills
            .split(RegExp(r'[,;/]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    }

    final skills = _map(root['skills']);
    out.addAll(_listString(skills['computerPrograms']));

    final legacySkills = _s(skills['computer']);
    if (legacySkills.isNotEmpty) {
      out.addAll(
        legacySkills
            .split(RegExp(r'[,;/]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    }

    return out.toList();
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    required CvSection section,
    String? ctaLabel,
  }) {
    final canEdit = mode == CvViewerMode.ownerEdit && onEditSection != null;

    return InkWell(
      onTap: canEdit ? () => onEditSection!(section) : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WorkaColors.divider),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              offset: const Offset(0, 6),
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: WorkaColors.textDark,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                if (canEdit)
                  const Icon(Icons.edit, size: 18, color: WorkaColors.blue),
              ],
            ),
            const SizedBox(height: 10),
            child,
            if (canEdit && ctaLabel != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => onEditSection!(section),
                  style: TextButton.styleFrom(
                    foregroundColor: WorkaColors.blue,
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  child: Text(ctaLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaLine(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: WorkaColors.textDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _languageText(List<Map<String, dynamic>> languages) {
    final rows = <String>[];
    for (final l in languages) {
      final language = _s(l['language'], fallback: _s(l['name']));
      final level = _s(l['level'], fallback: _s(l['proficiency']));
      final text = [language, level].where((x) => x.isNotEmpty).join(' — ');
      if (text.isNotEmpty) rows.add(text);
    }
    return rows.join('; ');
  }

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeCv(cv);
    final contacts = _map(normalized['contacts']);
    final desired = _map(normalized['desired']);

    final name = _firstNonEmpty(contacts, const ['name'], fallback: 'Кандидат');
    final email = _s(contacts['email']);
    final phone = _s(contacts['phone']);

    final title = _s(
      normalized['title'],
      fallback: _s(desired['position'], fallback: 'CV'),
    );
    final category = _firstNonEmpty(desired, const [
      'categoryGroup',
      'category',
    ]);
    final position = _s(desired['position']);

    final countries = _listString(desired['countries']);
    final locationLabel = _firstNonEmpty(desired, const [
      'locationLabel',
      'location',
    ], fallback: countries.join(', '));

    final summary = _s(normalized['summary']);
    final about = _s(normalized['about'], fallback: summary);
    final citizenship = _firstNonEmpty(contacts, const [
      'citizenshipCountry',
      'citizenshipName',
      'citizenship',
    ], fallback: _s(normalized['citizenshipCountry']));
    final cityFromContacts = _firstNonEmpty(contacts, const [
      'city',
      'location',
      'address',
    ]);
    final gender = _firstNonEmpty(contacts, const ['gender', 'sex']);
    final birthDateText = _birthDateText(
      _firstValue(contacts, const ['birthDate']) ?? normalized['birthDate'],
    );

    final employmentType = _firstNonEmpty(desired, const [
      'employmentType',
      'type',
    ]);
    final schedule = _firstNonEmpty(desired, const [
      'schedule',
      'shift',
      'rate',
    ]);
    final salary = _firstNonEmpty(desired, const [
      'salaryText',
      'salary',
      'salaryFrom',
    ]);
    final citiesText = _firstNonEmpty(desired, const [
      'citiesText',
    ], fallback: '');

    final experience = _listMap(normalized['experience']);
    final education = _listMap(normalized['education']);
    final languages = _listMap(normalized['languages']);
    final skills = _computerSkills(normalized);

    final drivingNew = _map(normalized['drivingLicense']);
    final drivingOld = _map(normalized['driving']);
    final hasLicense =
        drivingNew['hasLicense'] == true ||
        _s(drivingOld['license']).isNotEmpty;
    final drivingCategories = _listString(drivingNew['categories']);
    final drivingCategoryLabel = drivingCategories.isNotEmpty
        ? drivingCategories.join(', ')
        : _s(drivingOld['license']);
    final hasCar = drivingNew['hasCar'] == true || drivingOld['hasCar'] == true;
    final profileHasAny =
        name.trim().isNotEmpty ||
        email.trim().isNotEmpty ||
        phone.trim().isNotEmpty ||
        citizenship.trim().isNotEmpty ||
        cityFromContacts.trim().isNotEmpty ||
        gender.trim().isNotEmpty ||
        birthDateText.trim().isNotEmpty ||
        locationLabel.trim().isNotEmpty;
    final profileComplete =
        name.trim().isNotEmpty &&
        email.trim().isNotEmpty &&
        phone.trim().isNotEmpty;
    final profileCta = !profileHasAny
        ? 'Заполнить'
        : (profileComplete ? null : 'Дополнить');
    final hasAnyTitle = title.trim().isNotEmpty;
    final titleCta = hasAnyTitle ? null : 'Заполнить';
    final hasAnyDesired =
        category.isNotEmpty ||
        position.isNotEmpty ||
        employmentType.isNotEmpty ||
        schedule.isNotEmpty ||
        salary.isNotEmpty ||
        countries.isNotEmpty ||
        citiesText.isNotEmpty;
    final desiredComplete =
        category.isNotEmpty &&
        position.isNotEmpty &&
        employmentType.isNotEmpty &&
        countries.isNotEmpty;
    final desiredCta = !hasAnyDesired
        ? 'Заполнить'
        : (desiredComplete ? null : 'Дополнить');

    final hasAnyAbout = about.isNotEmpty;
    final aboutCta = hasAnyAbout ? null : 'Заполнить';

    bool hasAnyExperience = false;
    bool experienceComplete = true;
    for (final e in experience) {
      final positionLabel = _s(e['position']);
      final company = _s(e['company']);
      final desc = _s(e['description']);
      final period = formatRange(e);
      if (positionLabel.isNotEmpty ||
          company.isNotEmpty ||
          desc.isNotEmpty ||
          period.isNotEmpty) {
        hasAnyExperience = true;
      }
      if (positionLabel.isEmpty || company.isEmpty) {
        experienceComplete = false;
      }
    }
    final experienceCta = !hasAnyExperience
        ? 'Заполнить'
        : (experienceComplete ? null : 'Дополнить');

    bool hasAnyEducation = false;
    bool educationComplete = true;
    for (final e in education) {
      final school = _s(e['school']);
      final specialization = _firstNonEmpty(e, const [
        'specialization',
        'speciality',
      ]);
      final country = _s(e['country']);
      if (school.isNotEmpty ||
          specialization.isNotEmpty ||
          country.isNotEmpty) {
        hasAnyEducation = true;
      }
      if (school.isEmpty || country.isEmpty) {
        educationComplete = false;
      }
    }
    final educationCta = !hasAnyEducation
        ? 'Заполнить'
        : (educationComplete ? null : 'Дополнить');

    final hasAnyLanguages = _languageText(languages).trim().isNotEmpty;
    bool languagesComplete = true;
    for (final l in languages) {
      final language = _s(l['language'], fallback: _s(l['name']));
      final level = _s(l['level'], fallback: _s(l['proficiency']));
      if (language.isEmpty || level.isEmpty) {
        languagesComplete = false;
      }
    }
    final languagesCta = !hasAnyLanguages
        ? 'Заполнить'
        : (languagesComplete ? null : 'Дополнить');

    final hasAnySkills = skills.isNotEmpty;
    final skillsCta = hasAnySkills ? null : 'Заполнить';

    final hasAnyDriving =
        hasLicense || hasCar || drivingCategoryLabel.trim().isNotEmpty;
    final drivingComplete =
        hasLicense && drivingCategoryLabel.trim().isNotEmpty;
    final drivingCta = !hasAnyDriving
        ? 'Заполнить'
        : (drivingComplete ? null : 'Дополнить');
    final showProfileCard =
        showHeaderSection && (!hideEmptySections || profileHasAny);
    final showTitleCard =
        showTitleSection && (!hideEmptySections || hasAnyTitle);
    final showAboutCard = !hideEmptySections || hasAnyAbout;
    final showDesiredCard = !hideEmptySections || hasAnyDesired;
    final showExperienceCard = !hideEmptySections || hasAnyExperience;
    final showEducationCard = !hideEmptySections || hasAnyEducation;
    final showLanguagesCard = !hideEmptySections || hasAnyLanguages;
    final showSkillsCard = !hideEmptySections || hasAnySkills;
    final showDrivingCard = !hideEmptySections || hasAnyDriving;
    final initials = name
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e.substring(0, 1).toUpperCase())
        .join();
    final canRenderSensitiveContacts =
        mode != CvViewerMode.employer || showSensitiveContacts;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showProfileCard)
            _sectionCard(
              title: 'Профиль',
              section: CvSection.header,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      child: Text(
                        initials.isEmpty ? 'U' : initials,
                        style: const TextStyle(
                          color: WorkaColors.blue,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (cityFromContacts.isNotEmpty) cityFromContacts,
                              if (citizenship.isNotEmpty) citizenship,
                            ].where((e) => e.isNotEmpty).join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (locationLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              locationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          if (canRenderSensitiveContacts &&
                              (email.isNotEmpty || phone.isNotEmpty)) ...[
                            const SizedBox(height: 6),
                            Text(
                              [
                                email,
                                phone,
                              ].where((e) => e.isNotEmpty).join(' • '),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          if (gender.isNotEmpty ||
                              birthDateText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (gender.isNotEmpty) gender,
                                if (birthDateText.isNotEmpty) birthDateText,
                              ].join(' • '),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ctaLabel: profileCta,
            ),
          if (showProfileCard) const SizedBox(height: 12),

          if (showTitleCard)
            _sectionCard(
              title: 'Заголовок',
              section: CvSection.title,
              ctaLabel: titleCta,
              child: hasAnyTitle
                  ? Text(
                      title,
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    )
                  : const Text(
                      'Раздел пока пустой',
                      style: TextStyle(
                        color: WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          if (showTitleCard) const SizedBox(height: 12),

          if (showAboutCard)
            _sectionCard(
              title: 'О себе',
              section: CvSection.about,
              ctaLabel: aboutCta,
              child: hasAnyAbout
                  ? Text(
                      about,
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    )
                  : const Text(
                      'Раздел пока пустой',
                      style: TextStyle(
                        color: WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          if (showAboutCard) const SizedBox(height: 12),

          if (showDesiredCard)
            _sectionCard(
              title: 'Желаемая работа',
              section: CvSection.desiredJob,
              ctaLabel: desiredCta,
              child: hasAnyDesired
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _metaLine('Категория', category),
                        _metaLine('Должность', position),
                        _metaLine('График', employmentType),
                        _metaLine('График/ставка', schedule),
                        _metaLine('Зарплата', salary),
                        _metaLine('Страны', countries.join(', ')),
                        _metaLine('Города', citiesText),
                      ],
                    )
                  : const Text(
                      'Раздел пока пустой',
                      style: TextStyle(
                        color: WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          if (showDesiredCard) const SizedBox(height: 12),

          if (showExperienceCard)
            _sectionCard(
              title: 'Опыт работы',
              section: CvSection.experience,
              ctaLabel: experienceCta,
              child: hasAnyExperience
                  ? Column(
                      children: experience.map((e) {
                        final positionLabel = _s(e['position']);
                        final company = _s(e['company']);
                        final country = _s(e['country']);
                        final desc = _s(e['description']);
                        final period = formatRange(e);
                        final companyLine = [
                          company,
                          country,
                        ].where((x) => x.isNotEmpty).join(', ');

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: WorkaColors.fieldBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                positionLabel.isNotEmpty
                                    ? positionLabel
                                    : 'Должность не указана',
                                style: const TextStyle(
                                  color: WorkaColors.textDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (companyLine.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  companyLine,
                                  style: const TextStyle(
                                    color: WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if (period.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  period,
                                  style: const TextStyle(
                                    color: WorkaColors.textGrey,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  desc,
                                  style: const TextStyle(
                                    color: WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  : const Text(
                      'Раздел пока пустой',
                      style: TextStyle(
                        color: WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          if (showExperienceCard) const SizedBox(height: 12),

          if (showEducationCard)
            _sectionCard(
              title: 'Образование',
              section: CvSection.education,
              ctaLabel: educationCta,
              child: hasAnyEducation
                  ? Column(
                      children: education.map((e) {
                        final school = _s(e['school']);
                        final specialization = _firstNonEmpty(e, const [
                          'specialization',
                          'speciality',
                        ]);
                        final country = _s(e['country']);
                        final period = formatRange(e);

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: WorkaColors.fieldBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                school.isNotEmpty
                                    ? school
                                    : 'Учебное заведение не указано',
                                style: const TextStyle(
                                  color: WorkaColors.textDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (country.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '($country)',
                                  style: const TextStyle(
                                    color: WorkaColors.textGrey,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if (period.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  period,
                                  style: const TextStyle(
                                    color: WorkaColors.textGrey,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              if (specialization.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Специальность: $specialization',
                                  style: const TextStyle(
                                    color: WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  : const Text(
                      'Раздел пока пустой',
                      style: TextStyle(
                        color: WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          if (showEducationCard) const SizedBox(height: 12),

          if (showLanguagesCard)
            _sectionCard(
              title: 'Языки',
              section: CvSection.languages,
              ctaLabel: languagesCta,
              child: hasAnyLanguages
                  ? Text(
                      _languageText(languages),
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    )
                  : const Text(
                      'Раздел пока пустой',
                      style: TextStyle(
                        color: WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          if (showLanguagesCard) const SizedBox(height: 12),

          if (showSkillsCard)
            _sectionCard(
              title: 'Знание компьютера',
              section: CvSection.computerSkills,
              ctaLabel: skillsCta,
              child: hasAnySkills
                  ? Text(
                      skills.join(', '),
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    )
                  : const Text(
                      'Раздел пока пустой',
                      style: TextStyle(
                        color: WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          if (showSkillsCard) const SizedBox(height: 12),

          if (showDrivingCard)
            _sectionCard(
              title: 'Водительские права',
              section: CvSection.driving,
              ctaLabel: drivingCta,
              child: hasAnyDriving
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Категория',
                          style: TextStyle(
                            color: WorkaColors.textGrey,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          drivingCategoryLabel.isEmpty
                              ? 'Не указано'
                              : drivingCategoryLabel,
                          style: const TextStyle(
                            color: WorkaColors.textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        if (hasCar) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Личный автомобиль',
                            style: TextStyle(
                              color: WorkaColors.textGreyDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    )
                  : const Text(
                      'Раздел пока пустой',
                      style: TextStyle(
                        color: WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          if (showDrivingCard) const SizedBox(height: 12),
        ],
      ),
    );
  }
}
