import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:worka/features/payments/repository/payments_repository.dart';
import 'package:worka/screens/auth/auth_entry_screen.dart';
import 'package:worka/features/payments/payments_routes.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/services/user_role_prefs.dart';
import 'package:worka/core/events/app_events.dart';
import 'package:worka/features/payments/contact_access_controller.dart';
import 'package:worka/controllers/paid_entitlements_controller.dart';
import 'package:worka/screens/employer/search/widgets/candidate_details_sheet.dart';

String _currentLocation() => Uri.base.toString();

class PaymentSuccessScreen extends StatefulWidget {
  const PaymentSuccessScreen({super.key});

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  final _payments = PaymentsRepository();
  static const Duration _kAuthRestoreTimeout = Duration(seconds: 8);
  static const Duration _kAuthPollInterval = Duration(milliseconds: 250);
  String get _sessionId => Uri.base.queryParameters['session_id'] ?? '';
  String get _returnOrigin => Uri.base.queryParameters['origin'] ?? '';
  String get _returnJobId => Uri.base.queryParameters['job_id'] ?? '';
  String get _returnCvId => Uri.base.queryParameters['cv_id'] ?? '';
  String get _returnProduct => Uri.base.queryParameters['product'] ?? '';
  String get _returnSourceScreen =>
      Uri.base.queryParameters['source_screen'] ?? '';
  String get _returnCandidateId =>
      Uri.base.queryParameters['candidate_id'] ?? '';
  String get _returnMode => Uri.base.queryParameters['mode'] ?? '';
  String _statusText = 'Проверяем оплату...';
  bool _confirmedSuccess = false;
  bool _authMissing = false;
  bool _confirming = false;
  bool _promptedLogin = false;
  Future<void> _openCandidateDetails({required String candidateId}) async {
    final id = candidateId.trim();
    if (id.isEmpty || !mounted) return;
    await Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CandidateDetailsScreen(candidateId: id),
      ),
    );
  }

  bool _isTerminalFailureStatus(String value) {
    final clean = value.trim().toLowerCase();
    return clean == 'checkout_not_paid' ||
        clean == 'checkout_expired' ||
        clean == 'missing_payment_intent' ||
        clean == 'invalid_metadata' ||
        clean == 'missing_job_id' ||
        clean == 'validation_failed';
  }

  Future<void> _logMode(String marker) async {
    final user = FirebaseAuth.instance.currentUser;
    final role = await UserRolePrefs.getSelectedRole();
    debugPrint('[payments_return] opened payments success route');
    debugPrint('[payments_return] $marker route=/payments/success');
    debugPrint(
      '[payments_return] session_id=${_sessionId.isEmpty ? 'null' : _sessionId}',
    );
    debugPrint(
      '[payments_return] origin=${_returnOrigin.isEmpty ? 'null' : _returnOrigin}',
    );
    debugPrint(
      '[payments_return] job_id=${_returnJobId.isEmpty ? 'null' : _returnJobId}',
    );
    debugPrint(
      '[payments_return] product=${_returnProduct.isEmpty ? 'null' : _returnProduct}',
    );
    debugPrint(
      '[payments_return] candidate_id=${_returnCandidateId.isEmpty ? 'null' : _returnCandidateId}',
    );
    debugPrint(
      '[payments_return] mode=${_returnMode.isEmpty ? 'null' : _returnMode}',
    );
    debugPrint('[payments_return] current location=${_currentLocation()}');
    debugPrint(
      '[payments_return] auth snapshot uid=${user?.uid ?? 'null'} '
      'email=${user?.email ?? 'null'} anon=${user?.isAnonymous}',
    );
    debugPrint(
      '[payments_return] current profile mode after return: ${AppMode.currentMode.name}',
    );
    debugPrint('[payments_return] selected role pref: ${role ?? 'null'}');
  }

  Future<User?> _waitForRestoredUser() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;

    debugPrint(
      '[payments_return] auth user is null on return, waiting for restore',
    );
    if (mounted) {
      setState(() => _statusText = 'Восстанавливаем сессию...');
    }
    try {
      final restored = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((user) => user != null)
          .timeout(_kAuthRestoreTimeout);
      debugPrint(
        '[payments_return] auth restored uid=${restored?.uid ?? 'null'}',
      );
      return restored;
    } catch (e) {
      debugPrint('[payments_return] auth restore stream timeout/error: $e');
    }

    final sw = Stopwatch()..start();
    while (sw.elapsed < _kAuthRestoreTimeout) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        debugPrint('[payments_return] auth restored via polling uid=${u.uid}');
        return u;
      }
      await Future<void>.delayed(_kAuthPollInterval);
    }
    return FirebaseAuth.instance.currentUser;
  }

  Future<User?> _ensureAuthInteractive() async {
    if (_promptedLogin) return FirebaseAuth.instance.currentUser;
    _promptedLogin = true;
    try {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
    } catch (_) {}
    return FirebaseAuth.instance.currentUser;
  }

  bool _hasSafeVacancyRestoreOrigin(String origin) {
    final cleanOrigin = origin.trim();
    final cleanSource = _returnSourceScreen.trim();
    return cleanOrigin == 'promote_job' ||
        cleanOrigin == 'vacancy_owner_sheet' ||
        cleanOrigin == 'vacancy_urgent_entry' ||
        cleanSource == 'promote_job' ||
        cleanSource == 'promote_job_screen' ||
        cleanSource == 'vacancy_owner_sheet' ||
        cleanSource == 'vacancy_urgent_entry';
  }

  /// When Stripe redirects to a different domain than the one where checkout
  /// started, Firebase Auth persistence is not shared and the user appears
  /// signed out. If the return URL contains the original origin, bounce there
  /// before doing anything else so auth is restored from the right host.
  Future<bool> _maybeBounceToOriginalOrigin() async {
    if (!kIsWeb) return false;
    final rawOrigin = _returnOrigin.trim();
    if (rawOrigin.isEmpty) return false;

    Uri? originUri;
    try {
      originUri = Uri.parse(rawOrigin);
    } catch (_) {
      return false;
    }
    if (!originUri.hasScheme ||
        originUri.host.isEmpty ||
        originUri.origin == Uri.base.origin) {
      return false;
    }

    final target = originUri.replace(
      path: Uri.base.path,
      query: Uri.base.query,
      fragment: Uri.base.fragment,
    );
    debugPrint(
      '[payments_return] cross-origin bounce -> ${target.toString()} '
      '(current=${Uri.base.origin} origin=$rawOrigin)',
    );
    await launchUrl(target, webOnlyWindowName: '_self');
    return true;
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[PAYMENT] success return');
    _logMode('return route opened');
    debugPrint(
      '[payments_return] Uri.base.origin after return: ${Uri.base.origin}',
    );
    debugPrint('[payments_return] PaymentSuccessScreen opened');
    _maybeBounceToOriginalOrigin().then((bounced) {
      if (bounced) return;
      _confirmAndReturn();
    });
  }

  Future<void> _confirmAndReturn() async {
    if (_confirming) return;
    _confirming = true;
    final paidCtrl = context.read<PaidEntitlementsController>();
    debugPrint(
      '[PAYMENT SUCCESS ROUTE] mode=${_returnMode.isEmpty ? 'null' : _returnMode} '
      'candidate_id=${_returnCandidateId.isEmpty ? 'null' : _returnCandidateId} '
      'session_id=${_sessionId.isEmpty ? 'null' : _sessionId}',
    );
    final sessionId = _sessionId.trim();
    final modeLower = _returnMode.trim().toLowerCase();
    String? restoredVacancyJobId;
    String? resolvedJobId;
    String? resolvedCvId = _returnCvId.trim().isNotEmpty
        ? _returnCvId.trim()
        : null;
    if (sessionId.isEmpty) {
      setState(() => _statusText = 'Оплата не подтверждена.');
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      _confirming = false;
      return;
    }

    final restoredUser = await _waitForRestoredUser();
    if (!mounted) return;
    if (restoredUser == null) {
      final interactive = await _ensureAuthInteractive();
      if (!mounted) return;
      if (interactive == null) {
        _authMissing = true;
        setState(() {
          _statusText =
              'Сессия не восстановлена. Войдите снова и проверьте оплату.';
        });
        _confirming = false;
        return;
      }
    }

    for (var i = 0; i < 8; i++) {
      try {
        final status = await _payments.getCheckoutSessionStatus(
          sessionId: sessionId,
        );
        debugPrint(
          '[payments_return] checkout confirm status=${status.status} productId=${status.productId} canonicalProductId=${status.canonicalProductId} jobId=${status.jobId} applied=${status.applied}',
        );
        if (!mounted) return;
        if (!status.isVacancyCheckout) {
          _confirmedSuccess = true;
          setState(() => _statusText = 'Оплата подтверждена. Возвращаемся...');
          // Handle direct contact unlock resume on web return.
          final urlCandidate =
              _returnCandidateId.trim().isNotEmpty ? _returnCandidateId.trim() : '';
          final fallbackCandidate = (ContactAccessController
                      .instance.lastAttemptedCandidateId ??
                  '')
              .trim();
          final candidateId =
              urlCandidate.isNotEmpty ? urlCandidate : fallbackCandidate;
          debugPrint(
            '[CONTACT_UNLOCK_SUCCESS] urlCandidate=$urlCandidate fallbackCandidate=$fallbackCandidate resolved=$candidateId',
          );
          if (_returnMode.trim().toLowerCase() == 'direct_unlock' &&
              candidateId.isNotEmpty) {
            debugPrint(
              '[PAYMENT SUCCESS] mode=direct_unlock candidateId=$candidateId ctrlHash=${identityHashCode(ContactAccessController.instance)}',
            );
            final contactController = ContactAccessController.instance;
            debugPrint(
              '[CONTACT_CTRL_INSTANCE] hash=${identityHashCode(contactController)}',
            );
            debugPrint('[CONTACT_REFRESH] start candidateId=$candidateId');
            try {
              await contactController.getUnlockedCandidateIds(
                uid: FirebaseAuth.instance.currentUser?.uid,
              );
              debugPrint(
                '[CONTACT_REFRESH] done candidateId=$candidateId unlocked=${contactController.unlockedCandidateIds.length}',
              );
              debugPrint(
                '[CONTACT_LOAD] start candidateId=$candidateId hasAccess=${contactController.hasAccess(candidateId)} hasContact=${contactController.contactForCandidate(candidateId) != null}',
              );
              await contactController.ensureLoadedContactForCandidate(
                candidateId,
              );
              debugPrint(
                '[CONTACT_LOAD] done candidateId=$candidateId hasAccess=${contactController.hasAccess(candidateId)} hasContact=${contactController.contactForCandidate(candidateId) != null}',
              );
            } catch (e) {
              debugPrint('[PAYMENT SUCCESS] contact refresh failed $e');
            }
            if (mounted) {
              debugPrint(
                '[NAV_TO_CANDIDATE] pushReplacement candidateId=$candidateId',
              );
              await _openCandidateDetails(candidateId: candidateId);
              debugPrint(
                '[NAV_TO_CANDIDATE] navigation triggered candidateId=$candidateId',
              );
            }
            _confirming = false;
            return;
          }
          break;
        }
        if (status.applied) {
          _confirmedSuccess = true;
          final jobId = status.jobId.trim().isNotEmpty
              ? status.jobId.trim()
              : _returnJobId.trim();
          if (jobId.isNotEmpty) {
            resolvedJobId = jobId;
          }
          if (jobId.isNotEmpty && _hasSafeVacancyRestoreOrigin(_returnOrigin)) {
            restoredVacancyJobId = jobId;
          }
          if (jobId.isNotEmpty) {
            AppEvents.emitPaymentCompleted(jobId);
            debugPrint('PAYMENT COMPLETED FOR: $jobId');
          }
          setState(
            () => _statusText = 'Оплата подтверждена. Обновляем вакансию...',
          );
          break;
        }
        if (_isTerminalFailureStatus(status.status) ||
            status.paymentStatus.trim().toLowerCase() == 'unpaid') {
          setState(() => _statusText = 'Оплата отменена.');
          break;
        }
        setState(() => _statusText = 'Ожидаем подтверждение сервера...');
      } catch (e) {
        debugPrint('[payments_return] checkout confirm failed: $e');
        if (!mounted) return;
        setState(() => _statusText = 'Не удалось подтвердить оплату.');
      }
      if (i < 7) {
        if (mounted) {
          setState(() => _statusText = 'Ожидаем подтверждение сервера...');
        }
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }

    _confirming = false;
    if (!mounted) return;
    // Final safeguard refresh for direct unlock flows in case earlier refresh was too early.
    final candidateIdFinal = _returnCandidateId.trim().isNotEmpty
        ? _returnCandidateId.trim()
        : (ContactAccessController.instance.lastAttemptedCandidateId ?? '')
              .trim();
    if (_returnMode.trim().toLowerCase() == 'direct_unlock' &&
        candidateIdFinal.isNotEmpty) {
      try {
        debugPrint(
          '[PAYMENT SUCCESS] final direct_unlock refresh candidateId=$candidateIdFinal',
        );
        await ContactAccessController.instance.getUnlockedCandidateIds(
          uid: FirebaseAuth.instance.currentUser?.uid,
        );
        await ContactAccessController.instance.ensureLoadedContactForCandidate(
          candidateIdFinal,
        );
        debugPrint(
          '[PAYMENT SUCCESS] final direct_unlock refresh completed candidateId=$candidateIdFinal',
        );
      } catch (e) {
        debugPrint(
          '[PAYMENT SUCCESS] final direct_unlock refresh failed $e candidateId=$candidateIdFinal',
        );
      }
    }

    // Refresh CV / Job entitlements for non-contact flows when context is present.
    if (_confirmedSuccess) {
      if (resolvedCvId == null || resolvedCvId.isEmpty) {
        final fromJobParam = (_returnCvId.trim().isNotEmpty)
            ? _returnCvId.trim()
            : null;
        resolvedCvId = fromJobParam;
      }
      if ((modeLower == 'cv' || modeLower.startsWith('cv_')) &&
          (resolvedCvId != null && resolvedCvId!.isNotEmpty)) {
        try {
          debugPrint(
            '[PAYMENT SUCCESS] refresh cv entitlements cvId=$resolvedCvId',
          );
          await paidCtrl.refreshCvEntitlements(resolvedCvId!);
        } catch (e) {
          debugPrint(
            '[PAYMENT SUCCESS] refresh cv entitlements failed $e cvId=$resolvedCvId',
          );
        }
      }
      final jobIdFinal =
          resolvedJobId ??
          (_returnJobId.trim().isNotEmpty ? _returnJobId.trim() : null);
      if (jobIdFinal != null &&
          jobIdFinal.isNotEmpty &&
          (modeLower == 'job_promotion' ||
              modeLower.startsWith('job') ||
              modeLower.contains('job'))) {
        try {
          debugPrint(
            '[PAYMENT SUCCESS] refresh job entitlements jobId=$jobIdFinal',
          );
          await paidCtrl.refreshJobEntitlements(jobIdFinal);
          // Inform user that employer contacts may be available after purchase.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Контакты работодателя доступны. Откройте вакансию, чтобы увидеть их.',
                ),
                duration: Duration(seconds: 4),
              ),
            );
          }
        } catch (e) {
          debugPrint(
            '[PAYMENT SUCCESS] refresh job entitlements failed $e jobId=$jobIdFinal',
          );
        }
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    if (_confirmedSuccess &&
        restoredVacancyJobId != null &&
        restoredVacancyJobId.isNotEmpty) {
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        PaymentsRoutes.promoteJob,
        (_) => false,
        arguments: <String, dynamic>{'jobId': restoredVacancyJobId},
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _confirmedSuccess
                  ? Icons.check_circle
                  : _authMissing
                  ? Icons.lock_outline
                  : Icons.cancel_outlined,
              color: _confirmedSuccess
                  ? const Color(0xFF34C759)
                  : _authMissing
                  ? const Color(0xFFFF9500)
                  : const Color(0xFFFF3B30),
              size: 80,
            ),
            const SizedBox(height: 16),
            Text(
              _confirmedSuccess
                  ? 'Оплата прошла успешно!'
                  : _authMissing
                  ? 'Нужно восстановить сессию'
                  : 'Оплата отменена',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_statusText, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (_authMissing) ...[
              ElevatedButton(
                onPressed: _confirming ? null : _confirmAndReturn,
                child: const Text('Повторить восстановление'),
              ),
            ] else ...[
              TextButton(
                onPressed: _confirming ? null : _confirmAndReturn,
                child: const Text('Обновить статус'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PaymentCancelScreen extends StatefulWidget {
  const PaymentCancelScreen({super.key});

  @override
  State<PaymentCancelScreen> createState() => _PaymentCancelScreenState();
}

class _PaymentCancelScreenState extends State<PaymentCancelScreen> {
  bool _promptedLogin = false;

  Future<bool> _maybeBounceToOriginalOrigin() async {
    if (!kIsWeb) return false;
    final rawOrigin = (Uri.base.queryParameters['origin'] ?? '').trim();
    if (rawOrigin.isEmpty) return false;

    Uri? originUri;
    try {
      originUri = Uri.parse(rawOrigin);
    } catch (_) {
      return false;
    }
    if (!originUri.hasScheme ||
        originUri.host.isEmpty ||
        originUri.origin == Uri.base.origin) {
      return false;
    }
    final target = originUri.replace(
      path: Uri.base.path,
      query: Uri.base.query,
      fragment: Uri.base.fragment,
    );
    debugPrint(
      '[payments_return] cancel cross-origin bounce -> ${target.toString()} '
      '(current=${Uri.base.origin} origin=$rawOrigin)',
    );
    await launchUrl(target, webOnlyWindowName: '_self');
    return true;
  }

  Future<void> _logMode(String marker) async {
    final role = await UserRolePrefs.getSelectedRole();
    debugPrint('[payments_return] opened payments cancel route');
    debugPrint('[payments_return] $marker route=/payments/cancel');
    debugPrint(
      '[payments_return] session_id=${Uri.base.queryParameters['session_id'] ?? 'null'}',
    );
    debugPrint('[payments_return] current location=${_currentLocation()}');
    debugPrint(
      '[payments_return] current profile mode after return: ${AppMode.currentMode.name}',
    );
    debugPrint('[payments_return] selected role pref: ${role ?? 'null'}');
  }

  void _goHome() {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.popUntil((route) => route.isFirst);
  }

  Future<void> _ensureAuthInteractive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null || _promptedLogin) return;
    _promptedLogin = true;
    try {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[PAYMENT] cancel return');
    _logMode('return route opened');
    _maybeBounceToOriginalOrigin().then((bounced) {
      if (bounced) return;
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        _goHome();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cancel_outlined,
              color: Color(0xFFFF3B30),
              size: 80,
            ),
            const SizedBox(height: 16),
            const Text(
              'Оплата отменена',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Возвращаемся назад...',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextButton(onPressed: _goHome, child: const Text('Назад')),
          ],
        ),
      ),
    );
  }
}

class CandidateDetailsScreen extends StatelessWidget {
  final String candidateId;

  const CandidateDetailsScreen({super.key, required this.candidateId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CandidateDetailsSheet(
          candidateId: candidateId,
          candidateUid: candidateId,
          testMode: true,
        ),
      ),
    );
  }
}
