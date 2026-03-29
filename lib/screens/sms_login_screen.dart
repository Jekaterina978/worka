import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../account/account_store.dart';
import 'auth/auth_entry_screen.dart';
import '../theme/worka_colors.dart';
import '../widgets/phone_input_field.dart';

class SmsLoginScreen extends StatefulWidget {
  final String? initialPhone;
  final bool popParentOnSuccess;

  const SmsLoginScreen({
    super.key,
    this.initialPhone,
    this.popParentOnSuccess = false,
  });

  @override
  State<SmsLoginScreen> createState() => _SmsLoginScreenState();
}

class _SmsLoginScreenState extends State<SmsLoginScreen> {
  final _auth = FirebaseAuth.instance;

  bool _codeStep = false;
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _loading = false;
  String? _verificationId;
  String _phoneCountryCode = '+372';

  static const int _resendSeconds = 45;
  int _left = _resendSeconds;
  Timer? _timer;

  // Центровка: двигаем ВЕСЬ блок так, чтобы КНОПКА была в центре экрана
  final GlobalKey _blockKey = GlobalKey();
  final GlobalKey _buttonKey = GlobalKey();
  double _shiftY = 0;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialPhone?.trim() ?? '';
    if (seed.isNotEmpty) {
      _phoneCtrl.text = seed;
    }
    _phoneCtrl.addListener(() => setState(() {}));
    _codeCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _recenterBlock());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recenterBlock());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
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

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        setState(() => _left = 0);
      } else {
        setState(() => _left -= 1);
      }
    });
  }

  String _fullPhone() {
    final raw = _phoneCtrl.text.trim().replaceAll(' ', '');
    if (raw.isEmpty) return '';
    if (raw.startsWith('+')) return raw;
    return '$_phoneCountryCode$raw';
  }

  bool get _canSendCode {
    final phone = _fullPhone();
    return !_loading && phone.replaceAll('+', '').length >= 8;
  }

  bool get _canConfirm {
    final code = _codeCtrl.text.trim();
    return !_loading && _verificationId != null && code.length >= 4;
  }

  Future<void> _sendCode() async {
    final phone = _fullPhone();
    if (phone.replaceAll('+', '').length < 8) {
      _toast('Введите номер телефона');
      return;
    }

    setState(() => _loading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (_) {},
        verificationFailed: (e) => _toast(e.message ?? 'Ошибка'),
        codeSent: (id, _) {
          _verificationId = id;
          if (!mounted) return;
          setState(() => _codeStep = true);
          _startTimer();
          WidgetsBinding.instance.addPostFrameCallback((_) => _recenterBlock());
        },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
      );
    } catch (e) {
      _toast('Ошибка: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _confirmCode() async {
    final code = _codeCtrl.text.trim();
    if (_verificationId == null || code.length < 4) return;

    setState(() => _loading = true);
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      if (kDebugMode) {
        debugPrint('[SmsLoginScreen] signInWithCredential start');
      }
      final result = await _auth.signInWithCredential(cred);
      final user = result.user ?? _auth.currentUser;
      if (user != null) {
        await AccountStore.addOrUpdateFromFirebaseUser(user, provider: 'phone');
      }
      if (kDebugMode) {
        debugPrint('[SmsLoginScreen] signInWithCredential success');
      }
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      }
      if (widget.popParentOnSuccess && nav.canPop()) {
        nav.pop();
      }
    } catch (_) {
      _toast('Неверный код');
    }
    if (mounted) setState(() => _loading = false);
  }

  InputDecoration _decoCode({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFFB3B3B3),
        fontWeight: FontWeight.w400,
      ),
      prefixIcon: const Icon(Icons.lock_outline, color: WorkaColors.blue),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
      ),
    );
  }

  void _recenterBlock() {
    if (!mounted) return;

    final blockCtx = _blockKey.currentContext;
    final btnCtx = _buttonKey.currentContext;
    if (blockCtx == null || btnCtx == null) return;

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
    // Надпись под кнопкой всегда. До отправки — показываем 45 (как ты просила).
    final int shownLeft = _codeStep ? _left : _resendSeconds;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: WorkaColors.textDark,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 40,
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text(
                        'Worka',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: WorkaColors.blue,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Transform.translate(
                  offset: Offset(0, _shiftY),
                  child: Padding(
                    key: _blockKey,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),

                        Text(
                          _codeStep ? 'Введите код' : 'Введите номер телефона',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: WorkaColors.textDark,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _codeStep
                              ? 'Мы отправили вам SMS с кодом подтверждения'
                              : 'Мы отправим вам SMS с кодом подтверждения',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: WorkaColors.textGreyDark,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 22),

                        if (!_codeStep)
                          PhoneInputField(
                            controller: _phoneCtrl,
                            countryCode: _phoneCountryCode,
                            onCountryChanged: (code) =>
                                setState(() => _phoneCountryCode = code),
                            onChanged: (_) => setState(() {}),
                            hintText: '5123 4567',
                            enabled: !_loading,
                          )
                        else
                          TextField(
                            controller: _codeCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: WorkaColors.textDark,
                            ),
                            decoration: _decoCode(hint: 'Код из SMS'),
                          ),

                        const SizedBox(height: 18),

                        SizedBox(
                          key: _buttonKey,
                          height: 56,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _codeStep
                                ? (_canConfirm ? _confirmCode : null)
                                : (_canSendCode ? _sendCode : null),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: WorkaColors.orange,
                              disabledBackgroundColor: WorkaColors.orange
                                  .withValues(alpha: 0.35),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _codeStep ? 'Продолжить' : 'Получить код',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),

                        if (!_codeStep) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const AuthEntryScreen(),
                                      ),
                                    );
                                  },
                            child: const Text(
                              'Войти по email',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: WorkaColors.blue,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // ✅ Надпись под кнопкой — всегда. В codeStep кликабельно, когда таймер 0.
                        GestureDetector(
                          onTap: (_codeStep && _left == 0 && !_loading)
                              ? _sendCode
                              : null,
                          child: Text(
                            shownLeft > 0
                                ? 'Отправить SMS повторно через $shownLeft секунд'
                                : 'Отправить SMS повторно',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: shownLeft > 0
                                  ? WorkaColors.textGreyDark
                                  : WorkaColors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
