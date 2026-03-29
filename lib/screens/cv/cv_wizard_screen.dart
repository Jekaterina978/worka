import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/firebase_debug_diagnostics.dart';
import '../../services/app_mode.dart';
import '../../services/firestore_paths.dart';
import '../../services/auth_guard.dart';
import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';
import '../../widgets/ai_autofill_sheet.dart';
import '../../widgets/contact_fields.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../utils/country_display_formatter.dart';
import 'my_cvs_screen.dart';
import 'widgets/cv_profile_view.dart';
import 'widgets/cv_progress_dots.dart';
import '../auth/auth_entry_screen.dart';
import '../search/widgets/search_filters_config.dart';
import '../../features/monetization/pricing.dart';

abstract final class CvWizardStepIds {
  static const profile = 'profile';
  static const contacts = 'contacts';
  static const about = 'about';
  static const experience = 'experience';
  static const education = 'education';
  static const languages = 'languages';
  static const computerSkills = 'computerSkills';
  static const drivingLicense = 'drivingLicense';
  static const jobPreferences = 'jobPreferences';
}

class CvWizardScreen extends StatefulWidget {
  /// ✅ testMode = true => в тестовом режиме разрешаем ВСЁ без авторизации
  final bool testMode;
  final String? initialStepId;
  final String? existingCvId;

  const CvWizardScreen({
    super.key,
    this.testMode = true,
    this.initialStepId,
    this.existingCvId,
  });

  @override
  State<CvWizardScreen> createState() => _CvWizardScreenState();
}

class _CvWizardScreenState extends State<CvWizardScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== steps =====
  int _step = 0;

  // ===== step 0: contacts =====
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneNumberCtrl = TextEditingController();
  String _phoneCountryCode = '+372';
  final _citizenshipCtrl = TextEditingController();
  final _countryResidenceCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  String _gender = '';
  final _birthDateCtrl = TextEditingController();
  DateTime? _birthDate;

  // ===== step 1: title/summary =====
  final _cvTitleCtrl = TextEditingController();
  final _cvSummaryCtrl = TextEditingController();

  // ===== step 2: experience =====
  final List<_JobRow> _jobs = [const _JobRow()];
  bool _noExperience = false;

  // ===== step 3: education =====
  final List<_EduRow> _edu = [const _EduRow()];

  // ===== step 4: languages =====
  final List<_LangRow> _langs = [const _LangRow(language: '', level: '')];

  // ===== step 5: computer skills =====
  static const List<String> _computerPrograms = <String>[
    'MS Office',
    'Excel',
    'Word',
    'Google Sheets',
    '1C',
    'Касса',
    'Складские программы',
    'CRM',
    'Другое',
  ];
  final Set<String> _computerProgramsSelected = <String>{};
  final _computerOtherCtrl = TextEditingController();

  // ===== step 5 (same screen): driving =====
  bool _hasDrivingLicense = false;
  final Set<String> _drivingCategories = <String>{};
  bool _hasCar = false;
  bool _hasTools = false;
  bool _hasWorkwear = false;

  // ===== step 6: desired job =====
  String _desiredCategoryGroup = '';
  final _desiredPositionCtrl = TextEditingController(); // optional
  final _desiredCitiesCtrl =
      TextEditingController(); // optional, comma-separated
  final _desiredSalaryFromCtrl = TextEditingController(); // optional
  String _desiredSalaryCurrency = 'EUR';
  String _desiredSalaryPeriod = 'month';
  Set<String> _desiredCountries = {}; // ✅ ТОЛЬКО страны с чекбоксами
  final Set<String> _desiredEmploymentTypes = <String>{};
  String _desiredAvailabilityText = '';
  String _desiredSalaryText = '';

  static const List<String> _citizenshipValues = <String>[
    'EU',
    'Казахстан',
    'Узбекистан',
    'Кыргызстан',
    'Таджикистан',
    'Армения',
    'Азербайджан',
    'Молдова',
    'Беларусь',
    'Россия',
    'Украина',
  ];

  static const Map<String, String> _citizenshipLabels = <String, String>{
    'EU': '🇪🇺 EU',
    'Казахстан': '🇰🇿 Казахстан',
    'Узбекистан': '🇺🇿 Узбекистан',
    'Кыргызстан': '🇰🇬 Кыргызстан',
    'Таджикистан': '🇹🇯 Таджикистан',
    'Армения': '🇦🇲 Армения',
    'Азербайджан': '🇦🇿 Азербайджан',
    'Молдова': '🇲🇩 Молдова',
    'Беларусь': '🇧🇾 Беларусь',
    'Россия': '🇷🇺 Россия',
    'Украина': '🇺🇦 Украина',
  };

  // ===== save/limit =====
  static const int maxCv = MonetizationPricing.workerFreeActiveCvLimit;
  bool _checkingLimit = true;
  bool _limitOk = true;

  bool get _isAuthed => _auth.currentUser != null;

  static const List<String> _monthLabels = <String>[
    'Янв',
    'Фев',
    'Мар',
    'Апр',
    'Май',
    'Июн',
    'Июл',
    'Авг',
    'Сен',
    'Окт',
    'Ноя',
    'Дек',
  ];

  static const List<String> _drivingCategoryOptions = <String>[
    'A',
    'B',
    'C',
    'D',
    'BE',
    'CE',
    'DE',
    'AM',
  ];

  static const List<String> _desiredCategoryOptions = <String>[
    'Строительство и рабочие специальности',
    'Логистика и производство',
    'Транспорт и доставка',
    'Торговля и склад',
    'Уборка и обслуживание',
    'Общественное питание',
    'Красота и здоровье',
    'Медицина и уход',
    'Продажи и работа с клиентами',
    'Маркетинг и реклама',
    'Бизнес и управление',
    'Финансы и бухгалтерия',
    'IT и разработка',
    'Другое',
  ];

  static const List<String> _employmentTypeOptions = <String>[
    'Полная занятость',
    'Частичная занятость',
    'Удалённая работа',
    'Гибрид',
    'Проектная',
    'Вахта',
    'Стажировка',
  ];

  static const List<String> _salaryCurrencies = <String>['EUR', 'USD'];
  static const List<String> _salaryPeriods = <String>['hour', 'day', 'month'];

  static const Map<String, String> _countryEnToRu = <String, String>{
    'estonia': 'Эстония',
    'latvia': 'Латвия',
    'lithuania': 'Литва',
    'poland': 'Польша',
    'germany': 'Германия',
    'finland': 'Финляндия',
    'sweden': 'Швеция',
    'norway': 'Норвегия',
    'denmark': 'Дания',
    'france': 'Франция',
    'spain': 'Испания',
    'italy': 'Италия',
    'netherlands': 'Нидерланды',
    'russia': 'Россия',
    'ukraine': 'Украина',
    'belarus': 'Беларусь',
    'kazakhstan': 'Казахстан',
    'uzbekistan': 'Узбекистан',
    'kyrgyzstan': 'Кыргызстан',
    'tajikistan': 'Таджикистан',
    'turkmenistan': 'Туркменистан',
    'armenia': 'Армения',
    'azerbaijan': 'Азербайджан',
    'moldova': 'Молдова',
    'austria': 'Австрия',
    'belgium': 'Бельгия',
    'bulgaria': 'Болгария',
    'croatia': 'Хорватия',
    'cyprus': 'Кипр',
    'czech republic': 'Чехия',
    'czechia': 'Чехия',
    'greece': 'Греция',
    'hungary': 'Венгрия',
    'ireland': 'Ирландия',
    'iceland': 'Исландия',
    'luxembourg': 'Люксембург',
    'malta': 'Мальта',
    'portugal': 'Португалия',
    'romania': 'Румыния',
    'slovakia': 'Словакия',
    'slovenia': 'Словения',
    'georgia': 'Грузия',
  };

  /// Returns the Russian country name that matches `SearchFiltersConfig.countriesRu`,
  /// mapping English names / codes to Russian where necessary.
  static String _normalizeCountryToRu(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (SearchFiltersConfig.countriesRu.contains(trimmed)) return trimmed;
    return _countryEnToRu[trimmed.toLowerCase()] ?? trimmed;
  }

  bool get _isEditModeEntry {
    return (widget.initialStepId ?? '').trim().isNotEmpty ||
        (widget.existingCvId ?? '').trim().isNotEmpty;
  }

  String get _existingCvId => (widget.existingCvId ?? '').trim();
  bool _existingPublishedInCandidates = false;

  @override
  void initState() {
    super.initState();
    final initialStep = _stepIndexById(widget.initialStepId);
    if (initialStep != null) _step = initialStep;
    _prefillContacts();
    _prefillFromExistingCv();
    _checkCvLimit();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _citizenshipCtrl.dispose();
    _countryResidenceCtrl.dispose();
    _cityCtrl.dispose();
    _birthDateCtrl.dispose();
    _cvTitleCtrl.dispose();
    _cvSummaryCtrl.dispose();
    _desiredPositionCtrl.dispose();
    _desiredCitiesCtrl.dispose();
    _desiredSalaryFromCtrl.dispose();
    _computerOtherCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  bool _containsCopyToken(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('копия') || normalized.contains('copy');
  }

  String _formatBirthDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd.$mm.${date.year}';
  }

  DateTime? _parseBirthDateInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final dot = RegExp(
      r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$',
    ).firstMatch(value);
    if (dot != null) {
      final day = int.tryParse(dot.group(1)!);
      final month = int.tryParse(dot.group(2)!);
      final year = int.tryParse(dot.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return DateTime.tryParse(value);
  }

  void _setBirthDate(DateTime? value) {
    _birthDate = value;
    _birthDateCtrl.text = value == null ? '' : _formatBirthDate(value);
  }

  String? _normalizeCitizenshipValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    const map = <String, String>{
      'eu': 'EU',
      '🇪🇺 eu': 'EU',
      'kazakhstan': 'Казахстан',
      'казахстан': 'Казахстан',
      'uzbekistan': 'Узбекистан',
      'узбекистан': 'Узбекистан',
      'kyrgyzstan': 'Кыргызстан',
      'кыргызстан': 'Кыргызстан',
      'киргизстан': 'Кыргызстан',
      'tajikistan': 'Таджикистан',
      'таджикистан': 'Таджикистан',
      'armenia': 'Армения',
      'армения': 'Армения',
      'azerbaijan': 'Азербайджан',
      'азербайджан': 'Азербайджан',
      'moldova': 'Молдова',
      'молдова': 'Молдова',
      'belarus': 'Беларусь',
      'беларусь': 'Беларусь',
      'russia': 'Россия',
      'россия': 'Россия',
      'ukraine': 'Украина',
      'украина': 'Украина',
    };
    return map[lower] ?? (_citizenshipValues.contains(value) ? value : null);
  }

  String _normalizeGenderValue(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.isEmpty) return '';
    if (lower == 'female' || lower == 'женский' || lower == 'f') {
      return 'female';
    }
    if (lower == 'male' || lower == 'мужской' || lower == 'm') {
      return 'male';
    }
    return '';
  }

  String _countryWithFlag(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return clean;
    final flag = CountryDisplayFormatter.countryFlagOnly(
      clean,
      euAsToken: false,
    );
    return '$flag $clean';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final lastDate = DateTime(now.year - 14, now.month, now.day);
    final firstDate = DateTime(now.year - 80, 1, 1);
    final initial = _birthDate ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(lastDate) ? lastDate : initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Дата рождения',
      locale: const Locale('ru', 'RU'),
    );
    if (picked == null) return;
    setState(() => _setBirthDate(picked));
  }

  int? _stepIndexById(String? stepId) {
    final id = (stepId ?? '').trim();
    if (id.isEmpty) return null;
    return switch (id) {
      CvWizardStepIds.profile => 0,
      CvWizardStepIds.contacts => 0,
      CvWizardStepIds.about => 1,
      CvWizardStepIds.experience => 2,
      CvWizardStepIds.education => 3,
      CvWizardStepIds.languages => 4,
      CvWizardStepIds.computerSkills => 5,
      CvWizardStepIds.drivingLicense => 5,
      CvWizardStepIds.jobPreferences => 6,
      _ => null,
    };
  }

  // ─── AI autofill ──────────────────────────────────────────────────────────
  Future<void> _openCvAutofill() async {
    final result = await AiAutofillSheet.show(context, mode: AiAutofillMode.cv);
    if (result == null || !mounted) return;
    _applyCvAutofill(result);
  }

  void _applyCvAutofill(Map<String, dynamic> d) {
    String s(String key) => (d[key] ?? '').toString().trim();
    bool b(String key) {
      final v = d[key];
      if (v is bool) return v;
      return false;
    }

    List<Map<String, dynamic>> maps(String key) {
      final v = d[key];
      if (v is! List) return [];
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    setState(() {
      // Title & summary
      if (s('title').isNotEmpty) _cvTitleCtrl.text = s('title');
      if (s('summary').isNotEmpty) _cvSummaryCtrl.text = s('summary');

      // Experience
      final expList = maps('experience');
      if (expList.isNotEmpty) {
        _jobs.clear();
        _noExperience = false;
        for (final e in expList) {
          DateTime? parseDate(String? raw) {
            if (raw == null || raw.trim().isEmpty) return null;
            try {
              return DateTime.parse(raw.trim());
            } catch (_) {
              return null;
            }
          }

          _jobs.add(
            _JobRow(
              position: (e['position'] ?? '').toString(),
              company: (e['company'] ?? '').toString(),
              country: _normalizeCountryToRu((e['country'] ?? '').toString()),
              description: (e['description'] ?? '').toString(),
              startDate: parseDate(e['start_date']?.toString()),
              endDate: parseDate(e['end_date']?.toString()),
              isCurrent: (e['is_current'] ?? false) == true,
            ),
          );
        }
      }

      // Education
      final eduList = maps('education');
      if (eduList.isNotEmpty) {
        _edu.clear();
        for (final e in eduList) {
          int? parseYear(String? raw) {
            if (raw == null || raw.trim().isEmpty) return null;
            try {
              return DateTime.parse(raw.trim()).year;
            } catch (_) {
              return null;
            }
          }

          int? parseMonth(String? raw) {
            if (raw == null || raw.trim().isEmpty) return null;
            try {
              return DateTime.parse(raw.trim()).month;
            } catch (_) {
              return null;
            }
          }

          _edu.add(
            _EduRow(
              school: (e['school'] ?? '').toString(),
              speciality: (e['specialization'] ?? '').toString(),
              country: (e['country'] ?? '').toString(),
              startMonth: parseMonth(e['start_date']?.toString()),
              startYear: parseYear(e['start_date']?.toString()),
              endMonth: parseMonth(e['end_date']?.toString()),
              endYear: parseYear(e['end_date']?.toString()),
              isCurrent: (e['is_current'] ?? false) == true,
            ),
          );
        }
      }

      // Languages
      final langList = maps('languages');
      if (langList.isNotEmpty) {
        _langs.clear();
        for (final l in langList) {
          _langs.add(
            _LangRow(
              language: (l['name'] ?? '').toString(),
              level: (l['level'] ?? '').toString(),
            ),
          );
        }
      }

      // Driving license
      _hasDrivingLicense = b('driving_license');

      // Desired job preferences
      final prefs = d['job_preferences'];
      if (prefs is Map) {
        final p = Map<String, dynamic>.from(prefs);
        final cat = (p['category'] ?? '').toString().trim();
        if (cat.isNotEmpty) _desiredCategoryGroup = cat;
        final pos = (p['position'] ?? '').toString().trim();
        if (pos.isNotEmpty) _desiredPositionCtrl.text = pos;
        final city = (p['city'] ?? '').toString().trim();
        if (city.isNotEmpty) _desiredCitiesCtrl.text = city;
        final country = (p['country'] ?? '').toString().trim();
        if (country.isNotEmpty) _desiredCountries = {country};
        final emp = (p['employment_type'] ?? '').toString().trim();
        if (emp.isNotEmpty) {
          for (final value in emp.split(',')) {
            final clean = value.trim();
            if (clean.isNotEmpty) _desiredEmploymentTypes.add(clean);
          }
        }
        final availability = (p['availability'] ?? p['readiness'] ?? '')
            .toString()
            .trim();
        if (availability.isNotEmpty) {
          _desiredAvailabilityText = availability;
        }
        final salary =
            (p['salary_text'] ??
                    p['salary'] ??
                    p['salary_amount'] ??
                    p['salary_from'] ??
                    '')
                .toString()
                .trim();
        if (salary.isNotEmpty) _desiredSalaryText = salary;
      }

      // Computer skills → other field
      final skills = s('computer_skills');
      if (skills.isNotEmpty) {
        _computerProgramsSelected.add('Другое');
        _computerOtherCtrl.text = skills;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Данные из резюме применены. Проверьте и отредактируйте при необходимости.',
        ),
      ),
    );
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  Future<void> _prefillContacts() async {
    final u = _auth.currentUser;

    _emailCtrl.text = _s(u?.email);
    final parsedAuthPhone = ContactFieldsValidators.parseStoredPhone(
      _s(u?.phoneNumber),
    );
    _phoneCountryCode = parsedAuthPhone.countryCode;
    _phoneNumberCtrl.text = parsedAuthPhone.number;
    final displayParts = _s(
      u?.displayName,
    ).split(' ').where((e) => e.trim().isNotEmpty).toList();
    if (displayParts.isNotEmpty) {
      _firstNameCtrl.text = displayParts.first;
      _lastNameCtrl.text = displayParts.length > 1
          ? displayParts.sublist(1).join(' ')
          : _lastNameCtrl.text;
    }

    if (u != null) {
      try {
        final snap = await _db.collection('users').doc(u.uid).get();
        final m = snap.data() ?? {};
        final personal = (m['personal'] is Map)
            ? Map<String, dynamic>.from(m['personal'] as Map)
            : <String, dynamic>{};
        final contacts = (m['contacts'] is Map)
            ? Map<String, dynamic>.from(m['contacts'] as Map)
            : <String, dynamic>{};

        final first = _s(m['firstName']);
        final last = _s(m['lastName']);
        final email = _s(m['email']);
        final phone = _s(m['phone'], fallback: _s(contacts['phone']));
        final phoneCountryCode = _s(m['phoneCountryCode']);
        final phoneNumber = ContactFieldsValidators.normalizeDigits(
          _s(m['phoneNumber']),
        );
        final citizenship = _s(
          personal['citizenshipName'],
          fallback: _s(
            m['citizenshipName'],
            fallback: _s(
              personal['countryName'],
              fallback: _s(
                m['countryName'],
                fallback: _s(personal['country'], fallback: _s(m['country'])),
              ),
            ),
          ),
        );
        final countryResidence = _s(
          personal['countryResidence'],
          fallback: _s(
            m['countryResidence'],
            fallback: _s(
              personal['country'],
              fallback: _s(
                personal['countryName'],
                fallback: _s(m['country'], fallback: _s(m['countryName'])),
              ),
            ),
          ),
        );
        final city = _s(
          personal['city'],
          fallback: _s(
            m['city'],
            fallback: _s(
              contacts['city'],
              fallback: _s(
                m['location'],
                fallback: _s(personal['location'], fallback: _s(m['address'])),
              ),
            ),
          ),
        );
        final gender = _s(m['gender']);
        final rawBirthDate = m['birthDate'];
        if (rawBirthDate is Timestamp) {
          _setBirthDate(rawBirthDate.toDate());
        } else if (rawBirthDate is DateTime) {
          _setBirthDate(rawBirthDate);
        } else if (rawBirthDate is String && rawBirthDate.trim().isNotEmpty) {
          _setBirthDate(DateTime.tryParse(rawBirthDate.trim()));
        }

        if (first.isNotEmpty) _firstNameCtrl.text = first;
        if (last.isNotEmpty) _lastNameCtrl.text = last;
        if (email.isNotEmpty) _emailCtrl.text = email;
        if (phoneCountryCode.isNotEmpty) _phoneCountryCode = phoneCountryCode;
        if (phoneNumber.isNotEmpty) _phoneNumberCtrl.text = phoneNumber;
        if (phone.isNotEmpty && _phoneNumberCtrl.text.isEmpty) {
          final parsed = ContactFieldsValidators.parseStoredPhone(phone);
          _phoneCountryCode = parsed.countryCode;
          _phoneNumberCtrl.text = parsed.number;
        }
        if (city.isNotEmpty) _cityCtrl.text = city;
        final normalizedGender = _normalizeGenderValue(gender);
        if (normalizedGender.isNotEmpty) _gender = normalizedGender;
        if (countryResidence.isNotEmpty &&
            _countryResidenceCtrl.text.trim().isEmpty) {
          _countryResidenceCtrl.text = _normalizeCountryToRu(countryResidence);
        }
        if (citizenship.isNotEmpty && _citizenshipCtrl.text.trim().isEmpty) {
          _citizenshipCtrl.text =
              _normalizeCitizenshipValue(citizenship) ?? citizenship;
        }
      } catch (_) {}
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkCvLimit() async {
    if (_existingCvId.isNotEmpty) {
      setState(() {
        _checkingLimit = false;
        _limitOk = true;
      });
      return;
    }

    final effectiveUid = _auth.currentUser?.uid.trim();
    if (effectiveUid == null) {
      setState(() {
        _checkingLimit = false;
        _limitOk = true;
      });
      return;
    }

    try {
      final qRoot = _db
          .collection(FirestorePaths.cvs)
          .where('ownerId', isEqualTo: effectiveUid)
          .where('isDeleted', isEqualTo: false)
          .limit(maxCv);
      final snap = await qRoot.get();
      final count = snap.docs.length;
      setState(() {
        _checkingLimit = false;
        _limitOk = count < maxCv;
      });
    } catch (_) {
      setState(() {
        _checkingLimit = false;
        _limitOk = true;
      });
    }
  }

  DateTime? _dateFromAny(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  Future<Map<String, dynamic>> _loadPrivateContactsForCv(String cvId) async {
    final id = cvId.trim();
    if (id.isEmpty) return <String, dynamic>{};
    try {
      final snap = await _db
          .collection('candidate_contacts_private')
          .doc(id)
          .get();
      final data = snap.data();
      if (data == null || data.isEmpty) return <String, dynamic>{};
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _prefillFromExistingCv() async {
    if (_existingCvId.isEmpty) return;
    try {
      final snap = await _db
          .collection(FirestorePaths.cvs)
          .doc(_existingCvId)
          .get();
      final data = snap.data();
      if (data == null || !mounted) return;
      final privateContacts = await _loadPrivateContactsForCv(_existingCvId);

      final contacts = (data['contacts'] is Map)
          ? Map<String, dynamic>.from(data['contacts'] as Map)
          : <String, dynamic>{};
      if (privateContacts.isNotEmpty) {
        contacts['email'] = _s(
          privateContacts['email'],
          fallback: _s(contacts['email']),
        );
        contacts['phoneCountryCode'] = _s(
          privateContacts['phoneCountryCode'],
          fallback: _s(contacts['phoneCountryCode']),
        );
        contacts['phoneNumber'] = _s(
          privateContacts['phoneNumber'],
          fallback: _s(contacts['phoneNumber']),
        );
        contacts['phone'] = _s(
          privateContacts['phone'],
          fallback: _s(contacts['phone']),
        );
      }
      final desired = (data['desired'] is Map<String, dynamic>)
          ? (data['desired'] as Map<String, dynamic>)
          : <String, dynamic>{};
      final drivingLicense = (data['drivingLicense'] is Map<String, dynamic>)
          ? (data['drivingLicense'] as Map<String, dynamic>)
          : <String, dynamic>{};
      final skills = (data['skills'] is Map<String, dynamic>)
          ? (data['skills'] as Map<String, dynamic>)
          : <String, dynamic>{};
      final computerSkills = (data['computerSkills'] is Map<String, dynamic>)
          ? (data['computerSkills'] as Map<String, dynamic>)
          : <String, dynamic>{};

      setState(() {
        _existingPublishedInCandidates = data['publishedInCandidates'] == true;

        final first = _s(contacts['firstName']);
        final last = _s(contacts['lastName']);
        final full = _s(contacts['name']);
        if (first.isNotEmpty) _firstNameCtrl.text = first;
        if (last.isNotEmpty) _lastNameCtrl.text = last;
        if (_firstNameCtrl.text.trim().isEmpty &&
            _lastNameCtrl.text.trim().isEmpty &&
            full.isNotEmpty) {
          final parts = full
              .split(' ')
              .where((e) => e.trim().isNotEmpty)
              .toList();
          if (parts.isNotEmpty) {
            _firstNameCtrl.text = parts.first;
            if (parts.length > 1) {
              _lastNameCtrl.text = parts.sublist(1).join(' ');
            }
          }
        }
        final email = _s(contacts['email'], fallback: _s(data['email']));
        if (email.isNotEmpty) _emailCtrl.text = email;
        final phoneCode = _s(contacts['phoneCountryCode']);
        if (phoneCode.isNotEmpty) _phoneCountryCode = phoneCode;
        final phoneNum = _s(contacts['phoneNumber']);
        if (phoneNum.isNotEmpty) {
          _phoneNumberCtrl.text = ContactFieldsValidators.normalizeDigits(
            phoneNum,
          );
        } else {
          final phone = _s(contacts['phone'], fallback: _s(data['phone']));
          if (phone.isNotEmpty) {
            final parsed = ContactFieldsValidators.parseStoredPhone(phone);
            _phoneCountryCode = parsed.countryCode;
            _phoneNumberCtrl.text = parsed.number;
          }
        }

        final citizenship = _normalizeCitizenshipValue(
          _s(data['citizenshipCountry'], fallback: _s(data['citizenshipName'])),
        );
        if (citizenship != null && citizenship.isNotEmpty) {
          _citizenshipCtrl.text = citizenship;
        }
        final countryResidence = _s(
          data['countryResidence'],
          fallback: _s(
            data['country'],
            fallback: _s(
              contacts['country'],
              fallback: _s(contacts['countryName']),
            ),
          ),
        );
        if (countryResidence.isNotEmpty) {
          _countryResidenceCtrl.text = _normalizeCountryToRu(countryResidence);
        }
        _setBirthDate(_dateFromAny(data['birthDate']) ?? _birthDate);
        final city = _s(
          data['city'],
          fallback: _s(contacts['city'], fallback: _s(contacts['location'])),
        );
        if (city.isNotEmpty) _cityCtrl.text = city;
        final gender = _normalizeGenderValue(
          _s(data['gender'], fallback: _s(contacts['gender'])),
        );
        if (gender.isNotEmpty) _gender = gender;

        final title = _s(data['title'], fallback: _s(data['cvTitle']));
        if (title.isNotEmpty) _cvTitleCtrl.text = title;
        _cvSummaryCtrl.text = _s(
          data['summary'],
          fallback: _cvSummaryCtrl.text,
        );

        final expRaw = (data['experience'] is List)
            ? (data['experience'] as List)
            : const <dynamic>[];
        final expRows = expRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .map(
              (e) => _JobRow(
                position: _s(e['position']),
                company: _s(e['company']),
                country: _normalizeCountryToRu(_s(e['country'])),
                description: _s(e['description']),
                startDate: _dateFromAny(e['startDate'] ?? e['start_date']),
                endDate: _dateFromAny(e['endDate'] ?? e['end_date']),
                isCurrent: e['isCurrent'] == true || e['is_current'] == true,
              ),
            )
            .where((e) => e.toMap().isNotEmpty)
            .toList();
        if (expRows.isNotEmpty) {
          _jobs
            ..clear()
            ..addAll(expRows);
        }

        final eduRaw = (data['education'] is List)
            ? (data['education'] as List)
            : const <dynamic>[];
        final eduRows = eduRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .map(
              (e) => _EduRow(
                school: _s(e['school']),
                speciality: _s(
                  e['speciality'],
                  fallback: _s(e['specialization']),
                ),
                country: _normalizeCountryToRu(_s(e['country'])),
                startMonth: (e['startMonth'] as num?)?.toInt(),
                startYear: (e['startYear'] as num?)?.toInt(),
                endMonth: (e['endMonth'] as num?)?.toInt(),
                endYear: (e['endYear'] as num?)?.toInt(),
                isCurrent: e['isCurrent'] == true || e['is_current'] == true,
              ),
            )
            .where((e) => e.toMap().isNotEmpty)
            .toList();
        if (eduRows.isNotEmpty) {
          _edu
            ..clear()
            ..addAll(eduRows);
        }

        final langRaw = (data['languages'] is List)
            ? (data['languages'] as List)
            : const <dynamic>[];
        final langRows = langRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .map(
              (e) => _LangRow(
                language: _s(e['language'], fallback: _s(e['name'])),
                level: _s(e['level']),
              ),
            )
            .where(
              (e) => e.language.trim().isNotEmpty || e.level.trim().isNotEmpty,
            )
            .toList();
        if (langRows.isNotEmpty) {
          _langs
            ..clear()
            ..addAll(langRows);
        }

        final selectedPrograms = <String>{
          ...((skills['computerPrograms'] as List?) ?? const [])
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty),
          ...((computerSkills['selected'] as List?) ?? const [])
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty),
        };
        _computerProgramsSelected
          ..clear()
          ..addAll(
            selectedPrograms.where((e) => _computerPrograms.contains(e)),
          );
        _computerOtherCtrl.text = _s(
          computerSkills['other'],
          fallback: _s(data['computerSkillsDetails']),
        );
        if (_computerOtherCtrl.text.trim().isNotEmpty) {
          _computerProgramsSelected.add('Другое');
        }

        _hasDrivingLicense =
            drivingLicense['hasLicense'] == true ||
            _s(drivingLicense['license']).isNotEmpty;
        _drivingCategories
          ..clear()
          ..addAll(
            ((drivingLicense['categories'] as List?) ?? const [])
                .map((e) => e.toString().trim().toUpperCase())
                .where((e) => e.isNotEmpty),
          );
        _hasCar = data['hasCar'] == true || drivingLicense['hasCar'] == true;
        _hasTools = data['hasTools'] == true;
        _hasWorkwear = data['hasWorkwear'] == true;

        _desiredCategoryGroup = _s(
          desired['categoryGroup'],
          fallback: _s(desired['category']),
        );
        _desiredPositionCtrl.text = _s(desired['position']);
        _desiredCitiesCtrl.text = _s(desired['citiesText']);
        _desiredCountries = {
          ...((desired['countries'] as List?) ?? const [])
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty),
        };
        _desiredEmploymentTypes
          ..clear()
          ..addAll(
            ((desired['employmentTypes'] as List?) ?? const [])
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          );
        if (_desiredEmploymentTypes.isEmpty) {
          final fallbackType = _s(desired['employmentType']);
          for (final v in fallbackType.split(',')) {
            final clean = v.trim();
            if (clean.isNotEmpty) _desiredEmploymentTypes.add(clean);
          }
        }
        _desiredAvailabilityText = _s(
          desired['availabilityText'],
          fallback: _s(desired['availability']),
        );

        final salaryAmount = _s(desired['salaryAmount']);
        if (salaryAmount.isNotEmpty) {
          _desiredSalaryFromCtrl.text = salaryAmount;
        } else {
          final parsedAmount = RegExp(r'(\d+[.,]?\d*)').firstMatch(
            _s(desired['salaryText'], fallback: _s(data['salaryText'])),
          );
          if (parsedAmount != null) {
            _desiredSalaryFromCtrl.text = parsedAmount.group(1)!;
          }
        }
        _desiredSalaryCurrency = _s(desired['salaryCurrency'], fallback: 'EUR');
        _desiredSalaryPeriod = _s(desired['salaryPeriod'], fallback: 'month');
        _desiredSalaryText = _s(
          desired['salaryText'],
          fallback: _s(data['salaryText']),
        );
      });
    } catch (e) {
      debugPrint('CvWizardScreen _prefillFromExistingCv error: $e');
    }
  }

  bool _requiredOkForStep(int step) {
    if (!_limitOk && !_isEditModeEntry) return false;

    switch (step) {
      case 0:
        return ContactFieldsValidators.isNameValid(_firstNameCtrl.text) &&
            ContactFieldsValidators.isNameValid(_lastNameCtrl.text) &&
            ContactFieldsValidators.isEmailValid(_emailCtrl.text) &&
            ContactFieldsValidators.isPhoneValid(_phoneNumberCtrl.text);

      case 1:
        return _cvTitleCtrl.text.trim().isNotEmpty;

      case 2:
        if (_noExperience) return true;
        final j0 = _jobs.first;
        final started =
            j0.position.trim().isNotEmpty || j0.company.trim().isNotEmpty;
        if (!started) return true;
        return j0.position.trim().isNotEmpty && j0.company.trim().isNotEmpty;

      case 3:
        final e0 = _edu.first;
        final started =
            e0.school.trim().isNotEmpty || e0.country.trim().isNotEmpty;
        if (!started) return true;
        return e0.school.trim().isNotEmpty && e0.country.trim().isNotEmpty;

      case 4:
        for (final l in _langs) {
          final hasLang =
              l.language.trim().isNotEmpty ||
              l.customLanguage.trim().isNotEmpty;
          if (hasLang && l.level.trim().isEmpty) return false;
        }
        return true;

      case 5:
        // компьютер (не обяз.)
        return true;

      case 6:
        // желаемая работа: должность НЕ обязательна
        return _desiredCategoryGroup.trim().isNotEmpty &&
            _desiredCountries.isNotEmpty &&
            _desiredEmploymentTypes.isNotEmpty;

      default:
        return false;
    }
  }

  List<String> _computerProgramsForSave() {
    return _computerProgramsSelected.where((e) => e != 'Другое').toList();
  }

  Map<String, dynamic> _computerSkillsForSave() {
    return {
      'selected': _computerProgramsForSave(),
      'other': _computerOtherCtrl.text.trim(),
    };
  }

  List<int> _yearOptions() {
    final now = DateTime.now().year;
    return [for (int y = now; y >= 1980; y--) y];
  }

  String _drivingLabel() {
    if (!_hasDrivingLicense || _drivingCategories.isEmpty) return '';
    final sorted = _drivingCategories.toList()..sort();
    return sorted.join(', ');
  }

  String _currencySymbol(String code) {
    return switch (code) {
      'USD' => r'$',
      _ => '€',
    };
  }

  String _periodLabel(String value) {
    return switch (value) {
      'hour' => 'час',
      'day' => 'день',
      _ => 'месяц',
    };
  }

  String _languageDisplayLabel(String value) {
    final clean = value.trim();
    const map = <String, String>{
      'Русский': '🇷🇺 Русский',
      'English': '🇬🇧 English',
      'Deutsch': '🇩🇪 Deutsch',
      'Suomi': '🇫🇮 Suomi',
      'Svenska': '🇸🇪 Svenska',
      'Polski': '🇵🇱 Polski',
      'Eesti': '🇪🇪 Eesti',
      'Без языка': '🌍 Без языка',
      'Другой': '🌍 Другой',
    };
    return map[clean] ?? clean;
  }

  IconData _computerProgramIcon(String value) {
    return switch (value) {
      'MS Office' => Icons.insert_chart_outlined_rounded,
      'Excel' => Icons.table_chart_outlined,
      'Word' => Icons.description_outlined,
      'Google Sheets' => Icons.grid_view_rounded,
      '1C' => Icons.circle,
      'Касса' => Icons.point_of_sale_outlined,
      'Складские программы' => Icons.inventory_2_outlined,
      'CRM' => Icons.groups_2_outlined,
      _ => Icons.settings_outlined,
    };
  }

  IconData _categoryIconForItem(String value) {
    return switch (value) {
      'Строительство и рабочие специальности' => Icons.construction_outlined,
      'Логистика и производство' => Icons.factory_outlined,
      'Транспорт и доставка' => Icons.local_shipping_outlined,
      'Торговля и склад' => Icons.storefront_outlined,
      'Уборка и обслуживание' => Icons.cleaning_services_outlined,
      'Общественное питание' => Icons.restaurant_menu_outlined,
      'Красота и здоровье' => Icons.spa_outlined,
      'Медицина и уход' => Icons.local_hospital_outlined,
      'Продажи и работа с клиентами' => Icons.support_agent_outlined,
      'Маркетинг и реклама' => Icons.campaign_outlined,
      'Бизнес и управление' => Icons.manage_accounts_outlined,
      'Финансы и бухгалтерия' => Icons.account_balance_wallet_outlined,
      'IT и разработка' => Icons.code_outlined,
      _ => Icons.business_center_outlined,
    };
  }

  Map<String, dynamic> _draftCvData({required bool addToCandidates}) {
    final parsedBirthDate =
        _parseBirthDateInput(_birthDateCtrl.text) ?? _birthDate;
    final isComplete =
        _requiredOkForStep(0) && _requiredOkForStep(1) && _requiredOkForStep(6);
    final effectiveUid = AuthGuard.effectiveUidOrNull();
    final ownerKey = AppMode.effectiveOwnerKey(
      authUid: effectiveUid,
      testMode: widget.testMode,
    );
    final citizenshipValue =
        _normalizeCitizenshipValue(_citizenshipCtrl.text) ??
        _citizenshipCtrl.text.trim();
    final salaryAmount = _desiredSalaryFromCtrl.text.trim();
    final hasSalary = salaryAmount.isNotEmpty;
    final salaryValue = hasSalary
        ? '${_currencySymbol(_desiredSalaryCurrency)} $salaryAmount / ${_periodLabel(_desiredSalaryPeriod)}'
        : _desiredSalaryText.trim();
    final availabilityValue = _desiredAvailabilityText.trim();
    final employmentTypes = _desiredEmploymentTypes.toList()..sort();
    final employmentTypeText = employmentTypes.join(', ');
    return <String, dynamic>{
      'ownerId': effectiveUid ?? ownerKey,
      'ownerKey': ownerKey,
      'ownerUid': _auth.currentUser?.uid,
      'isDeleted': false,
      'contacts': {
        'name': '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'
            .trim(),
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phoneCountryCode': _phoneCountryCode,
        'phoneNumber': ContactFieldsValidators.normalizeDigits(
          _phoneNumberCtrl.text,
        ),
        'phone':
            '$_phoneCountryCode${ContactFieldsValidators.normalizeDigits(_phoneNumberCtrl.text)}',
        'city': _cityCtrl.text.trim(),
        'country': _countryResidenceCtrl.text.trim(),
        'gender': _gender.trim(),
      },
      'city': _cityCtrl.text.trim(),
      'countryResidence': _countryResidenceCtrl.text.trim(),
      'country': _countryResidenceCtrl.text.trim(),
      'gender': _gender.trim(),
      'citizenshipCountry': citizenshipValue,
      'citizenshipGroup': citizenshipValue == 'EU' ? 'EU' : 'CIS',
      if (parsedBirthDate != null)
        'birthDate': Timestamp.fromDate(parsedBirthDate),
      'title': _cvTitleCtrl.text.trim(),
      'summary': _cvSummaryCtrl.text.trim(),
      'experience': _noExperience
          ? []
          : _jobs.map((e) => e.toMap()).where((m) => m.isNotEmpty).toList(),
      'languages': _langs
          .map((e) => e.toMap())
          .where((m) => m.isNotEmpty)
          .toList(),
      'education': _edu
          .map((e) => e.toMap())
          .where((m) => m.isNotEmpty)
          .toList(),
      'skills': {
        'computerPrograms': _computerProgramsForSave(),
        'computer': [
          ..._computerProgramsForSave(),
          if (_computerOtherCtrl.text.trim().isNotEmpty)
            _computerOtherCtrl.text.trim(),
        ].join(', '),
      },
      'computerSkills': _computerSkillsForSave(),
      'driving': {'license': _drivingLabel(), 'hasCar': _hasCar},
      'drivingLicense': {
        'hasLicense': _hasDrivingLicense,
        'categories': (_drivingCategories.toList()..sort()),
        'hasCar': _hasCar,
      },
      'hasCar': _hasCar,
      'hasTools': _hasTools,
      'hasWorkwear': _hasWorkwear,
      'hasComputerSkills': _computerProgramsForSave().isNotEmpty,
      'computerSkillsDetails': _computerProgramsForSave().join(', '),
      'desired': {
        'categoryGroup': _desiredCategoryGroup.trim(),
        'position': _desiredPositionCtrl.text.trim(),
        'citiesText': _desiredCitiesCtrl.text.trim(),
        'cities': _desiredCitiesCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'countries': _desiredCountries.toList(),
        'employmentTypes': employmentTypes,
        'employmentType': employmentTypeText,
        if (hasSalary) 'salaryAmount': salaryAmount,
        if (hasSalary) 'salaryCurrency': _desiredSalaryCurrency,
        if (hasSalary) 'salaryPeriod': _desiredSalaryPeriod,
        if (availabilityValue.isNotEmpty) 'availabilityText': availabilityValue,
        if (availabilityValue.isNotEmpty) 'availability': availabilityValue,
        if (salaryValue.isNotEmpty) 'salaryText': salaryValue,
      },
      'salaryText': salaryValue.isNotEmpty ? salaryValue : null,
      if (availabilityValue.isNotEmpty) 'availabilityText': availabilityValue,
      'isComplete': isComplete,
      'incomplete': !isComplete,
      'isDraft': !isComplete,
      'status': isComplete ? 'complete' : 'incomplete',
      'cvStatus': isComplete ? 'complete' : 'incomplete',
      'visibility': {'inCandidates': addToCandidates},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'test': widget.testMode && _auth.currentUser == null,
      'source': _auth.currentUser == null ? 'debug_or_test' : 'user',
      'mode': widget.testMode ? 'test' : 'prod',
    };
  }

  Future<bool> _ensureAuthIfNeededForSave() async {
    if (_isAuthed) return true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Нужна регистрация'),
        content: const Text(
          'Вы можете заполнить CV как гость, но для сохранения нужно войти или создать аккаунт.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('later'),
            child: const Text('Позже'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('register'),
            child: const Text('Создать аккаунт'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('login'),
            child: const Text('Войти'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (action == 'register') {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
    } else if (action == 'login') {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
    }
    if (!mounted) return false;
    if (_isAuthed) return true;
    _toast('Чтобы сохранить CV, нужен вход или регистрация.');
    return false;
  }

  Future<void> _pickCountries() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final temp = Set<String>.from(_desiredCountries);
        final countries = SearchFiltersConfig.countriesRu;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Локация',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: WorkaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: countries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = countries[i];
                          final selected = temp.contains(item);
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            hoverColor: WorkaColors.hoverBlueSoft,
                            splashColor: WorkaColors.hoverBlueSoft,
                            onTap: () {
                              setModalState(() {
                                if (selected) {
                                  temp.remove(item);
                                } else {
                                  temp.add(item);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? WorkaColors.hoverBlueSoft
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? WorkaColors.blue
                                      : WorkaColors.fieldBorder,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: selected,
                                    onChanged: (_) {
                                      setModalState(() {
                                        if (selected) {
                                          temp.remove(item);
                                        } else {
                                          temp.add(item);
                                        }
                                      });
                                    },
                                    activeColor: WorkaColors.blue,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    CountryDisplayFormatter.countryFlagOnly(
                                      item,
                                      euAsToken: false,
                                    ),
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? WorkaColors.blue
                                            : WorkaColors.textGreyDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, temp),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.blue,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Готово',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() {
      _desiredCountries = {...result};
    });
  }

  Future<void> _pickEmploymentTypes() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final temp = Set<String>.from(_desiredEmploymentTypes);
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Тип работы',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: WorkaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _employmentTypeOptions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = _employmentTypeOptions[i];
                          final selected = temp.contains(item);
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            hoverColor: WorkaColors.hoverBlueSoft,
                            splashColor: WorkaColors.hoverBlueSoft,
                            onTap: () {
                              setModalState(() {
                                if (selected) {
                                  temp.remove(item);
                                } else {
                                  temp.add(item);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? WorkaColors.hoverBlueSoft
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? WorkaColors.blue
                                      : WorkaColors.fieldBorder,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: selected,
                                    onChanged: (_) {
                                      setModalState(() {
                                        if (selected) {
                                          temp.remove(item);
                                        } else {
                                          temp.add(item);
                                        }
                                      });
                                    },
                                    activeColor: WorkaColors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? WorkaColors.blue
                                            : WorkaColors.textGreyDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, temp),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.blue,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Готово',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (result == null) return;
    setState(() {
      _desiredEmploymentTypes
        ..clear()
        ..addAll(result);
    });
  }

  // ===== Preview overlay (big card on top) =====

  Future<void> _openPreviewAndMaybeSave() async {
    bool addToCandidates = false;

    final result = await showModalBottomSheet<_PreviewResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return _CvPreviewSheet(
          cvData: _draftCvData(addToCandidates: false),
          onEditSectionId: (stepId) {
            Navigator.pop(
              context,
              const _PreviewResult(edit: true, addToCandidates: false),
            );
            final step = _stepIndexById(stepId);
            if (step != null) {
              setState(() => _step = step);
            }
          },
        );
      },
    );

    if (result == null) return;

    if (result.edit) {
      // просто вернулись редактировать
      return;
    }

    addToCandidates = result.addToCandidates;

    // ✅ сохранить
    await _saveCv(addToCandidates: addToCandidates);
  }

  Future<void> _saveCv({required bool addToCandidates}) async {
    try {
      final okAuth = await _ensureAuthIfNeededForSave();
      if (!okAuth) return;

      final effectiveUid = AuthGuard.effectiveUidOrNull();
      final ownerKey = AppMode.effectiveOwnerKey(
        authUid: effectiveUid,
        testMode: widget.testMode,
      );
      if (effectiveUid == null) {
        _toast('Чтобы сохранить CV, нужен вход по SMS.');
        return;
      }
      final colName = FirestorePaths.cvs;

      final cv = _draftCvData(addToCandidates: addToCandidates);
      cv['ownerKey'] = ownerKey;
      cv['publishedInCandidates'] = addToCandidates || _existingPublishedInCandidates;
      final isEditingExisting = _existingCvId.isNotEmpty;
      String targetId;

      final resp = await _saveCvViaApi(cv, existingId: _existingCvId);
      targetId = resp ?? _existingCvId;

      if (cv['publishedInCandidates'] == true &&
          _containsCopyToken(_cvTitleCtrl.text)) {
        _toast('Исправьте название');
        return;
      }

      _toast('CV сохранено ✅');

      if (!mounted) return;
      if (_isEditModeEntry) {
        Navigator.pop(context, true);
        return;
      }
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(true);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MyCvsScreen(testMode: widget.testMode),
          ),
        );
      }
    } catch (e) {
      debugPrint('CvWizardScreen _saveCv error: $e');
      _toast('Ошибка сохранения: $e');
      if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
        _toast(FirebaseDebugDiagnostics.permissionHintText());
      }
    }
  }

  Future<void> _addToCandidates({
    required String cvId,
    required Map<String, dynamic> cv,
  }) async {
    // No-op: publishing handled by backend payload
    debugPrint('CvWizard publish flag set via API payload for $cvId');
  }

  Future<String?> _saveCvViaApi(
    Map<String, dynamic> cv, {
    String existingId = '',
  }) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Требуется авторизация для сохранения CV.');
    }
    final base = const String.fromEnvironment(
      'WORKA_API_BASE_URL',
      defaultValue: '',
    );
    assert(base.trim().isNotEmpty, 'WORKA_API_BASE_URL is required');
    final normalizedBase = base.endsWith('/api') ? base : '$base/api';
    final uri = existingId.trim().isEmpty
        ? Uri.parse('$normalizedBase/candidates/cv')
        : Uri.parse('$normalizedBase/candidates/cv/$existingId');

    final resp = await (existingId.trim().isEmpty
        ? http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(cv),
          )
        : http.patch(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(cv),
          ));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw StateError(
        'Не удалось сохранить CV: '
        '${body.isNotEmpty ? body : 'status=${resp.statusCode}'}',
      );
    }
    final json = jsonDecode(resp.body);
    if (json is Map && json['cv'] is Map) {
      final map = Map<String, dynamic>.from(json['cv'] as Map);
      return (map['id'] ?? map['cvId'] ?? '').toString().trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const stepsTotal = 7;

    final canNext =
        (_isEditModeEntry || !_checkingLimit) && _requiredOkForStep(_step);

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          // Navigation row — on blue background
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Создать CV',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ProfileAvatarButton(testMode: widget.testMode),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Progress dots — on blue background (white dots)
          CvProgressDots(current: _step, total: stepsTotal, onBlue: true),
          const SizedBox(height: 16),
          // White content block
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                      children: [
                        if (_checkingLimit)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (!_limitOk)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: WorkaColors.hoverBlueSoft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: WorkaColors.fieldBorder,
                              ),
                            ),
                            child: Text(
                              'Можно добавить не больше $maxCv CV.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: WorkaColors.textDark,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        _stepTitle(),
                        const SizedBox(height: 12),
                        ..._stepBody(),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 56,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: canNext
                                  ? () async {
                                      if (_isEditModeEntry) {
                                        await _saveCv(
                                          addToCandidates:
                                              _existingPublishedInCandidates,
                                        );
                                        return;
                                      }
                                      if (_step < stepsTotal - 1) {
                                        setState(() => _step++);
                                      } else {
                                        await _openPreviewAndMaybeSave();
                                      }
                                    }
                                  : null,
                              style: WorkaButtonStyles.primaryOrange(),
                              child: Text(
                                _isEditModeEntry
                                    ? 'Сохранить'
                                    : (_step == stepsTotal - 1
                                          ? 'Готово'
                                          : 'Продолжить'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 56,
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _isEditModeEntry
                                  ? () => Navigator.pop(context)
                                  : (_step == 0
                                        ? () => Navigator.pop(context)
                                        : () => setState(() => _step--)),
                              style: WorkaButtonStyles.outlineNeutral(),
                              child: Text(
                                _isEditModeEntry ? 'Отмена' : 'Предыдущий шаг',
                                style: const TextStyle(
                                  color: WorkaColors.orange,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepTitle() {
    switch (_step) {
      case 0:
        return const Text(
          'Профиль',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        );
      case 1:
        return const Text(
          'Заголовок CV и описание',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        );
      case 2:
        return const Text(
          'Опыт работы',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        );
      case 3:
        return const Text(
          'Образование',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        );
      case 4:
        return const Text(
          'Владение языками',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        );
      case 5:
        return const Text(
          'Знание компьютера',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        );
      case 6:
        return const Text(
          'Желаемая работа',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _stepBody() {
    switch (_step) {
      case 0:
        return [
          OutlinedButton.icon(
            onPressed: _openCvAutofill,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Заполнить из текста резюме'),
            style: OutlinedButton.styleFrom(
              foregroundColor: WorkaColors.blue,
              side: const BorderSide(color: WorkaColors.blue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
          const SizedBox(height: 14),
          Form(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ContactFields(
              firstNameController: _firstNameCtrl,
              lastNameController: _lastNameCtrl,
              emailController: _emailCtrl,
              phoneNumberController: _phoneNumberCtrl,
              phoneCountryCode: _phoneCountryCode,
              onPhoneCountryCodeChanged: (v) =>
                  setState(() => _phoneCountryCode = v),
              onChanged: () => setState(() {}),
              enabled: true,
            ),
          ),
          const SizedBox(height: 12),
          _citizenshipDropdown(),
          const SizedBox(height: 12),
          _dropdownSingle(
            label: 'Страна проживания',
            value: _countryResidenceCtrl.text.trim().isEmpty
                ? null
                : _countryResidenceCtrl.text.trim(),
            items: SearchFiltersConfig.countriesRu,
            icon: Icons.location_on_outlined,
            displayLabel: _countryWithFlag,
            flagForItem: (v) =>
                CountryDisplayFormatter.countryFlagOnly(v, euAsToken: false),
            onChanged: (v) =>
                setState(() => _countryResidenceCtrl.text = v ?? ''),
          ),
          const SizedBox(height: 12),
          _field(label: 'Город', ctrl: _cityCtrl, hint: 'Введите город'),
          const SizedBox(height: 12),
          _genderSelector(),
          const SizedBox(height: 12),
          _birthDateField(),
        ];

      case 1:
        return [
          _field(
            label: 'Заголовок *',
            ctrl: _cvTitleCtrl,
            hint: 'Например: Официант / Продавец / Уборка',
          ),
          const SizedBox(height: 12),
          _multiline(
            label: 'Краткое вступление',
            ctrl: _cvSummaryCtrl,
            hint: 'Коротко: опыт, сильные стороны, цели',
          ),
        ];

      case 2:
        return [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _noExperience = true;
                      _jobs
                        ..clear()
                        ..add(const _JobRow());
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: WorkaColors.fieldBorder,
                      width: 1.2,
                    ),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'У меня нет опыта работы  ›',
                    style: TextStyle(
                      color: WorkaColors.blue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_noExperience)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WorkaColors.hoverBlueSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WorkaColors.fieldBorder),
              ),
              child: const Text(
                'Ок — отметили “без опыта”. Этот шаг можно пропустить.',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: WorkaColors.textDark,
                ),
              ),
            ),
          if (_noExperience) const SizedBox(height: 12),
          if (!_noExperience) ...[
            ..._jobs.asMap().entries.expand((e) {
              final i = e.key;
              final row = e.value;
              return [
                _jobBlock(
                  index: i,
                  row: row,
                  onChanged: (nr) => setState(() => _jobs[i] = nr),
                  onRemove: i == 0
                      ? null
                      : () => setState(() => _jobs.removeAt(i)),
                ),
                const SizedBox(height: 12),
              ];
            }),
            _addLineButton(
              'Добавить место работы',
              () => setState(() => _jobs.add(const _JobRow())),
            ),
          ],
        ];

      case 3:
        return [
          ..._edu.asMap().entries.expand((e) {
            final i = e.key;
            final row = e.value;
            return [
              _eduBlock(
                index: i,
                row: row,
                onChanged: (nr) => setState(() => _edu[i] = nr),
                onRemove: i == 0
                    ? null
                    : () => setState(() => _edu.removeAt(i)),
              ),
              const SizedBox(height: 12),
            ];
          }),
          _addLineButton(
            'Добавить учебное заведение',
            () => setState(() => _edu.add(const _EduRow())),
          ),
        ];

      case 4:
        return [
          ..._langs.asMap().entries.expand((e) {
            final i = e.key;
            final row = e.value;
            return [
              _langBlock(
                index: i,
                row: row,
                onChanged: (nr) => setState(() => _langs[i] = nr),
                onRemove: i == 0
                    ? null
                    : () => setState(() => _langs.removeAt(i)),
              ),
              const SizedBox(height: 12),
            ];
          }),
          _addLineButton(
            'Добавить язык',
            () => setState(
              () => _langs.add(const _LangRow(language: '', level: '')),
            ),
          ),
        ];

      case 5:
        return [
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: WorkaColors.fieldBorder),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: WorkaColors.fieldBorder),
            ),
            title: const Text(
              'Знание компьютера',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: WorkaColors.textDark,
              ),
            ),
            subtitle: Text(
              _computerProgramsForSave().isEmpty
                  ? 'Не выбрано'
                  : 'Выбрано: ${_computerProgramsForSave().length}',
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Выберите программы',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: WorkaColors.textGreyDark,
                    ),
                  ),
                ),
              ),
              ..._computerPrograms.map((program) {
                final selected = _computerProgramsSelected.contains(program);
                return CheckboxListTile(
                  dense: true,
                  value: selected,
                  activeColor: WorkaColors.blue,
                  checkColor: Colors.white,
                  title: Row(
                    children: [
                      Icon(
                        _computerProgramIcon(program),
                        size: 18,
                        color: WorkaColors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          program,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: WorkaColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  controlAffinity: ListTileControlAffinity.trailing,
                  onChanged: (_) {
                    setState(() {
                      if (selected) {
                        _computerProgramsSelected.remove(program);
                      } else {
                        _computerProgramsSelected.add(program);
                      }
                      if (!_computerProgramsSelected.contains('Другое')) {
                        _computerOtherCtrl.clear();
                      }
                    });
                  },
                );
              }),
            ],
          ),
          if (_computerProgramsSelected.contains('Другое')) ...[
            const SizedBox(height: 6),
            _field(
              label: 'Другое',
              ctrl: _computerOtherCtrl,
              hint: 'Введите навыки через запятую',
            ),
          ],
          const SizedBox(height: 12),
          _switchRow(
            title: 'Есть водительские права',
            value: _hasDrivingLicense,
            onChanged: (v) {
              setState(() {
                _hasDrivingLicense = v;
                if (!v) {
                  _drivingCategories.clear();
                  _hasCar = false;
                }
              });
            },
          ),
          if (_hasDrivingLicense) ...[
            const SizedBox(height: 12),
            const Text(
              'Категории',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: WorkaColors.textGreyDark,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _drivingCategoryOptions.map((cat) {
                final selected = _drivingCategories.contains(cat);
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _drivingCategories.remove(cat);
                      } else {
                        _drivingCategories.add(cat);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? WorkaColors.hoverBlueSoft
                          : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? WorkaColors.blue
                            : WorkaColors.fieldBorder,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: WorkaColors.textDark,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _switchRow(
              title: 'Есть личный автомобиль',
              value: _hasCar,
              onChanged: (v) => setState(() => _hasCar = v),
            ),
          ],
          const SizedBox(height: 12),
          _switchRow(
            title: 'Есть свои инструменты',
            value: _hasTools,
            onChanged: (v) => setState(() => _hasTools = v),
          ),
          const SizedBox(height: 8),
          _switchRow(
            title: 'Есть рабочая одежда',
            value: _hasWorkwear,
            onChanged: (v) => setState(() => _hasWorkwear = v),
          ),
        ];

      case 6:
        return [
          _tapLikeField(
            label: 'Категория *',
            value: _desiredCategoryGroup.isEmpty
                ? 'Выберите категорию'
                : _desiredCategoryGroup,
            hasValue: _desiredCategoryGroup.isNotEmpty,
            onTap: () async {
              final selected = await _pickSingleValue(
                title: 'Категория',
                items: _desiredCategoryOptions,
                current: _desiredCategoryGroup.isEmpty
                    ? null
                    : _desiredCategoryGroup,
                icon: Icons.business_center_outlined,
                iconForItem: _categoryIconForItem,
              );
              if (selected != null) {
                setState(() => _desiredCategoryGroup = selected);
              }
            },
            icon: Icons.business_center_outlined,
          ),
          const SizedBox(height: 12),
          _autocompleteField(
            label: 'Должность',
            ctrl: _desiredPositionCtrl,
            hints: SearchFiltersConfig.positions,
            hintText: 'Начните писать — появятся подсказки',
          ),
          const SizedBox(height: 12),

          // ✅ ЛОКАЦИЯ = страны чекбоксами (LocationPickerSheet)
          _tapLikeField(
            label: 'Локация *',
            value: _desiredCountries.isEmpty
                ? 'Выберите страны'
                : CountryDisplayFormatter.formatCountriesWithFlags(
                    _desiredCountries.toList()..sort(),
                  ).join(', '),
            hasValue: _desiredCountries.isNotEmpty,
            onTap: _pickCountries,
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Дополнительно',
            ctrl: _desiredCitiesCtrl,
            hint: 'Город, место',
          ),
          const SizedBox(height: 12),

          _tapLikeField(
            label: 'Тип работы *',
            value: _desiredEmploymentTypes.isEmpty
                ? 'Выберите'
                : (_desiredEmploymentTypes.toList()..sort()).join(', '),
            hasValue: _desiredEmploymentTypes.isNotEmpty,
            onTap: _pickEmploymentTypes,
            icon: Icons.work_outline_rounded,
          ),
          const SizedBox(height: 12),
          _salaryExpectedField(),
        ];

      default:
        return [];
    }
  }

  // ===== UI helpers =====

  Widget _field({
    required String label,
    required TextEditingController ctrl,
    String? hint,
    TextInputType? keyboard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WorkaColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _genderSelector() {
    Widget button({
      required String value,
      required String label,
      required IconData icon,
    }) {
      final selected = _gender == value;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _gender = value),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: selected ? WorkaColors.blue : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WorkaColors.fieldBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : WorkaColors.textGreyDark,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Пол',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            button(value: 'female', label: 'Женский', icon: Icons.female),
            const SizedBox(width: 12),
            button(value: 'male', label: 'Мужской', icon: Icons.male),
          ],
        ),
      ],
    );
  }

  Widget _birthDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Дата рождения',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _birthDateCtrl,
          keyboardType: TextInputType.datetime,
          onChanged: (v) => setState(() {
            _birthDate = _parseBirthDateInput(v);
          }),
          decoration: InputDecoration(
            hintText: 'ДД.ММ.ГГГГ',
            filled: true,
            fillColor: Colors.white,
            suffixIcon: IconButton(
              onPressed: _pickBirthDate,
              icon: const Icon(Icons.calendar_today, color: WorkaColors.blue),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WorkaColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _citizenshipDropdown() {
    final selected = _normalizeCitizenshipValue(_citizenshipCtrl.text);
    return _dropdownSingle(
      label: 'Гражданство',
      value: selected,
      items: _citizenshipValues,
      displayLabel: (v) => _citizenshipLabels[v] ?? v,
      flagForItem: (v) =>
          CountryDisplayFormatter.countryFlagOnly(v, euAsToken: false),
      onChanged: (v) => setState(() => _citizenshipCtrl.text = v ?? ''),
    );
  }

  Widget _salaryExpectedField() {
    const rowHeight = 54.0;
    const radius = 14.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Желаемая зарплата (необязательно)',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final gap = compact ? 6.0 : 8.0;
            final currencyWidth = compact ? 84.0 : 92.0;
            final periodWidth = compact ? 112.0 : 124.0;
            return Row(
              children: [
                SizedBox(
                  width: currencyWidth,
                  child: SizedBox(
                    height: rowHeight,
                    child: _dropdownSingle(
                      label: 'Валюта',
                      value: _desiredSalaryCurrency,
                      items: _salaryCurrencies,
                      icon: Icons.payments_outlined,
                      showLabel: false,
                      displayLabel: (v) => v == 'USD' ? r'$' : '€',
                      borderRadius: radius,
                      onChanged: (v) => setState(() {
                        _desiredSalaryCurrency = v ?? 'EUR';
                      }),
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: SizedBox(
                    height: rowHeight,
                    child: TextField(
                      controller: _desiredSalaryFromCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Сумма',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 15,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(radius),
                          borderSide: const BorderSide(
                            color: WorkaColors.fieldBorder,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(radius),
                          borderSide: const BorderSide(
                            color: WorkaColors.blue,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: gap),
                SizedBox(
                  width: periodWidth,
                  child: SizedBox(
                    height: rowHeight,
                    child: _dropdownSingle(
                      label: 'Период',
                      value: _desiredSalaryPeriod,
                      items: _salaryPeriods,
                      icon: Icons.schedule,
                      showLabel: false,
                      displayLabel: (v) => _periodLabel(v),
                      borderRadius: radius,
                      onChanged: (v) => setState(() {
                        _desiredSalaryPeriod = v ?? 'month';
                      }),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _multiline({
    required String label,
    required TextEditingController ctrl,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WorkaColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _autocompleteField({
    required String label,
    required TextEditingController ctrl,
    required List<String> hints,
    required String hintText,
  }) {
    final orderedHints = [...hints]
      ..sort((a, b) {
        int rank(String v) {
          final lower = v.toLowerCase();
          if (lower.contains('младш') || lower.contains('junior')) return 2;
          if (lower.contains('старш') ||
              lower.contains('senior') ||
              lower.contains('руковод') ||
              lower.contains('lead')) {
            return 4;
          }
          if (lower.contains('специалист') ||
              lower.contains('менеджер') ||
              lower.contains('инженер') ||
              lower.contains('аналитик')) {
            return 3;
          }
          return 1;
        }

        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return a.compareTo(b);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (t) {
            final q = t.text.trim().toLowerCase();
            if (q.isEmpty) return const Iterable<String>.empty();
            return orderedHints
                .where((e) => e.toLowerCase().contains(q))
                .take(25);
          },
          fieldViewBuilder: (ctx, textCtrl, focusNode, _) {
            if (textCtrl.text != ctrl.text) {
              textCtrl.text = ctrl.text;
              textCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: textCtrl.text.length),
              );
            }
            textCtrl.addListener(() => ctrl.text = textCtrl.text);

            return TextField(
              controller: textCtrl,
              focusNode: focusNode,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: hintText,
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: WorkaColors.fieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: WorkaColors.blue,
                    width: 1.6,
                  ),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final v = list[i];
                      return InkWell(
                        onTap: () => onSelected(v),
                        borderRadius: BorderRadius.circular(12),
                        hoverColor: WorkaColors.hoverBlueSoft,
                        splashColor: WorkaColors.hoverBlueSoft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                            border: Border.all(color: WorkaColors.fieldBorder),
                          ),
                          child: Text(
                            v,
                            style: const TextStyle(
                              color: WorkaColors.textGreyDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
          onSelected: (v) => setState(() => ctrl.text = v),
        ),
      ],
    );
  }

  Widget _tapLikeField({
    required String label,
    required String value,
    required bool hasValue,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            hoverColor: WorkaColors.hoverBlueSoft,
            splashColor: WorkaColors.hoverBlueSoft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WorkaColors.fieldBorder),
              ),
              child: Row(
                children: [
                  Icon(icon, color: WorkaColors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasValue
                            ? WorkaColors.textGreyDark
                            : WorkaColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: WorkaColors.blue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownSingle({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    IconData? icon,
    bool showLabel = true,
    String Function(String value)? displayLabel,
    double borderRadius = 16,
    String Function(String value)? flagForItem,
  }) {
    final normalized = <String>{
      for (final e in items.map((e) => e.trim()).where((e) => e.isNotEmpty)) e,
    }.toList();
    final safeValue = (value != null && normalized.contains(value.trim()))
        ? value.trim()
        : null;
    final selectedText = safeValue == null
        ? 'Выберите'
        : (displayLabel?.call(safeValue) ?? safeValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: WorkaColors.textGreyDark,
            ),
          ),
          const SizedBox(height: 8),
        ],
        InkWell(
          onTap: () async {
            final selected = await _pickSingleValue(
              title: label,
              items: normalized,
              current: safeValue,
              icon: icon,
              displayLabel: displayLabel,
              flagForItem: flagForItem,
            );
            if (selected != null) onChanged(selected);
          },
          borderRadius: BorderRadius.circular(16),
          hoverColor: WorkaColors.hoverBlueSoft,
          splashColor: WorkaColors.hoverBlueSoft,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: WorkaColors.fieldBorder),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: WorkaColors.blue),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    selectedText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: safeValue == null
                          ? WorkaColors.textGrey
                          : WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: WorkaColors.blue,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<String?> _pickSingleValue({
    required String title,
    required List<String> items,
    required String? current,
    IconData? icon,
    String Function(String value)? displayLabel,
    IconData Function(String value)? iconForItem,
    String Function(String value)? flagForItem,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final selected = (current ?? '').trim();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: WorkaColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final isSelected = selected == item;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        hoverColor: WorkaColors.hoverBlueSoft,
                        splashColor: WorkaColors.hoverBlueSoft,
                        onTap: () => Navigator.pop(ctx, item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? WorkaColors.hoverBlueSoft
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? WorkaColors.blue
                                  : WorkaColors.fieldBorder,
                              width: 1.2,
                            ),
                          ),
                          child: flagForItem != null
                              ? Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      color: isSelected
                                          ? WorkaColors.blue
                                          : WorkaColors.textGrey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      flagForItem(item),
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item,
                                        style: TextStyle(
                                          color: isSelected
                                              ? WorkaColors.blue
                                              : WorkaColors.textGreyDark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Icon(
                                      iconForItem?.call(item) ??
                                          icon ??
                                          Icons.circle_outlined,
                                      size: 18,
                                      color: WorkaColors.blue,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        displayLabel?.call(item) ?? item,
                                        style: TextStyle(
                                          color: isSelected
                                              ? WorkaColors.blue
                                              : WorkaColors.textGreyDark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      color: isSelected
                                          ? WorkaColors.blue
                                          : WorkaColors.textGrey,
                                      size: 18,
                                    ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: WorkaColors.textDark,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _addLineButton(String text, VoidCallback onTap) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add, color: WorkaColors.blue),
            label: Text(
              text,
              style: const TextStyle(
                color: WorkaColors.textDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: WorkaColors.fieldBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardBlock({
    required String header,
    required Widget child,
    VoidCallback? onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  header,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: WorkaColors.textGreyDark,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _miniField({
    required String label,
    required String initial,
    required ValueChanged<String> onText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: initial,
          maxLines: maxLines,
          onChanged: onText,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: WorkaColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownInline({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    IconData leadingIcon = Icons.list_alt_rounded,
    String Function(String value)? displayLabel,
    String Function(String value)? flagForItem,
  }) {
    final normalized = <String>{
      for (final e in items.map((e) => e.trim()).where((e) => e.isNotEmpty)) e,
    }.toList();
    final safeValue = (value != null && normalized.contains(value.trim()))
        ? value.trim()
        : null;
    final selectedText = safeValue == null
        ? hint
        : (displayLabel?.call(safeValue) ?? safeValue);
    return InkWell(
      onTap: () async {
        final selected = await _pickSingleValue(
          title: hint,
          items: normalized,
          current: safeValue,
          icon: leadingIcon,
          displayLabel: displayLabel,
          flagForItem: flagForItem,
        );
        if (selected != null) onChanged(selected);
      },
      borderRadius: BorderRadius.circular(14),
      hoverColor: WorkaColors.hoverBlueSoft,
      splashColor: WorkaColors.hoverBlueSoft,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WorkaColors.fieldBorder),
        ),
        child: Row(
          children: [
            Icon(leadingIcon, color: WorkaColors.blue, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: safeValue == null
                      ? WorkaColors.textGrey
                      : WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: WorkaColors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthYearRow({
    required String title,
    required int? month,
    required int? year,
    required ValueChanged<int?> onMonth,
    required ValueChanged<int?> onYear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _pickerField(
                label: month == null ? 'Месяц' : _monthLabels[month - 1],
                onTap: () async {
                  final picked = await _pickMonthBottomSheet(
                    initialMonth: month,
                  );
                  if (picked != null) onMonth(picked);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _pickerField(
                label: year?.toString() ?? 'Год',
                onTap: () async {
                  final picked = await _pickYearBottomSheet(initialYear: year);
                  if (picked != null) onYear(picked);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _monthYearDateRow({
    required String title,
    required DateTime? date,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return _monthYearRow(
      title: title,
      month: date?.month,
      year: date?.year,
      onMonth: (m) {
        if (m == null) {
          onChanged(null);
          return;
        }
        final year = date?.year ?? DateTime.now().year;
        onChanged(DateTime(year, m, 1));
      },
      onYear: (y) {
        if (y == null) {
          onChanged(null);
          return;
        }
        final month = date?.month ?? 1;
        onChanged(DateTime(y, month, 1));
      },
    );
  }

  Widget _pickerField({
    required String label,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      hoverColor: WorkaColors.hoverBlueSoft,
      splashColor: WorkaColors.hoverBlueSoft,
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WorkaColors.fieldBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: (label == 'Месяц' || label == 'Год')
                      ? WorkaColors.textGrey
                      : WorkaColors.textDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: WorkaColors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _pickMonthBottomSheet({int? initialMonth}) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Месяц',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: WorkaColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _monthLabels.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final month = i + 1;
                      final selected = month == initialMonth;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        hoverColor: WorkaColors.hoverBlueSoft,
                        splashColor: WorkaColors.hoverBlueSoft,
                        onTap: () => Navigator.pop(ctx, month),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? WorkaColors.hoverBlueSoft
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? WorkaColors.blue
                                  : WorkaColors.fieldBorder,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _monthLabels[i],
                                  style: TextStyle(
                                    color: selected
                                        ? WorkaColors.blue
                                        : WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_rounded,
                                  color: WorkaColors.blue,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<int?> _pickYearBottomSheet({int? initialYear}) {
    final years = _yearOptions();
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Год',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: WorkaColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: years.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final year = years[i];
                      final selected = year == initialYear;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        hoverColor: WorkaColors.hoverBlueSoft,
                        splashColor: WorkaColors.hoverBlueSoft,
                        onTap: () => Navigator.pop(ctx, year),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? WorkaColors.hoverBlueSoft
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? WorkaColors.blue
                                  : WorkaColors.fieldBorder,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$year',
                                  style: TextStyle(
                                    color: selected
                                        ? WorkaColors.blue
                                        : WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_rounded,
                                  color: WorkaColors.blue,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===== blocks: experience / education / languages =====

  Widget _jobBlock({
    required int index,
    required _JobRow row,
    required ValueChanged<_JobRow> onChanged,
    VoidCallback? onRemove,
  }) {
    return _cardBlock(
      header: 'Место работы ${index + 1}',
      onRemove: onRemove,
      child: Column(
        children: [
          _miniField(
            label: 'Должность',
            initial: row.position,
            onText: (v) => onChanged(row.copyWith(position: v)),
          ),
          const SizedBox(height: 10),
          _miniField(
            label: 'Название фирмы',
            initial: row.company,
            onText: (v) => onChanged(row.copyWith(company: v)),
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Локация (страна)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: WorkaColors.textGreyDark,
                ),
              ),
              const SizedBox(height: 8),
              _dropdownInline(
                hint: 'Выберите',
                value: row.country.isEmpty ? null : row.country,
                items: SearchFiltersConfig.countriesRu,
                displayLabel: _countryWithFlag,
                flagForItem: (v) => CountryDisplayFormatter.countryFlagOnly(
                  v,
                  euAsToken: false,
                ),
                onChanged: (v) => onChanged(row.copyWith(country: v ?? '')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _miniField(
            label: 'Описание работы и достижений',
            initial: row.description,
            maxLines: 4,
            onText: (v) => onChanged(row.copyWith(description: v)),
          ),
          const SizedBox(height: 10),
          _monthYearDateRow(
            title: 'Дата начала',
            date: row.startDate,
            onChanged: (d) => onChanged(row.copyWith(startDate: d)),
          ),
          const SizedBox(height: 10),
          _switchRow(
            title: 'По настоящее время',
            value: row.isCurrent,
            onChanged: (v) => onChanged(
              row.copyWith(isCurrent: v, endDate: v ? null : row.endDate),
            ),
          ),
          if (!row.isCurrent) ...[
            const SizedBox(height: 10),
            _monthYearDateRow(
              title: 'Дата окончания',
              date: row.endDate,
              onChanged: (d) => onChanged(row.copyWith(endDate: d)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _eduBlock({
    required int index,
    required _EduRow row,
    required ValueChanged<_EduRow> onChanged,
    VoidCallback? onRemove,
  }) {
    return _cardBlock(
      header: 'Образование ${index + 1}',
      onRemove: onRemove,
      child: Column(
        children: [
          _miniField(
            label: 'Учебное заведение',
            initial: row.school,
            onText: (v) => onChanged(row.copyWith(school: v)),
          ),
          const SizedBox(height: 10),
          _miniField(
            label: 'Специальность',
            initial: row.speciality,
            onText: (v) => onChanged(row.copyWith(speciality: v)),
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Государство',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: WorkaColors.textGreyDark,
                ),
              ),
              const SizedBox(height: 8),
              _dropdownInline(
                hint: 'Выберите',
                value: row.country.isEmpty ? null : row.country,
                items: SearchFiltersConfig.countriesRu,
                displayLabel: _countryWithFlag,
                flagForItem: (v) => CountryDisplayFormatter.countryFlagOnly(
                  v,
                  euAsToken: false,
                ),
                onChanged: (v) => onChanged(row.copyWith(country: v ?? '')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _monthYearRow(
            title: 'Дата начала',
            month: row.startMonth,
            year: row.startYear,
            onMonth: (v) => onChanged(row.copyWith(startMonth: v)),
            onYear: (v) => onChanged(row.copyWith(startYear: v)),
          ),
          const SizedBox(height: 10),
          _switchRow(
            title: 'Учусь сейчас',
            value: row.isCurrent,
            onChanged: (v) => onChanged(
              row.copyWith(
                isCurrent: v,
                endMonth: v ? null : row.endMonth,
                endYear: v ? null : row.endYear,
              ),
            ),
          ),
          if (!row.isCurrent) ...[
            const SizedBox(height: 10),
            _monthYearRow(
              title: 'Дата окончания',
              month: row.endMonth,
              year: row.endYear,
              onMonth: (v) => onChanged(row.copyWith(endMonth: v)),
              onYear: (v) => onChanged(row.copyWith(endYear: v)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _langBlock({
    required int index,
    required _LangRow row,
    required ValueChanged<_LangRow> onChanged,
    VoidCallback? onRemove,
  }) {
    final List<String> langs = <String>[
      ...SearchFiltersConfig.languages,
      'Другой',
    ];
    final levels = const ['Начальный', 'Средний', 'Свободный'];

    return _cardBlock(
      header: 'Язык ${index + 1}',
      onRemove: onRemove,
      child: Column(
        children: [
          _dropdownInline(
            hint: 'Выберите язык',
            value: row.language.isEmpty ? null : row.language,
            items: langs,
            leadingIcon: Icons.translate,
            displayLabel: _languageDisplayLabel,
            onChanged: (v) {
              if (v == null) return;
              if (v == 'Другой') {
                onChanged(row.copyWith(language: 'Другой'));
              } else {
                onChanged(row.copyWith(language: v, customLanguage: ''));
              }
            },
          ),
          if (row.language == 'Другой') ...[
            const SizedBox(height: 10),
            _miniField(
              label: 'Введите свой язык',
              initial: row.customLanguage,
              onText: (v) => onChanged(row.copyWith(customLanguage: v)),
            ),
          ],
          const SizedBox(height: 10),
          _dropdownInline(
            hint: 'Уровень',
            value: row.level.isEmpty ? null : row.level,
            items: levels,
            onChanged: (v) => onChanged(row.copyWith(level: v ?? '')),
          ),
        ],
      ),
    );
  }
}

// =====================
// Preview sheet (big card overlay)
// =====================

class _PreviewResult {
  final bool edit;
  final bool addToCandidates;
  const _PreviewResult({required this.edit, required this.addToCandidates});
}

class _CvPreviewSheet extends StatefulWidget {
  final Map<String, dynamic> cvData;

  final ValueChanged<String> onEditSectionId;

  const _CvPreviewSheet({required this.cvData, required this.onEditSectionId});

  @override
  State<_CvPreviewSheet> createState() => _CvPreviewSheetState();
}

class _CvPreviewSheetState extends State<_CvPreviewSheet> {
  bool _addToCandidates = false;
  bool _editMode = false;

  dynamic _normalizePreviewValue(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate().toIso8601String();
    }
    if (raw is DateTime) {
      return raw.toIso8601String();
    }
    if (raw is Map) {
      return raw.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), _normalizePreviewValue(value)),
      );
    }
    if (raw is List) {
      return raw.map(_normalizePreviewValue).toList();
    }
    return raw;
  }

  String _stepIdForSection(CvSection section) {
    return switch (section) {
      CvSection.header => CvWizardStepIds.profile,
      CvSection.title => CvWizardStepIds.about,
      CvSection.about => CvWizardStepIds.about,
      CvSection.desiredJob => CvWizardStepIds.jobPreferences,
      CvSection.experience => CvWizardStepIds.experience,
      CvSection.education => CvWizardStepIds.education,
      CvSection.languages => CvWizardStepIds.languages,
      CvSection.computerSkills => CvWizardStepIds.computerSkills,
      CvSection.driving => CvWizardStepIds.drivingLicense,
    };
  }

  Widget _editFab({required String text, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: _editMode ? onTap : null,
      icon: const Icon(Icons.edit, size: 16),
      label: Text(text),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: WorkaColors.fieldBorder),
        foregroundColor: WorkaColors.orange,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.92;
    final normalizedCvData = _normalizePreviewValue(widget.cvData);
    final normalizedCvMap = normalizedCvData is Map
        ? Map<String, dynamic>.from(normalizedCvData)
        : const <String, dynamic>{};
    final cvMap = <String, dynamic>{
      ...normalizedCvMap,
      'visibility': {'inCandidates': _addToCandidates},
    };

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: SizedBox(
            height: h,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: WorkaColors.divider,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      CvProfileView(
                        cvId: 'draft',
                        cv: cvMap,
                        mode: _editMode
                            ? CvViewerMode.ownerEdit
                            : CvViewerMode.ownerView,
                        padding: EdgeInsets.zero,
                        onEditSection: _editMode
                            ? (section) => widget.onEditSectionId(
                                _stepIdForSection(section),
                              )
                            : null,
                      ),
                      if (_editMode) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _editFab(
                              text: 'Контакты',
                              onTap: () => widget.onEditSectionId(
                                CvWizardStepIds.profile,
                              ),
                            ),
                            _editFab(
                              text: 'Заголовок',
                              onTap: () =>
                                  widget.onEditSectionId(CvWizardStepIds.about),
                            ),
                            _editFab(
                              text: 'Опыт',
                              onTap: () => widget.onEditSectionId(
                                CvWizardStepIds.experience,
                              ),
                            ),
                            _editFab(
                              text: 'Образование',
                              onTap: () => widget.onEditSectionId(
                                CvWizardStepIds.education,
                              ),
                            ),
                            _editFab(
                              text: 'Языки',
                              onTap: () => widget.onEditSectionId(
                                CvWizardStepIds.languages,
                              ),
                            ),
                            _editFab(
                              text: 'Компьютер и права',
                              onTap: () => widget.onEditSectionId(
                                CvWizardStepIds.computerSkills,
                              ),
                            ),
                            _editFab(
                              text: 'Желаемая работа',
                              onTap: () => widget.onEditSectionId(
                                CvWizardStepIds.jobPreferences,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),

                      // toggle
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: WorkaColors.fieldBorder),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Показывать работодателям',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: WorkaColors.textDark,
                                ),
                              ),
                            ),
                            Switch(
                              value: _addToCandidates,
                              onChanged: (v) =>
                                  setState(() => _addToCandidates = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 90),
                    ],
                  ),
                ),

                // bottom buttons
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () =>
                                  setState(() => _editMode = !_editMode),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WorkaColors.orange,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: Text(
                                _editMode
                                    ? 'Редактирование включено'
                                    : 'Редактировать',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(
                                context,
                                _PreviewResult(
                                  edit: false,
                                  addToCandidates: _addToCandidates,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: WorkaColors.fieldBorder,
                                  width: 1.2,
                                ),
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: const Text(
                                'Готово',
                                style: TextStyle(
                                  color: WorkaColors.orange,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================
// Rows
// =====================

const Object _noChange = Object();

class _LangRow {
  final String language; // can be 'Другой'
  final String customLanguage;
  final String level;

  const _LangRow({
    required this.language,
    required this.level,
    this.customLanguage = '',
  });

  _LangRow copyWith({String? language, String? customLanguage, String? level}) {
    return _LangRow(
      language: language ?? this.language,
      customLanguage: customLanguage ?? this.customLanguage,
      level: level ?? this.level,
    );
  }

  Map<String, dynamic> toMap() {
    final lang = (language == 'Другой')
        ? customLanguage.trim()
        : language.trim();
    if (lang.isEmpty && level.trim().isEmpty) return {};
    return {'language': lang, 'level': level.trim()};
  }
}

class _JobRow {
  final String position;
  final String company;
  final String country;
  final String description;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCurrent;

  const _JobRow({
    this.position = '',
    this.company = '',
    this.country = '',
    this.description = '',
    this.startDate,
    this.endDate,
    this.isCurrent = false,
  });

  _JobRow copyWith({
    String? position,
    String? company,
    String? country,
    String? description,
    Object? startDate = _noChange,
    Object? endDate = _noChange,
    bool? isCurrent,
  }) {
    return _JobRow(
      position: position ?? this.position,
      company: company ?? this.company,
      country: country ?? this.country,
      description: description ?? this.description,
      startDate: identical(startDate, _noChange)
          ? this.startDate
          : startDate as DateTime?,
      endDate: identical(endDate, _noChange)
          ? this.endDate
          : endDate as DateTime?,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }

  Map<String, dynamic> toMap() {
    final p = position.trim();
    final c = company.trim();
    final countryValue = country.trim();
    final d = description.trim();
    if (p.isEmpty &&
        c.isEmpty &&
        countryValue.isEmpty &&
        d.isEmpty &&
        startDate == null &&
        endDate == null &&
        !isCurrent) {
      return {};
    }
    String fmt(DateTime value) {
      final mm = value.month.toString().padLeft(2, '0');
      final dd = value.day.toString().padLeft(2, '0');
      return '${value.year}-$mm-$dd';
    }

    return {
      'position': p,
      'company': c,
      'country': countryValue,
      'description': d,
      if (startDate != null) 'startDate': fmt(startDate!),
      'startMonth': startDate?.month,
      'startYear': startDate?.year,
      if (!isCurrent && endDate != null) 'endDate': fmt(endDate!),
      'endMonth': isCurrent ? null : endDate?.month,
      'endYear': isCurrent ? null : endDate?.year,
      'isCurrent': isCurrent,
    };
  }
}

class _EduRow {
  final String school;
  final String speciality;
  final String country;
  final int? startMonth;
  final int? startYear;
  final int? endMonth;
  final int? endYear;
  final bool isCurrent;

  const _EduRow({
    this.school = '',
    this.speciality = '',
    this.country = '',
    this.startMonth,
    this.startYear,
    this.endMonth,
    this.endYear,
    this.isCurrent = false,
  });

  _EduRow copyWith({
    String? school,
    String? speciality,
    String? country,
    Object? startMonth = _noChange,
    Object? startYear = _noChange,
    Object? endMonth = _noChange,
    Object? endYear = _noChange,
    bool? isCurrent,
  }) {
    return _EduRow(
      school: school ?? this.school,
      speciality: speciality ?? this.speciality,
      country: country ?? this.country,
      startMonth: identical(startMonth, _noChange)
          ? this.startMonth
          : startMonth as int?,
      startYear: identical(startYear, _noChange)
          ? this.startYear
          : startYear as int?,
      endMonth: identical(endMonth, _noChange)
          ? this.endMonth
          : endMonth as int?,
      endYear: identical(endYear, _noChange) ? this.endYear : endYear as int?,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }

  Map<String, dynamic> toMap() {
    final s = school.trim();
    final sp = speciality.trim();
    final c = country.trim();
    if (s.isEmpty &&
        sp.isEmpty &&
        c.isEmpty &&
        startMonth == null &&
        startYear == null &&
        endMonth == null &&
        endYear == null &&
        !isCurrent) {
      return {};
    }
    return {
      'school': s,
      'specialization': sp,
      'speciality': sp,
      'country': c,
      'startMonth': startMonth,
      'startYear': startYear,
      'endMonth': isCurrent ? null : endMonth,
      'endYear': isCurrent ? null : endYear,
      'isCurrent': isCurrent,
    };
  }
}
