import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../account/account_store.dart';
import '../../auth/auth_service.dart';
import '../../theme/worka_colors.dart';
import '../../ui/snack.dart';
import '../../widgets/contact_fields.dart';
import '../../widgets/worka_header.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RegisterScreen();
  }
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _passwordObscured = true;
  bool _confirmPasswordObscured = true;
  String _countryCode = '+372';

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  bool get _isValid {
    final data = ContactFieldsData(
      firstName: _firstCtrl.text.trim(),
      lastName: _lastCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phoneCountryCode: _countryCode,
      phoneNumber: ContactFieldsValidators.normalizeDigits(_phoneCtrl.text),
    );
    return data.isValid &&
        _passwordCtrl.text.length >= 6 &&
        _passwordCtrl.text == _confirmPasswordCtrl.text;
  }

  Future<void> _register() async {
    if (!_isValid || !(_formKey.currentState?.validate() ?? false)) {
      UiSnack.show(context, 'Проверьте корректность контактных данных');
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      final uid = cred.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw StateError('Не удалось создать пользователя');
      }

      final createdUser = cred.user ?? FirebaseAuth.instance.currentUser;
      if (createdUser != null) {
        await AccountStore.addOrUpdateFromFirebaseUser(
          createdUser,
          provider: 'password',
        );
      }

      final payload = <String, dynamic>{
        'firstName': _firstCtrl.text.trim(),
        'lastName': _lastCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone':
            '$_countryCode${ContactFieldsValidators.normalizeDigits(_phoneCtrl.text)}',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(payload, SetOptions(merge: true));
      } on FirebaseException catch (e) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Аккаунт создан, но профиль не сохранён. Повторить?'),
            backgroundColor: WorkaColors.textDark,
            action: SnackBarAction(
              label: 'Повторить',
              textColor: Colors.white,
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .set(payload, SetOptions(merge: true));
              },
            ),
          ),
        );
        debugPrint('[RegisterScreen] profile save failed: ${e.message}');
      }

      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on FirebaseAuthException catch (e) {
      UiSnack.show(context, AuthService.mapFirebaseAuthError(e));
    } catch (e) {
      UiSnack.show(context, 'Ошибка регистрации: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          children: [
            const Text(
              'Создать аккаунт',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: WorkaColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Заполните данные профиля',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: WorkaColors.textGreyDark,
              ),
            ),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ContactFields(
                firstNameController: _firstCtrl,
                lastNameController: _lastCtrl,
                emailController: _emailCtrl,
                phoneNumberController: _phoneCtrl,
                phoneCountryCode: _countryCode,
                onPhoneCountryCodeChanged: (v) =>
                    setState(() => _countryCode = v),
                onChanged: () => setState(() {}),
                enabled: !_loading,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _passwordObscured,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'Пароль *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _passwordObscured = !_passwordObscured),
                  icon: Icon(
                    _passwordObscured ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Введите пароль';
                if (t.length < 6) {
                  return 'Пароль должен быть не короче 6 символов';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPasswordCtrl,
              obscureText: _confirmPasswordObscured,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'Подтвердите пароль *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIcon: IconButton(
                  onPressed: () => setState(
                    () => _confirmPasswordObscured = !_confirmPasswordObscured,
                  ),
                  icon: Icon(
                    _confirmPasswordObscured
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                ),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Подтвердите пароль';
                if (t != _passwordCtrl.text) return 'Пароли не совпадают';
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _loading || !_isValid ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: WorkaColors.orange,
                  foregroundColor: WorkaColors.onColored,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Создать',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Нажимая “Создать”, вы соглашаетесь с правилами сервиса',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        )),
        ],
      ),
    );
  }
}
