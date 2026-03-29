import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../services/auth_guard.dart';
import '../services/app_mode.dart';
import '../services/effective_uid.dart';
import '../theme/worka_colors.dart';
import '../widgets/contact_fields.dart';
import '../widgets/worka_header.dart';

/// EDIT screen:
/// - Белый фон
/// - Dropdown/Autocomplete белые
/// - Hover/выделение в выпадающих — синее
/// - DatePicker: белый фон, серый текст, выделение оранжевое
/// - Кнопка Save активна только если заполнены все обязательные (*)
class WorkerProfileEditScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final bool isInitialFill;
  final VoidCallback? onSaved;

  const WorkerProfileEditScreen({
    super.key,
    this.initialData,
    this.isInitialFill = false,
    this.onSaved,
  });

  @override
  State<WorkerProfileEditScreen> createState() =>
      _WorkerProfileEditScreenState();
}

class _WorkerProfileEditScreenState extends State<WorkerProfileEditScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _whatsapp = TextEditingController();
  final _telegram = TextEditingController();
  final _viber = TextEditingController();
  final _messenger = TextEditingController();
  String _phoneCountryCode = '+372';

  String? _gender; // 'male' | 'female'
  DateTime? _birthDate;

  String? _country; // обязательная
  final _cityCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  static const List<String> _citizenshipValues = <String>[
    'EU',
    'Kazakhstan',
    'Uzbekistan',
    'Kyrgyzstan',
    'Tajikistan',
    'Armenia',
    'Azerbaijan',
    'Moldova',
    'Belarus',
    'Russia',
    'Ukraine',
  ];

  static const Map<String, String> _citizenshipLabels = <String, String>{
    'EU': '🇪🇺 EU',
    'Kazakhstan': '🇰🇿 Kazakhstan',
    'Uzbekistan': '🇺🇿 Uzbekistan',
    'Kyrgyzstan': '🇰🇬 Kyrgyzstan',
    'Tajikistan': '🇹🇯 Tajikistan',
    'Armenia': '🇦🇲 Armenia',
    'Azerbaijan': '🇦🇿 Azerbaijan',
    'Moldova': '🇲🇩 Moldova',
    'Belarus': '🇧🇾 Belarus',
    'Russia': '🇷🇺 Russia',
    'Ukraine': '🇺🇦 Ukraine',
  };

  final List<String> _cityHints = const [
    'Tallinn',
    'Tartu',
    'Narva',
    'Pärnu',
    'Helsinki',
    'Espoo',
    'Tampere',
    'Riga',
    'Vilnius',
    'Kaunas',
    'Stockholm',
    'Gothenburg',
    'Oslo',
    'Bergen',
    'Copenhagen',
    'Aarhus',
    'Berlin',
    'Hamburg',
    'Munich',
    'Warsaw',
    'Krakow',
    'Prague',
    'Bratislava',
    'Ljubljana',
    'Kyiv',
    'Lviv',
  ];

  String? get _uid {
    final uid = _auth.currentUser?.uid.trim();
    if (uid != null && uid.isNotEmpty) return uid;
    return AuthGuard.effectiveUidOrNull();
  }

  DocumentReference<Map<String, dynamic>>? get _ref {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _first.addListener(() => setState(() {}));
    _last.addListener(() => setState(() {}));
    _email.addListener(() => setState(() {}));
    _phoneNumber.addListener(() => setState(() {}));
    _whatsapp.addListener(() => setState(() {}));
    _telegram.addListener(() => setState(() {}));
    _viber.addListener(() => setState(() {}));
    _messenger.addListener(() => setState(() {}));
    _cityCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phoneNumber.dispose();
    _whatsapp.dispose();
    _telegram.dispose();
    _viber.dispose();
    _messenger.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(t),
        backgroundColor: WorkaColors.textDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDate(DateTime d) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  String _s(dynamic v) => (v ?? '').toString().trim();
  String? _cleanOptionalContact(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    return value;
  }

  String? _normalizeCitizenshipValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    const map = <String, String>{
      'eu': 'EU',
      '🇪🇺 eu': 'EU',
      'kazakhstan': 'Kazakhstan',
      'казахстан': 'Kazakhstan',
      'uzbekistan': 'Uzbekistan',
      'узбекистан': 'Uzbekistan',
      'kyrgyzstan': 'Kyrgyzstan',
      'кыргызстан': 'Kyrgyzstan',
      'киргизстан': 'Kyrgyzstan',
      'tajikistan': 'Tajikistan',
      'таджикистан': 'Tajikistan',
      'armenia': 'Armenia',
      'армения': 'Armenia',
      'azerbaijan': 'Azerbaijan',
      'азербайджан': 'Azerbaijan',
      'moldova': 'Moldova',
      'молдова': 'Moldova',
      'belarus': 'Belarus',
      'беларусь': 'Belarus',
      'russia': 'Russia',
      'россия': 'Russia',
      'ukraine': 'Ukraine',
      'украина': 'Ukraine',
    };
    return map[lower] ?? (_citizenshipValues.contains(value) ? value : null);
  }

  String _countryIsoByName(String? name) {
    const isoByValue = <String, String>{
      'EU': 'EU',
      'Kazakhstan': 'KZ',
      'Uzbekistan': 'UZ',
      'Kyrgyzstan': 'KG',
      'Tajikistan': 'TJ',
      'Armenia': 'AM',
      'Azerbaijan': 'AZ',
      'Moldova': 'MD',
      'Belarus': 'BY',
      'Russia': 'RU',
      'Ukraine': 'UA',
    };
    return isoByValue[name?.trim()] ?? '';
  }

  Future<void> _load() async {
    final ref = _ref;

    Map<String, dynamic> m = <String, dynamic>{};

    if (widget.initialData != null) {
      m = Map<String, dynamic>.from(widget.initialData!);
    } else if (ref != null) {
      try {
        final snap = await ref.get();
        m = snap.data() ?? <String, dynamic>{};
      } catch (_) {
        m = <String, dynamic>{};
      }
    }

    final personal = (m['personal'] is Map)
        ? Map<String, dynamic>.from(m['personal'] as Map)
        : const <String, dynamic>{};

    _first.text = _s(personal['firstName']).isNotEmpty
        ? _s(personal['firstName'])
        : _s(m['firstName']);
    _last.text = _s(personal['lastName']).isNotEmpty
        ? _s(personal['lastName'])
        : _s(m['lastName']);
    _email.text = _s(personal['email']).isNotEmpty
        ? _s(personal['email'])
        : _s(m['email']);

    final authPhone = (_auth.currentUser?.phoneNumber ?? '').trim();
    final storedPhone = _s(personal['phone']).isNotEmpty
        ? _s(personal['phone'])
        : _s(m['phone']);
    final storedCountryCode = _s(personal['phoneCountryCode']).isNotEmpty
        ? _s(personal['phoneCountryCode'])
        : _s(m['phoneCountryCode']);
    final storedPhoneNumber = ContactFieldsValidators.normalizeDigits(
      _s(personal['phoneNumber']).isNotEmpty
          ? _s(personal['phoneNumber'])
          : _s(m['phoneNumber']),
    );
    if (storedCountryCode.isNotEmpty && storedPhoneNumber.isNotEmpty) {
      _phoneCountryCode = storedCountryCode;
      _phoneNumber.text = storedPhoneNumber;
    } else {
      final parsed = ContactFieldsValidators.parseStoredPhone(
        storedPhone.isNotEmpty ? storedPhone : authPhone,
        fallbackCountryCode: '+372',
      );
      _phoneCountryCode = parsed.countryCode;
      _phoneNumber.text = parsed.number;
    }

    _gender = _s(personal['gender']).isNotEmpty
        ? _s(personal['gender'])
        : _s(m['gender']);

    final bd = personal['birthDate'] ?? m['birthDate'];
    if (bd is Timestamp) _birthDate = bd.toDate();

    _country = _normalizeCitizenshipValue(
      _s(personal['country']).isNotEmpty
          ? _s(personal['country'])
          : _s(m['country']),
    );
    final countryName = _s(personal['citizenshipName']).isNotEmpty
        ? _s(personal['citizenshipName'])
        : (_s(personal['countryName']).isNotEmpty
              ? _s(personal['countryName'])
              : _s(m['countryName']));
    if (countryName.isNotEmpty) {
      _country = _normalizeCitizenshipValue(countryName) ?? _country;
    }
    _cityCtrl.text = _s(personal['city']).isNotEmpty
        ? _s(personal['city'])
        : _s(m['city']);

    String pickContact(String key) {
      final contacts = (m['contacts'] is Map)
          ? Map<String, dynamic>.from(m['contacts'] as Map)
          : const <String, dynamic>{};
      final socialLinks = (m['socialLinks'] is Map)
          ? Map<String, dynamic>.from(m['socialLinks'] as Map)
          : const <String, dynamic>{};
      final personalMap = (m['personal'] is Map)
          ? Map<String, dynamic>.from(m['personal'] as Map)
          : const <String, dynamic>{};
      final values = <String>[
        _s(m[key]),
        _s(personalMap[key]),
        _s(contacts[key]),
        _s(socialLinks[key]),
      ];
      for (final value in values) {
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    _whatsapp.text = pickContact('whatsapp');
    _telegram.text = pickContact('telegram');
    _viber.text = pickContact('viber');
    _messenger.text = pickContact('messenger');

    _country = _normalizeCitizenshipValue(_country) ?? 'EU';

    if (mounted) setState(() => _loading = false);
  }

  String? _firstValidationError() {
    final firstNameError = ContactFieldsValidators.validateRequiredName(
      _first.text,
      fieldTitle: 'Имя',
    );
    if (firstNameError != null) return firstNameError;

    final lastNameError = ContactFieldsValidators.validateRequiredName(
      _last.text,
      fieldTitle: 'Фамилия',
    );
    if (lastNameError != null) return lastNameError;

    final emailError = ContactFieldsValidators.validateEmail(_email.text);
    if (emailError != null) return emailError;

    final phoneError = ContactFieldsValidators.validatePhone(_phoneNumber.text);
    if (phoneError != null) return phoneError;

    if ((_country ?? '').trim().isEmpty) return 'Выберите страну';
    if ((_gender ?? '').isEmpty) return 'Выберите пол';
    if (_birthDate == null) return 'Выберите дату рождения';

    return null;
  }

  bool get _canSave {
    final fn = _first.text.trim();
    final ln = _last.text.trim();
    final em = _email.text.trim();
    final ph = ContactFieldsValidators.normalizeDigits(_phoneNumber.text);
    final c = (_country ?? '').trim();

    return !_saving &&
        ContactFieldsValidators.isNameValid(fn) &&
        ContactFieldsValidators.isNameValid(ln) &&
        ContactFieldsValidators.isEmailValid(em) &&
        ContactFieldsValidators.isPhoneValid(ph) &&
        c.isNotEmpty &&
        (_gender ?? '').isNotEmpty &&
        _birthDate != null;
  }

  InputDecoration _deco(String label, {IconData? icon, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: WorkaColors.textGreyDark,
      ),
      hintStyle: const TextStyle(
        color: WorkaColors.textGrey,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: icon == null ? null : Icon(icon, color: WorkaColors.blue),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
      ),
    );
  }

  Theme _whiteDropdownTheme(BuildContext context, Widget child) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        canvasColor: Colors.white,
        dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
        highlightColor: WorkaColors.hoverBlueSoft,
        splashColor: WorkaColors.hoverBlueSoft,
        hoverColor: WorkaColors.hoverBlueSoft,
        colorScheme: base.colorScheme.copyWith(
          surface: Colors.white,
          onSurface: WorkaColors.textGreyDark,
          primary: WorkaColors.blue,
        ),
      ),
      child: child,
    );
  }

  Widget _citizenshipDropdown() {
    final value = _normalizeCitizenshipValue(_country);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Гражданство *',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded),
          items: _citizenshipValues
              .map(
                (v) => DropdownMenuItem<String>(
                  value: v,
                  child: Text(_citizenshipLabels[v] ?? v),
                ),
              )
              .toList(),
          onChanged: _saving ? null : (v) => setState(() => _country = v),
          decoration: InputDecoration(
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial = _birthDate ?? DateTime(now.year - 25, 1, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year - 14, now.month, now.day),
      builder: (ctx, child) {
        final base = Theme.of(ctx);
        return Theme(
          data: base.copyWith(
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
            colorScheme: base.colorScheme.copyWith(
              primary: WorkaColors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: WorkaColors.textGreyDark,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: WorkaColors.blue,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    setState(
      () => _birthDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  Future<void> _save() async {
    if (!_canSave) {
      _toast(_firstValidationError() ?? 'Заполните все обязательные поля (*)');
      return;
    }

    var ref = _ref;
    if (ref == null) {
      final uid = await getEffectiveUid(ensureAnonymousIfMissing: true);
      if (uid != null && uid.isNotEmpty) {
        ref = _db.collection('users').doc(uid);
      }
    }
    if (ref == null) {
      _toast('Не удалось определить пользователя. Попробуйте ещё раз.');
      return;
    }

    setState(() => _saving = true);
    try {
      final citizenshipName = (_country ?? '').trim();
      final citizenshipIso = _countryIsoByName(citizenshipName);
      final whatsapp = _cleanOptionalContact(_whatsapp.text);
      final telegram = _cleanOptionalContact(_telegram.text);
      final viber = _cleanOptionalContact(_viber.text);
      final messenger = _cleanOptionalContact(_messenger.text);
      await ref.set({
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'email': _email.text.trim(),
        'phoneCountryCode': _phoneCountryCode,
        'phoneNumber': ContactFieldsValidators.normalizeDigits(
          _phoneNumber.text,
        ),
        'phone':
            '$_phoneCountryCode${ContactFieldsValidators.normalizeDigits(_phoneNumber.text)}',
        'gender': _gender,
        'birthDate': Timestamp.fromDate(_birthDate!),
        'citizenshipName': citizenshipName,
        'citizenshipIso': citizenshipIso,
        'countryName': citizenshipName,
        'country': citizenshipName,
        'countryIso': citizenshipIso,
        'city': _cityCtrl.text.trim(),
        'whatsapp': whatsapp ?? FieldValue.delete(),
        'telegram': telegram ?? FieldValue.delete(),
        'viber': viber ?? FieldValue.delete(),
        'messenger': messenger ?? FieldValue.delete(),
        'contacts.whatsapp': whatsapp ?? FieldValue.delete(),
        'contacts.telegram': telegram ?? FieldValue.delete(),
        'contacts.viber': viber ?? FieldValue.delete(),
        'contacts.messenger': messenger ?? FieldValue.delete(),
        'socialLinks.whatsapp': whatsapp ?? FieldValue.delete(),
        'socialLinks.telegram': telegram ?? FieldValue.delete(),
        'socialLinks.viber': viber ?? FieldValue.delete(),
        'socialLinks.messenger': messenger ?? FieldValue.delete(),
        'personal': {
          'firstName': _first.text.trim(),
          'lastName': _last.text.trim(),
          'email': _email.text.trim(),
          'phoneCountryCode': _phoneCountryCode,
          'phoneNumber': ContactFieldsValidators.normalizeDigits(
            _phoneNumber.text,
          ),
          'phone':
              '$_phoneCountryCode${ContactFieldsValidators.normalizeDigits(_phoneNumber.text)}',
          'gender': _gender,
          'birthDate': Timestamp.fromDate(_birthDate!),
          'citizenshipName': citizenshipName,
          'citizenshipIso': citizenshipIso,
          'countryName': citizenshipName,
          'country': citizenshipName,
          'countryIso': citizenshipIso,
          'city': _cityCtrl.text.trim(),
          'whatsapp': whatsapp ?? FieldValue.delete(),
          'telegram': telegram ?? FieldValue.delete(),
          'viber': viber ?? FieldValue.delete(),
          'messenger': messenger ?? FieldValue.delete(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'personalProfileCompleted': true,
        'personalProfileCompletedAt': FieldValue.serverTimestamp(),
        if (widget.isInitialFill) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      widget.onSaved?.call();

      if (!mounted) return;

      if (!widget.isInitialFill) {
        Navigator.pop(context, true);
      } else {
        AppMode.setMode(AccountMode.personal);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    final title = widget.isInitialFill
        ? 'Заполните профиль'
        : 'Редактирование аккаунта';

    return _whiteDropdownTheme(
      context,
      Scaffold(
        backgroundColor: const Color(0xFF4A6FDB),
        body: Column(
          children: [
            WorkaHeader(
              title: title,
              leading: widget.isInitialFill
                  ? null
                  : IconButton(
                      onPressed: () => Navigator.maybePop(context),
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    Form(
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: ContactFields(
                        firstNameController: _first,
                        lastNameController: _last,
                        emailController: _email,
                        phoneNumberController: _phoneNumber,
                        phoneCountryCode: _phoneCountryCode,
                        onPhoneCountryCodeChanged: (v) =>
                            setState(() => _phoneCountryCode = v),
                        onChanged: () => setState(() {}),
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _whatsapp,
                      enabled: !_saving,
                      decoration: _deco(
                        'WhatsApp',
                        icon: FontAwesomeIcons.whatsapp,
                        hint: '+372...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _telegram,
                      enabled: !_saving,
                      decoration: _deco(
                        'Telegram',
                        icon: FontAwesomeIcons.telegram,
                        hint: '@username',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _viber,
                      enabled: !_saving,
                      decoration: _deco(
                        'Viber',
                        icon: FontAwesomeIcons.viber,
                        hint: '+372...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _messenger,
                      enabled: !_saving,
                      decoration: _deco(
                        'Messenger',
                        icon: FontAwesomeIcons.facebookMessenger,
                        hint: 'm.me/username',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _citizenshipDropdown(),
                    const SizedBox(height: 12),
                    _CityAutocomplete(
                      controller: _cityCtrl,
                      hints: _cityHints,
                      label: 'Город (по желанию)',
                    ),
                    const SizedBox(height: 12),
                    _Chips(
                      label: 'Пол *',
                      values: const ['Мужчина', 'Женщина'],
                      selected: _gender == 'female'
                          ? 'Женщина'
                          : _gender == 'male'
                          ? 'Мужчина'
                          : null,
                      onTap: (v) => setState(
                        () => _gender = v == 'Женщина' ? 'female' : 'male',
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickBirthDate,
                      borderRadius: BorderRadius.circular(16),
                      child: InputDecorator(
                        decoration: _deco(
                          'Дата рождения *',
                          icon: Icons.cake_outlined,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _birthDate == null
                                    ? 'Выбрать дату'
                                    : _formatDate(_birthDate!),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: WorkaColors.textGreyDark,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.calendar_month_outlined,
                              color: WorkaColors.orange,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _canSave ? _save : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.orange,
                          disabledBackgroundColor: WorkaColors.orange
                              .withValues(alpha: 0.35),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Сохранить',
                                style: TextStyle(
                                  color: Colors.white,
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
    );
  }
}

class _CityAutocomplete extends StatelessWidget {
  final TextEditingController controller;
  final List<String> hints;
  final String label;

  const _CityAutocomplete({
    required this.controller,
    required this.hints,
    required this.label,
  });

  InputDecoration _deco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: WorkaColors.textGreyDark,
      ),
      hintStyle: const TextStyle(
        color: WorkaColors.textGrey,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: const Icon(
        Icons.location_city_outlined,
        color: WorkaColors.blue,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (t) {
        final q = t.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return hints.where((e) => e.toLowerCase().contains(q)).take(30);
      },
      fieldViewBuilder: (ctx, textCtrl, focusNode, _) {
        textCtrl.text = controller.text;
        textCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: textCtrl.text.length),
        );
        textCtrl.addListener(() => controller.text = textCtrl.text);

        return TextField(
          controller: textCtrl,
          focusNode: focusNode,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: WorkaColors.textGreyDark,
          ),
          decoration: _deco(label),
        );
      },
      onSelected: (v) => controller.text = v,
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.white,
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final opt = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    hoverColor: WorkaColors.hoverBlueSoft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Text(
                        opt,
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
    );
  }
}

class _Chips extends StatelessWidget {
  final String label;
  final List<String> values;
  final String? selected;
  final ValueChanged<String> onTap;

  const _Chips({
    required this.label,
    required this.values,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: values.map((v) {
            final isSelected = v == selected;
            return InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onTap(v),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? WorkaColors.hoverBlueSoft : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected
                        ? WorkaColors.blue
                        : WorkaColors.fieldBorder,
                    width: 1.2,
                  ),
                ),
                child: Text(
                  v,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                    color: WorkaColors.textGreyDark,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
