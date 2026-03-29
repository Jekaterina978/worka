import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../data/worka_countries.dart';
import '../../utils/country_display_formatter.dart';
import '../../services/firebase_debug_diagnostics.dart';
import '../../services/firestore_paths.dart';
import '../../services/auth_guard.dart';
import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';
import '../../widgets/contact_fields.dart';
import '../jobs/services/job_draft_storage.dart';
import '../auth/auth_entry_screen.dart';
import '../../services/ownership_context.dart';
import '../search/services/exchange_rate_service.dart';
import '../search/widgets/search_filters_config.dart';
import '../search/widgets/location_picker_sheet.dart';
import '../employer_company_profile_screen.dart';
import '../../features/monetization/monetization_i18n.dart';
import '../../features/monetization/monetization_repository.dart';
import '../../features/monetization/monetization_routes.dart';
import '../../features/monetization/pricing.dart';
import '../../services/app_mode.dart' as app_mode;
import '../../widgets/ai_autofill_sheet.dart';
import '../../widgets/profile_avatar_button.dart';
import '../cv/widgets/cv_progress_dots.dart';
import '../../features/payments/screens/promote_job_screen.dart';

import 'my_publications_screen.dart';

// ─── Step titles ───────────────────────────────────────────────────────────
const List<String> _kStepTitles = [
  'Основное',
  'Условия',
  'Требования',
  'Описание',
  'Публикация',
];

class _JobFlowUi {
  static const double screenPadding = 16;
  static const double blockGap = 14;
  static const double tilePadding = 12;
  static const double tileIconSize = 20;
  static const double trailingIconSize = 20;
  static const double radiusCard = 16;
  static const double radiusPill = WorkaUiRadius.control;

  static const Color primary = WorkaColors.blue;
  static const Color surface = WorkaColors.cardBg;
  static const Color border = WorkaColors.divider;
  static const Color muted = WorkaColors.textGreyDark;
}

// ─── Country flags ─────────────────────────────────────────────────────────
const Map<String, String> _kCountryFlags = {
  'Эстония': '🇪🇪',
  'Латвия': '🇱🇻',
  'Литва': '🇱🇹',
  'Финляндия': '🇫🇮',
  'Швеция': '🇸🇪',
  'Норвегия': '🇳🇴',
  'Дания': '🇩🇰',
  'Германия': '🇩🇪',
  'Австрия': '🇦🇹',
  'Швейцария': '🇨🇭',
  'Польша': '🇵🇱',
  'Чехия': '🇨🇿',
  'Словакия': '🇸🇰',
  'Венгрия': '🇭🇺',
  'Румыния': '🇷🇴',
  'Болгария': '🇧🇬',
  'Хорватия': '🇭🇷',
  'Словения': '🇸🇮',
  'Сербия': '🇷🇸',
  'Франция': '🇫🇷',
  'Бельгия': '🇧🇪',
  'Нидерланды': '🇳🇱',
  'Испания': '🇪🇸',
  'Португалия': '🇵🇹',
  'Италия': '🇮🇹',
  'Греция': '🇬🇷',
  'Великобритания': '🇬🇧',
  'Ирландия': '🇮🇪',
  'США': '🇺🇸',
  'Канада': '🇨🇦',
};

// ─── Extended country → cities ─────────────────────────────────────────────
const Map<String, List<String>> _kCitiesByCountry = {
  'Эстония': ['Таллинн', 'Тарту', 'Нарва', 'Пярну', 'Кохтла-Ярве', 'Вильянди'],
  'Латвия': ['Рига', 'Даугавпилс', 'Лиепая', 'Елгава', 'Юрмала', 'Вентспилс'],
  'Литва': ['Вильнюс', 'Каунас', 'Клайпеда', 'Шяуляй', 'Паневежис'],
  'Финляндия': ['Хельсинки', 'Тампере', 'Турку', 'Оулу', 'Ювяскюля'],
  'Швеция': ['Стокгольм', 'Гётеборг', 'Мальмё', 'Уппсала', 'Вастерос'],
  'Норвегия': ['Осло', 'Берген', 'Тронхейм', 'Ставангер', 'Кристиансанн'],
  'Дания': ['Копенгаген', 'Орхус', 'Оденсе', 'Ольборг', 'Эсбьерг'],
  'Германия': [
    'Берлин',
    'Мюнхен',
    'Гамбург',
    'Франкфурт',
    'Кёльн',
    'Штутгарт',
    'Дюссельдорф',
    'Лейпциг',
    'Дрезден',
  ],
  'Австрия': ['Вена', 'Грац', 'Линц', 'Зальцбург', 'Инсбрук'],
  'Швейцария': ['Цюрих', 'Женева', 'Базель', 'Берн', 'Лозанна'],
  'Польша': [
    'Варшава',
    'Краков',
    'Лодзь',
    'Вроцлав',
    'Познань',
    'Гданьск',
    'Щецин',
    'Катовице',
  ],
  'Чехия': ['Прага', 'Брно', 'Острава', 'Пльзень', 'Либерец'],
  'Словакия': ['Братислава', 'Кошице', 'Прешов', 'Жилина', 'Нитра'],
  'Венгрия': ['Будапешт', 'Дебрецен', 'Мишкольц', 'Печ', 'Дьёр'],
  'Румыния': ['Бухарест', 'Клуж-Напока', 'Тимишоара', 'Яссы', 'Констанца'],
  'Болгария': ['София', 'Пловдив', 'Варна', 'Бургас', 'Русе'],
  'Хорватия': ['Загреб', 'Сплит', 'Риека', 'Осиек', 'Задар'],
  'Словения': ['Любляна', 'Марибор', 'Целе', 'Крань', 'Копер'],
  'Сербия': ['Белград', 'Нови-Сад', 'Ниш', 'Крагуевац', 'Суботица'],
  'Франция': [
    'Париж',
    'Марсель',
    'Лион',
    'Тулуза',
    'Ницца',
    'Нант',
    'Страсбург',
    'Бордо',
  ],
  'Бельгия': ['Брюссель', 'Антверпен', 'Гент', 'Льеж', 'Брюгге'],
  'Нидерланды': ['Амстердам', 'Роттердам', 'Гаага', 'Утрехт', 'Эйндховен'],
  'Испания': [
    'Мадрид',
    'Барселона',
    'Валенсия',
    'Севилья',
    'Сарагоса',
    'Малага',
    'Бильбао',
  ],
  'Португалия': ['Лиссабон', 'Порту', 'Амадора', 'Брага', 'Коимбра'],
  'Италия': [
    'Рим',
    'Милан',
    'Неаполь',
    'Турин',
    'Палермо',
    'Генуя',
    'Болонья',
    'Флоренция',
    'Венеция',
  ],
  'Греция': ['Афины', 'Салоники', 'Пирей', 'Патры', 'Гераклион'],
  'Великобритания': [
    'Лондон',
    'Бирмингем',
    'Манчестер',
    'Лидс',
    'Глазго',
    'Ливерпуль',
    'Эдинбург',
    'Бристоль',
  ],
  'Ирландия': ['Дублин', 'Корк', 'Лимерик', 'Голуэй', 'Уотерфорд'],
  'США': [
    'Нью-Йорк',
    'Лос-Анджелес',
    'Чикаго',
    'Хьюстон',
    'Финикс',
    'Филадельфия',
    'Сан-Диего',
    'Даллас',
  ],
  'Канада': [
    'Торонто',
    'Монреаль',
    'Ванкувер',
    'Калгари',
    'Эдмонтон',
    'Оттава',
  ],
};

// ─── Requirements presets ──────────────────────────────────────────────────
const _kExperienceOptions = [
  'Без опыта',
  'До 1 года',
  '1–3 года',
  '3–5 лет',
  '5+ лет',
];

const _kCitizenshipOptions = [
  'ЕС (любая страна)',
  'Украина',
  'Беларусь',
  'Молдова',
  'Грузия',
  'Армения',
  'Азербайджан',
  'Казахстан',
  'Узбекистан',
  'Таджикистан',
];

const _kDrivingLicenseOptions = ['A', 'B', 'C', 'D', 'E', 'BE', 'CE'];

const _kLanguageOptions = [
  'Русский',
  'Английский',
  'Немецкий',
  'Финский',
  'Шведский',
  'Польский',
  'Другое',
];

class CreateJobScreen extends StatefulWidget {
  final String? employerType; // 'company' | 'private'

  /// testMode=true: сохраняем вакансии даже без авторизации (для тестов)
  final bool testMode;
  final String? editJobId;
  final DocumentReference<Map<String, dynamic>>? editJobRef;
  final int? initialStep;

  const CreateJobScreen({
    super.key,
    this.employerType,
    this.testMode = true,
    this.editJobId,
    this.editJobRef,
    this.initialStep,
  });

  @override
  State<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends State<CreateJobScreen> {
  _CreateJobScreenState() {
    debugPrint('🔥 [CREATE_JOB_SCREEN] FILE = lib/screens/employer/create_job_screen.dart');
  }
  static const int _stepsCount = 5;
  int _step = 0;
  bool _saving = false;
  String? _newJobCode;

  Uri _buildJobsCreateUri() {
    final base = const String.fromEnvironment('WORKA_API_BASE_URL', defaultValue: '')
        .replaceAll(RegExp(r'/+$'), '');
    assert(base.isNotEmpty, 'WORKA_API_BASE_URL is required');
    debugPrint('🔥 [BASE_URL] base=$base');
    return Uri.parse('$base/api/jobs');
  }

  final OwnershipContext _ownership = OwnershipContext();

  // ─── Step 1: Basic Info ────────────────────────────────────────────────
  final _vacancyNumberCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  String? _category;
  final _cityCtrl = TextEditingController();
  String _country = 'Эстония';

  // ─── Step 2: Work Conditions ───────────────────────────────────────────
  String? _employmentType;
  final _salaryFromCtrl = TextEditingController();
  final _salaryToCtrl = TextEditingController();
  String _salaryCurrency = 'EUR';
  String _salaryPeriodRu = 'В месяц';
  String? _workSchedule;
  final _customWorkScheduleCtrl = TextEditingController();
  String? _gender;
  final _openingsCtrl = TextEditingController(text: '1');

  // ─── Step 3: Requirements ──────────────────────────────────────────────
  final Set<String> _citizenships = {};
  String? _experience;
  final _ageFromCtrl = TextEditingController();
  final _ageToCtrl = TextEditingController();
  final Set<String> _drivingLicenses = {};
  bool _hasCar = false;
  final Set<String> _languages = {};
  String? _languageDraftSelection;
  final _otherLanguageCtrl = TextEditingController();
  final _additionalRequirementsCtrl = TextEditingController();

  // ─── Step 4: Description ──────────────────────────────────────────────
  final _responsibilitiesCtrl = TextEditingController();
  final _requirementsCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  bool _housingProvided = false;
  bool _transportProvided = false;
  final _housingCostFromCtrl = TextEditingController();
  final _housingCostToCtrl = TextEditingController();
  final _transportCostFromCtrl = TextEditingController();
  final _transportCostToCtrl = TextEditingController();
  bool _teenFriendly = false;
  bool _disabilityFriendly = false;
  bool _isUrgent = false;
  bool _paidUrgent = false;
  bool _urgentRequested = false;

  // ─── Step 5: Duration + Company/Contact ───────────────────────────────
  int _expiryPresetDays = 7;
  final _customDaysCtrl = TextEditingController(text: '7');
  final _companyNameCtrl = TextEditingController();
  final _regNumberCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  bool _showContacts = true;
  final _contactFirstCtrl = TextEditingController();
  final _contactLastCtrl = TextEditingController();
  final _phoneNumberCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _phoneCountryCode = '+372';
  final _telegramCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _viberCtrl = TextEditingController();
  bool _hasBusinessProfilePrefill = false;

  static const Map<String, IconData> _categoryIcons = {
    'Строительство и рабочие специальности': Icons.construction,
    'Строитель': Icons.handyman,
    'Сварщик': Icons.precision_manufacturing,
    'Маляр': Icons.format_paint,
    'Сантехник': Icons.plumbing,
    'Электрик': Icons.electrical_services,
    'Логистика и производство': Icons.local_shipping,
    'Склад': Icons.warehouse,
    'Продажи и сервис': Icons.shopping_bag,
    'Офис и администрирование': Icons.business_center,
    'IT и digital': Icons.terminal,
    'Медицина': Icons.medical_services,
    'Красота и спорт': Icons.content_cut,
    'Дом и сервис': Icons.home,
    'Общественное питание': Icons.restaurant_menu,
    'Транспорт и авто': Icons.local_taxi,
    'Финансы': Icons.payments,
  };

  @override
  void initState() {
    super.initState();
    debugPrint('🔥 [SCREEN_RUNTIME] employer/create_job_screen opened');

    if (SearchFiltersConfig.countriesRu.isNotEmpty) {
      _country = SearchFiltersConfig.countriesRu.firstWhere(
        (c) => c == 'Эстония',
        orElse: () => SearchFiltersConfig.countriesRu.first,
      );
    }

    _prefillContactsIfLoggedIn()
        .then((_) => _loadForEditIfNeeded())
        .then((_) => _restoreDraftIfAny())
        .then((_) {
          if (!mounted) return;
          final initial = widget.initialStep;
          if (_isEditMode &&
              initial != null &&
              initial >= 0 &&
              initial < _stepsCount) {
            setState(() => _step = initial);
          }
        });
  }

  bool get _isEditMode => widget.editJobId != null || widget.editJobRef != null;

  bool get _isCustomWorkSchedule => (_workSchedule ?? '').trim() == 'Другое';

  static const List<String> _kWorkScheduleOptions = <String>[
    'Пн–Пт, 8 часов',
    'Сменный график',
    'Вахта',
    'Гибкий',
    'Другое',
  ];

  String _resolvedWorkSchedule() {
    if (_isCustomWorkSchedule) {
      return _customWorkScheduleCtrl.text.trim();
    }
    return (_workSchedule ?? '').trim();
  }

  void _restoreWorkSchedule({
    required String option,
    required String custom,
    required String legacy,
  }) {
    final opt = option.trim();
    final cus = custom.trim();
    final old = legacy.trim();
    if (opt.isNotEmpty) {
      _workSchedule = opt;
      if (opt == 'Другое') {
        _customWorkScheduleCtrl.text = cus.isNotEmpty ? cus : old;
      }
      return;
    }
    if (old.isEmpty) return;
    if (_kWorkScheduleOptions.contains(old)) {
      _workSchedule = old;
      return;
    }
    _workSchedule = 'Другое';
    _customWorkScheduleCtrl.text = cus.isNotEmpty ? cus : old;
  }

  // ─── Draft ─────────────────────────────────────────────────────────────

  Map<String, dynamic> _draftData() {
    return <String, dynamic>{
      'status': 'unfinished',
      'savedAt': DateTime.now().toIso8601String(),
      'step': _step,
      'vacancyNumber': _vacancyNumberCtrl.text.trim(),
      'title': _titleCtrl.text.trim(),
      'category': (_category ?? '').trim(),
      'city': _cityCtrl.text.trim(),
      'country': _country.trim(),
      'employmentType': (_employmentType ?? '').trim(),
      'salaryFrom': _salaryFromCtrl.text.trim(),
      'salaryTo': _salaryToCtrl.text.trim(),
      'salaryCurrency': _salaryCurrency,
      'salaryPeriodRu': _salaryPeriodRu,
      'workSchedule': _resolvedWorkSchedule(),
      'workScheduleOption': (_workSchedule ?? '').trim(),
      'workScheduleCustom': _customWorkScheduleCtrl.text.trim(),
      'gender': (_gender ?? '').trim(),
      'openings': _openingsCtrl.text.trim(),
      'citizenships': _citizenships.toList(),
      'experience': (_experience ?? '').trim(),
      'ageFrom': _ageFromCtrl.text.trim(),
      'ageTo': _ageToCtrl.text.trim(),
      'drivingLicenses': _drivingLicenses.toList(),
      'hasCar': _hasCar,
      'languages': _languages.toList(),
      'otherLanguage': _otherLanguageCtrl.text.trim(),
      'additionalRequirements': _additionalRequirementsCtrl.text.trim(),
      'responsibilities': _responsibilitiesCtrl.text.trim(),
      'requirements': _requirementsCtrl.text.trim(),
      'description': _descriptionCtrl.text.trim(),
      'housingProvided': _housingProvided,
      'transportProvided': _transportProvided,
      'housingCostFrom': _housingCostFromCtrl.text.trim(),
      'housingCostTo': _housingCostToCtrl.text.trim(),
      'transportCostFrom': _transportCostFromCtrl.text.trim(),
      'transportCostTo': _transportCostToCtrl.text.trim(),
      'teenFriendly': _teenFriendly,
      'disabilityFriendly': _disabilityFriendly,
      'isUrgent': _isUrgent,
      'paidUrgent': _paidUrgent,
      'urgentRequested': _urgentRequested,
      'expiryPresetDays': _expiryPresetDays,
      'customDays': _customDaysCtrl.text.trim(),
      'showContacts': _showContacts,
      'companyName': _companyNameCtrl.text.trim(),
      'regNumber': _regNumberCtrl.text.trim(),
      'website': _websiteCtrl.text.trim(),
      'contactFirstName': _contactFirstCtrl.text.trim(),
      'contactLastName': _contactLastCtrl.text.trim(),
      'phoneCountryCode': _phoneCountryCode,
      'phoneNumber': ContactFieldsValidators.normalizeDigits(
        _phoneNumberCtrl.text,
      ),
      'email': _emailCtrl.text.trim(),
      'telegram': _telegramCtrl.text.trim(),
      'whatsapp': _whatsappCtrl.text.trim(),
      'viber': _viberCtrl.text.trim(),
    };
  }

  bool _hasAnyDraftData(Map<String, dynamic> d) {
    final keys = <String>[
      'title',
      'vacancyNumber',
      'category',
      'city',
      'country',
      'employmentType',
      'workSchedule',
      'workScheduleOption',
      'workScheduleCustom',
      'gender',
      'salaryFrom',
      'salaryTo',
      'responsibilities',
      'description',
      'companyName',
      'email',
      'requirements',
      'otherLanguage',
    ];
    for (final k in keys) {
      if ((d[k] ?? '').toString().trim().isNotEmpty) return true;
    }
    for (final k in ['citizenships', 'drivingLicenses', 'languages']) {
      if ((d[k] as List?)?.isNotEmpty == true) return true;
    }
    return (d['housingProvided'] == true) ||
        (d['transportProvided'] == true) ||
        (d['hasCar'] == true) ||
        (d['teenFriendly'] == true) ||
        (d['disabilityFriendly'] == true) ||
        (d['isUrgent'] == true) ||
        (d['urgentRequested'] == true);
  }

  Future<void> _saveDraftIfNeeded() async {
    if (_isEditMode || _saving) return;
    final d = _draftData();
    if (_hasAnyDraftData(d)) {
      await JobDraftStorage.save(d);
    } else {
      await JobDraftStorage.clear();
    }
  }

  Future<void> _restoreDraftIfAny() async {
    if (_isEditMode) return;
    final d = await JobDraftStorage.load();
    if (d == null || !_hasAnyDraftData(d)) return;
    if (!mounted) return;

    _vacancyNumberCtrl.text = (d['vacancyNumber'] ?? _vacancyNumberCtrl.text)
        .toString()
        .trim();
    _titleCtrl.text = (d['title'] ?? _titleCtrl.text).toString().trim();
    final cat = (d['category'] ?? '').toString().trim();
    _category = cat.isEmpty ? _category : cat;
    _cityCtrl.text = (d['city'] ?? _cityCtrl.text).toString().trim();
    final c = (d['country'] ?? '').toString().trim();
    if (c.isNotEmpty) _country = c;
    final et = (d['employmentType'] ?? '').toString().trim();
    _employmentType = et.isEmpty ? _employmentType : et;
    _salaryFromCtrl.text = (d['salaryFrom'] ?? _salaryFromCtrl.text)
        .toString()
        .trim();
    _salaryToCtrl.text = (d['salaryTo'] ?? _salaryToCtrl.text)
        .toString()
        .trim();
    final curr = (d['salaryCurrency'] ?? '').toString().trim();
    if (curr.isNotEmpty) _salaryCurrency = curr;
    final period = (d['salaryPeriodRu'] ?? '').toString().trim();
    if (period.isNotEmpty) _salaryPeriodRu = period;
    _restoreWorkSchedule(
      option: (d['workScheduleOption'] ?? '').toString(),
      custom: (d['workScheduleCustom'] ?? '').toString(),
      legacy: (d['workSchedule'] ?? '').toString(),
    );
    final gender = (d['gender'] ?? '').toString().trim();
    _gender = gender.isEmpty ? _gender : gender;
    _openingsCtrl.text = (d['openings'] ?? _openingsCtrl.text)
        .toString()
        .trim();

    final citizenships = d['citizenships'];
    if (citizenships is List) {
      _citizenships.addAll(citizenships.map((e) => e.toString()));
    }
    final exp = (d['experience'] ?? '').toString().trim();
    if (exp.isNotEmpty) _experience = exp;
    _ageFromCtrl.text = (d['ageFrom'] ?? '').toString().trim();
    _ageToCtrl.text = (d['ageTo'] ?? '').toString().trim();
    final drivingLicenses = d['drivingLicenses'];
    if (drivingLicenses is List) {
      _drivingLicenses.addAll(drivingLicenses.map((e) => e.toString()));
    }
    _hasCar = (d['hasCar'] ?? _hasCar) == true;
    final languages = d['languages'];
    if (languages is List) {
      _languages.addAll(languages.map((e) => e.toString()));
    }
    _otherLanguageCtrl.text = (d['otherLanguage'] ?? '').toString().trim();
    if (_otherLanguageCtrl.text.isNotEmpty) {
      _languages.add('Другое');
    }
    _additionalRequirementsCtrl.text = (d['additionalRequirements'] ?? '')
        .toString()
        .trim();

    _responsibilitiesCtrl.text = (d['responsibilities'] ?? '')
        .toString()
        .trim();
    _requirementsCtrl.text = (d['requirements'] ?? '').toString().trim();
    _descriptionCtrl.text = (d['description'] ?? _descriptionCtrl.text)
        .toString()
        .trim();
    _housingProvided = (d['housingProvided'] ?? _housingProvided) == true;
    _transportProvided = (d['transportProvided'] ?? _transportProvided) == true;
    _housingCostFromCtrl.text = (d['housingCostFrom'] ?? '').toString().trim();
    _housingCostToCtrl.text = (d['housingCostTo'] ?? '').toString().trim();
    _transportCostFromCtrl.text = (d['transportCostFrom'] ?? '')
        .toString()
        .trim();
    _transportCostToCtrl.text = (d['transportCostTo'] ?? '').toString().trim();
    _teenFriendly = (d['teenFriendly'] ?? _teenFriendly) == true;
    _disabilityFriendly =
        (d['disabilityFriendly'] ?? _disabilityFriendly) == true;
    _paidUrgent = (d['paidUrgent'] ?? _paidUrgent) == true;
    _urgentRequested = (d['urgentRequested'] ?? _urgentRequested) == true;
    _isUrgent = (d['isUrgent'] == true) && _paidUrgent;

    _expiryPresetDays = (d['expiryPresetDays'] is int)
        ? d['expiryPresetDays'] as int
        : _expiryPresetDays;
    _customDaysCtrl.text = (d['customDays'] ?? _customDaysCtrl.text)
        .toString()
        .trim();
    _showContacts = (d['showContacts'] ?? _showContacts) == true;
    _companyNameCtrl.text = (d['companyName'] ?? _companyNameCtrl.text)
        .toString()
        .trim();
    _regNumberCtrl.text = (d['regNumber'] ?? _regNumberCtrl.text)
        .toString()
        .trim();
    _websiteCtrl.text = (d['website'] ?? _websiteCtrl.text).toString().trim();
    _contactFirstCtrl.text = (d['contactFirstName'] ?? _contactFirstCtrl.text)
        .toString()
        .trim();
    _contactLastCtrl.text = (d['contactLastName'] ?? _contactLastCtrl.text)
        .toString()
        .trim();
    final pcc = (d['phoneCountryCode'] ?? '').toString().trim();
    if (pcc.isNotEmpty) _phoneCountryCode = pcc;
    final pn = (d['phoneNumber'] ?? '').toString().trim();
    if (pn.isNotEmpty) {
      _phoneNumberCtrl.text = ContactFieldsValidators.normalizeDigits(pn);
    }
    _emailCtrl.text = (d['email'] ?? _emailCtrl.text).toString().trim();
    _telegramCtrl.text = (d['telegram'] ?? _telegramCtrl.text)
        .toString()
        .trim();
    _whatsappCtrl.text = (d['whatsapp'] ?? _whatsappCtrl.text)
        .toString()
        .trim();
    _viberCtrl.text = (d['viber'] ?? _viberCtrl.text).toString().trim();

    final s = d['step'];
    if (s is int && s >= 0 && s < _stepsCount) {
      _step = s;
    }
    setState(() {});
  }

  Future<void> _loadForEditIfNeeded() async {
    if (!_isEditMode) return;
    final ref =
        widget.editJobRef ??
        FirebaseFirestore.instance
            .collection(FirestorePaths.vacancies)
            .doc(widget.editJobId!);
    try {
      final snap = await ref.get();
      if (!snap.exists) return;
      final m = snap.data() ?? <String, dynamic>{};
      final employer = (m['employer'] is Map<String, dynamic>)
          ? (m['employer'] as Map<String, dynamic>)
          : <String, dynamic>{};

      // Step 1: Basic
      _vacancyNumberCtrl.text = (m['vacancyNumber'] ?? '').toString().trim();
      _titleCtrl.text = (m['title'] ?? '').toString().trim();
      final cat = (m['category'] ?? '').toString().trim();
      _category = cat.isEmpty ? null : cat;
      _cityCtrl.text = (m['city'] ?? '').toString().trim();
      final c = (m['country'] ?? '').toString().trim();
      if (c.isNotEmpty) _country = c;

      // Step 2: Conditions
      _employmentType = (m['employmentType'] ?? '').toString().trim().isEmpty
          ? null
          : (m['employmentType'] ?? '').toString().trim();
      _salaryFromCtrl.text = (m['salaryAmount'] ?? '').toString().trim();
      _salaryToCtrl.text = (m['salaryAmountTo'] ?? '').toString().trim();
      final curr = (m['salaryCurrency'] ?? '').toString().trim();
      if (curr.isNotEmpty) _salaryCurrency = curr;
      final p = (m['salaryPeriod'] ?? '').toString().trim();
      if (p == 'hour') _salaryPeriodRu = 'В час';
      if (p == 'month') _salaryPeriodRu = 'В месяц';
      if (p == 'year') _salaryPeriodRu = 'В год';
      _restoreWorkSchedule(
        option: (m['workScheduleOption'] ?? '').toString(),
        custom: (m['workScheduleCustom'] ?? '').toString(),
        legacy: (m['workSchedule'] ?? '').toString(),
      );
      final gender = (m['gender'] ?? '').toString().trim();
      if (gender.isNotEmpty) _gender = gender;
      final openings = (m['openings'] ?? '').toString().trim();
      if (openings.isNotEmpty) _openingsCtrl.text = openings;

      // Step 3: Requirements
      final citizenships = m['citizenship'];
      if (citizenships is List) {
        _citizenships.addAll(citizenships.map((e) => e.toString()));
      }
      final exp = (m['experience'] ?? '').toString().trim();
      if (exp.isNotEmpty) _experience = exp;
      _ageFromCtrl.text = (m['ageFrom'] ?? '').toString().trim();
      _ageToCtrl.text = (m['ageTo'] ?? '').toString().trim();
      final dl = m['drivingLicenses'];
      if (dl is List) _drivingLicenses.addAll(dl.map((e) => e.toString()));
      _hasCar = (m['hasCar'] ?? false) == true;
      final langs = m['languages'];
      if (langs is List) _languages.addAll(langs.map((e) => e.toString()));
      _otherLanguageCtrl.text = (m['otherLanguage'] ?? '').toString().trim();
      if (_otherLanguageCtrl.text.isNotEmpty) {
        _languages.add('Другое');
      }
      _additionalRequirementsCtrl.text = (m['additionalRequirements'] ?? '')
          .toString()
          .trim();

      // Step 4: Description
      _responsibilitiesCtrl.text = (m['responsibilities'] ?? '')
          .toString()
          .trim();
      _requirementsCtrl.text = (m['requirements'] ?? '').toString().trim();
      _descriptionCtrl.text = (m['description'] ?? '').toString();
      _housingProvided = (m['housingProvided'] ?? false) == true;
      _transportProvided = (m['transportProvided'] ?? false) == true;
      _housingCostFromCtrl.text = (m['housingCostFrom'] ?? '')
          .toString()
          .trim();
      _housingCostToCtrl.text = (m['housingCostTo'] ?? '').toString().trim();
      _transportCostFromCtrl.text = (m['transportCostFrom'] ?? '')
          .toString()
          .trim();
      _transportCostToCtrl.text = (m['transportCostTo'] ?? '')
          .toString()
          .trim();
      _teenFriendly = (m['teenFriendly'] ?? false) == true;
      _disabilityFriendly = (m['disabilityFriendly'] ?? false) == true;
      _paidUrgent =
          (m['paidUrgent'] == true) ||
          (m['isUrgent'] == true) ||
          (m['urgentActiveUntil'] != null);
      _urgentRequested = (m['urgentRequested'] ?? false) == true;
      _isUrgent = (m['isUrgent'] == true) && _paidUrgent;

      // Step 5: Duration + Company
      _companyNameCtrl.text =
          (employer['companyName'] ?? m['companyName'] ?? '').toString().trim();
      _regNumberCtrl.text = (employer['regNumber'] ?? '').toString().trim();
      _websiteCtrl.text = (employer['website'] ?? '').toString().trim();
      _showContacts = (m['showContacts'] ?? true) == true;
      _contactFirstCtrl.text =
          (employer['contactFirstName'] ?? _contactFirstCtrl.text)
              .toString()
              .trim();
      _contactLastCtrl.text =
          (employer['contactLastName'] ?? _contactLastCtrl.text)
              .toString()
              .trim();
      final contactName = (employer['contactName'] ?? '').toString().trim();
      if (contactName.isNotEmpty && _contactFirstCtrl.text.isEmpty) {
        final parts = contactName
            .split(' ')
            .where((e) => e.trim().isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          _contactFirstCtrl.text = parts.first.trim();
          if (parts.length > 1) {
            _contactLastCtrl.text = parts.sublist(1).join(' ').trim();
          }
        }
      }
      _phoneCountryCode = (employer['phoneCountryCode'] ?? _phoneCountryCode)
          .toString()
          .trim();
      _phoneNumberCtrl.text = ContactFieldsValidators.normalizeDigits(
        (employer['phoneNumber'] ?? '').toString().trim(),
      );
      if (_phoneNumberCtrl.text.isEmpty) {
        final parsed = ContactFieldsValidators.parseStoredPhone(
          (employer['phone'] ?? '').toString().trim(),
        );
        _phoneCountryCode = parsed.countryCode;
        _phoneNumberCtrl.text = parsed.number;
      }
      _emailCtrl.text = (employer['email'] ?? _emailCtrl.text)
          .toString()
          .trim();
      _telegramCtrl.text = (employer['telegram'] ?? '').toString().trim();
      _whatsappCtrl.text = (employer['whatsapp'] ?? '').toString().trim();
      _viberCtrl.text = (employer['viber'] ?? '').toString().trim();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('CreateJobScreen load edit job error: $e');
    }
  }

  Future<void> _prefillContactsIfLoggedIn() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      if (widget.testMode) {
        _contactFirstCtrl.text = _contactFirstCtrl.text.trim().isEmpty
            ? 'Тестовый'
            : _contactFirstCtrl.text;
        _contactLastCtrl.text = _contactLastCtrl.text.trim().isEmpty
            ? 'профиль'
            : _contactLastCtrl.text;
        _emailCtrl.text = _emailCtrl.text.trim().isEmpty
            ? 'test@worka.local'
            : _emailCtrl.text;
        if (_phoneNumberCtrl.text.trim().isEmpty) {
          _phoneCountryCode = '+372';
          _phoneNumberCtrl.text = '000000000';
        }
      }
      return;
    }

    // из auth
    final parsedAuthPhone = ContactFieldsValidators.parseStoredPhone(
      (u.phoneNumber ?? '').trim(),
    );
    _phoneCountryCode = parsedAuthPhone.countryCode;
    _phoneNumberCtrl.text = parsedAuthPhone.number;
    _emailCtrl.text = (u.email ?? '').trim();
    final displayParts = (u.displayName ?? '')
        .trim()
        .split(' ')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (displayParts.isNotEmpty) {
      _contactFirstCtrl.text = displayParts.first;
      _contactLastCtrl.text = displayParts.length > 1
          ? displayParts.sublist(1).join(' ')
          : _contactLastCtrl.text;
    }

    // из users/{uid}
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      final m = snap.data() ?? {};
      final business = m['business'] is Map
          ? Map<String, dynamic>.from(m['business'] as Map)
          : <String, dynamic>{};

      String pick(List<String> keys) {
        for (final k in keys) {
          final vb = (business[k] ?? '').toString().trim();
          if (vb.isNotEmpty) return vb;
          final vm = (m[k] ?? '').toString().trim();
          if (vm.isNotEmpty) return vm;
        }
        return '';
      }

      final first = pick(const ['contactFirstName', 'firstName']);
      final last = pick(const ['contactLastName', 'lastName']);
      final phone = pick(const ['phone']);
      final phoneCountryCode = pick(const ['phoneCountryCode']);
      final phoneNumber = pick(const ['phoneNumber']);
      final email = pick(const ['email']);
      final companyName = pick(const ['companyName']);
      final companyRegNumber = pick(const ['companyRegNumber', 'regNumber']);
      final companyWebsite = pick(const ['companyWebsite', 'website']);
      final telegram = pick(const ['telegram']);
      final whatsapp = pick(const ['whatsapp']);
      final viber = pick(const ['viber']);

      _hasBusinessProfilePrefill = [
        first,
        last,
        phone,
        phoneCountryCode,
        phoneNumber,
        email,
        companyName,
        companyRegNumber,
        companyWebsite,
        telegram,
        whatsapp,
        viber,
      ].any((v) => v.isNotEmpty);

      if (first.isNotEmpty) _contactFirstCtrl.text = first;
      if (last.isNotEmpty) _contactLastCtrl.text = last;
      if (phoneCountryCode.isNotEmpty) _phoneCountryCode = phoneCountryCode;
      if (phoneNumber.isNotEmpty) {
        _phoneNumberCtrl.text = ContactFieldsValidators.normalizeDigits(
          phoneNumber,
        );
      }
      if (phone.isNotEmpty && _phoneNumberCtrl.text.isEmpty) {
        final parsed = ContactFieldsValidators.parseStoredPhone(phone);
        _phoneCountryCode = parsed.countryCode;
        _phoneNumberCtrl.text = parsed.number;
      }
      if (email.isNotEmpty) _emailCtrl.text = email;
      if (companyName.isNotEmpty) _companyNameCtrl.text = companyName;
      if (companyRegNumber.isNotEmpty) _regNumberCtrl.text = companyRegNumber;
      if (companyWebsite.isNotEmpty) _websiteCtrl.text = companyWebsite;
      if (telegram.isNotEmpty) _telegramCtrl.text = telegram;
      if (whatsapp.isNotEmpty) _whatsappCtrl.text = whatsapp;
      if (viber.isNotEmpty) _viberCtrl.text = viber;
    } catch (_) {}

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _vacancyNumberCtrl.dispose();
    _cityCtrl.dispose();
    _salaryFromCtrl.dispose();
    _salaryToCtrl.dispose();
    _customWorkScheduleCtrl.dispose();
    _openingsCtrl.dispose();
    _requirementsCtrl.dispose();
    _housingCostFromCtrl.dispose();
    _housingCostToCtrl.dispose();
    _transportCostFromCtrl.dispose();
    _transportCostToCtrl.dispose();
    _ageFromCtrl.dispose();
    _ageToCtrl.dispose();
    _otherLanguageCtrl.dispose();
    _additionalRequirementsCtrl.dispose();
    _responsibilitiesCtrl.dispose();
    _descriptionCtrl.dispose();
    _customDaysCtrl.dispose();
    _companyNameCtrl.dispose();
    _regNumberCtrl.dispose();
    _websiteCtrl.dispose();
    _contactFirstCtrl.dispose();
    _contactLastCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _emailCtrl.dispose();
    _telegramCtrl.dispose();
    _whatsappCtrl.dispose();
    _viberCtrl.dispose();
    super.dispose();
  }

  // ─── UI Helpers ────────────────────────────────────────────────────────

  TextStyle get _labelStyle => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: WorkaColors.textGreyDark,
  );

  TextStyle get _hintStyle => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: WorkaColors.textGrey,
  );

  InputDecoration _decor(
    String label, {
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: _labelStyle,
      hintText: hintText,
      hintStyle: _hintStyle,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
      suffixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
      filled: true,
      fillColor: _JobFlowUi.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_JobFlowUi.radiusCard),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_JobFlowUi.radiusCard),
        borderSide: const BorderSide(color: _JobFlowUi.primary, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_JobFlowUi.radiusCard),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _JobFlowUi.surface,
        border: Border.all(color: _JobFlowUi.border),
        borderRadius: BorderRadius.circular(_JobFlowUi.radiusCard),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sp() => const SizedBox(height: _JobFlowUi.blockGap);

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: WorkaColors.textDark,
        ),
      ),
    );
  }

  Widget _autofillBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: WorkaColors.hoverBlueSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WorkaColors.blue.withValues(alpha: 0.3)),
      ),
      child: const Text(
        'Из профиля',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: WorkaColors.blue,
        ),
      ),
    );
  }

  Widget _tf(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    required Widget iconWidget,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: WorkaColors.textDark,
      ),
      decoration: _decor(label, hintText: hint, prefixIcon: iconWidget),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _toggleRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    Color? iconColor,
    Widget? leadingOverride,
  }) {
    return _FieldTile(
      onTap: () => onChanged(!value),
      leading:
          leadingOverride ?? Icon(icon, color: iconColor ?? _JobFlowUi.primary),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: value ? FontWeight.w600 : FontWeight.w500,
          color: value ? WorkaColors.textDark : _JobFlowUi.muted,
        ),
      ),
      trailing: _WorkaSwitch(value: value, onChanged: onChanged),
    );
  }

  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(_JobFlowUi.radiusPill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? WorkaColors.hoverBlueSoft : _JobFlowUi.surface,
          borderRadius: BorderRadius.circular(_JobFlowUi.radiusPill),
          border: Border.all(
            color: selected ? _JobFlowUi.primary : _JobFlowUi.border,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: WorkaColors.textDark,
          ),
        ),
      ),
    );
  }

  Widget _chipsRow({
    required List<String> values,
    required String? selected,
    required ValueChanged<String> onTap,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map((v) => _chip(v, selected: v == selected, onTap: () => onTap(v)))
          .toList(),
    );
  }

  Widget _expiryOption({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return _FieldTile(
      onTap: onTap,
      backgroundColor: selected
          ? WorkaColors.hoverBlueSoft
          : _JobFlowUi.surface,
      borderColor: selected ? _JobFlowUi.primary : _JobFlowUi.border,
      leading: const Icon(Icons.timer, color: WorkaColors.blue),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? WorkaColors.textDark : WorkaColors.textGreyDark,
        ),
      ),
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: selected
            ? const Icon(
                Icons.check_circle_rounded,
                key: ValueKey('selected'),
                color: WorkaColors.blue,
                size: 20,
              )
            : const Icon(
                Icons.radio_button_unchecked_rounded,
                key: ValueKey('idle'),
                color: WorkaColors.fieldBorder,
                size: 20,
              ),
      ),
    );
  }

  // ─── Pickers ───────────────────────────────────────────────────────────

  Future<void> _pickCountry() async {
    final cityToCountry = <String, String>{};
    for (final e in _kCitiesByCountry.entries) {
      for (final city in e.value) {
        cityToCountry[city] = e.key;
      }
    }

    final selected = await LocationPickerSheet.open(
      context,
      allCountries: SearchFiltersConfig.countriesRu,
      initialCountries: _country.trim().isEmpty
          ? const <String>{}
          : {_country.trim()},
      singleSelect: true,
      cityToCountry: cityToCountry,
    );

    if (selected != null && selected.countries.isNotEmpty) {
      final newCountry = selected.countries.first.trim();
      if (newCountry != _country) {
        setState(() {
          _country = newCountry;
          _cityCtrl.clear();
        });
      }
    }
  }

  Future<void> _pickCategoryFromGroups() async {
    final mainCategories = SearchFiltersConfig.categoryGroups.keys.toList();
    final uid = AuthGuard.effectiveUidOrNull();
    final ent = uid == null
        ? const EmployerEntitlements(
            employerType: EmployerType.private,
            plan: EmployerPlan.privateFree,
            activeJobLimit: MonetizationPricing.privateFreeActiveJobs,
            includedCreditsMonthly: 0,
            bumpsMonthly: 0,
            urgentMonthly: 0,
          )
        : await MonetizationRepository(
            FirebaseFirestore.instance,
          ).getEmployerEntitlements(uid);
    final isPrivate = ent.employerType == EmployerType.private;
    if (!mounted) return;

    if (isPrivate) {
      final selectedSet = await showModalBottomSheet<Set<String>>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _CategoryPickerSheet(
          items: mainCategories,
          selected: _category == null ? const <String>{} : {_category!},
          itemIconBuilder: (label) => _categoryIcons[label] ?? Icons.category,
          singleSelect: true,
          lockedItems: const <String>{},
          onLockedTap: null,
        ),
      );

      if (selectedSet == null) return;
      setState(() {
        if (selectedSet.isEmpty) {
          _category = null;
        } else {
          _category = selectedSet.first.trim();
        }
      });
      return;
    }

    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CategoryPickerSheet(
        items: mainCategories,
        selected: _category == null ? const <String>{} : {_category!},
        itemIconBuilder: (label) => _categoryIcons[label] ?? Icons.category,
      ),
    );

    if (selected == null) return;
    setState(() {
      if (selected.isEmpty) {
        _category = null;
      } else if (_category != null && selected.contains(_category)) {
        _category = _category;
      } else {
        _category = selected.first;
      }
    });
  }

  // ─── Validation ────────────────────────────────────────────────────────

  bool _isNonEmpty(TextEditingController c) => c.text.trim().isNotEmpty;

  bool _containsCopyToken(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('копия') || normalized.contains('copy');
  }

  bool _isStepValid(int stepIndex) {
    switch (stepIndex) {
      case 0: // Basic
        if (!_isNonEmpty(_titleCtrl)) return false;
        if ((_category ?? '').trim().isEmpty) return false;
        if (!_isNonEmpty(_cityCtrl)) return false;
        if (_country.trim().isEmpty) return false;
        return true;

      case 1: // Conditions
        if ((_employmentType ?? '').trim().isEmpty) return false;
        if (_isCustomWorkSchedule &&
            _customWorkScheduleCtrl.text.trim().isEmpty) {
          return false;
        }
        final from = double.tryParse(
          _salaryFromCtrl.text.trim().replaceAll(',', '.'),
        );
        if (from == null || from <= 0) return false;
        final toText = _salaryToCtrl.text.trim();
        if (toText.isNotEmpty) {
          final to = double.tryParse(toText.replaceAll(',', '.'));
          if (to == null || to <= 0) return false;
          if (to < from) return false;
        }
        final openings = int.tryParse(_openingsCtrl.text.trim());
        if (openings == null || openings <= 0) return false;
        return true;

      case 2: // Requirements – optional
        return true;

      case 3: // Description
        return _isNonEmpty(_descriptionCtrl);

      case 4: // Duration + Company
        if (!_isNonEmpty(_companyNameCtrl)) return false;
        if (_showContacts) {
          if (!ContactFieldsValidators.isNameValid(_contactFirstCtrl.text)) {
            return false;
          }
          if (!ContactFieldsValidators.isNameValid(_contactLastCtrl.text)) {
            return false;
          }
          if (!ContactFieldsValidators.isEmailValid(_emailCtrl.text)) {
            return false;
          }
          if (!ContactFieldsValidators.isPhoneValid(_phoneNumberCtrl.text)) {
            return false;
          }
        }
        if (_expiryPresetDays == -1) {
          final d = int.tryParse(_customDaysCtrl.text.trim());
          if (d == null || d <= 0 || d > 30) return false;
        } else {
          if (_expiryPresetDays <= 0 || _expiryPresetDays > 30) return false;
        }
        return true;

      default:
        return false;
    }
  }

  Future<void> _pickCitizenship() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CitizenshipSheet(
        items: _kCitizenshipOptions,
        selected: _citizenships,
      ),
    );
    if (selected == null) return;
    setState(() {
      _citizenships
        ..clear()
        ..addAll(selected);
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: WorkaColors.textDark),
    );
  }

  // ─── Salary helpers ────────────────────────────────────────────────────

  String _salaryPeriodInternal(String ru) {
    switch (ru) {
      case 'В час':
        return 'hour';
      case 'В день':
        return 'day';
      case 'В месяц':
      default:
        return 'month';
    }
  }

  double _toMonthlyUnits(double amount, String periodInternal) {
    switch (periodInternal) {
      case 'hour':
        return amount * 160.0;
      case 'day':
        return amount * 30.0;
      default:
        return amount;
    }
  }

  String _salaryUi({
    required double from,
    double? to,
    required String currency,
    required String periodInternal,
  }) {
    final symbol = currency == 'EUR' ? '€' : currency;
    final per = periodInternal == 'hour'
        ? 'час'
        : periodInternal == 'day'
        ? 'день'
        : 'месяц';
    final fromStr = from % 1 == 0
        ? from.toStringAsFixed(0)
        : from.toStringAsFixed(2);
    if (to != null) {
      final toStr = to % 1 == 0 ? to.toStringAsFixed(0) : to.toStringAsFixed(2);
      return '$symbol$fromStr–$toStr / $per';
    }
    return '$symbol$fromStr / $per';
  }

  // ─── Navigation ────────────────────────────────────────────────────────

  // ─── AI autofill ──────────────────────────────────────────────────────────
  Future<void> _openVacancyAutofill() async {
    final result = await AiAutofillSheet.show(
      context,
      mode: AiAutofillMode.vacancy,
    );
    if (result == null || !mounted) return;
    _applyVacancyAutofill(result);
  }

  void _applyVacancyAutofill(Map<String, dynamic> d) {
    // ── safe extractors ──────────────────────────────────────────────────────
    String s(String key) => (d[key] ?? '').toString().trim();
    bool? nb(String key) {
      final v = d[key];
      if (v is bool) return v;
      return null;
    }

    List<String> lst(String key) {
      final v = d[key];
      if (v is List) {
        return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    // ── enum → Russian UI value maps ─────────────────────────────────────────
    // salary_period: backend returns 'month'|'hour'|'day'|'year'
    // SearchFiltersConfig.salaryPeriods has only ['В час', 'В день', 'В месяц'].
    // 'year' is NOT a valid dropdown choice — omit it to keep current default.
    const periodMap = {
      'month': 'В месяц',
      'hour': 'В час',
      'day': 'В день',
      // 'year' intentionally omitted — not in SearchFiltersConfig.salaryPeriods
    };
    // experience_required: backend returns 'no_experience'|'lt1'|'1_3'|'3_5'|'5_plus'
    const experienceMap = {
      'no_experience': 'Без опыта',
      'lt1': 'До 1 года',
      '1_3': '1–3 года',
      '3_5': '3–5 лет',
      '5_plus': '5+ лет',
    };
    // gender: backend returns 'male'|'female'|'not_specified'
    const genderMap = {
      'male': 'Мужской',
      'female': 'Женский',
      'not_specified': null,
    };

    // ── country normalisation ────────────────────────────────────────────────
    // AI may return English country names when the source text is in English.
    // WorkaCountries.enToRu maps English → Russian for all supported countries.
    String normalizeCountry(String raw) {
      if (raw.isEmpty) return raw;
      // If it's already Russian (exists as a key in ruToEn), return as-is.
      if (WorkaCountries.ruToEn.containsKey(raw)) return raw;
      // Otherwise try EN→RU lookup.
      return WorkaCountries.enToRu[raw] ?? raw;
    }

    setState(() {
      if (s('title').isNotEmpty) _titleCtrl.text = s('title');
      if (s('vacancy_number').isNotEmpty) {
        _vacancyNumberCtrl.text = s('vacancy_number');
      }
      if (s('category').isNotEmpty) _category = s('category');
      if (s('country').isNotEmpty) _country = normalizeCountry(s('country'));
      if (s('city').isNotEmpty) _cityCtrl.text = s('city');

      // Salary — backend returns numbers; convert to string for text controllers
      final salaryFrom = d['salary_from'];
      final salaryTo = d['salary_to'];
      if (salaryFrom != null) _salaryFromCtrl.text = salaryFrom.toString();
      if (salaryTo != null) _salaryToCtrl.text = salaryTo.toString();
      if (s('currency').isNotEmpty) _salaryCurrency = s('currency');
      final periodRu = periodMap[s('salary_period')];
      if (periodRu != null) _salaryPeriodRu = periodRu;

      if (s('work_schedule').isNotEmpty) _workSchedule = s('work_schedule');

      // Gender — map English code to Russian display value
      final genderKey = s('gender');
      if (genderKey.isNotEmpty && genderMap.containsKey(genderKey)) {
        _gender = genderMap[genderKey]; // null means "Не указан"
      }

      final countStr = s('vacancies_count');
      if (countStr.isNotEmpty) _openingsCtrl.text = countStr;

      final citizenships = lst('citizenship');
      if (citizenships.isNotEmpty) {
        _citizenships
          ..clear()
          ..addAll(citizenships);
      } else if (s('citizenship').isNotEmpty) {
        _citizenships
          ..clear()
          ..add(s('citizenship'));
      }

      // Experience — map English code to Russian display value
      final expRu = experienceMap[s('experience_required')];
      if (expRu != null) _experience = expRu;

      final ageFrom = d['age_from'];
      final ageTo = d['age_to'];
      if (ageFrom != null) _ageFromCtrl.text = ageFrom.toString();
      if (ageTo != null) _ageToCtrl.text = ageTo.toString();

      final licenses = lst('driving_licenses');
      if (licenses.isNotEmpty) {
        _drivingLicenses
          ..clear()
          ..addAll(licenses);
      }
      final carRequired = nb('car_required');
      if (carRequired != null) _hasCar = carRequired;

      final langs = lst('languages');
      if (langs.isNotEmpty) {
        _languages
          ..clear()
          ..addAll(langs);
      }

      final responsibilities = lst('responsibilities');
      if (responsibilities.isNotEmpty) {
        _responsibilitiesCtrl.text = responsibilities.join('\n');
      }

      final requirements = lst('requirements');
      if (requirements.isNotEmpty) {
        _requirementsCtrl.text = requirements.join('\n');
      }

      if (s('description').isNotEmpty) _descriptionCtrl.text = s('description');

      if (nb('housing_provided') != null) {
        _housingProvided = nb('housing_provided')!;
      }
      if (nb('transport_provided') != null) {
        _transportProvided = nb('transport_provided')!;
      }
      if (nb('for_teens') != null) _teenFriendly = nb('for_teens')!;
      if (nb('for_disabled') != null) _disabilityFriendly = nb('for_disabled')!;
      if (nb('urgent_vacancy') == true) _isUrgent = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Данные применены. Проверьте и отредактируйте при необходимости.',
        ),
      ),
    );
  }

  void _back() {
    if (_isEditMode) {
      Navigator.of(context).maybePop(false);
      return;
    }
    if (_step == 0) {
      _saveDraftIfNeeded().then((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      });
      return;
    }
    setState(() => _step -= 1);
  }

  void _next() {
    if (!_isStepValid(_step)) {
      _snack('Заполни обязательные поля текущего шага.');
      return;
    }
    if (_step == _stepsCount - 1) {
      _submit();
      return;
    }
    _saveDraftIfNeeded();
    setState(() => _step += 1);
  }

  Future<bool> _ensureAuthIfNeededForPublish() async {
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (authUid != null && authUid.isNotEmpty) return true;

    final goAuth = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Нужна регистрация'),
        content: const Text(
          'Чтобы опубликовать вакансию, нужно войти по телефону (SMS).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Позже'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Войти'),
          ),
        ],
      ),
    );

    if (goAuth != true) return false;

    if (!mounted) return false;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AuthEntryScreen()),
    );

    final updatedAuthUid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (updatedAuthUid != null && updatedAuthUid.isNotEmpty) {
      await _prefillContactsIfLoggedIn();
      return true;
    }

    if (!mounted) return false;
    _snack('Вход не выполнен');
    return false;
  }

  Future<void> _submit() async {
    debugPrint('🔥 [CREATE_JOB_RUNTIME] SUBMIT TRIGGERED');
    debugPrint('[CREATE_JOB_TRACE] REAL submit triggered (employer/create_job_screen)');
    for (int i = 0; i < _stepsCount; i++) {
      if (!_isStepValid(i)) {
        setState(() => _step = i);
        _snack('Есть незаполненные поля.');
        return;
      }
    }

    if (_containsCopyToken(_titleCtrl.text)) {
      _step = 0;
      if (mounted) setState(() {});
      _snack('Исправьте название');
      return;
    }

    final okAuth = await _ensureAuthIfNeededForPublish();
    if (!okAuth) return;

    final uid = AuthGuard.effectiveUidOrNull();
    if (uid == null || uid.trim().isEmpty) {
      _snack('Нужен вход');
      return;
    }
    final ownerKey = uid;

    final monetizationRepo = MonetizationRepository(FirebaseFirestore.instance);
    final ent = await monetizationRepo.getEmployerEntitlements(uid);
    if (ent.employerType == EmployerType.private) {
      if (!_isEditMode) {
        final activeJobs = await monetizationRepo.countActiveVacancies(uid);
        if (activeJobs >= ent.activeJobLimit) {
          if (!mounted) return;
          _snack(MonetizationI18n.t(context, 'job_limit_subtitle'));
          if (mounted) {
            await Navigator.of(
              context,
              rootNavigator: true,
            ).pushNamed(MonetizationRoutes.employerPlans);
          }
          return;
        }
      }
    }

    setState(() => _saving = true);

    try {
      final openings = int.parse(_openingsCtrl.text.trim());
      final int expiryDays = _expiryPresetDays == -1
          ? int.parse(_customDaysCtrl.text.trim())
          : _expiryPresetDays;
      final expiresAtIso = DateTime.now()
          .add(Duration(days: expiryDays))
          .toUtc()
          .toIso8601String();

      final from = double.parse(
        _salaryFromCtrl.text.trim().replaceAll(',', '.'),
      );
      final toText = _salaryToCtrl.text.trim();
      final double? to = toText.isEmpty
          ? null
          : double.parse(toText.replaceAll(',', '.'));

      final periodInternal = _salaryPeriodInternal(_salaryPeriodRu);
      final fromMonthly = _toMonthlyUnits(from, periodInternal);
      final rateToEur = await ExchangeRateService.rateToEur(_salaryCurrency);
      final double? eurPerMonth = rateToEur == null
          ? null
          : (fromMonthly * rateToEur);
      final contactFullName =
          '${_contactFirstCtrl.text.trim()} ${_contactLastCtrl.text.trim()}'
              .trim();
      final contactPhoneNumber = ContactFieldsValidators.normalizeDigits(
        _phoneNumberCtrl.text,
      );
      final contactPhone = '$_phoneCountryCode$contactPhoneNumber';

      final ownerType =
          app_mode.AppMode.currentMode == app_mode.AccountMode.business
          ? 'business'
          : 'personal';

      final data = <String, dynamic>{
        'ownerId': uid,
        'ownerKey': ownerKey,
        'ownerUid': uid,
        'ownerType': ownerType,
        if (_ownership.activeProfileId != null)
          'created_by_profile_id': _ownership.activeProfileId,
        if (_ownership.activeCompanyId != null)
          'company_id': _ownership.activeCompanyId,
        'isDeleted': false,
        'isDraft': false,
        'test': widget.testMode,
        'vacancyNumber': _vacancyNumberCtrl.text.trim(),
        'title': _titleCtrl.text.trim(),
        'category': _category,
        'city': _cityCtrl.text.trim(),
        'country': _country.trim(),
        'employmentType': _employmentType,
        'workSchedule': _resolvedWorkSchedule(),
        'workScheduleOption': (_workSchedule ?? '').trim(),
        'workScheduleCustom': _customWorkScheduleCtrl.text.trim(),
        'gender': (_gender ?? '').trim(),
        'citizenship': _citizenships.toList(),
        'experience': _experience,
        'ageFrom': _ageFromCtrl.text.trim(),
        'ageTo': _ageToCtrl.text.trim(),
        'drivingLicenses': _drivingLicenses.toList(),
        'hasCar': _hasCar,
        'languages': _languages.toList(),
        'otherLanguage': _otherLanguageCtrl.text.trim(),
        'additionalRequirements': _additionalRequirementsCtrl.text.trim(),
        'responsibilities': _responsibilitiesCtrl.text.trim(),
        'requirements': _requirementsCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'isUrgent': _isUrgent && _paidUrgent,
        'paidUrgent': _paidUrgent,
        'urgentRequested': _urgentRequested,
        'paidServices': (_paidUrgent || _urgentRequested)
            ? const ['urgent']
            : const <String>[],
        'salaryAmount': from,
        'salaryCurrency': _salaryCurrency,
        'salaryPeriod': periodInternal,
        'salaryText': _salaryUi(
          from: from,
          to: to,
          currency: _salaryCurrency,
          periodInternal: periodInternal,
        ),
        'salary': _salaryUi(
          from: from,
          to: to,
          currency: _salaryCurrency,
          periodInternal: periodInternal,
        ),
        'salaryEurPerMonth': eurPerMonth,
        if (to != null) 'salaryAmountTo': to,
        'housingProvided': _housingProvided,
        'transportProvided': _transportProvided,
        'housingCostFrom': _housingCostFromCtrl.text.trim(),
        'housingCostTo': _housingCostToCtrl.text.trim(),
        'transportCostFrom': _transportCostFromCtrl.text.trim(),
        'transportCostTo': _transportCostToCtrl.text.trim(),
        'housingCostText': _costText(
          _housingCostFromCtrl.text,
          _housingCostToCtrl.text,
        ),
        'transportCostText': _costText(
          _transportCostFromCtrl.text,
          _transportCostToCtrl.text,
        ),
        'teenFriendly': _teenFriendly,
        'disabilityFriendly': _disabilityFriendly,
        'expiresAt': expiresAtIso,
        'openings': openings,
        'showContacts': _showContacts,
        'employer': <String, dynamic>{
          'type': widget.employerType,
          'companyName': _companyNameCtrl.text.trim(),
          'regNumber': _regNumberCtrl.text.trim(),
          'website': _websiteCtrl.text.trim(),
          if (_showContacts) 'contactName': contactFullName,
          if (_showContacts) 'contactFirstName': _contactFirstCtrl.text.trim(),
          if (_showContacts) 'contactLastName': _contactLastCtrl.text.trim(),
          if (_showContacts) 'phoneCountryCode': _phoneCountryCode,
          if (_showContacts) 'phoneNumber': contactPhoneNumber,
          if (_showContacts) 'phone': contactPhone,
          if (_showContacts) 'email': _emailCtrl.text.trim(),
          if (_showContacts) 'telegram': _telegramCtrl.text.trim(),
          if (_showContacts) 'whatsapp': _whatsappCtrl.text.trim(),
          if (_showContacts) 'viber': _viberCtrl.text.trim(),
        },
        'meta': {'testMode': widget.testMode},
      };

      if (_isEditMode && widget.editJobId != null) {
        await _patchJob(widget.editJobId!, data);
        _newJobCode = widget.editJobId!;
        debugPrint('CreateJobScreen update vacancy jobCode=${widget.editJobId}');
      } else {
        final job = await _createJob(data);
        _newJobCode = job['jobCode']?.toString().trim();
        debugPrint('CreateJobScreen save vacancy jobCode=${_newJobCode ?? 'null'}');
      }

      if (!mounted) return;
      await JobDraftStorage.clear();

      if (_newJobCode != null) {
        if (_urgentRequested && mounted) {
          await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => PromoteJobScreen(jobCode: _newJobCode!),
            ),
          );
        }
        await _maybeShowPostPublishUpsell(_newJobCode!);
      }

      if (!mounted) return;
      if (_isEditMode) {
        Navigator.of(context).pop(true);
      } else {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop(true);
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MyPublicationsScreen(testMode: widget.testMode),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('CreateJobScreen _submit error: $e');
      if (!mounted) return;
      _snack('Ошибка сохранения: $e');
      if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
        _snack(FirebaseDebugDiagnostics.permissionHintText());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> input) {
    final Map<String, dynamic> out = {};
    input.forEach((key, value) {
      if (value is DateTime) {
        out[key] = value.toUtc().toIso8601String();
      } else if (value is Map) {
        out[key] = _sanitizePayload(Map<String, dynamic>.from(value));
      } else if (value is Iterable) {
        out[key] = value
            .map((e) => e is Map
                ? _sanitizePayload(Map<String, dynamic>.from(e as Map))
                : (e is DateTime ? e.toUtc().toIso8601String() : e))
            .toList();
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  Future<Map<String, dynamic>> _createJob(Map<String, dynamic> payload) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Требуется авторизация для создания вакансии.');
    }
    final uri = _buildJobsCreateUri();
    final safePayload = _sanitizePayload(payload);
    debugPrint('🔥 [CREATE_JOB_RUNTIME] BASE_URL=${uri.origin}');
    debugPrint('🔥 [CREATE_JOB_RUNTIME] URI=$uri');
    debugPrint('🔥 [CREATE_JOB_RUNTIME] METHOD=POST');
    debugPrint('🔥 [CREATE_JOB_RUNTIME] REQUEST BODY=${jsonEncode(safePayload)}');

    http.Response resp;
    try {
      resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(safePayload),
      );
    } catch (e, st) {
      debugPrint('🔥 [CREATE_JOB_RUNTIME] ERROR=$e');
      debugPrint('🔥 [CREATE_JOB_RUNTIME] STACK=$st');
      rethrow;
    }

    debugPrint('🔥 [CREATE_JOB_RUNTIME] STATUS=${resp.statusCode}');
    debugPrint('🔥 [CREATE_JOB_RUNTIME] RESPONSE BODY=${resp.body}');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw StateError(
        'Не удалось создать вакансию: '
        '${body.isNotEmpty ? body : 'status=${resp.statusCode}'}',
      );
    }
    final json = jsonDecode(resp.body);
    if (json is Map && json['job'] is Map) {
      return Map<String, dynamic>.from(json['job'] as Map);
    }
    return const {};
  }

  Future<void> _patchJob(String jobCode, Map<String, dynamic> payload) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Требуется авторизация для обновления вакансии.');
    }
    final base = const String.fromEnvironment('WORKA_API_BASE_URL', defaultValue: '')
        .replaceAll(RegExp(r'/+$'), '');
    assert(base.isNotEmpty, 'WORKA_API_BASE_URL is required');
    final normalizedBase = base.endsWith('/api') ? base : '$base/api';
    final uri = Uri.parse('$normalizedBase/jobs/$jobCode');
    final resp = await http.patch(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(_sanitizePayload(payload)),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw StateError(
        'Не удалось сохранить вакансию: '
        '${body.isNotEmpty ? body : 'status=${resp.statusCode}'}',
      );
    }
  }

  Future<void> _maybeShowPostPublishUpsell(String jobId) async {
    if (!mounted) return;
    final wantPromote = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Вакансия опубликована 🎉',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: WorkaColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Хотите получить больше откликов быстрее?',
                style: TextStyle(
                  fontSize: 15,
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WorkaColors.orange,
                    elevation: 5,
                    shadowColor: Colors.black.withValues(alpha: 0.18),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                  ),
                  child: const Text(
                    '🔥 Продвижение вакансии',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Не сейчас',
                    style: TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (wantPromote == true && mounted) {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => PromoteJobScreen(jobCode: jobId),
        ),
      );
    }
  }

  // ─── Steps UI ──────────────────────────────────────────────────────────

  String _costText(String fromRaw, String toRaw) {
    final from = double.tryParse(fromRaw.trim().replaceAll(',', '.')) ?? 0;
    final to = double.tryParse(toRaw.trim().replaceAll(',', '.')) ?? 0;
    if (from <= 0 && to <= 0) return 'бесплатно';
    if (from > 0 && to > 0) return '$from–$to €';
    if (from > 0) return 'от $from €';
    return 'до $to €';
  }

  Widget _step1() {
    final cityOptions = (_kCitiesByCountry[_country] ?? const <String>[])
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final cityQuery = _cityCtrl.text.trim().toLowerCase();
    final citySuggestions = cityQuery.isEmpty
        ? cityOptions.take(6).toList()
        : cityOptions
              .where((c) => c.toLowerCase().contains(cityQuery))
              .take(6)
              .toList();
    final showCitySuggestions =
        cityQuery.isNotEmpty && citySuggestions.isNotEmpty;

    return Column(
      children: [
        // ─── AI autofill banner ─────────────────────────────────────────
        OutlinedButton.icon(
          onPressed: _openVacancyAutofill,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Заполнить из текста вакансии'),
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
        _tf(
          _vacancyNumberCtrl,
          'Номер вакансии',
          hint: 'Например, JV-1024',
          iconWidget: const Icon(
            Icons.confirmation_number_outlined,
            color: WorkaColors.blue,
          ),
        ),
        _sp(),
        _tf(
          _titleCtrl,
          'Название должности *',
          hint: 'Сварщик',
          iconWidget: const Icon(
            Icons.work_outline_rounded,
            color: WorkaColors.blue,
          ),
        ),
        _sp(),
        _FieldTile(
          onTap: _pickCategoryFromGroups,
          leading: const Icon(Icons.category_outlined, color: WorkaColors.blue),
          title: Text(
            _category == null ? 'Категория *' : _category!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: _category == null ? FontWeight.w500 : FontWeight.w700,
              color: _category == null
                  ? WorkaColors.textGreyDark
                  : WorkaColors.textDark,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: WorkaColors.textGreyDark,
          ),
        ),
        _sp(),
        _FieldTile(
          onTap: _pickCountry,
          leading: const Icon(
            Icons.location_on_outlined,
            color: WorkaColors.blue,
          ),
          title: Row(
            children: [
              if (_kCountryFlags[_country] != null) ...[
                Text(
                  _kCountryFlags[_country]!,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _country.trim().isEmpty ? 'Страна *' : _country,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: _country.trim().isEmpty
                        ? FontWeight.w500
                        : FontWeight.w700,
                    color: _country.trim().isEmpty
                        ? WorkaColors.textGreyDark
                        : WorkaColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: WorkaColors.textGreyDark,
          ),
        ),
        _sp(),
        TextField(
          controller: _cityCtrl,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: WorkaColors.textDark,
          ),
          onChanged: (_) => setState(() {}),
          decoration: _decor(
            'Город *',
            hintText: 'Начни вводить город',
            prefixIcon: const Icon(
              Icons.location_on_outlined,
              color: WorkaColors.blue,
            ),
            suffixIcon: const Icon(
              Icons.chevron_right_rounded,
              color: WorkaColors.textGreyDark,
            ),
          ),
        ),
        if (showCitySuggestions) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _JobFlowUi.surface,
              borderRadius: BorderRadius.circular(_JobFlowUi.radiusCard),
              border: Border.all(color: WorkaColors.fieldBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: citySuggestions.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: WorkaColors.divider),
              itemBuilder: (context, i) {
                final city = citySuggestions[i];
                return InkWell(
                  onTap: () {
                    _cityCtrl.text = city;
                    setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_city,
                          size: 18,
                          color: WorkaColors.textGreyDark,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            city,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: WorkaColors.textDark,
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
        ],
      ],
    );
  }

  Widget _step2() {
    final currencyOptions = SearchFiltersConfig.currencies.toSet().toList();
    final periodOptions = SearchFiltersConfig.salaryPeriods.toSet().toList();
    final scheduleOptions = _kWorkScheduleOptions;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Зарплата *'),
          _tf(
            _salaryFromCtrl,
            'Зарплата от *',
            hint: '1500',
            keyboardType: TextInputType.number,
            iconWidget: const Icon(Icons.payments, color: WorkaColors.blue),
          ),
          _sp(),
          _tf(
            _salaryToCtrl,
            'Зарплата до',
            hint: '2000',
            keyboardType: TextInputType.number,
            iconWidget: const Icon(
              Icons.payments_outlined,
              color: WorkaColors.blue,
            ),
          ),
          _sp(),
          Row(
            children: [
              Expanded(
                child: _dropdownFieldTile(
                  label: 'Валюта',
                  hint: 'Валюта',
                  value: currencyOptions.contains(_salaryCurrency)
                      ? _salaryCurrency
                      : null,
                  items: currencyOptions,
                  prefixIcon: const Icon(
                    Icons.currency_exchange,
                    color: WorkaColors.blue,
                  ),
                  onChanged: (v) =>
                      setState(() => _salaryCurrency = v ?? 'EUR'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdownFieldTile(
                  label: 'Период',
                  hint: 'Период',
                  value: periodOptions.contains(_salaryPeriodRu)
                      ? _salaryPeriodRu
                      : null,
                  items: periodOptions,
                  prefixIcon: const Icon(Icons.repeat, color: WorkaColors.blue),
                  onChanged: (v) =>
                      setState(() => _salaryPeriodRu = v ?? 'В месяц'),
                ),
              ),
            ],
          ),
          _sp(),
          _dropdownFieldTile(
            label: 'График работы',
            hint: 'Выбрать',
            isExpanded: true,
            value: _workSchedule,
            items: scheduleOptions,
            prefixIcon: const Icon(Icons.schedule, color: WorkaColors.blue),
            onChanged: (v) => setState(() {
              _workSchedule = v;
              if (!_isCustomWorkSchedule) {
                _customWorkScheduleCtrl.clear();
              }
            }),
          ),
          if (_isCustomWorkSchedule) ...[
            _sp(),
            _tf(
              _customWorkScheduleCtrl,
              'Свой график',
              hint: 'Введите свой график',
              iconWidget: const Icon(
                Icons.edit_calendar,
                color: WorkaColors.blue,
              ),
            ),
          ],
          _sp(),
          _sectionHeader('Уточненные теги'),
          _chipsRow(
            values: SearchFiltersConfig.employmentTypes,
            selected: _employmentType,
            onTap: (v) => setState(() => _employmentType = v),
          ),
          _sp(),
          _sectionHeader('Пол (необязательно)'),
          _chipsRow(
            values: const ['Не указан', 'Мужской', 'Женский'],
            selected: _gender ?? 'Не указан',
            onTap: (v) => setState(() => _gender = v == 'Не указан' ? null : v),
          ),
          _sp(),
          _tf(
            _openingsCtrl,
            'Количество человек *',
            hint: '1',
            keyboardType: TextInputType.number,
            iconWidget: const Icon(Icons.groups, color: WorkaColors.blue),
          ),
        ],
      ),
    );
  }

  Widget _dropdownFieldTile({
    required String label,
    required String hint,
    required String? value,
    required List<String> items,
    required Widget prefixIcon,
    required ValueChanged<String?> onChanged,
    bool isExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: InputDecorator(
        decoration: _decor(label, prefixIcon: prefixIcon),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            hint: Text(
              hint,
              style: _hintStyle.copyWith(
                fontWeight: FontWeight.w500,
                color: WorkaColors.textGreyDark,
              ),
            ),
            isExpanded: isExpanded,
            isDense: true,
            borderRadius: BorderRadius.circular(16),
            menuMaxHeight: 320,
            itemHeight: 52,
            dropdownColor: Colors.white,
            icon: const Icon(
              Icons.expand_more_rounded,
              color: WorkaColors.textGreyDark,
              size: _JobFlowUi.trailingIconSize,
            ),
            items: items
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: WorkaColors.textDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _step3() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Гражданство'),
          _FieldTile(
            onTap: _pickCitizenship,
            leading: const Text('🌍', style: TextStyle(fontSize: 16)),
            title: Text(
              _citizenships.isEmpty
                  ? 'Не выбрано'
                  : 'Выбрано: ${_citizenships.length}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: _citizenships.isEmpty
                    ? FontWeight.w600
                    : FontWeight.w700,
                color: _citizenships.isEmpty
                    ? WorkaColors.textGreyDark
                    : WorkaColors.textDark,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: WorkaColors.textGreyDark,
            ),
          ),
          _sp(),
          _sectionHeader('Опыт работы'),
          _chipsRow(
            values: _kExperienceOptions,
            selected: _experience,
            onTap: (v) =>
                setState(() => _experience = _experience == v ? null : v),
          ),
          _sp(),
          Opacity(
            opacity: 0.92,
            child: Row(
              children: [
                Expanded(
                  child: _tf(
                    _ageFromCtrl,
                    'Возраст от',
                    hint: '18',
                    keyboardType: TextInputType.number,
                    iconWidget: const Icon(
                      Icons.person,
                      color: WorkaColors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _tf(
                    _ageToCtrl,
                    'Возраст до',
                    hint: '60',
                    keyboardType: TextInputType.number,
                    iconWidget: const Icon(
                      Icons.person_outline,
                      color: WorkaColors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _sp(),
          _sectionHeader('Водительские права'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kDrivingLicenseOptions
                .map(
                  (v) => _licenseChip(
                    label: v,
                    selected: _drivingLicenses.contains(v),
                    onTap: () => setState(() {
                      if (_drivingLicenses.contains(v)) {
                        _drivingLicenses.remove(v);
                      } else {
                        _drivingLicenses.add(v);
                      }
                    }),
                  ),
                )
                .toList(),
          ),
          _sp(),
          _toggleRow(
            title: 'Есть автомобиль',
            value: _hasCar,
            onChanged: (v) => setState(() => _hasCar = v),
            icon: Icons.directions_car,
          ),
          _sp(),
          _sectionHeader('Знание языков'),
          _sectionCard(
            child: Builder(
              builder: (context) {
                final available = _kLanguageOptions
                    .where((lang) => !_languages.contains(lang))
                    .toList(growable: false);
                final draftValue =
                    (_languageDraftSelection != null &&
                        available.contains(_languageDraftSelection))
                    ? _languageDraftSelection
                    : (available.isNotEmpty ? available.first : null);
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: draftValue,
                            items: available
                                .map(
                                  (lang) => DropdownMenuItem<String>(
                                    value: lang,
                                    child: Text(
                                      lang,
                                      style: const TextStyle(
                                        color: WorkaColors.textGreyDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: available.isEmpty
                                ? null
                                : (v) => setState(
                                    () => _languageDraftSelection = v,
                                  ),
                            decoration: InputDecoration(
                              hintText: available.isEmpty
                                  ? 'Все языки добавлены'
                                  : 'Выберите язык',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: WorkaColors.fieldBorder,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: WorkaColors.blue,
                                  width: 1.6,
                                ),
                              ),
                            ),
                            dropdownColor: Colors.white,
                            iconEnabledColor: WorkaColors.blue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: available.isEmpty
                                ? null
                                : () {
                                    final lang =
                                        (_languageDraftSelection ??
                                                draftValue ??
                                                '')
                                            .trim();
                                    if (lang.isEmpty) return;
                                    setState(() {
                                      _languages.add(lang);
                                      _languageDraftSelection = null;
                                    });
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: WorkaColors.blue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Добавить'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_languages.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Языки не выбраны',
                          style: TextStyle(
                            color: WorkaColors.textGrey,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (_languages.toList()..sort()).map((lang) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: WorkaColors.hoverBlueSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: WorkaColors.blue),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                lang,
                                style: const TextStyle(
                                  color: WorkaColors.textGreyDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => setState(() {
                                  _languages.remove(lang);
                                  if (lang == 'Другое') {
                                    _otherLanguageCtrl.clear();
                                  }
                                }),
                                borderRadius: BorderRadius.circular(999),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: WorkaColors.blue,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_languages.contains('Другое')) ...[
            _sp(),
            _tf(
              _otherLanguageCtrl,
              'Укажите язык',
              hint: 'Например: Чешский',
              iconWidget: const Icon(Icons.edit, color: WorkaColors.blue),
            ),
          ],
          _sp(),
          _sectionCard(
            child: _tf(
              _additionalRequirementsCtrl,
              'Дополнительные требования',
              hint: 'Например: наличие инструмента, физическая подготовка...',
              maxLines: 3,
              iconWidget: const Icon(Icons.checklist, color: WorkaColors.blue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.fieldBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _licenseChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? WorkaColors.hoverBlueSoft : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? WorkaColors.blue : WorkaColors.fieldBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? WorkaColors.blue : WorkaColors.textGreyDark,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _step4() {
    return _card(
      child: Column(
        children: [
          _sectionCard(
            child: Column(
              children: [
                const _SectionCardHeader(
                  icon: Icons.format_list_bulleted,
                  title: 'Обязанности',
                ),
                const SizedBox(height: 10),
                _tf(
                  _responsibilitiesCtrl,
                  'Обязанности',
                  hint: 'Опиши основные задачи...',
                  maxLines: 4,
                  iconWidget: const Icon(
                    Icons.format_list_bulleted,
                    color: WorkaColors.blue,
                  ),
                ),
              ],
            ),
          ),
          _sp(),
          _sectionCard(
            child: Column(
              children: [
                const _SectionCardHeader(icon: Icons.rule, title: 'Требования'),
                const SizedBox(height: 10),
                _tf(
                  _requirementsCtrl,
                  'Требования',
                  hint: 'Опишите требования к кандидату...',
                  maxLines: 4,
                  iconWidget: const Icon(Icons.rule, color: WorkaColors.blue),
                ),
              ],
            ),
          ),
          _sp(),
          _sectionCard(
            child: Column(
              children: [
                const _SectionCardHeader(
                  icon: Icons.description_rounded,
                  title: 'Описание вакансии *',
                ),
                const SizedBox(height: 10),
                _tf(
                  _descriptionCtrl,
                  'Описание вакансии *',
                  hint: 'Расскажи о компании, условиях, что предлагаете...',
                  maxLines: 6,
                  iconWidget: const Icon(
                    Icons.description,
                    color: WorkaColors.blue,
                  ),
                ),
              ],
            ),
          ),
          _sp(),
          _toggleRow(
            title: 'Жильё предоставляется',
            value: _housingProvided,
            onChanged: (v) => setState(() {
              _housingProvided = v;
              if (!v) {
                _housingCostFromCtrl.clear();
                _housingCostToCtrl.clear();
              }
            }),
            icon: Icons.home,
          ),
          if (_housingProvided) ...[
            _sp(),
            Row(
              children: [
                Expanded(
                  child: _compactMoneyField(
                    _housingCostFromCtrl,
                    'Жильё: стоимость от',
                    icon: Icons.euro,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _compactMoneyField(
                    _housingCostToCtrl,
                    'Жильё: стоимость до',
                    icon: Icons.euro_outlined,
                  ),
                ),
              ],
            ),
          ],
          _sp(),
          _toggleRow(
            title: 'Транспорт предоставляется',
            value: _transportProvided,
            onChanged: (v) => setState(() {
              _transportProvided = v;
              if (!v) {
                _transportCostFromCtrl.clear();
                _transportCostToCtrl.clear();
              }
            }),
            icon: Icons.directions_bus,
          ),
          if (_transportProvided) ...[
            _sp(),
            Row(
              children: [
                Expanded(
                  child: _compactMoneyField(
                    _transportCostFromCtrl,
                    'Развозка: стоимость от',
                    icon: Icons.euro,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _compactMoneyField(
                    _transportCostToCtrl,
                    'Развозка: стоимость до',
                    icon: Icons.euro_outlined,
                  ),
                ),
              ],
            ),
          ],
          _sp(),
          _toggleRow(
            title: 'Подходит для подростков',
            value: _teenFriendly,
            onChanged: (v) => setState(() => _teenFriendly = v),
            icon: Icons.emoji_people,
          ),
          _sp(),
          _toggleRow(
            title: 'Подходит для людей с инвалидностью',
            value: _disabilityFriendly,
            onChanged: (v) => setState(() => _disabilityFriendly = v),
            icon: Icons.accessible,
          ),
          _sp(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _toggleRow(
                title: 'Срочная вакансия',
                value: _isUrgent,
                onChanged: _onUrgentToggleChanged,
                icon: Icons.priority_high,
                iconColor: WorkaColors.orange,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: WorkaColors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _paidUrgent
                        ? 'Платная опция оплачена'
                        : 'Платная опция — требуется оплата',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: WorkaColors.textGreyDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onUrgentToggleChanged(bool value) async {
    if (!value) {
      setState(() {
        _isUrgent = false;
        _urgentRequested = false;
      });
      return;
    }

    final String jobIdForPaywall =
        (widget.editJobId ?? widget.editJobRef?.id ?? _newJobCode ?? '').trim();
    if (jobIdForPaywall.isEmpty) {
      setState(() {
        _isUrgent = false;
        _paidUrgent = false;
        _urgentRequested = true;
      });
      _snack('Опция платная. Оплатите после публикации вакансии.');
      return;
    }

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PromoteJobScreen(jobCode: jobIdForPaywall),
      ),
    );
    if (!mounted) return;
    _snack('Срочная вакансия включается после подтверждения оплаты.');
  }

  Widget _compactMoneyField(
    TextEditingController controller,
    String label, {
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: WorkaColors.textDark,
      ),
      decoration:
          _decor(
            label,
            hintText: '0',
            prefixIcon: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Icon(icon, color: WorkaColors.blue),
            ),
          ).copyWith(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _step5() {
    final custom = _expiryPresetDays == -1;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionCardHeader(
                  icon: Icons.calendar_month_rounded,
                  title: 'Срок действия вакансии *',
                ),
                const SizedBox(height: 4),
                const Text(
                  'Выберите, как долго вакансия будет активна (до 30 дней).',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: WorkaColors.textGreyDark,
                    height: 1.25,
                  ),
                ),
                _sp(),
                _expiryOption(
                  title: '1 неделя',
                  selected: _expiryPresetDays == 7,
                  onTap: () => setState(() => _expiryPresetDays = 7),
                ),
                _sp(),
                _expiryOption(
                  title: '2 недели',
                  selected: _expiryPresetDays == 14,
                  onTap: () => setState(() => _expiryPresetDays = 14),
                ),
                _sp(),
                _expiryOption(
                  title: '1 месяц',
                  selected: _expiryPresetDays == 30,
                  onTap: () => setState(() => _expiryPresetDays = 30),
                ),
                _sp(),
                _expiryOption(
                  title: 'Другое (до 30 дней)',
                  selected: custom,
                  onTap: () => setState(() => _expiryPresetDays = -1),
                ),
                if (custom) ...[
                  _sp(),
                  _tf(
                    _customDaysCtrl,
                    'Количество дней (макс. 30) *',
                    hint: '10',
                    keyboardType: TextInputType.number,
                    iconWidget: const Icon(
                      Icons.event,
                      color: WorkaColors.blue,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: _SectionCardHeader(
                        icon: Icons.business_center_rounded,
                        title: 'Данные компании',
                      ),
                    ),
                    if (_hasBusinessProfilePrefill) _autofillBadge(),
                  ],
                ),
                const SizedBox(height: 10),
                if (!_hasBusinessProfilePrefill) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: WorkaColors.hoverBlueSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WorkaColors.fieldBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: WorkaColors.textGreyDark,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Данные компании и контактов не найдены в бизнес-профиле.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: WorkaColors.textGreyDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const EmployerCompanyProfileScreen(),
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 0,
                                    vertical: 2,
                                  ),
                                ),
                                child: const Text(
                                  'Заполнить профиль',
                                  style: TextStyle(
                                    color: WorkaColors.blue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _sp(),
                ],
                _tf(
                  _companyNameCtrl,
                  'Название фирмы *',
                  hint: 'Worka OÜ',
                  iconWidget: const Icon(
                    Icons.business,
                    color: WorkaColors.blue,
                  ),
                ),
                _sp(),
                _tf(
                  _regNumberCtrl,
                  'Рег. номер',
                  hint: '1234567',
                  iconWidget: const Icon(Icons.badge, color: WorkaColors.blue),
                ),
                _sp(),
                _tf(
                  _websiteCtrl,
                  'Веб-сайт',
                  hint: 'site.com',
                  keyboardType: TextInputType.url,
                  iconWidget: const Icon(
                    Icons.language,
                    color: WorkaColors.blue,
                  ),
                ),
                _sp(),
                _toggleRow(
                  title: 'Показывать контакты в вакансии',
                  value: _showContacts,
                  onChanged: (v) => setState(() => _showContacts = v),
                  icon: Icons.contact_phone,
                  iconColor: WorkaColors.blue,
                ),
              ],
            ),
          ),

          if (_showContacts) ...[
            const SizedBox(height: 16),
            _sectionCard(
              child: Column(
                children: [
                  const _SectionCardHeader(
                    icon: Icons.contact_mail_rounded,
                    title: 'Контакты',
                  ),
                  const SizedBox(height: 10),
                  Form(
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: ContactFields(
                      firstNameController: _contactFirstCtrl,
                      lastNameController: _contactLastCtrl,
                      emailController: _emailCtrl,
                      phoneNumberController: _phoneNumberCtrl,
                      phoneCountryCode: _phoneCountryCode,
                      onPhoneCountryCodeChanged: (v) =>
                          setState(() => _phoneCountryCode = v),
                      onChanged: () => setState(() {}),
                      enabled: !_saving,
                    ),
                  ),
                  _sp(),
                  _tf(
                    _telegramCtrl,
                    'Telegram',
                    hint: '@username',
                    iconWidget: const FaIcon(
                      FontAwesomeIcons.telegram,
                      color: WorkaColors.blue,
                      size: 18,
                    ),
                  ),
                  _sp(),
                  _tf(
                    _whatsappCtrl,
                    'WhatsApp',
                    hint: '+372 ...',
                    keyboardType: TextInputType.phone,
                    iconWidget: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: WorkaColors.blue,
                      size: 18,
                    ),
                  ),
                  _sp(),
                  _tf(
                    _viberCtrl,
                    'Viber',
                    hint: '+372 ...',
                    keyboardType: TextInputType.phone,
                    iconWidget: const FaIcon(
                      FontAwesomeIcons.viber,
                      color: WorkaColors.blue,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bodyForStep() {
    switch (_step) {
      case 0:
        return _step1();
      case 1:
        return _step2();
      case 2:
        return _step3();
      case 3:
        return _step4();
      case 4:
        return _step5();
      default:
        return _step1();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canNext = _isStepValid(_step);
    final canSaveEdit = List<bool>.generate(
      _stepsCount,
      (i) => _isStepValid(i),
    ).every((v) => v);
    final last = _step == _stepsCount - 1;
    final stepTitle = _kStepTitles[_step];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        if (_saving) return;
        if (_isEditMode) {
          Navigator.of(context).pop();
          return;
        }
        if (_step > 0) {
          setState(() => _step -= 1);
          return;
        }
        await _saveDraftIfNeeded();
        if (!mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF4A6FDB),
        body: Column(
          children: [
            // Navigation row — on blue background (1.5× taller than CV)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _saving ? null : _back,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        _isEditMode
                            ? 'Редактировать вакансию'
                            : 'Новая вакансия',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const ProfileAvatarButton(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Progress dots — on blue background (white dots, 1.5× more space)
            CvProgressDots(current: _step, total: _stepsCount, onBlue: true),
            const SizedBox(height: 24),
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
                        padding: const EdgeInsets.fromLTRB(
                          _JobFlowUi.screenPadding,
                          20,
                          _JobFlowUi.screenPadding,
                          _JobFlowUi.screenPadding,
                        ),
                        children: [
                          Text(
                            stepTitle,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _bodyForStep(),
                        ],
                      ),
                    ),
                    _JobFlowBottomBar(
                      onBack: _saving
                          ? null
                          : (_isEditMode
                                ? () => Navigator.of(context).pop(false)
                                : _back),
                      onNext: _saving ? null : (_isEditMode ? _submit : _next),
                      canNext: _isEditMode ? canSaveEdit : canNext,
                      isSaving: _saving,
                      nextLabel: _isEditMode
                          ? 'Сохранить'
                          : (last ? 'Опубликовать' : 'Продолжить'),
                      backLabel: _isEditMode ? 'Отмена' : 'Назад',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.items,
    required this.selected,
    required this.itemIconBuilder,
    this.singleSelect = false,
    this.lockedItems = const <String>{},
    this.onLockedTap,
  });

  final List<String> items;
  final Set<String> selected;
  final IconData Function(String label) itemIconBuilder;
  final bool singleSelect;
  final Set<String> lockedItems;
  final VoidCallback? onLockedTap;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selected};
  }

  void _toggleItem(String item) {
    final isLocked = widget.lockedItems.contains(item);
    if (isLocked) {
      widget.onLockedTap?.call();
      return;
    }
    setState(() {
      if (widget.singleSelect) {
        if (_selected.contains(item)) {
          _selected = <String>{};
        } else {
          _selected = {item};
        }
        return;
      }
      if (_selected.contains(item)) {
        _selected.remove(item);
      } else {
        _selected.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: WorkaColors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  Icon(Icons.category_rounded, color: WorkaColors.orange),
                  SizedBox(width: 8),
                  Text(
                    'Категория',
                    style: TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: WorkaColors.divider),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: widget.items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: WorkaColors.divider),
                itemBuilder: (context, i) {
                  final category = widget.items[i];
                  final locked = widget.lockedItems.contains(category);
                  final isSelected = _selected.contains(category);
                  return InkWell(
                    onTap: () => _toggleItem(category),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleItem(category),
                            activeColor: WorkaColors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              category,
                              style: TextStyle(
                                color: locked
                                    ? WorkaColors.textGreyDark
                                    : WorkaColors.textDark,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (locked)
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: WorkaColors.textGreyDark,
                            )
                          else
                            Icon(
                              widget.itemIconBuilder(category),
                              size: 18,
                              color: WorkaColors.orange,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: WorkaColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => setState(() => _selected = <String>{}),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: WorkaColors.textGreyDark,
                          side: BorderSide(
                            color: WorkaColors.divider.withValues(alpha: 0.9),
                          ),
                          backgroundColor: WorkaColors.pageBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Очистить',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(_selected),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: WorkaColors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Готово',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.onTap,
    this.leading,
    required this.title,
    this.trailing,
    this.backgroundColor,
    this.borderColor,
  });

  final VoidCallback? onTap;
  final Widget? leading;
  final Widget title;
  final Widget? trailing;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(_JobFlowUi.radiusCard),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: _JobFlowUi.tilePadding,
          vertical: _JobFlowUi.tilePadding,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor ?? _JobFlowUi.border),
          borderRadius: BorderRadius.circular(_JobFlowUi.radiusCard),
          color: backgroundColor ?? _JobFlowUi.surface,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme.merge(
                data: const IconThemeData(size: _JobFlowUi.tileIconSize),
                child: leading!,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: title),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              IconTheme.merge(
                data: const IconThemeData(size: _JobFlowUi.trailingIconSize),
                child: trailing!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionCardHeader extends StatelessWidget {
  const _SectionCardHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: WorkaColors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: WorkaColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _JobFlowBottomBar extends StatelessWidget {
  const _JobFlowBottomBar({
    required this.onBack,
    required this.onNext,
    required this.canNext,
    required this.isSaving,
    required this.nextLabel,
    this.backLabel = 'Назад',
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final bool canNext;
  final bool isSaving;
  final String nextLabel;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          _JobFlowUi.screenPadding,
          10,
          _JobFlowUi.screenPadding,
          14,
        ),
        decoration: BoxDecoration(
          color: _JobFlowUi.surface,
          border: Border(
            top: BorderSide(color: _JobFlowUi.border.withValues(alpha: 0.85)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 56,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onNext,
                style: WorkaButtonStyles.primaryOrange(),
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        nextLabel,
                        style: const TextStyle(
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
                onPressed: onBack,
                style: WorkaButtonStyles.outlineNeutral(),
                child: Text(
                  backLabel,
                  style: TextStyle(
                    color: _JobFlowUi.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkaSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _WorkaSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const onBg = Color(0xFF3B82F6);
    const onBorder = Color(0xFF2563EB);
    const onKnob = Color(0xFF2563EB);
    const offBg = Colors.white;
    const offBorder = Color(0xFF3B82F6);
    const offKnob = Color(0xFF3B82F6);

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: value ? onBg : offBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: value ? onBorder : offBorder, width: 1.4),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? onKnob : offKnob,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _CitizenshipSheet extends StatefulWidget {
  final List<String> items;
  final Set<String> selected;

  const _CitizenshipSheet({required this.items, required this.selected});

  @override
  State<_CitizenshipSheet> createState() => _CitizenshipSheetState();
}

class _CitizenshipSheetState extends State<_CitizenshipSheet> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected.isNotEmpty;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Text(
              'Гражданство',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: WorkaColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: widget.items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: WorkaColors.divider),
                itemBuilder: (context, i) {
                  final country = widget.items[i];
                  final flag = country == 'ЕС (любая страна)' ? '🇪🇺' : '';
                  final checked = _selected.contains(country);
                  return InkWell(
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(country);
                      } else {
                        _selected.add(country);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Checkbox(
                            value: checked,
                            activeColor: WorkaColors.blue,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (_) => setState(() {
                              if (checked) {
                                _selected.remove(country);
                              } else {
                                _selected.add(country);
                              }
                            }),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            flag.isNotEmpty
                                ? flag
                                : CountryDisplayFormatter.countryFlagOnly(
                                    country,
                                    euAsToken: false,
                                  ),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              country,
                              style: const TextStyle(
                                color: WorkaColors.textDark,
                                fontWeight: FontWeight.w700,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => setState(_selected.clear),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasSelection
                              ? WorkaColors.orange
                              : const Color(0xFFFFD9AE),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Очистить',
                          style: TextStyle(
                            color: hasSelection
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, _selected),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.blue,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
