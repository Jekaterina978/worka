import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';
import '../widgets/worka_header.dart';

class EmailAuthScreen extends StatefulWidget {
  final String? initialEmail;

  const EmailAuthScreen({super.key, this.initialEmail});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _auth = FirebaseAuth.instance;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _isSignIn = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialEmail?.trim() ?? '';
    if (seed.isNotEmpty) {
      _emailCtrl.text = seed;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Неверный формат email';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Неверный email или пароль';
      case 'email-already-in-use':
        return 'Этот email уже зарегистрирован';
      case 'weak-password':
        return 'Пароль слишком простой';
      case 'too-many-requests':
        return 'Слишком много попыток. Попробуйте позже';
      default:
        return e.message ?? 'Ошибка авторизации';
    }
  }

  InputDecoration _deco({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: WorkaColors.textGrey,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: WorkaColors.blue),
      suffixIcon: suffix,
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
      errorText: null,
    );
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorText = 'Введите корректный email');
      return;
    }
    if (pass.length < 6) {
      setState(() => _errorText = 'Пароль должен быть не короче 6 символов');
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      if (_isSignIn) {
        await _auth.signInWithEmailAndPassword(email: email, password: pass);
      } else {
        await _auth.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = _mapAuthError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Ошибка: $e');
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
            title: 'Вход по email',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: WorkaColors.divider),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _deco(
                      hint: 'Эл. почта',
                      icon: Icons.alternate_email_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _deco(
                      hint: 'Пароль',
                      icon: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: WorkaColors.textGreyDark,
                        ),
                      ),
                    ),
                  ),
                  if ((_errorText ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _errorText!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WorkaColors.orange,
                        foregroundColor: Colors.white,
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
                          : Text(
                              _isSignIn ? 'Войти' : 'Создать аккаунт',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _isSignIn = !_isSignIn),
                    child: Text(
                      _isSignIn ? 'Создать аккаунт' : 'У меня уже есть аккаунт',
                      style: const TextStyle(
                        color: WorkaColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        )),
        ],
      ),
    );
  }
}
