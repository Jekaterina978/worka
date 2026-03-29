import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../account/account_store.dart';
import '../../auth/auth_service.dart';
import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';
import '../../widgets/app_background.dart';
import '../../widgets/social_auth_button.dart';
import '../../widgets/worka_standard_screen_layout.dart';
import '../sms_login_screen.dart';

class AuthEntryScreen extends StatefulWidget {
  const AuthEntryScreen({super.key});

  @override
  State<AuthEntryScreen> createState() => _AuthEntryScreenState();
}

class _AuthEntryScreenState extends State<AuthEntryScreen> {
  final TextEditingController _loginCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  String? _errorText;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _rememberLoginData = true;
  bool _registerMode = false;

  static const List<_CountryCodeHint> _countryCodes = [
    _CountryCodeHint(flag: '🇪🇪', code: '+372', name: 'Эстония'),
    _CountryCodeHint(flag: '🇩🇪', code: '+49', name: 'Германия'),
    _CountryCodeHint(flag: '🇵🇱', code: '+48', name: 'Польша'),
    _CountryCodeHint(flag: '🇱🇹', code: '+370', name: 'Литва'),
    _CountryCodeHint(flag: '🇱🇻', code: '+371', name: 'Латвия'),
    _CountryCodeHint(flag: '🇺🇦', code: '+380', name: 'Украина'),
    _CountryCodeHint(flag: '🇷🇴', code: '+40', name: 'Румыния'),
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool _isEmail(String s) => s.contains('@');

  bool get _isEmailMode => _isEmail(_loginCtrl.text.trim());

  bool get _showCountryHints {
    final value = _loginCtrl.text.trim();
    return !_isEmailMode && value.startsWith('+');
  }

  List<_CountryCodeHint> get _filteredCountryHints {
    final query = _loginCtrl.text.trim();
    if (query.isEmpty || !query.startsWith('+')) return const [];
    final matched = _countryCodes
        .where((item) => item.code.startsWith(query))
        .toList();
    if (matched.isNotEmpty) return matched;
    return _countryCodes.take(4).toList();
  }

  Future<void> _continueAuth() async {
    if (_loading) return;

    final raw = _loginCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorText = 'Введите телефон или email');
      return;
    }

    if (_isEmailMode) {
      final pass = _passwordCtrl.text;
      if (pass.length < 6) {
        setState(() => _errorText = 'Пароль должен быть не короче 6 символов');
        return;
      }

      setState(() {
        _loading = true;
        _errorText = null;
      });

      try {
        final cred = _registerMode
            ? await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: raw,
                password: pass,
              )
            : await FirebaseAuth.instance.signInWithEmailAndPassword(
                email: raw,
                password: pass,
              );
        final user = cred.user ?? FirebaseAuth.instance.currentUser;
        if (user != null) {
          await AuthService.ensureUserProfile(user);
          await AccountStore.addOrUpdateFromFirebaseUser(
            user,
            provider: _registerMode ? 'register' : 'password',
          );
        }
        if (!mounted) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        }
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        if (!_registerMode && e.code == 'user-not-found') {
          setState(
            () => _errorText =
                'Пользователь не найден. Нажмите «Зарегистрироваться».',
          );
        } else {
          setState(() => _errorText = AuthService.mapFirebaseAuthError(e));
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _errorText = 'Ошибка: $e');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final openedAsRoute = Navigator.of(context).canPop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SmsLoginScreen(
          initialPhone: raw,
          popParentOnSuccess: openedAsRoute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppBackground.gradient),
            ),
          ),
          Positioned.fill(
            child: WorkaStandardScreenLayout(
              headerPadding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
              header: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Worka',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Войти или зарегистрироваться',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 120),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  decoration: const BoxDecoration(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Телефон / электронная почта',
                          style: TextStyle(
                            color: Color(0xFF6C7894),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: TextField(
                          controller: _loginCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: WorkaColors.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Введите телефон или email',
                            hintStyle: const TextStyle(
                              color: Color(0xFFB4BED2),
                              fontWeight: FontWeight.w500,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            errorText: (_errorText ?? '').isEmpty
                                ? null
                                : _errorText,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                WorkaUiRadius.button,
                              ),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                WorkaUiRadius.button,
                              ),
                              borderSide: const BorderSide(
                                color: WorkaColors.border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                WorkaUiRadius.button,
                              ),
                              borderSide: const BorderSide(
                                color: WorkaColors.primaryBlue,
                                width: 1.4,
                              ),
                            ),
                          ),
                          onChanged: (_) {
                            if ((_errorText ?? '').isNotEmpty) {
                              setState(() => _errorText = null);
                            } else {
                              setState(() {});
                            }
                          },
                          onSubmitted: (_) => _continueAuth(),
                        ),
                      ),
                      if (_showCountryHints &&
                          _filteredCountryHints.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD8E2FB)),
                            boxShadow: [WorkaUiShadows.single],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _filteredCountryHints.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFE8EEFF),
                            ),
                            itemBuilder: (context, index) {
                              final hint = _filteredCountryHints[index];
                              return ListTile(
                                dense: true,
                                visualDensity: const VisualDensity(
                                  vertical: -2,
                                ),
                                title: Text(
                                  '${hint.flag} ${hint.code}',
                                  style: const TextStyle(
                                    color: Color(0xFF334A83),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: () {
                                  _loginCtrl.text = '${hint.code} ';
                                  _loginCtrl.selection =
                                      TextSelection.fromPosition(
                                        TextPosition(
                                          offset: _loginCtrl.text.length,
                                        ),
                                      );
                                  setState(() {});
                                },
                              );
                            },
                          ),
                        ),
                      ],
                      if (_isEmailMode) ...[
                        const SizedBox(height: 14),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Пароль',
                            style: TextStyle(
                              color: Color(0xFF6C7894),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 52,
                          child: TextField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Введите пароль',
                              hintStyle: const TextStyle(
                                color: Color(0xFFB4BED2),
                                fontWeight: FontWeight.w500,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: const Color(0xFF7C8DB4),
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: WorkaColors.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: WorkaColors.primaryBlue,
                                  width: 1.4,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _continueAuth(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _rememberLoginData,
                          onChanged: (v) {
                            setState(() => _rememberLoginData = v ?? true);
                          },
                          dense: true,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'Запомнить данные для входа',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF5F6F93),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xFF6C8EF6),
                                Color(0xFF4F6FE8),
                                Color(0xFF3459D6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [WorkaUiShadows.single],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _continueAuth,
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                            ),
                            label: Text(
                              _isEmailMode
                                  ? (_registerMode
                                        ? 'Зарегистрироваться'
                                        : 'Войти')
                                  : 'Получить код по SMS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              surfaceTintColor: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: WorkaColors.divider,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'или',
                              style: TextStyle(
                                color: WorkaColors.textGreyDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: WorkaColors.divider,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SocialAuthButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Скоро')),
                          );
                        },
                        label: 'Продолжить с Google',
                        icon: const _GoogleMarkIcon(),
                      ),
                      const SizedBox(height: 13),
                      SocialAuthButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Скоро')),
                          );
                        },
                        label: 'Продолжить с Facebook',
                        icon: const _FacebookMarkIcon(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Нет аккаунта? ',
                            style: TextStyle(
                              color: Color(0xFF7E8AA4),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _registerMode = true;
                                _errorText = null;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Режим регистрации: введите email и пароль.',
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'Зарегистрироваться',
                              style: TextStyle(
                                color: WorkaColors.blue,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryCodeHint {
  final String flag;
  final String code;
  final String name;

  const _CountryCodeHint({
    required this.flag,
    required this.code,
    required this.name,
  });
}

class _GoogleMarkIcon extends StatelessWidget {
  const _GoogleMarkIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(30, 30),
      painter: _GoogleGlyphPainter(),
    );
  }
}

class _FacebookMarkIcon extends StatelessWidget {
  const _FacebookMarkIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        color: Color(0xFF1877F2),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Text(
        'f',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.8;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    void drawArc(double startDeg, double sweepDeg, Color color) {
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        startDeg * math.pi / 180,
        sweepDeg * math.pi / 180,
        false,
        p,
      );
    }

    drawArc(-45, 88, const Color(0xFF4285F4));
    drawArc(45, 92, const Color(0xFF34A853));
    drawArc(137, 90, const Color(0xFFFABB05));
    drawArc(227, 88, const Color(0xFFEA4335));

    final bar = Paint()..color = const Color(0xFF4285F4);
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.50,
        size.height * 0.43,
        size.width * 0.34,
        2.6,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(barRect, bar);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
