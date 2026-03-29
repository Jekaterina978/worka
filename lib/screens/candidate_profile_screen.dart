import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/worka_colors.dart';
import '../widgets/contact_fields.dart';
import '../services/firestore_paths.dart';

class CandidateProfileScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String city;
  final String country;
  final String phone;

  const CandidateProfileScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.city,
    required this.country,
    required this.phone,
  });

  @override
  State<CandidateProfileScreen> createState() => _CandidateProfileScreenState();
}

class _CandidateProfileScreenState extends State<CandidateProfileScreen> {
  final _auth = FirebaseAuth.instance;

  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _email;
  late final TextEditingController _phoneNumber;
  late final TextEditingController _city;
  late String _country;
  String _phoneCountryCode = '+372';

  final _profession = TextEditingController();
  final _about = TextEditingController();

  String _gender = 'male'; // male | female
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _first = TextEditingController(text: widget.firstName);
    _last = TextEditingController(text: widget.lastName);
    _email = TextEditingController(text: widget.email);
    final parsed = ContactFieldsValidators.parseStoredPhone(widget.phone);
    _phoneCountryCode = parsed.countryCode;
    _phoneNumber = TextEditingController(text: parsed.number);
    _city = TextEditingController(text: widget.city);
    _country = widget.country;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phoneNumber.dispose();
    _city.dispose();
    _profession.dispose();
    _about.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  InputDecoration _deco(String label, {String? hint, required IconData icon, Widget? iconWidget}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: WorkaColors.textGreyDark,
      ),
      hintStyle: const TextStyle(color: WorkaColors.textGrey),
      prefixIcon: iconWidget ?? Icon(icon, color: WorkaColors.blue),
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

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? WorkaColors.hoverBlueSoft : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? WorkaColors.blue : WorkaColors.textDark,
            width: 1.2,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            color: WorkaColors.textDark,
          ),
        ),
      ),
    );
  }

  IconData get _genderIcon => _gender == 'female' ? Icons.woman : Icons.man;

  Future<void> _save() async {
    final user = _auth.currentUser;
    if (user == null) {
      _toast('Сначала войдите по SMS.');
      return;
    }

    final fn = _first.text.trim();
    final ln = _last.text.trim();
    final em = _email.text.trim();
    final phoneDigits = ContactFieldsValidators.normalizeDigits(
      _phoneNumber.text,
    );
    final phoneE164 = '$_phoneCountryCode$phoneDigits';
    final city = _city.text.trim();
    final prof = _profession.text.trim();
    final about = _about.text.trim();

    if (!ContactFieldsValidators.isNameValid(fn) ||
        !ContactFieldsValidators.isNameValid(ln) ||
        !ContactFieldsValidators.isEmailValid(em) ||
        !ContactFieldsValidators.isPhoneValid(phoneDigits)) {
      _toast('Проверьте корректность контактных данных.');
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = user.uid;

      final token = await user.getIdToken();
      final base = const String.fromEnvironment(
      'WORKA_API_BASE_URL',
      defaultValue: '',
    ).trim();
    assert(baseUrl.isNotEmpty, 'WORKA_API_BASE_URL is required');
      final normalizedBase = base.endsWith('/api') ? base : '$base/api';
      final uri = Uri.parse('$normalizedBase/candidates/cv');
      final payload = {
        'candidateId': uid,
        'ownerId': uid,
        'ownerUid': uid,
        'uid': uid,
        'name': '$fn $ln',
        'firstName': fn,
        'lastName': ln,
        'email': em,
        'phoneCountryCode': _phoneCountryCode,
        'phoneNumber': phoneDigits,
        'phone': phoneE164,
        'gender': _gender,
        'city': city,
        'country': _country,
        'profession': prof,
        'about': about,
        'cvCount': 1,
      };

      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final body = resp.body.trim();
        throw StateError(
          'Не удалось сохранить профиль кандидата: '
          '${body.isNotEmpty ? body : 'status=${resp.statusCode}'}',
        );
      }

      if (!mounted) return;

      _toast('Профиль сохранён ✅');

      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    } catch (e) {
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: WorkaColors.hoverBlueSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: WorkaColors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WorkaColors.divider),
                  ),
                  child: Icon(_genderIcon, color: WorkaColors.blue, size: 30),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Заполните профиль — это нужно, чтобы работодатели могли вас найти.',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: WorkaColors.textDark,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

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

          const Text(
            'Пол',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: WorkaColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              _chip(
                'Мужчина',
                _gender == 'male',
                () => setState(() => _gender = 'male'),
              ),
              _chip(
                'Женщина',
                _gender == 'female',
                () => setState(() => _gender = 'female'),
              ),
            ],
          ),

          const SizedBox(height: 14),

          TextField(
            controller: _city,
            decoration: _deco(
              'Город',
              hint: 'Например: Tallinn',
              icon: Icons.location_on_outlined,
            ),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: () async {
              // простой ввод страны (MVP). Можно заменить на твой picker.
              final res = await _askText(context, 'Страна', _country);
              if (res == null) return;
              setState(() => _country = res.isEmpty ? _country : res);
            },
            borderRadius: BorderRadius.circular(16),
            child: InputDecorator(
              decoration: _deco('Страна', icon: Icons.public_rounded, iconWidget: const Center(widthFactor: 0, child: Text('🌍', style: TextStyle(fontSize: 18)))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _country,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: WorkaColors.textDark,
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

          const SizedBox(height: 12),

          TextField(
            controller: _profession,
            decoration: _deco(
              'Профессия',
              hint: 'Например: Сварщик',
              icon: Icons.work_outline,
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: _about,
            maxLines: 5,
            decoration: _deco(
              'О себе',
              hint: 'Коротко: опыт, навыки, график…',
              icon: Icons.description_outlined,
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            height: 56,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.orange,
                foregroundColor: WorkaColors.onColored,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Сохранить',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askText(BuildContext context, String title, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: WorkaColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(hintText: 'Введите значение'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: WorkaColors.orange,
                  foregroundColor: WorkaColors.onColored,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Готово',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
