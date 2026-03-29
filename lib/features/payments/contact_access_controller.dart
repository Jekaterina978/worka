import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/admin_config.dart';
import 'analytics/monetization_analytics.dart';
import 'contact_unlock_store.dart';
import 'domain/models/credits_models.dart';
import 'models/employer_payment_models.dart';
import 'models/payment_product.dart';
import 'repository/payments_repository.dart';
import 'screens/contact_unlock_paywall_sheet.dart';
import 'services/payment_sheet_service.dart';
import 'services/stripe_payment_sheet_service.dart';

enum ContactUnlockStatus {
  unlocked,
  alreadyUnlocked,
  cancelled,
  purchasePending,
  failed,
}

class ContactUnlockResult {
  final ContactUnlockStatus status;
  final CandidateContact? contact;
  final int creditsLeft;
  final String message;
  final String stabilizationStage;
  final bool recentPurchase;

  const ContactUnlockResult({
    required this.status,
    this.contact,
    this.creditsLeft = 0,
    this.message = '',
    this.stabilizationStage = '',
    this.recentPurchase = false,
  });

  bool get isSuccess =>
      status == ContactUnlockStatus.unlocked ||
      status == ContactUnlockStatus.alreadyUnlocked;
}

class ContactAccessController extends ChangeNotifier {
  static const int _postPurchaseSyncAttempts = 8;
  static const Duration _postPurchaseSyncDelay = Duration(milliseconds: 800);

  ContactAccessController({
    PaymentsRepository? repository,
    ContactUnlockStore? unlockStore,
    StripePaymentSheetService? stripePaymentSheetService,
  }) : _repository = repository ?? PaymentsRepository(),
       _unlockStore = unlockStore ?? ContactUnlockStore.instance,
       _stripeSheet = stripePaymentSheetService ?? StripePaymentSheetService();

  static final ContactAccessController instance = ContactAccessController();

  final PaymentsRepository _repository;
  final ContactUnlockStore _unlockStore;
  final StripePaymentSheetService _stripeSheet;
  final MonetizationAnalytics _analytics = MonetizationAnalytics.instance;

  final Map<String, Future<ContactUnlockResult>> _inFlightByCandidate =
      <String, Future<ContactUnlockResult>>{};
  final Map<String, Future<CreditSpendTransaction>> _spendInFlightByCandidate =
      <String, Future<CreditSpendTransaction>>{};
  final Map<String, Future<CandidateContact?>> _contactLoadInFlightByCandidate =
      <String, Future<CandidateContact?>>{};
  final Map<String, CandidateContact> _openedContacts =
      <String, CandidateContact>{};
  final Set<String> _serverUnlockedCandidateIds = <String>{};
  Future<PurchaseTransaction>? _purchaseInFlight;
  String? lastAttemptedCandidateId;

  String _uidScope = 'guest';
  int _creditsBalance = 0;
  bool _bootstrapped = false;
  EmployerWallet? _wallet;

  int get creditsBalance => _creditsBalance;
  EmployerWallet? get wallet => _wallet;
  Set<String> get unlockedCandidateIds =>
      Set<String>.from(_serverUnlockedCandidateIds);
  bool get isPurchaseInProgress => _purchaseInFlight != null;
  bool isUnlockInProgress(String candidateId) {
    final id = candidateId.trim();
    if (id.isEmpty) return false;
    return _inFlightByCandidate.containsKey(id) ||
        _spendInFlightByCandidate.containsKey(id);
  }

  List<CreditPack> getCreditPacks() {
    final packs = PaymentProducts.creditPackages;
    return packs
        .map((p) {
          final contacts = p.credits ?? _contactsFromTitle(p.title);
          return CreditPack(
            id: p.id,
            contacts: contacts,
            cents: p.cents,
            title: p.title,
            subtitle: p.subtitle,
            isMostPopular: p.isMostPopular,
            isBestValue: p.isBestValue,
          );
        })
        .toList(growable: false);
  }

  bool hasAccessToCandidate(String candidateId) {
    _ensureAuthScopeConsistency();
    final id = candidateId.trim();
    if (id.isEmpty) return false;
    return _serverUnlockedCandidateIds.contains(id) ||
        _openedContacts.containsKey(id);
  }

  CandidateContact? contactForCandidate(String candidateId) {
    _ensureAuthScopeConsistency();
    final id = candidateId.trim();
    if (id.isEmpty) return null;
    return _openedContacts[id];
  }

  Future<CandidateContact?> ensureLoadedContactForCandidate(
    String candidateId,
  ) async {
    final id = candidateId.trim();
    if (id.isEmpty) return null;
    debugPrint(
      '[CONTACT_CTRL][load] start candidateId=$id ctrlHash=${identityHashCode(this)} hasAccess=${hasAccess(id)} cached=${_openedContacts[id] != null}',
    );
    await bootstrap(uid: FirebaseAuth.instance.currentUser?.uid);
    final cached = _openedContacts[id];
    if (cached != null) return cached;
    if (!hasAccessToCandidate(id)) return null;
    final pending = _contactLoadInFlightByCandidate[id];
    if (pending != null) return pending;

    final future = _loadUnlockedContactInternal(id);
    _contactLoadInFlightByCandidate[id] = future;
    return future.whenComplete(() {
      _contactLoadInFlightByCandidate.remove(id);
    });
  }

  Future<CandidateContact?> _loadUnlockedContactInternal(
    String candidateId,
  ) async {
    try {
      final contact = await _repository.getUnlockedCandidateContact(
        candidateId: candidateId,
      );
      _openedContacts[candidateId] = contact;
      debugPrint(
        '[CONTACT_CTRL][load] done candidateId=$candidateId hasContact=${contact != null} ctrlHash=${identityHashCode(this)}',
      );
      notifyListeners();
      debugPrint('[CONTACT_CTRL][notify] load');
      return contact;
    } catch (e) {
      debugPrint(
        '[CONTACT_UNLOCK] contact fetch failed candidateId=$candidateId error=$e',
      );
      return _openedContacts[candidateId];
    }
  }

  Future<void> bootstrap({String? uid}) async {
    final next = _normalizeUid(uid);
    if (_bootstrapped && next == _uidScope) return;
    if (_uidScope != next) {
      _openedContacts.clear();
      _serverUnlockedCandidateIds.clear();
      _inFlightByCandidate.clear();
      _spendInFlightByCandidate.clear();
      _contactLoadInFlightByCandidate.clear();
      _creditsBalance = 0;
      _wallet = null;
      _purchaseInFlight = null;
    }
    _uidScope = next;
    await _unlockStore.load(uid: uid);
    _bootstrapped = true;
  }

  Future<EmployerWallet> getWallet({String? uid}) async {
    try {
      final wallet = await _repository.getAuthoritativeEmployerWalletState();
      await _applyAuthoritativeWalletState(
        wallet,
        uid: uid ?? FirebaseAuth.instance.currentUser?.uid,
      );
      return _wallet!;
    } catch (_) {
      final fallback = EmployerWallet(
        uid: _normalizeUid(uid),
        balance: _creditsBalance,
        unlockedCandidateIds: Set<String>.from(_serverUnlockedCandidateIds),
        fetchedAt: DateTime.now(),
      );
      _wallet = fallback;
      return fallback;
    }
  }

  Future<void> refreshWallet() async {
    await getWallet(uid: FirebaseAuth.instance.currentUser?.uid);
  }

  Future<Set<String>> getUnlockedCandidateIds({String? uid}) async {
    await bootstrap(uid: uid ?? FirebaseAuth.instance.currentUser?.uid);
    try {
      final ids = await _repository.getUnlockedCandidateIds();
      _serverUnlockedCandidateIds
        ..clear()
        ..addAll(ids);
      debugPrint(
        '[CONTACT_CTRL][refresh] ctrlHash=${identityHashCode(this)} unlocked=${_serverUnlockedCandidateIds.length}',
      );
      notifyListeners();
      debugPrint('[CONTACT_CTRL][notify] refresh');
      debugPrint('[CONTACT_REFRESH] unlockedIds loaded count=${ids.length}');
      return Set<String>.from(_serverUnlockedCandidateIds);
    } catch (e) {
      debugPrint('[CONTACT_REFRESH] failed to load unlocked ids: $e');
      return Set<String>.from(_serverUnlockedCandidateIds);
    }
  }

  bool hasAccessToCandidateContact(String candidateId) {
    return hasAccessToCandidate(candidateId);
  }

  bool hasAccess(String candidateId) {
    return hasAccessToCandidate(candidateId);
  }

  Future<bool> syncHasAccessToCandidateContact(String candidateId) async {
    await getUnlockedCandidateIds(uid: FirebaseAuth.instance.currentUser?.uid);
    return hasAccessToCandidateContact(candidateId);
  }

  Future<PurchaseTransaction> purchaseCreditPack(CreditPack pack) async {
    final product = PaymentProducts.creditPackages.firstWhere(
      (p) => p.id == pack.id,
      orElse: () => PaymentProduct(
        id: pack.id,
        title: pack.title,
        subtitle: pack.subtitle,
        cents: pack.cents,
      ),
    );
    return purchaseContactProduct(product);
  }

  Future<PurchaseTransaction> purchaseContactProduct(
    PaymentProduct product, {
    String entryPoint = 'unknown',
    String? candidateId,
  }) {
    final pending = _purchaseInFlight;
    if (pending != null) return pending;

    _analytics.trackPurchaseStarted(
      entryPoint: entryPoint,
      packId: product.id,
      creditsBefore: _creditsBalance,
      candidateId: candidateId,
    );
    final future = _purchaseProductInternal(
      product,
      entryPoint: entryPoint,
      candidateId: candidateId,
    );
    _purchaseInFlight = future;
    notifyListeners();
    return future.whenComplete(() {
      _purchaseInFlight = null;
      notifyListeners();
    });
  }

  Future<PurchaseTransaction> _purchaseProductInternal(
    PaymentProduct product, {
    required String entryPoint,
    String? candidateId,
  }) async {
    final cleanCandidateId = (candidateId ?? '').trim();
    debugPrint(
      '[PAYMENT] contact checkout payload candidateId=$cleanCandidateId product=${product.id} entryPoint=$entryPoint',
    );
    if (product.id == PaymentProducts.credit1.id && cleanCandidateId.isEmpty) {
      debugPrint(
        '[PAYMENT] blocked contact_1: missing candidateId entryPoint=$entryPoint',
      );
      return PurchaseTransaction(
        productId: product.id,
        amountCents: product.cents,
        status: PurchaseStatus.failed,
        createdAt: DateTime.now(),
        message: 'candidate_id_required',
      );
    }

    final before = _creditsBalance;
    try {
      if (kDebugMode) {
        debugPrint(
          '[PAYMENT] openPaymentFlow contact product=${product.id} entryPoint=$entryPoint candidateId=${candidateId ?? ''} creditsBefore=$before',
        );
      }
      final paymentResult = await _stripeSheet.startCheckout(
        productId: product.id,
        quantity: 1,
        targetId: cleanCandidateId.isEmpty ? null : cleanCandidateId,
        targetType: 'candidate',
      );
      if (paymentResult.status == PaymentSheetFlowStatus.cancelled) {
        debugPrint('[PAYMENT] checkout cancelled product=${product.id}');
        _analytics.trackPurchaseFailed(
          entryPoint: entryPoint,
          packId: product.id,
          creditsBefore: before,
          creditsAfter: _creditsBalance,
          resultStatus: 'cancelled',
          candidateId: candidateId,
        );
        return PurchaseTransaction(
          productId: product.id,
          amountCents: product.cents,
          status: PurchaseStatus.cancelled,
          createdAt: DateTime.now(),
          message: paymentResult.message,
        );
      }
      if (paymentResult.status == PaymentSheetFlowStatus.failed) {
        debugPrint(
          '[PAYMENT] checkout failed product=${product.id} message=${paymentResult.message}',
        );
        throw StateError(
          paymentResult.message.isEmpty
              ? 'Payment failed'
              : paymentResult.message,
        );
      }
      debugPrint('[PAYMENT] checkout success product=${product.id}');
      final wallet = await _refreshAuthoritativeCreditsState(
        reason: 'purchase_success',
      );
      _analytics.trackPurchaseSuccess(
        entryPoint: entryPoint,
        packId: product.id,
        creditsBefore: before,
        creditsAfter: wallet.balance,
        candidateId: candidateId,
      );
      return PurchaseTransaction(
        productId: product.id,
        amountCents: product.cents,
        status: PurchaseStatus.success,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      _analytics.trackPurchaseFailed(
        entryPoint: entryPoint,
        packId: product.id,
        creditsBefore: before,
        creditsAfter: _creditsBalance,
        resultStatus: 'failed',
        candidateId: candidateId,
      );
      return PurchaseTransaction(
        productId: product.id,
        amountCents: product.cents,
        status: PurchaseStatus.failed,
        createdAt: DateTime.now(),
        message: e.toString(),
      );
    }
  }

  Future<CreditSpendTransaction> spendCreditForCandidate({
    required String candidateId,
  }) async {
    final id = candidateId.trim();
    if (id.isEmpty) {
      return CreditSpendTransaction(
        candidateId: candidateId,
        creditsBefore: _creditsBalance,
        creditsAfter: _creditsBalance,
        status: CreditSpendStatus.failed,
        createdAt: DateTime.now(),
        message: 'candidateId is empty',
      );
    }
    final inFlight = _spendInFlightByCandidate[id];
    if (inFlight != null) return inFlight;
    final future = _spendCreditForCandidateInternal(id);
    _spendInFlightByCandidate[id] = future;
    notifyListeners();
    return future.whenComplete(() {
      _spendInFlightByCandidate.remove(id);
      notifyListeners();
    });
  }

  Future<CreditSpendTransaction> _spendCreditForCandidateInternal(
    String candidateId,
  ) async {
    final before = _creditsBalance;
    if (hasAccessToCandidate(candidateId)) {
      return CreditSpendTransaction(
        candidateId: candidateId,
        creditsBefore: before,
        creditsAfter: before,
        status: CreditSpendStatus.alreadyOpened,
        createdAt: DateTime.now(),
      );
    }
    try {
      // Temporary: disable direct credit consumption; force paywall/checkout path.
      return CreditSpendTransaction(
        candidateId: candidateId,
        creditsBefore: before,
        creditsAfter: _creditsBalance,
        status: CreditSpendStatus.insufficientCredits,
        createdAt: DateTime.now(),
        message: 'credit consume disabled (debug)',
      );
    } catch (e) {
      final msg = e.toString();
      return CreditSpendTransaction(
        candidateId: candidateId,
        creditsBefore: before,
        creditsAfter: _creditsBalance,
        status: _isInsufficientCredits(msg)
            ? CreditSpendStatus.insufficientCredits
            : CreditSpendStatus.failed,
        createdAt: DateTime.now(),
        message: msg,
      );
    }
  }

  Future<ContactUnlockResult> unlockCandidateContact(
    BuildContext context, {
    required String candidateId,
    String? candidateName,
    String entryPoint = 'unknown',
  }) async {
    return ensureContactUnlocked(
      context,
      candidateId: candidateId,
      candidateName: candidateName,
      entryPoint: entryPoint,
    );
  }

  Future<ContactUnlockResult> ensureContactUnlocked(
    BuildContext context, {
    required String candidateId,
    String? candidateName,
    String entryPoint = 'unknown',
  }) async {
    final id = candidateId.trim();
    if (id.isEmpty) {
      return const ContactUnlockResult(
        status: ContactUnlockStatus.failed,
        message: 'candidateId is empty',
      );
    }

    final pending = _inFlightByCandidate[id];
    if (pending != null) return pending;

    debugPrint(
      '[CONTACT_UNLOCK] ensure start candidateId=$id entryPoint=$entryPoint '
      'ctrlHash=${identityHashCode(this)}',
    );
    lastAttemptedCandidateId = id;

    _analytics.trackContactUnlockTap(
      entryPoint: entryPoint,
      candidateId: id,
      creditsBefore: _creditsBalance,
    );

    await bootstrap(uid: FirebaseAuth.instance.currentUser?.uid);
    if (!context.mounted) {
      return const ContactUnlockResult(status: ContactUnlockStatus.cancelled);
    }

    if (hasAccessToCandidate(id)) {
      final cachedContact =
          _openedContacts[id] ?? await ensureLoadedContactForCandidate(id);
      _analytics.trackContactAlreadyUnlocked(
        entryPoint: entryPoint,
        candidateId: id,
        creditsBefore: _creditsBalance,
      );
      return ContactUnlockResult(
        status: ContactUnlockStatus.alreadyUnlocked,
        contact: cachedContact,
        creditsLeft: _creditsBalance,
        stabilizationStage: 'already_unlocked',
      );
    }

    final future = _unlockInternal(
      context,
      candidateId: id,
      candidateName: candidateName,
      entryPoint: entryPoint,
    ).whenComplete(() async {
      // Force authoritative refresh after purchase attempt
      try {
        debugPrint('[CONTACT_UNLOCK] refresh unlocked ids candidateId=$id');
        await getUnlockedCandidateIds(uid: FirebaseAuth.instance.currentUser?.uid);
        await ensureLoadedContactForCandidate(id);
        debugPrint('[CONTACT_UNLOCK] contact fetch completed candidateId=$id');
        notifyListeners();
      } catch (e) {
        debugPrint('[CONTACT_UNLOCK] post-purchase refresh failed $e');
      }
    });
    lastAttemptedCandidateId = id;
    _inFlightByCandidate[id] = future;
    try {
      return await future;
    } finally {
      _inFlightByCandidate.remove(id);
    }
  }

  Future<ContactUnlockResult> _unlockInternal(
    BuildContext context, {
    required String candidateId,
    String? candidateName,
    required String entryPoint,
  }) async {
    if (!context.mounted) {
      return const ContactUnlockResult(status: ContactUnlockStatus.cancelled);
    }

    final bought = await ContactUnlockPaywallSheet.open(
      context,
      candidateName: candidateName,
      candidateId: candidateId,
      entryPoint: entryPoint,
      mode: PaywallMode.directUnlock,
    );
    if (!bought) {
      _analytics.trackContactUnlockFailed(
        entryPoint: entryPoint,
        candidateId: candidateId,
        creditsBefore: _creditsBalance,
        creditsAfter: _creditsBalance,
        resultStatus: 'cancelled',
      );
      return const ContactUnlockResult(status: ContactUnlockStatus.cancelled);
    }

    await getUnlockedCandidateIds(uid: FirebaseAuth.instance.currentUser?.uid);

    if (_serverUnlockedCandidateIds.contains(candidateId)) {
      final contact = await ensureLoadedContactForCandidate(candidateId);
      _analytics.trackContactUnlockSuccess(
        entryPoint: entryPoint,
        candidateId: candidateId,
        creditsBefore: _creditsBalance,
        creditsAfter: _creditsBalance,
      );
      return ContactUnlockResult(
        status: ContactUnlockStatus.unlocked,
        contact: contact,
        creditsLeft: _creditsBalance,
        stabilizationStage: 'unlock_completed',
      );
    }

    return ContactUnlockResult(
      status: ContactUnlockStatus.failed,
      message: 'Contact was not unlocked after checkout.',
      creditsLeft: _creditsBalance,
      stabilizationStage: 'unlock_not_visible_after_checkout',
    );
  }

  static bool _isInsufficientCredits(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('insufficient') ||
        lower.contains('недостат') ||
        lower.contains('credits');
  }

  Future<void> _applyAuthoritativeWalletState(
    EmployerWallet wallet, {
    String? uid,
  }) async {
    _serverUnlockedCandidateIds
      ..clear()
      ..addAll(wallet.unlockedCandidateIds);
    _creditsBalance = wallet.balance;
    _wallet = EmployerWallet(
      uid: wallet.uid,
      balance: wallet.balance,
      unlockedCandidateIds: Set<String>.from(_serverUnlockedCandidateIds),
      fetchedAt: wallet.fetchedAt,
    );
    await _unlockStore.replaceOpenedIds(
      _serverUnlockedCandidateIds,
      uid: uid ?? FirebaseAuth.instance.currentUser?.uid,
    );
    notifyListeners();
  }

  Future<EmployerWallet> _refreshAuthoritativeCreditsState({
    required String reason,
  }) async {
    final wallet = await _repository.getAuthoritativeEmployerWalletState();
    await _applyAuthoritativeWalletState(
      wallet,
      uid: FirebaseAuth.instance.currentUser?.uid,
    );
    if (kDebugMode) {
      debugPrint(
        '[ContactAccessController] authoritative credits refresh reason=$reason balance=${wallet.balance} unlocked=${wallet.unlockedCandidateIds.length}',
      );
    }
    return wallet;
  }

  Future<ContactUnlockResult> _stabilizeAfterRecentPurchase({
    required String candidateId,
    required String entryPoint,
    required int previousBalance,
  }) async {
    return ContactUnlockResult(
      status: ContactUnlockStatus.failed,
      message: 'Post-purchase stabilization disabled (debug).',
      creditsLeft: _creditsBalance,
      stabilizationStage: 'post_purchase_sync_disabled',
      recentPurchase: true,
    );
  }

  static String _normalizeUid(String? uid) {
    final value = (uid ?? '').trim();
    return value.isEmpty ? 'guest' : value;
  }

  static int _contactsFromTitle(String title) {
    final m = RegExp(r'(\d+)').firstMatch(title);
    return int.tryParse(m?.group(1) ?? '') ?? 1;
  }

  void _ensureAuthScopeConsistency() {
    final currentUid = _normalizeUid(FirebaseAuth.instance.currentUser?.uid);
    if (currentUid == _uidScope) return;
    _uidScope = currentUid;
    _openedContacts.clear();
    _serverUnlockedCandidateIds.clear();
    _inFlightByCandidate.clear();
    _spendInFlightByCandidate.clear();
    _contactLoadInFlightByCandidate.clear();
    _creditsBalance = 0;
    _wallet = null;
    _purchaseInFlight = null;
    _bootstrapped = false;
  }
}
