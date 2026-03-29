// ✅ EDIT_ACCOUNT_SCREEN_V2

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/widgets/contact_fields.dart';
import 'package:worka/widgets/worka_header.dart';

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key});

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _email = TextEditingController();
  final _whatsapp = TextEditingController();
  final _telegram = TextEditingController();
  final _viber = TextEditingController();
  final _messenger = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _phoneCountryCode = '+372';

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstName.addListener(() => setState(() {}));
    _lastName.addListener(() => setState(() {}));
    _phoneNumber.addListener(() => setState(() {}));
    _email.addListener(() => setState(() {}));
    _whatsapp.addListener(() => setState(() {}));
    _telegram.addListener(() => setState(() {}));
    _viber.addListener(() => setState(() {}));
    _messenger.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phoneNumber.dispose();
    _email.dispose();
    _whatsapp.dispose();
    _telegram.dispose();
    _viber.dispose();
    _messenger.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  String _s(dynamic v) => (v ?? '').toString().trim();
  String? _cleanOptionalContact(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    return value;
  }

  ContactFieldsData _data() {
    return ContactFieldsData(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      email: _email.text.trim(),
      phoneCountryCode: _phoneCountryCode,
      phoneNumber: ContactFieldsValidators.normalizeDigits(_phoneNumber.text),
    );
  }

  Future<void> _load() async {
    final u = _auth.currentUser;
    if (u == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final snap = await _db.collection('users').doc(u.uid).get();
      final m = snap.data() ?? {};
      final contacts = (m['contacts'] is Map)
          ? Map<String, dynamic>.from(m['contacts'] as Map)
          : const <String, dynamic>{};
      final socialLinks = (m['socialLinks'] is Map)
          ? Map<String, dynamic>.from(m['socialLinks'] as Map)
          : const <String, dynamic>{};
      final business = (m['business'] is Map)
          ? Map<String, dynamic>.from(m['business'] as Map)
          : const <String, dynamic>{};

      _firstName.text = _s(m['firstName']).isNotEmpty
          ? _s(m['firstName'])
          : _s(m['name']);
      _lastName.text = _s(m['lastName']);
      _email.text = _s(m['email']).isNotEmpty ? _s(m['email']) : _s(u.email);

      final storedCode = _s(m['phoneCountryCode']);
      final storedNum = ContactFieldsValidators.normalizeDigits(
        _s(m['phoneNumber']),
      );
      if (storedCode.isNotEmpty && storedNum.isNotEmpty) {
        _phoneCountryCode = storedCode;
        _phoneNumber.text = storedNum;
      } else {
        final parsed = ContactFieldsValidators.parseStoredPhone(
          _s(m['phone']).isNotEmpty ? _s(m['phone']) : _s(u.phoneNumber),
        );
        _phoneCountryCode = parsed.countryCode;
        _phoneNumber.text = parsed.number;
      }

      String pick(String key) {
        final values = <String>[
          _s(m[key]),
          _s(contacts[key]),
          _s(socialLinks[key]),
          _s(business[key]),
        ];
        for (final value in values) {
          if (value.isNotEmpty) return value;
        }
        return '';
      }

      _whatsapp.text = pick('whatsapp');
      _telegram.text = pick('telegram');
      _viber.text = pick('viber');
      _messenger.text = pick('messenger');
    } catch (e) {
      _toast('Ошибка загрузки: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final u = _auth.currentUser;
    if (u == null) return;

    final data = _data();
    if (!data.isValid || !(_formKey.currentState?.validate() ?? false)) {
      _toast('Проверьте корректность контактных данных');
      return;
    }

    setState(() => _saving = true);
    try {
      final whatsapp = _cleanOptionalContact(_whatsapp.text);
      final telegram = _cleanOptionalContact(_telegram.text);
      final viber = _cleanOptionalContact(_viber.text);
      final messenger = _cleanOptionalContact(_messenger.text);
      await _db.collection('users').doc(u.uid).set({
        'firstName': data.firstName,
        'lastName': data.lastName,
        'phoneCountryCode': data.phoneCountryCode,
        'phoneNumber': data.phoneNumber,
        'phone': data.phoneE164,
        'email': data.email,
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
        'business.whatsapp': whatsapp ?? FieldValue.delete(),
        'business.telegram': telegram ?? FieldValue.delete(),
        'business.viber': viber ?? FieldValue.delete(),
        'business.messenger': messenger ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _toast('Аккаунт обновлён ✅');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Редактировать аккаунт',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
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
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                      children: [
                        Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: ContactFields(
                            firstNameController: _firstName,
                            lastNameController: _lastName,
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
                          decoration: InputDecoration(
                            labelText: 'WhatsApp',
                            hintText: '+372...',
                            prefixIcon: const FaIcon(
                              FontAwesomeIcons.whatsapp,
                              color: WorkaColors.blue,
                              size: 18,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
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
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _telegram,
                          enabled: !_saving,
                          decoration: InputDecoration(
                            labelText: 'Telegram',
                            hintText: '@username',
                            prefixIcon: const FaIcon(
                              FontAwesomeIcons.telegram,
                              color: WorkaColors.blue,
                              size: 18,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
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
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _viber,
                          enabled: !_saving,
                          decoration: InputDecoration(
                            labelText: 'Viber',
                            hintText: '+372...',
                            prefixIcon: const FaIcon(
                              FontAwesomeIcons.viber,
                              color: WorkaColors.blue,
                              size: 18,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
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
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _messenger,
                          enabled: !_saving,
                          decoration: InputDecoration(
                            labelText: 'Messenger',
                            hintText: 'm.me/username',
                            prefixIcon: const FaIcon(
                              FontAwesomeIcons.facebookMessenger,
                              color: WorkaColors.blue,
                              size: 18,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
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
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _saving || !_data().isValid
                                ? null
                                : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: WorkaColors.orange,
                              foregroundColor: WorkaColors.onColored,
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
                                    ),
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
            ),
          ),
        ],
      ),
    );
  }
}
