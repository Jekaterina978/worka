import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/worka_colors.dart';

class DialCodeOption {
  final String country;
  final String code;
  final String flag;

  const DialCodeOption({
    required this.country,
    required this.code,
    required this.flag,
  });
}

class ContactFieldsData {
  final String firstName;
  final String lastName;
  final String email;
  final String phoneCountryCode;
  final String phoneNumber;

  const ContactFieldsData({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneCountryCode,
    required this.phoneNumber,
  });

  String get phoneE164 => '$phoneCountryCode$phoneNumber';

  bool get isValid {
    return ContactFieldsValidators.isNameValid(firstName) &&
        ContactFieldsValidators.isNameValid(lastName) &&
        ContactFieldsValidators.isEmailValid(email) &&
        ContactFieldsValidators.isPhoneValid(phoneNumber);
  }
}

class ParsedPhone {
  final String countryCode;
  final String number;

  const ParsedPhone({required this.countryCode, required this.number});
}

class ContactFieldsValidators {
  static final RegExp _emailRegExp = RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

  static String normalizeDigits(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  static bool isNameValid(String value) {
    return value.trim().length >= 2;
  }

  static bool isEmailValid(String value) {
    final v = value.trim();
    if (v.contains(' ')) return false;
    return _emailRegExp.hasMatch(v);
  }

  static bool isPhoneValid(String value) {
    return normalizeDigits(value).length >= 6;
  }

  static String? validateRequiredName(String? value, {required String fieldTitle}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$fieldTitle обязательно';
    if (v.length < 2) return '$fieldTitle должно содержать минимум 2 символа';
    return null;
  }

  static String? validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Эл. почта обязательна';
    if (!isEmailValid(v)) {
      return 'Введите корректный email, например name@example.com';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    final digits = normalizeDigits(value ?? '');
    if (digits.isEmpty) return 'Телефон обязателен';
    if (digits.length < 6) return 'Введите корректный телефон';
    return null;
  }

  static ParsedPhone parseStoredPhone(String raw, {String fallbackCountryCode = '+372'}) {
    final value = raw.trim();
    if (value.isEmpty) {
      return ParsedPhone(countryCode: fallbackCountryCode, number: '');
    }

    final matched = defaultDialCodes.where((d) => value.startsWith(d.code)).toList();
    if (matched.isNotEmpty) {
      final d = matched.first;
      final number = normalizeDigits(value.substring(d.code.length));
      return ParsedPhone(countryCode: d.code, number: number);
    }

    final digits = normalizeDigits(value);
    return ParsedPhone(countryCode: fallbackCountryCode, number: digits);
  }
}

const List<DialCodeOption> defaultDialCodes = [
  DialCodeOption(country: 'Австрия', code: '+43', flag: '🇦🇹'),
  DialCodeOption(country: 'Азербайджан', code: '+994', flag: '🇦🇿'),
  DialCodeOption(country: 'Армения', code: '+374', flag: '🇦🇲'),
  DialCodeOption(country: 'Беларусь', code: '+375', flag: '🇧🇾'),
  DialCodeOption(country: 'Бельгия', code: '+32', flag: '🇧🇪'),
  DialCodeOption(country: 'Болгария', code: '+359', flag: '🇧🇬'),
  DialCodeOption(country: 'Венгрия', code: '+36', flag: '🇭🇺'),
  DialCodeOption(country: 'Германия', code: '+49', flag: '🇩🇪'),
  DialCodeOption(country: 'Греция', code: '+30', flag: '🇬🇷'),
  DialCodeOption(country: 'Грузия', code: '+995', flag: '🇬🇪'),
  DialCodeOption(country: 'Дания', code: '+45', flag: '🇩🇰'),
  DialCodeOption(country: 'Ирландия', code: '+353', flag: '🇮🇪'),
  DialCodeOption(country: 'Исландия', code: '+354', flag: '🇮🇸'),
  DialCodeOption(country: 'Испания', code: '+34', flag: '🇪🇸'),
  DialCodeOption(country: 'Италия', code: '+39', flag: '🇮🇹'),
  DialCodeOption(country: 'Казахстан', code: '+7', flag: '🇰🇿'),
  DialCodeOption(country: 'Кипр', code: '+357', flag: '🇨🇾'),
  DialCodeOption(country: 'Киргизстан', code: '+996', flag: '🇰🇬'),
  DialCodeOption(country: 'Латвия', code: '+371', flag: '🇱🇻'),
  DialCodeOption(country: 'Литва', code: '+370', flag: '🇱🇹'),
  DialCodeOption(country: 'Люксембург', code: '+352', flag: '🇱🇺'),
  DialCodeOption(country: 'Мальта', code: '+356', flag: '🇲🇹'),
  DialCodeOption(country: 'Молдова', code: '+373', flag: '🇲🇩'),
  DialCodeOption(country: 'Нидерланды', code: '+31', flag: '🇳🇱'),
  DialCodeOption(country: 'Норвегия', code: '+47', flag: '🇳🇴'),
  DialCodeOption(country: 'Польша', code: '+48', flag: '🇵🇱'),
  DialCodeOption(country: 'Португалия', code: '+351', flag: '🇵🇹'),
  DialCodeOption(country: 'Россия', code: '+7', flag: '🇷🇺'),
  DialCodeOption(country: 'Румыния', code: '+40', flag: '🇷🇴'),
  DialCodeOption(country: 'Словакия', code: '+421', flag: '🇸🇰'),
  DialCodeOption(country: 'Словения', code: '+386', flag: '🇸🇮'),
  DialCodeOption(country: 'Таджикистан', code: '+992', flag: '🇹🇯'),
  DialCodeOption(country: 'Туркменистан', code: '+993', flag: '🇹🇲'),
  DialCodeOption(country: 'Украина', code: '+380', flag: '🇺🇦'),
  DialCodeOption(country: 'Узбекистан', code: '+998', flag: '🇺🇿'),
  DialCodeOption(country: 'Финляндия', code: '+358', flag: '🇫🇮'),
  DialCodeOption(country: 'Франция', code: '+33', flag: '🇫🇷'),
  DialCodeOption(country: 'Хорватия', code: '+385', flag: '🇭🇷'),
  DialCodeOption(country: 'Чехия', code: '+420', flag: '🇨🇿'),
  DialCodeOption(country: 'Швеция', code: '+46', flag: '🇸🇪'),
  DialCodeOption(country: 'Эстония', code: '+372', flag: '🇪🇪'),
];

class ContactFields extends StatelessWidget {
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController phoneNumberController;
  final String phoneCountryCode;
  final ValueChanged<String> onPhoneCountryCodeChanged;
  final VoidCallback? onChanged;
  final bool enabled;

  const ContactFields({
    super.key,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.phoneNumberController,
    required this.phoneCountryCode,
    required this.onPhoneCountryCodeChanged,
    this.onChanged,
    this.enabled = true,
  });

  ContactFieldsData getData() {
    return ContactFieldsData(
      firstName: firstNameController.text.trim(),
      lastName: lastNameController.text.trim(),
      email: emailController.text.trim(),
      phoneCountryCode: phoneCountryCode,
      phoneNumber: ContactFieldsValidators.normalizeDigits(phoneNumberController.text),
    );
  }

  InputDecoration _deco(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: WorkaColors.textGreyDark),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  Future<void> _pickCountryCode(BuildContext context) async {
    final selected = defaultDialCodes.firstWhere(
      (d) => d.code == phoneCountryCode,
      orElse: () => defaultDialCodes.first,
    );

    final picked = await showModalBottomSheet<DialCodeOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        final insets = MediaQuery.of(ctx).viewInsets.bottom;
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + insets),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Код страны',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: WorkaColors.textDark),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: defaultDialCodes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: WorkaColors.divider),
                      itemBuilder: (_, i) {
                        final c = defaultDialCodes[i];
                        final isSelected = c.code == selected.code;
                        final textColor = isSelected ? WorkaColors.blue : WorkaColors.textGreyDark;
                        return InkWell(
                          onTap: () => Navigator.pop(ctx, c),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Text(c.flag, style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 6),
                                Text(c.code, style: TextStyle(fontWeight: FontWeight.w900, color: textColor)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    c.country,
                                    style: TextStyle(fontWeight: FontWeight.w800, color: textColor),
                                  ),
                                ),
                                if (isSelected) const Icon(Icons.check, color: WorkaColors.blue),
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
          ),
        );
      },
    );

    if (picked != null) {
      onPhoneCountryCodeChanged(picked.code);
      onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: firstNameController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          decoration: _deco('Имя *', icon: Icons.badge_outlined),
          onChanged: (_) => onChanged?.call(),
          validator: (v) => ContactFieldsValidators.validateRequiredName(v, fieldTitle: 'Имя'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: lastNameController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          decoration: _deco('Фамилия *', icon: Icons.account_circle_outlined),
          onChanged: (_) => onChanged?.call(),
          validator: (v) => ContactFieldsValidators.validateRequiredName(v, fieldTitle: 'Фамилия'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: emailController,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _deco('Эл. почта *', icon: Icons.email_outlined),
          onChanged: (_) => onChanged?.call(),
          validator: ContactFieldsValidators.validateEmail,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            InkWell(
              onTap: enabled ? () => _pickCountryCode(context) : null,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: WorkaColors.fieldBorder),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      defaultDialCodes.firstWhere((d) => d.code == phoneCountryCode, orElse: () => defaultDialCodes.first).flag,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(phoneCountryCode, style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textDark)),
                    const Icon(Icons.keyboard_arrow_down, color: WorkaColors.textGreyDark),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: phoneNumberController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                decoration: _deco('Телефон *', icon: Icons.phone_outlined),
                onChanged: (_) => onChanged?.call(),
                validator: ContactFieldsValidators.validatePhone,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
