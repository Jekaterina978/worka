import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../account/account_store.dart';
import '../../auth/auth_service.dart';
import '../../theme/worka_colors.dart';
import '../../ui/snack.dart';
import '../../widgets/primary_pill_button.dart';
import '../../widgets/worka_header.dart';
import 'register_screen.dart';

class EmailAuthScreen extends StatefulWidget {
  final String? initialEmail;
  final bool autofocusPassword;

  const EmailAuthScreen({
    super.key,
    this.initialEmail,
    this.autofocusPassword = false,
  });

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _auth = FirebaseAuth.instance;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialEmail?.trim() ?? '';
    if (seed.isNotEmpty) {
      _emailCtrl.text = seed;
    }
    if (widget.autofocusPassword) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _passwordFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String _mapAuthError(FirebaseAuthException e) {
    return AuthService.mapFirebaseAuthError(e);
  }

  InputDecoration _deco({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(
        color: WorkaColors.textGrey,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: WorkaColors.blue),
      suffixIcon: suffix,
      prefixIconConstraints: const BoxConstraints(minHeight: 52, minWidth: 52),
      suffixIconConstraints: const BoxConstraints(minHeight: 52, minWidth: 52),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
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
      if (kDebugMode) {
        debugPrint('[EmailAuthScreen] signInWithEmailAndPassword start');
      }
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final user = cred.user ?? _auth.currentUser;
      if (user != null) {
        await AccountStore.addOrUpdateFromFirebaseUser(
          user,
          provider: 'password',
        );
      }
      if (kDebugMode) {
        debugPrint('[EmailAuthScreen] signInWithEmailAndPassword success');
      }
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('[EmailAuthScreen] auth error ${e.code}: ${e.message}');
      }
      if (!mounted) return;
      final message = _mapAuthError(e);
      setState(() => _errorText = message);
      UiSnack.show(context, message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EmailAuthScreen] unexpected auth error: $e');
      }
      if (!mounted) return;
      final message = 'Ошибка: $e';
      setState(() => _errorText = message);
      UiSnack.show(context, message);
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
          Expanded(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [WorkaColors.blueLight, WorkaColors.bg],
              stops: [0.0, 0.5],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  color: WorkaColors.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: WorkaColors.border),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 52,
                          child: TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(
                              color: WorkaColors.textDark,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _deco(
                              label: 'Email',
                              hint: 'Введите email',
                              icon: Icons.alternate_email_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 52,
                          child: TextField(
                            controller: _passCtrl,
                            focusNode: _passwordFocus,
                            obscureText: _obscure,
                            style: const TextStyle(
                              color: WorkaColors.textDark,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _deco(
                              label: 'Пароль',
                              hint: 'Введите пароль',
                              icon: Icons.lock_outline_rounded,
                              suffix: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 52,
                                  height: 52,
                                ),
                                splashRadius: 20,
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: WorkaColors.textGreyDark,
                                ),
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
                          height: 52,
                          child: PrimaryPillButton(
                            onPressed: _loading ? null : _submit,
                            label: _loading ? 'Загрузка...' : 'Войти',
                            icon: Icons.login_rounded,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SignUpScreen(),
                                    ),
                                  );
                                },
                          child: const Text(
                            'Создать аккаунт',
                            style: TextStyle(
                              color: WorkaColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
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
