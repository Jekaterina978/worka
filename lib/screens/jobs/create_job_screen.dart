import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../services/firebase_debug_diagnostics.dart';
import '../../services/firestore_paths.dart';
import '../../services/auth_guard.dart';
import '../../theme/worka_colors.dart';
import '../../widgets/contact_fields.dart';
import '../search/services/exchange_rate_service.dart';
import '../search/widgets/search_filters_config.dart';
import '../search/widgets/multi_select_sheet.dart';
import '../search/widgets/location_picker_sheet.dart';
import '../employer_company_profile_screen.dart';
import '../../services/app_mode.dart' as app_mode;
import '../../services/ownership_context.dart';
import '../../features/monetization/monetization_repository.dart';
import '../../features/monetization/monetization_i18n.dart';
import '../../features/monetization/monetization_routes.dart';
import '../../features/monetization/pricing.dart';
import '../../features/payments/screens/promote_job_screen.dart';

import 'package:worka/screens/employer/my_publications_screen.dart';
import 'package:worka/widgets/worka_header.dart';

// ✅ ВАЖНО: путь может отличаться у тебя — поправь import при необходимости
import '../auth/auth_entry_screen.dart';

class CreateJobScreen extends StatefulWidget {
  final String? employerType; // 'company' | 'private'

  /// ✅ testMode=true: можно публиковать без регистрации (uid может быть null)
  final bool testMode;

  const CreateJobScreen({super.key, this.employerType, this.testMode = true});

  @override
  State<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends State<CreateJobScreen> {
  @override
  void initState() {
    super.initState();
    debugPrint('🔥 [SCREEN_RUNTIME] jobs/create_job_screen opened');
  }

  _CreateJobScreenState() {
    debugPrint('🔥 [CREATE_JOB_SCREEN] FILE = lib/screens/jobs/create_job_screen.dart');
  }
  static const int _stepsCount = 6;
  int _step = 0;
  bool _saving = false;
  String? _newJobCode;
  final OwnershipContext _ownership = OwnershipContext();

  Uri _buildJobsCreateUri() {
    final base = const String.fromEnvironment('WORKA_API_BASE_URL', defaultValue: '')
        .replaceAll(RegExp(r'/+$'), '');
    assert(base.isNotEmpty, 'WORKA_API_BASE_URL is required');
    debugPrint('🔥 [BASE_URL] base=$base');
    return Uri.parse('$base/api/jobs');
  }

  // ---------------- Step 1 (Company + contacts) ----------------
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

  // ---------------- Step 2 (Job basics) ----------------
  final _titleCtrl = TextEditingController();
  String? _category; // из grouped list
  final _cityCtrl = TextEditingController();
  String _country = 'Эстония';

  // ---------------- Step 3 (Expiry + openings) ----------------
  int _expiryPresetDays = 7; // 7/14/30 or custom (<=30)
  final _customDaysCtrl = TextEditingController(text: '7');
  final _openingsCtrl = TextEditingController(text: '1');

  // ---------------- Step 4 (Employment type) ----------------
  String? _workSchedule;
  final _customWorkScheduleCtrl = TextEditingController();

  // ---------------- Step 5 (Salary) ----------------
  final _salaryFromCtrl = TextEditingController();
  final _salaryToCtrl = TextEditingController();
  String _salaryCurrency = 'EUR';
  String _salaryPeriodRu = 'В месяц';

  // ---------------- Step 6 (Description + switches) ----------------
  final _descriptionCtrl = TextEditingController();
  bool _housingProvided = false;
  bool _transportProvided = false;
  bool _teenFriendly = false;
  bool _disabilityFriendly = false;
  bool _isUrgent = false;
  bool _paidUrgent = false;
  bool _urgentRequested = false;
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

  static const Map<String, List<String>> _countryCitiesMap = {
    'Эстония': ['Таллинн', 'Тарту', 'Пярну', 'Нарва'],
    'Германия': ['Берлин', 'Мюнхен', 'Гамбург', 'Франкфурт'],
    'Финляндия': ['Хельсинки', 'Тампере', 'Турку'],
    'Латвия': ['Рига', 'Даугавпилс'],
    'Литва': ['Вильнюс', 'Каунас', 'Клайпеда'],
    'Польша': ['Варшава', 'Краков', 'Гданьск'],
    'Швеция': ['Стокгольм', 'Гётеборг', 'Мальмё'],
    'Норвегия': ['Осло', 'Берген'],
    'Дания': ['Копенгаген', 'Орхус'],
    'Франция': ['Париж', 'Лион'],
    'Испания': ['Мадрид', 'Барселона', 'Валенсия'],
  };

  static const List<String> _kWorkScheduleOptions = <String>[
    'Пн–Пт, 8 часов',
    'Сменный график',
    'Вахта',
    'Гибкий',
    'Другое',
  ];

  bool get _isCustomWorkSchedule => (_workSchedule ?? '').trim() == 'Другое';

  String _resolvedWorkSchedule() {
    if (_isCustomWorkSchedule) {
      return _customWorkScheduleCtrl.text.trim();
    }
    return (_workSchedule ?? '').trim();
  }

  @override
  void initState() {
    super.initState();
    if (SearchFiltersConfig.countriesRu.isNotEmpty) {
      _country = SearchFiltersConfig.countriesRu.firstWhere(
        (c) => c == 'Эстония',
        orElse: () => SearchFiltersConfig.countriesRu.first,
      );
    }
    if (AuthGuard.effectiveUidOrNull() == null) {
      _contactFirstCtrl.text = 'Тестовый';
      _contactLastCtrl.text = 'профиль';
      _emailCtrl.text = 'test@worka.local';
      _phoneCountryCode = '+372';
      _phoneNumberCtrl.text = '000000000';
    }
    _prefillContactsIfLoggedIn();
  }

  Future<void> _prefillContactsIfLoggedIn() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

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

    _titleCtrl.dispose();
    _cityCtrl.dispose();

    _customDaysCtrl.dispose();
    _openingsCtrl.dispose();
    _customWorkScheduleCtrl.dispose();

    _salaryFromCtrl.dispose();
    _salaryToCtrl.dispose();

    _descriptionCtrl.dispose();
    super.dispose();
  }

  // ---------------- UI helpers ----------------

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
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.blue, width: 1.4),
      ),
    );
  }

  Widget _progressDots() {
    bool done(int i) => _isStepValid(i);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_stepsCount, (i) {
        final bool isActive = i == _step;
        final bool isDone = done(i) && i < _step;
        final Color color = isActive || isDone
            ? WorkaColors.blue
            : WorkaColors.divider;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: isActive ? 10 : 8,
          height: isActive ? 10 : 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );
      }),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: WorkaColors.divider),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sp() => const SizedBox(height: 12);

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
      decoration: _decor(
        label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: iconWidget,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _toggleRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    Color? iconColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: WorkaColors.divider),
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? WorkaColors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                  color: value
                      ? WorkaColors.textDark
                      : WorkaColors.textGreyDark,
                ),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
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
      spacing: 10,
      runSpacing: 10,
      children: values.map((v) {
        final isSelected = v == selected;
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onTap(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? WorkaColors.hoverBlueSoft : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected ? WorkaColors.blue : WorkaColors.textDark,
                width: 1.2,
              ),
            ),
            child: Text(
              v,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: WorkaColors.textDark,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _expiryOption({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? WorkaColors.hoverBlueSoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? WorkaColors.blue : WorkaColors.divider,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.timer, color: WorkaColors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title + (selected ? '  ✓' : ''),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? WorkaColors.textDark : WorkaColors.textGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Auth gate ----------------

  Future<bool> _ensureAuthIfNeeded() async {
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (authUid != null && authUid.isNotEmpty) return true;

    final ok = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));

    return ok == true || AuthGuard.effectiveUidOrNull() != null;
  }

  // ---------------- Pickers ----------------

  Future<void> _pickCountry() async {
    final cityToCountry = <String, String>{};
    for (final e in _countryCitiesMap.entries) {
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
    final groups = SearchFiltersConfig.categoryGroups;
    final allGroups = groups.keys.toList();
    if (!mounted) return;

    if (isPrivate) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: allGroups.length + 1,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: WorkaColors.divider),
            itemBuilder: (context, index) {
              if (index == allGroups.length) {
                return ListTile(
                  onTap: () => Navigator.pop(ctx, ''),
                  title: const Text(
                    'Очистить',
                    style: TextStyle(
                      color: WorkaColors.orange,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }
              final category = allGroups[index];
              return ListTile(
                onTap: () async {
                  Navigator.pop(ctx, category);
                },
                leading: Icon(
                  _categoryIcons[category] ?? Icons.category,
                  color: WorkaColors.orange,
                ),
                title: Text(
                  category,
                  style: TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ),
      );
      if (picked == null) return;
      setState(() {
        _category = picked.trim().isEmpty ? null : picked.trim();
      });
      return;
    }

    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MultiSelectSheet(
        title: 'Категория',
        items: const [],
        selected: _category == null ? const <String>{} : {_category!},
        grouped: SearchFiltersConfig.categoryGroups,
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

  // ---------------- Validation ----------------

  bool _isNonEmpty(TextEditingController c) => c.text.trim().isNotEmpty;

  bool _isStepValid(int stepIndex) {
    switch (stepIndex) {
      case 0:
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
        return true;

      case 1:
        if (!_isNonEmpty(_titleCtrl)) return false;
        if ((_category ?? '').trim().isEmpty) return false;
        if (!_isNonEmpty(_cityCtrl)) return false;
        if (_country.trim().isEmpty) return false;
        return true;

      case 2:
        final openings = int.tryParse(_openingsCtrl.text.trim());
        if (openings == null || openings <= 0) return false;

        if (_expiryPresetDays == -1) {
          final d = int.tryParse(_customDaysCtrl.text.trim());
          if (d == null || d <= 0 || d > 30) return false;
        } else {
          if (_expiryPresetDays <= 0 || _expiryPresetDays > 30) return false;
        }
        return true;

      case 3:
        if ((_workSchedule ?? '').trim().isEmpty) return false;
        if (_isCustomWorkSchedule &&
            _customWorkScheduleCtrl.text.trim().isEmpty) {
          return false;
        }
        return true;

      case 4:
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
        return true;

      case 5:
        return _isNonEmpty(_descriptionCtrl);

      default:
        return false;
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: WorkaColors.textDark),
    );
  }

  // ---------------- Salary helpers ----------------

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

  // ---------------- Navigation ----------------

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
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
    setState(() => _step += 1);
  }

  Future<void> _submit() async {
    for (int i = 0; i < _stepsCount; i++) {
      if (!_isStepValid(i)) {
        setState(() => _step = i);
        _snack('Есть незаполненные поля.');
        return;
      }
    }

    setState(() => _saving = true);

    try {
      // ✅ PROD: перед публикацией требуем вход; ✅ TEST: не требуем
      final authed = await _ensureAuthIfNeeded();
      if (!authed) {
        _snack(
          'Чтобы опубликовать вакансию, нужно зарегистрироваться / войти.',
        );
        return;
      }

      final uid = AuthGuard.effectiveUidOrNull();
      if (uid == null || uid.trim().isEmpty) {
        _snack('Нужен вход');
        return;
      }
      final ownerKey = uid;

      final monetizationRepo = MonetizationRepository(
        FirebaseFirestore.instance,
      );
      final ent = await monetizationRepo.getEmployerEntitlements(uid);
      if (ent.employerType == EmployerType.private) {
        final selectedCategory = (_category ?? '').trim();
        if (selectedCategory.isNotEmpty &&
            kPrivateLockedCategoryGroups.contains(selectedCategory)) {
          if (!mounted) return;
          _snack(MonetizationI18n.t(context, 'locked_business_soon'));
          await Navigator.of(
            context,
            rootNavigator: true,
          ).pushNamed(MonetizationRoutes.employerPlans);
          return;
        }
        final activeJobs = await monetizationRepo.countActiveVacancies(uid);
        if (activeJobs >= ent.activeJobLimit) {
          if (!mounted) return;
          _snack(MonetizationI18n.t(context, 'job_limit_subtitle'));
          await Navigator.of(
            context,
            rootNavigator: true,
          ).pushNamed(MonetizationRoutes.employerPlans);
          return;
        }
      }

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
        if (_ownership.activeProfileId != null)
          'created_by_profile_id': _ownership.activeProfileId,
        if (_ownership.activeCompanyId != null)
          'company_id': _ownership.activeCompanyId,
        'ownerType': ownerType,
        'isDeleted': false,
        'test': widget.testMode,
        'title': _titleCtrl.text.trim(),
        'category': _category,
        'city': _cityCtrl.text.trim(),
        'country': _country.trim(),
        'employmentType': _resolvedWorkSchedule(),
        'workSchedule': _resolvedWorkSchedule(),
        'workScheduleOption': (_workSchedule ?? '').trim(),
        'workScheduleCustom': _customWorkScheduleCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'expiresAt': expiresAtIso,
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
        'teenFriendly': _teenFriendly,
        'disabilityFriendly': _disabilityFriendly,
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
      };

      final col = FirestorePaths.vacancies;
      final resp = await _createJob(payload: data);
      _newJobCode = resp['jobCode']?.toString().trim();
      debugPrint('[CreateJobScreen] created via API jobCode=${_newJobCode ?? 'null'}');

      if (_urgentRequested && mounted) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => PromoteJobScreen(jobCode: _newJobCode ?? ''),
          ),
        );
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MyPublicationsScreen(testMode: widget.testMode),
        ),
      );
    } catch (e) {
      debugPrint('CreateJobScreen(jobs) _submit error: $e');
      if (!mounted) return;
      _snack('Ошибка сохранения: $e');
      if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
        _snack(FirebaseDebugDiagnostics.permissionHintText());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>> _createJob({
    required Map<String, dynamic> payload,
  }) async {
    debugPrint('[CREATE_JOB_TRACE] submit triggered (jobs/create)');
    Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
      final Map<String, dynamic> out = {};
      input.forEach((key, value) {
        if (value is DateTime) {
          out[key] = value.toUtc().toIso8601String();
        } else if (value is Map) {
          out[key] = _sanitize(Map<String, dynamic>.from(value));
        } else if (value is Iterable) {
          out[key] = value
              .map((e) => e is Map
                  ? _sanitize(Map<String, dynamic>.from(e as Map))
                  : (e is DateTime ? e.toUtc().toIso8601String() : e))
              .toList();
        } else {
          out[key] = value;
        }
      });
      return out;
    }

    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Требуется авторизация для создания вакансии.');
    }
    final uri = _buildJobsCreateUri();
    final safePayload = _sanitize(payload);
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

  // ---------------- Steps UI ----------------

  Widget _step1() {
    return _card(
      child: Column(
        children: [
          _tf(
            _companyNameCtrl,
            'Название фирмы *',
            hint: 'Worka OÜ',
            iconWidget: const Icon(Icons.business, color: WorkaColors.blue),
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
            iconWidget: const Icon(Icons.language, color: WorkaColors.blue),
          ),
          if (!_hasBusinessProfilePrefill) ...[
            _sp(),
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
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          ],
          _sp(),
          _toggleRow(
            title: 'Показывать контакты в вакансии',
            value: _showContacts,
            onChanged: (v) => setState(() => _showContacts = v),
            icon: Icons.contact_phone,
            iconColor: WorkaColors.blue,
          ),
          if (_showContacts) ...[
            _sp(),
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
        ],
      ),
    );
  }

  Widget _step2() {
    final cityOptions = (_countryCitiesMap[_country] ?? const <String>[])
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

    return _card(
      child: Column(
        children: [
          _tf(
            _titleCtrl,
            'Название должности *',
            hint: 'Сварщик',
            iconWidget: const Icon(Icons.work, color: WorkaColors.blue),
          ),
          _sp(),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickCategoryFromGroups,
            child: InputDecorator(
              decoration: _decor(
                'Категория *',
                prefixIcon: const Icon(Icons.category, color: WorkaColors.blue),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (_category ?? 'Выбрать'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: (_category == null)
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: (_category == null)
                            ? WorkaColors.textGrey
                            : WorkaColors.textDark,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: WorkaColors.textGreyDark,
                  ),
                ],
              ),
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
              'Локация *',
              hintText: 'Начни вводить город',
              prefixIcon: const Icon(
                Icons.location_on_outlined,
                color: WorkaColors.blue,
              ),
            ),
          ),
          if (showCitySuggestions) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WorkaColors.fieldBorder),
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
          _sp(),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickCountry,
            child: InputDecorator(
              decoration: _decor(
                'Страна',
                prefixIcon: const Icon(
                  Icons.location_on_outlined,
                  color: WorkaColors.blue,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _country,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _country.trim().isEmpty
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: _country.trim().isEmpty
                            ? WorkaColors.textGrey
                            : WorkaColors.textDark,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: WorkaColors.textGreyDark,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step3() {
    final custom = _expiryPresetDays == -1;
    return _card(
      child: Column(
        children: [
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
              iconWidget: const Icon(Icons.event, color: WorkaColors.blue),
            ),
          ],
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

  Widget _step4() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule, color: WorkaColors.blue),
              SizedBox(width: 10),
              Text(
                'График *',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WorkaColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _chipsRow(
            values: _kWorkScheduleOptions,
            selected: _workSchedule,
            onTap: (v) => setState(() {
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
        ],
      ),
    );
  }

  Widget _step5() {
    return _card(
      child: Column(
        children: [
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
                child: InputDecorator(
                  decoration: _decor(
                    'Валюта',
                    prefixIcon: const Icon(
                      Icons.currency_exchange,
                      color: WorkaColors.blue,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value:
                          SearchFiltersConfig.currencies.toSet().contains(
                            _salaryCurrency,
                          )
                          ? _salaryCurrency
                          : null,
                      hint: const Text('Валюта'),
                      items: SearchFiltersConfig.currencies
                          .toSet()
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _salaryCurrency = v ?? 'EUR'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InputDecorator(
                  decoration: _decor(
                    'Период',
                    prefixIcon: const Icon(
                      Icons.repeat,
                      color: WorkaColors.blue,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value:
                          SearchFiltersConfig.salaryPeriods.toSet().contains(
                            _salaryPeriodRu,
                          )
                          ? _salaryPeriodRu
                          : null,
                      hint: const Text('Период'),
                      items: SearchFiltersConfig.salaryPeriods
                          .toSet()
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _salaryPeriodRu = v ?? 'В месяц'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step6() {
    return _card(
      child: Column(
        children: [
          _tf(
            _descriptionCtrl,
            'Описание вакансии *',
            hint: 'Опиши задачи, требования, условия...',
            maxLines: 6,
            iconWidget: const Icon(Icons.description, color: WorkaColors.blue),
          ),
          _sp(),
          _toggleRow(
            title: 'Жильё предоставляется',
            value: _housingProvided,
            onChanged: (v) => setState(() => _housingProvided = v),
            icon: Icons.home,
          ),
          _sp(),
          _toggleRow(
            title: 'Транспорт предоставляется',
            value: _transportProvided,
            onChanged: (v) => setState(() => _transportProvided = v),
            icon: Icons.directions_bus,
          ),
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

    final String jobIdForPaywall = (_newJobCode ?? '').trim();
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
    setState(() {
      _paidUrgent = false;
      _isUrgent = false;
      _urgentRequested = true;
    });
    _snack('Срочная вакансия включается после подтверждения оплаты.');
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
      case 5:
        return _step6();
      default:
        return _step1();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canNext = _isStepValid(_step);
    final last = _step == _stepsCount - 1;

    final btnColor = canNext
        ? WorkaColors.orange
        : WorkaColors.orange.withValues(alpha: 0.35);

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Добавление вакансии',
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _progressDots(),
                    const SizedBox(height: 14),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [_bodyForStep()],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: WorkaColors.divider),
                          ),
                        ),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: _saving ? null : _back,
                              child: const Text(
                                'Назад',
                                style: TextStyle(
                                  color: WorkaColors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _saving ? null : _next,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: btnColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 26,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  elevation: 0,
                                ),
                                child: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        last ? 'Опубликовать' : 'Далее',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
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
        ],
      ),
    );
  }
}
