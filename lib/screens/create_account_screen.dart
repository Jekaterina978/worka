import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/worka_colors.dart';
import '../widgets/contact_fields.dart';
import '../widgets/phone_input_field.dart';
import '../widgets/worka_header.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _saving = false;
  bool _passwordObscured = true;
  bool _confirmPasswordObscured = true;
  String _phoneCountryCode = '+372';

  // Центровка: двигаем ВЕСЬ блок так, чтобы КНОПКА "Создать" была по центру экрана
  final GlobalKey _blockKey = GlobalKey();
  final GlobalKey _buttonKey = GlobalKey();
  double _shiftY = 0;

  @override
  void initState() {
    super.initState();
    _first.addListener(() => setState(() {}));
    _last.addListener(() => setState(() {}));
    _email.addListener(() => setState(() {}));
    _phoneNumber.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillPhoneIfPossible();
      _recenterBlock();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recenterBlock());
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phoneNumber.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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

  Future<void> _prefillPhoneIfPossible() async {
    final u = _auth.currentUser;
    if (u == null) return;

    final raw = (u.phoneNumber ?? '').trim();
    if (raw.isEmpty) return;

    final parsed = ContactFieldsValidators.parseStoredPhone(raw);
    setState(() {
      _phoneCountryCode = parsed.countryCode;
      _phoneNumber.text = parsed.number;
    });
  }

  ContactFieldsData _contactData() {
    return ContactFieldsData(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      email: _email.text.trim(),
      phoneCountryCode: _phoneCountryCode,
      phoneNumber: ContactFieldsValidators.normalizeDigits(_phoneNumber.text),
    );
  }

  bool get _allOk {
    final data = _contactData();
    final pass = _password.text;
    final confirm = _confirmPassword.text;
    return data.isValid && pass.length >= 6 && pass == confirm;
  }

  InputDecoration _deco(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: WorkaColors.textGreyDark,
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

  Widget _orangeButton(String text, VoidCallback onPressed) {
    return SizedBox(
      key: _buttonKey,
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _saving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: WorkaColors.orange,
          disabledBackgroundColor: WorkaColors.orange.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
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
            : Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
      ),
    );
  }

  String? _firstValidationError() {
    final first = ContactFieldsValidators.validateRequiredName(
      _first.text,
      fieldTitle: 'Имя',
    );
    if (first != null) return first;

    final last = ContactFieldsValidators.validateRequiredName(
      _last.text,
      fieldTitle: 'Фамилия',
    );
    if (last != null) return last;

    final email = ContactFieldsValidators.validateEmail(_email.text);
    if (email != null) return email;

    final phone = ContactFieldsValidators.validatePhone(_phoneNumber.text);
    if (phone != null) return phone;

    if (_password.text.trim().isEmpty) return 'Введите пароль';
    if (_password.text.length < 6) {
      return 'Пароль должен быть не короче 6 символов';
    }
    if (_confirmPassword.text.trim().isEmpty) {
      return 'Подтвердите пароль';
    }
    if (_password.text != _confirmPassword.text) return 'Пароли не совпадают';

    return null;
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || !_allOk) {
      _toast(
        _firstValidationError() ?? 'Проверьте корректность контактных данных.',
      );
      return;
    }

    final data = _contactData();

    setState(() => _saving = true);
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: data.email,
        password: _password.text,
      );
      final uid = cred.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw StateError('Не удалось создать пользователя');
      }

      await _db.collection('users').doc(uid).set({
        'firstName': data.firstName,
        'lastName': data.lastName,
        'email': data.email,
        'phone': data.phoneE164,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      _toast(AuthService.mapFirebaseAuthError(e));
    } catch (e) {
      _toast('Ошибка регистрации: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _recenterBlock() {
    if (!mounted) return;

    final btnCtx = _buttonKey.currentContext;
    if (btnCtx == null) return;
    final btnBox = btnCtx.findRenderObject();
    if (btnBox is! RenderBox) return;

    final btnTopLeft = btnBox.localToGlobal(Offset.zero);
    final btnCenterY = btnTopLeft.dy + btnBox.size.height / 2;

    final mq = MediaQuery.of(context);
    final screenCenterY =
        mq.padding.top +
        (mq.size.height - mq.padding.top - mq.padding.bottom) / 2;

    final desiredShift = (screenCenterY - btnCenterY);
    if ((desiredShift - _shiftY).abs() > 1.0) {
      setState(() => _shiftY = desiredShift);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Создать аккаунт',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          Expanded(child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Transform.translate(
            offset: Offset(0, _shiftY),
            child: Padding(
              key: _blockKey,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Создать аккаунт',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: WorkaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Все поля обязательны.',
                      style: TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _first,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      decoration: _deco('Имя *', icon: Icons.badge_outlined),
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          ContactFieldsValidators.validateRequiredName(
                            v,
                            fieldTitle: 'Имя',
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _last,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      decoration: _deco(
                        'Фамилия *',
                        icon: Icons.account_circle_outlined,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          ContactFieldsValidators.validateRequiredName(
                            v,
                            fieldTitle: 'Фамилия',
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      enabled: !_saving,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _deco(
                        'Эл. почта *',
                        icon: Icons.email_outlined,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: ContactFieldsValidators.validateEmail,
                    ),
                    const SizedBox(height: 12),
                    PhoneInputField(
                      controller: _phoneNumber,
                      countryCode: _phoneCountryCode,
                      onCountryChanged: (v) =>
                          setState(() => _phoneCountryCode = v),
                      onChanged: (_) => setState(() {}),
                      enabled: !_saving,
                      hintText: '5123 4567',
                      validator: ContactFieldsValidators.validatePhone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      enabled: !_saving,
                      obscureText: _passwordObscured,
                      textInputAction: TextInputAction.next,
                      decoration: _deco('Пароль *', icon: Icons.lock_outline)
                          .copyWith(
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _passwordObscured = !_passwordObscured,
                              ),
                              icon: Icon(
                                _passwordObscured
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: WorkaColors.textGreyDark,
                              ),
                            ),
                          ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return 'Введите пароль';
                        if (text.length < 6) {
                          return 'Пароль должен быть не короче 6 символов';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPassword,
                      enabled: !_saving,
                      obscureText: _confirmPasswordObscured,
                      textInputAction: TextInputAction.done,
                      decoration:
                          _deco(
                            'Подтвердите пароль *',
                            icon: Icons.lock_reset_outlined,
                          ).copyWith(
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _confirmPasswordObscured =
                                    !_confirmPasswordObscured,
                              ),
                              icon: Icon(
                                _confirmPasswordObscured
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: WorkaColors.textGreyDark,
                              ),
                            ),
                          ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return 'Подтвердите пароль';
                        if (text != _password.text) {
                          return 'Пароли не совпадают';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _orangeButton('Создать', _save),
                  ],
                ),
              ),
            ),
          ),
        ),
      )),
        ],
      ),
    );
  }
}
