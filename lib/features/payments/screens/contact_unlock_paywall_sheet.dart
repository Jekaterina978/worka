import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:worka/theme/worka_colors.dart';

import '../../../screens/auth/auth_entry_screen.dart';
import '../analytics/monetization_analytics.dart';
import '../contact_access_controller.dart';
import '../domain/models/credits_models.dart';
import '../models/payment_product.dart';
import '../payments_i18n.dart';
import '../widgets/money_primary_button.dart';
import '../widgets/payment_package_tile.dart';

/// Determines which purchase flow to run.
///
/// [directUnlock] — the user is unlocking a specific candidate; [candidateId]
/// is required. After a successful purchase the contact for that candidate
/// is opened automatically.
///
/// [creditsOnly] — the user is buying a credits pack without a specific
/// candidate in mind (nudge banners, profile CTA, etc.). [candidateId] may
/// be null. After a successful purchase the sheet simply closes with `true`.
enum PaywallMode { directUnlock, creditsOnly }

class ContactUnlockPaywallSheet extends StatefulWidget {
  static const String urgencyFlag = 'CONTACT_PAYWALL_URGENCY_AB';
  static const String ctaFlag = 'CONTACT_PAYWALL_CTA_AB';
  static const String socialProofFlag = 'CONTACT_PAYWALL_SOCIAL_PROOF_AB';
  static const String valueFlag = 'CONTACT_PAYWALL_VALUE_AB';
  static const String firstTimeFlag = 'CONTACT_PAYWALL_FIRST_TIME_AB';
  static const String urgencyRolloutFlag = 'CONTACT_PAYWALL_URGENCY_ROLLOUT';
  static const String ctaRolloutFlag = 'CONTACT_PAYWALL_CTA_ROLLOUT';
  static const String socialProofRolloutFlag =
      'CONTACT_PAYWALL_SOCIAL_PROOF_ROLLOUT';
  static const String valueRolloutFlag = 'CONTACT_PAYWALL_VALUE_ROLLOUT';
  static const String firstTimeRolloutFlag =
      'CONTACT_PAYWALL_FIRST_TIME_ROLLOUT';

  static const String _urgencyVariantOverride = String.fromEnvironment(
    urgencyFlag,
    defaultValue: 'auto',
  );
  static const String _ctaCopyVariantOverride = String.fromEnvironment(
    ctaFlag,
    defaultValue: 'auto',
  );
  static const String _socialProofVariantOverride = String.fromEnvironment(
    socialProofFlag,
    defaultValue: 'auto',
  );
  static const String _valueVariantOverride = String.fromEnvironment(
    valueFlag,
    defaultValue: 'auto',
  );
  static const String _firstTimeVariantOverride = String.fromEnvironment(
    firstTimeFlag,
    defaultValue: 'auto',
  );
  static const String _urgencyRolloutRaw = String.fromEnvironment(
    urgencyRolloutFlag,
    defaultValue: '50',
  );
  static const String _ctaRolloutRaw = String.fromEnvironment(
    ctaRolloutFlag,
    defaultValue: '50',
  );
  static const String _socialProofRolloutRaw = String.fromEnvironment(
    socialProofRolloutFlag,
    defaultValue: '50',
  );
  static const String _valueRolloutRaw = String.fromEnvironment(
    valueRolloutFlag,
    defaultValue: '50',
  );
  static const String _firstTimeRolloutRaw = String.fromEnvironment(
    firstTimeRolloutFlag,
    defaultValue: '50',
  );

  const ContactUnlockPaywallSheet({
    super.key,
    this.candidateName,
    this.candidateId,
    this.entryPoint = 'unknown',
    this.initialProductId = '',
    this.mode = PaywallMode.directUnlock,
  });

  final String? candidateName;
  final String? candidateId;
  final String entryPoint;
  final String initialProductId;
  final PaywallMode mode;

  static Future<bool> open(
    BuildContext context, {
    String? candidateName,
    String? candidateId,
    String entryPoint = 'unknown',
    PaywallMode mode = PaywallMode.directUnlock,
  }) async {
    final safeId = (candidateId ?? '').trim();

    // Direct unlock requires a candidateId — block early if missing.
    if (mode == PaywallMode.directUnlock && safeId.isEmpty) {
      debugPrint(
        '[contact_paywall] blocked direct unlock: missing candidateId '
        'entryPoint=$entryPoint',
      );
      return false;
    }

    debugPrint(
      '[contact_paywall] open mode=$mode candidateId=$safeId '
      'entryPoint=$entryPoint',
    );

    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    await ContactAccessController.instance.bootstrap(
      uid: uid.isEmpty ? null : uid,
    );
    if (!context.mounted) return false;
    final isFirstUnlockMode =
        ContactAccessController.instance.unlockedCandidateIds.isEmpty &&
        ContactAccessController.instance.creditsBalance <= 0;
    MonetizationAnalytics.instance.trackPaywallOpened(
      entryPoint: entryPoint,
      candidateId: candidateId,
      packId: PaymentProducts.defaultContactProduct.id,
      creditsBefore: ContactAccessController.instance.creditsBalance,
      ctaVariant: _variantLabel(
        overrideValue: _ctaCopyVariantOverride,
        rolloutPercent: _parseRolloutPercent(_ctaRolloutRaw),
        uid: uid,
        candidateId: candidateId,
        entryPoint: entryPoint,
        experimentSalt: 'cta_copy',
      ),
      socialProofVariant: _variantLabel(
        overrideValue: _socialProofVariantOverride,
        rolloutPercent: _parseRolloutPercent(_socialProofRolloutRaw),
        uid: uid,
        candidateId: candidateId,
        entryPoint: entryPoint,
        experimentSalt: 'social_proof',
      ),
      valueVariant: _variantLabel(
        overrideValue: _valueVariantOverride,
        rolloutPercent: _parseRolloutPercent(_valueRolloutRaw),
        uid: uid,
        candidateId: candidateId,
        entryPoint: entryPoint,
        experimentSalt: 'value_emphasis',
      ),
      firstTimeVariant: _variantLabel(
        overrideValue: _firstTimeVariantOverride,
        rolloutPercent: _parseRolloutPercent(_firstTimeRolloutRaw),
        uid: uid,
        candidateId: candidateId,
        entryPoint: entryPoint,
        experimentSalt: 'first_time_framing',
      ),
      isFirstUnlockMode: isFirstUnlockMode,
    );
    final result = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => ContactUnlockPaywallSheet(
        candidateName: candidateName,
        candidateId: safeId.isEmpty ? null : safeId,
        entryPoint: entryPoint,
        mode: mode,
      ),
    );
    return result ?? false;
  }

  static String _variantLabel({
    required String overrideValue,
    required int rolloutPercent,
    required String uid,
    required String? candidateId,
    required String entryPoint,
    required String experimentSalt,
  }) {
    return _isVariantB(
          overrideValue: overrideValue,
          rolloutPercent: rolloutPercent,
          uid: uid,
          candidateId: candidateId,
          entryPoint: entryPoint,
          experimentSalt: experimentSalt,
        )
        ? 'b'
        : 'a';
  }

  static bool _isVariantB({
    required String overrideValue,
    required int rolloutPercent,
    required String uid,
    required String? candidateId,
    required String entryPoint,
    required String experimentSalt,
  }) {
    final override = overrideValue.trim().toLowerCase();
    if (override == 'a' || override == 'control') return false;
    if (override == 'b' || override == 'variant_b') return true;
    if (rolloutPercent <= 0) return false;
    if (rolloutPercent >= 100) return true;

    final base = uid.isNotEmpty ? uid : '${candidateId ?? ''}:$entryPoint';
    final seed = experimentSalt.isEmpty ? base : '$base:$experimentSalt';
    if (seed.isEmpty) return false;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final bucket = hash % 100;
    return bucket < rolloutPercent;
  }

  static int _parseRolloutPercent(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) return 50;
    if (parsed < 0) return 0;
    if (parsed > 100) return 100;
    return parsed;
  }

  @override
  State<ContactUnlockPaywallSheet> createState() =>
      _ContactUnlockPaywallSheetState();
}

class _ContactUnlockPaywallSheetState extends State<ContactUnlockPaywallSheet> {
  final _contactAccess = ContactAccessController.instance;
  final _analytics = MonetizationAnalytics.instance;
  bool _firstUnlockModeResolved = false;
  bool _isFirstUnlockMode = false;
  bool _isOpening = false;
  late PaymentProduct _selectedProduct;

  void _toast(String text, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : WorkaColors.textDark,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _contactAccess.addListener(_onAccessChanged);
    _selectedProduct =
        PaymentProducts.byId(widget.initialProductId) ??
        PaymentProducts.defaultContactProduct;
    _resolveFirstUnlockMode();

    final entry = widget.entryPoint.isEmpty ? 'unknown' : widget.entryPoint;
    debugPrint(
      '[contact_paywall] mode=${widget.mode.name} '
      'candidateId=${widget.candidateId ?? ''} entryPoint=$entry',
    );
  }

  @override
  void dispose() {
    _contactAccess.removeListener(_onAccessChanged);
    super.dispose();
  }

  void _onAccessChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _resolveFirstUnlockMode() async {
    await _contactAccess.bootstrap();
    if (!mounted) return;
    final isFirst =
        _contactAccess.unlockedCandidateIds.isEmpty &&
        _contactAccess.creditsBalance <= 0;
    setState(() {
      _isFirstUnlockMode = isFirst;
      _firstUnlockModeResolved = true;
      if (isFirst && widget.initialProductId.trim().isEmpty) {
        _selectedProduct = PaymentProducts.credit1;
      }
    });
  }

  Future<void> _openPackages({String? initialProductId}) async {
    if (_isOpening) return;
    _isOpening = true;
    debugPrint(
      '[contact_paywall] openPackages start initialProductId=${initialProductId ?? _selectedProduct.id}',
    );
    try {
    final purchased = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => _ContactUnlockProductPickerSheet(
        candidateName: widget.candidateName,
        candidateId: widget.candidateId,
        entryPoint: widget.entryPoint,
        initialProductId: initialProductId ?? _selectedProduct.id,
        mode: widget.mode,
      ),
    );
    debugPrint('[contact_paywall] openPackages result purchased=$purchased');
    if (!mounted || purchased != true) return;
    debugPrint('[contact_paywall] closing first paywall with success');
    Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  Future<void> _continueFromOffer() async {
    debugPrint(
      '[contact_paywall] continueFromOffer candidateId=${widget.candidateId} selectedProduct=${_selectedProduct.id}',
    );
    final selectedProductId = _selectedProduct.id.trim();
    if (selectedProductId.isEmpty) {
      _toast('Не удалось определить тариф', error: true);
      return;
    }
    await _openPackages(initialProductId: selectedProductId);
  }

  void _cancel() => Navigator.pop(context, false);

  String _contextualHeader() {
    if (widget.mode == PaywallMode.creditsOnly) {
      return 'Пополнить пакет контактов';
    }
    final entry = widget.entryPoint.trim().toLowerCase();
    if (entry.contains('candidate_search')) {
      return 'Свяжитесь с кандидатом напрямую';
    }
    if (entry.contains('candidate_details')) {
      return 'Откройте контакты и свяжитесь прямо сейчас';
    }
    if (entry.contains('interaction')) {
      return 'Кандидат уже взаимодействует с вами';
    }
    return 'Открыть контакт кандидата';
  }

  bool _isUrgencyVariantB() {
    return _isVariantB(
      overrideValue: ContactUnlockPaywallSheet._urgencyVariantOverride,
      rolloutPercent: ContactUnlockPaywallSheet._parseRolloutPercent(
        ContactUnlockPaywallSheet._urgencyRolloutRaw,
      ),
      experimentSalt: '',
    );
  }

  bool _isSocialProofVariantB() {
    return _isVariantB(
      overrideValue: ContactUnlockPaywallSheet._socialProofVariantOverride,
      rolloutPercent: ContactUnlockPaywallSheet._parseRolloutPercent(
        ContactUnlockPaywallSheet._socialProofRolloutRaw,
      ),
      experimentSalt: 'social_proof',
    );
  }

  bool _isFirstTimeFramingVariantB() {
    return _isVariantB(
      overrideValue: ContactUnlockPaywallSheet._firstTimeVariantOverride,
      rolloutPercent: ContactUnlockPaywallSheet._parseRolloutPercent(
        ContactUnlockPaywallSheet._firstTimeRolloutRaw,
      ),
      experimentSalt: 'first_time_framing',
    );
  }

  bool _isValueEmphasisVariantB() {
    return _isVariantB(
      overrideValue: ContactUnlockPaywallSheet._valueVariantOverride,
      rolloutPercent: ContactUnlockPaywallSheet._parseRolloutPercent(
        ContactUnlockPaywallSheet._valueRolloutRaw,
      ),
      experimentSalt: 'value_emphasis',
    );
  }

  String _valueSavingsLabel(PaymentProduct product) {
    final credits = product.credits ?? 0;
    if (credits <= 1) return '';
    final singleUnit = PaymentProducts.credit1.cents;
    if (singleUnit <= 0) return '';
    final regularTotal = singleUnit * credits;
    if (regularTotal <= 0 ||
        product.cents <= 0 ||
        product.cents >= regularTotal) {
      return '';
    }
    final savingsPercent =
        (((regularTotal - product.cents) / regularTotal) * 100).round();
    if (savingsPercent <= 0) return '';
    return 'Экономия $savingsPercent% по сравнению с покупкой по одному';
  }

  bool _isVariantB({
    required String overrideValue,
    required int rolloutPercent,
    required String experimentSalt,
  }) {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    return ContactUnlockPaywallSheet._isVariantB(
      overrideValue: overrideValue,
      rolloutPercent: rolloutPercent,
      uid: uid,
      candidateId: widget.candidateId,
      entryPoint: widget.entryPoint,
      experimentSalt: experimentSalt,
    );
  }

  String _pricePerContactLabel(PaymentProduct product) {
    final contacts = product.credits ?? 1;
    if (contacts <= 0) return '';
    final value = (product.cents / 100) / contacts;
    return '≈ €${value.toStringAsFixed(2)} за контакт';
  }

  void _selectProduct(PaymentProduct product) {
    if (_selectedProduct.id == product.id) return;
    setState(() => _selectedProduct = product);
    _analytics.trackPackSelected(
      entryPoint: widget.entryPoint,
      packId: product.id,
      creditsBefore: _contactAccess.creditsBalance,
      candidateId: widget.candidateId,
    );
  }

  Widget _optionTile({required PaymentProduct product, required String title}) {
    final selected = _selectedProduct.id == product.id;
    final mostPopular = product.isMostPopular;
    final badge = product.badgeLabel;
    final badgeIcon = product.isMostPopular
        ? Icons.local_fire_department_rounded
        : (product.isBestValue ? Icons.savings_outlined : null);
    final cardBorderColor = selected
        ? WorkaColors.orange
        : (mostPopular
              ? WorkaColors.orange.withValues(alpha: 0.75)
              : WorkaColors.divider);
    final cardBorderWidth = selected ? 1.8 : (mostPopular ? 1.5 : 1.0);
    final cardBackground = selected
        ? const Color(0xFFFFF7EF)
        : (mostPopular ? const Color(0xFFFFFBF3) : Colors.white);
    final showSocialProof =
        product.id == PaymentProducts.contactPackage10.id &&
        _isSocialProofVariantB();
    final showValueEmphasis =
        _isValueEmphasisVariantB() &&
        (product.id == PaymentProducts.contactPackage10.id ||
            product.id == PaymentProducts.contactPackage30.id);
    final valueSavingsLabel = _valueSavingsLabel(product);
    return InkWell(
      onTap: () => _selectProduct(product),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorderColor, width: cardBorderWidth),
          boxShadow: (selected || mostPopular)
              ? [
                  BoxShadow(
                    color: WorkaColors.orange.withValues(
                      alpha: selected ? 0.16 : 0.10,
                    ),
                    blurRadius: selected ? 14 : 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Checkbox(
                value: selected,
                onChanged: (_) => _selectProduct(product),
                activeColor: WorkaColors.orange,
                side: const BorderSide(color: WorkaColors.textGreyDark),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((badge ?? '').trim().isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: mostPopular
                              ? WorkaColors.orange.withValues(alpha: 0.18)
                              : WorkaColors.hoverBlueSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: mostPopular
                                ? WorkaColors.orange.withValues(alpha: 0.45)
                                : WorkaColors.divider,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (badgeIcon != null) ...[
                              Icon(
                                badgeIcon,
                                size: 14,
                                color: mostPopular
                                    ? WorkaColors.orange
                                    : WorkaColors.textGreyDark,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              badge!,
                              style: TextStyle(
                                color: mostPopular
                                    ? WorkaColors.orange
                                    : WorkaColors.textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if ((badge ?? '').trim().isNotEmpty)
                    const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _pricePerContactLabel(product),
                    style: TextStyle(
                      color: selected
                          ? WorkaColors.textDark
                          : WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  if (showValueEmphasis && valueSavingsLabel.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      valueSavingsLabel,
                      style: const TextStyle(
                        color: WorkaColors.orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  if (mostPopular) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'Экономия по сравнению с покупкой по одному',
                      style: TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  if (showSocialProof) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'Чаще всего выбирают работодатели',
                      style: TextStyle(
                        color: WorkaColors.blue,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final helperText = !_firstUnlockModeResolved
        ? 'Подберите подходящий пакет контактов'
        : _isFirstUnlockMode
        ? 'После выбора пакета откроется список тарифов'
        : 'Нажмите ниже, чтобы открыть список пакетов';
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _contextualHeader(),
              style: TextStyle(
                color: WorkaColors.textDark,
                fontWeight: FontWeight.w900,
                fontSize: 21,
              ),
            ),
            const SizedBox(height: 6),
            if (_isUrgencyVariantB()) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: WorkaColors.orange.withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  'Не упустите кандидата — свяжитесь прямо сейчас',
                  style: TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_firstUnlockModeResolved &&
                _isFirstUnlockMode &&
                _isFirstTimeFramingVariantB()) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: WorkaColors.hoverBlueSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: WorkaColors.divider),
                ),
                child: const Text(
                  'Первый контакт — самый важный. Начните прямо сейчас',
                  style: TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if ((widget.candidateName ?? '').trim().isNotEmpty) ...[
              Text(
                widget.candidateName!,
                style: const TextStyle(
                  color: WorkaColors.blue,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              const Text(
                'Контакт откроется навсегда',
                style: TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
            ] else
              const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WorkaColors.divider),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: WorkaColors.blue,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Контакты готовы к открытию: +371 *** **23 · j***@gmail.com',
                      style: TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: WorkaColors.hoverBlueSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WorkaColors.divider),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: WorkaColors.orange,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Активно ищет работу',
                          style: TextStyle(
                            color: WorkaColors.textDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: WorkaColors.blue,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Отвечает в течение 24 часов',
                          style: TextStyle(
                            color: WorkaColors.textDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: WorkaColors.blue,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Прямой контакт без посредников',
                    style: TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: WorkaColors.blue,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Контакт остаётся навсегда',
                    style: TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _optionTile(
              product: PaymentProducts.credit1,
              title: PaymentProducts.paywallOfferLine(PaymentProducts.credit1),
            ),
            const SizedBox(height: 10),
            Text(
              helperText,
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _openPackages,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: WorkaColors.blue,
              ),
              child: const Text(
                'Показать пакеты',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: MoneyPrimaryButton(
                text: 'Открыть за ${_selectedProduct.priceLabel}',
                onPressed: _continueFromOffer,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: _cancel,
                child: const Text(
                  'Отмена',
                  style: TextStyle(
                    color: WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w700,
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

class _ContactUnlockProductPickerSheet extends StatefulWidget {
  const _ContactUnlockProductPickerSheet({
    this.candidateName,
    this.candidateId,
    this.entryPoint = 'unknown',
    this.initialProductId = '',
    this.mode = PaywallMode.directUnlock,
  });

  final String? candidateName;
  final String? candidateId;
  final String entryPoint;
  final String initialProductId;
  final PaywallMode mode;

  @override
  State<_ContactUnlockProductPickerSheet> createState() =>
      _ContactUnlockProductPickerSheetState();
}

class _ContactUnlockProductPickerSheetState
    extends State<_ContactUnlockProductPickerSheet> {
  final _contactAccess = ContactAccessController.instance;
  late PaymentProduct _selected;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selected =
        PaymentProducts.byId(widget.initialProductId) ??
        PaymentProducts.defaultContactProduct;
  }

  void _toast(String text, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : WorkaColors.textDark,
      ),
    );
  }

  String _friendlyPurchaseError(String raw) {
    final msg = raw.trim();
    if (msg.isEmpty) {
      return 'Не удалось провести оплату. Попробуйте снова.';
    }
    final lower = msg.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('socket')) {
      return 'Проблема с сетью. Проверьте интернет и повторите оплату.';
    }
    if (lower.contains('declined') || lower.contains('insufficient')) {
      return 'Платёж отклонён. Попробуйте другую карту или способ оплаты.';
    }
    if (lower.contains('failed')) {
      return 'Не удалось провести оплату. Попробуйте снова.';
    }
    return msg;
  }

  Future<void> _buySelected() async {
    if (_loading) return;
    if (_contactAccess.isPurchaseInProgress) {
      _toast('Платёж уже выполняется. Пожалуйста, подождите...');
      return;
    }
    final candidateId = (widget.candidateId ?? '').trim();
    // directUnlock requires a real candidate; creditsOnly may have no candidateId.
    if (widget.mode == PaywallMode.directUnlock && candidateId.isEmpty) {
      debugPrint('[contact_paywall] blocked purchase: directUnlock missing candidateId');
      _toast('Не удалось определить кандидата', error: true);
      return;
    }
    if (_selected.id.trim().isEmpty) {
      _toast('Не удалось определить тариф', error: true);
      return;
    }
    debugPrint(
      '[contact_paywall] purchase mode=${widget.mode.name} '
      'candidateId=$candidateId product=${_selected.id}',
    );
    // Require auth at confirm step; prompt login if missing.
    var user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      try {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const AuthEntryScreen()),
        );
      } catch (_) {}
      user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) {
        _toast('Войдите, чтобы купить доступ к контактам', error: true);
        return;
      }
    }
    setState(() => _loading = true);
    try {
      final tx = await _contactAccess.purchaseContactProduct(
        _selected,
        entryPoint: widget.entryPoint,
        candidateId: candidateId.isEmpty ? null : candidateId,
      );
      if (!mounted) return;
      if (tx.status == PurchaseStatus.cancelled) {
        _toast('Оплата отменена');
        return;
      }
      if (tx.status != PurchaseStatus.success) {
        _toast(_friendlyPurchaseError(tx.message), error: true);
        return;
      }
      _toast(PaymentsI18n.t(context, 'success'));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _toast('${PaymentsI18n.t(context, 'failed')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = PaymentProducts.creditPackages;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Открыть контакт кандидата',
              style: TextStyle(
                color: WorkaColors.textDark,
                fontWeight: FontWeight.w900,
                fontSize: 21,
              ),
            ),
            if ((widget.candidateName ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.candidateName!.trim(),
                style: const TextStyle(
                  color: WorkaColors.blue,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            ...products.map((product) {
              final badgeText = product.badgeLabel;
              final badgeIcon = product.isMostPopular
                  ? Icons.local_fire_department_rounded
                  : (product.isBestValue ? Icons.savings_outlined : null);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PaymentPackageTile(
                  product: product,
                  selected: _selected.id == product.id,
                  onTap: () => setState(() => _selected = product),
                  badgeText: badgeText,
                  badgeIcon: badgeIcon,
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: MoneyPrimaryButton(
                text: _selected.id == PaymentProducts.credit1.id
                    ? 'Открыть за ${_selected.priceLabel}'
                    : 'Купить ${_selected.credits ?? 1} контактов за ${_selected.priceLabel}',
                onPressed: _buySelected,
                isLoading: _loading,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Отмена',
                  style: TextStyle(
                    color: WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w700,
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
