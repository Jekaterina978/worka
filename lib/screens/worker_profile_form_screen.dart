import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';
import '../utils/country_display_formatter.dart';
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
  String _phoneCountryCode = '+372';

  String? _gender; // 'male' | 'female'
  DateTime? _birthDate;

  String? _country; // обязательная
  final _cityCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  // ✅ встроенные данные (без SearchFiltersConfig)
  final List<String> _countries = const [
    'Австрия',
    'Азербайджан',
    'Армения',
    'Беларусь',
    'Бельгия',
    'Болгария',
    'Венгрия',
    'Германия',
    'Греция',
    'Грузия',
    'Дания',
    'Ирландия',
    'Исландия',
    'Испания',
    'Италия',
    'Казахстан',
    'Кипр',
    'Киргизстан',
    'Латвия',
    'Литва',
    'Люксембург',
    'Мальта',
    'Молдова',
    'Нидерланды',
    'Норвегия',
    'Польша',
    'Португалия',
    'Россия',
    'Румыния',
    'Словакия',
    'Словения',
    'Таджикистан',
    'Туркменистан',
    'Украина',
    'Узбекистан',
    'Финляндия',
    'Франция',
    'Хорватия',
    'Чехия',
    'Швеция',
    'Эстония',
  ];

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

  String? get _uid => _auth.currentUser?.uid;

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
    _cityCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phoneNumber.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  String _formatDate(DateTime d) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

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

    _first.text = _s(m['firstName']);
    _last.text = _s(m['lastName']);
    _email.text = _s(m['email']);

    final authPhone = (_auth.currentUser?.phoneNumber ?? '').trim();
    final storedPhone = _s(m['phone']);
    final storedCountryCode = _s(m['phoneCountryCode']);
    final storedPhoneNumber = ContactFieldsValidators.normalizeDigits(
      _s(m['phoneNumber']),
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

    _gender = _s(m['gender']);

    final bd = m['birthDate'];
    if (bd is Timestamp) _birthDate = bd.toDate();

    _country = _s(m['citizenshipName']);
    if (_country == null || _country!.isEmpty) {
      _country = _s(m['citizenshipCountry']);
    }
    if (_country == null || _country!.isEmpty) {
      _country = _s(m['country']);
    }
    _cityCtrl.text = _s(m['city']);

    if ((_country ?? '').isEmpty) {
      _country = _countries.contains('Эстония') ? 'Эстония' : _countries.first;
    }

    if (mounted) setState(() => _loading = false);
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
      _toast('Заполните все обязательные поля (*)');
      return;
    }

    final ref = _ref;
    if (ref == null) {
      _toast('Нужно войти, чтобы сохранить профиль');
      return;
    }

    setState(() => _saving = true);
    try {
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
        'country': (_country ?? '').trim(),
        'countryName': (_country ?? '').trim(),
        'citizenshipName': (_country ?? '').trim(),
        'citizenshipCountry': (_country ?? '').trim(),
        'city': _cityCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (widget.isInitialFill) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      widget.onSaved?.call();

      if (!mounted) return;

      if (!widget.isInitialFill) {
        Navigator.pop(context, true);
      } else {
        Navigator.pop(
          context,
          true,
        ); // ✅ важно: возвращаем true для VacancyDetails
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
                  _CountryDropdown(
                    label: 'Локация (страна) *',
                    value: (_country ?? '').isEmpty ? null : _country,
                    items: _countries,
                    onChanged: (v) => setState(() => _country = v),
                  ),
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
                        disabledBackgroundColor: WorkaColors.orange.withValues(alpha: 0.35),
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

class _CountryDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _CountryDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
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
        InputDecorator(
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
              horizontal: 12,
              vertical: 6,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              dropdownColor: Colors.white,
              iconEnabledColor: WorkaColors.textGreyDark,
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
              ),
              hint: const Text(
                'Выберите страну',
                style: TextStyle(color: WorkaColors.textGrey),
              ),
              items: items.map((e) {
                final flag = CountryDisplayFormatter.countryFlagOnly(e, euAsToken: false);
                return DropdownMenuItem(
                  value: e,
                  child: Row(
                    children: [
                      if (flag.isNotEmpty) ...[
                        Text(flag, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        e,
                        style: const TextStyle(
                          color: WorkaColors.textGreyDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
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
