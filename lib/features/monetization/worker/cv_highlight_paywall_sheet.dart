import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:worka/features/payments/models/payment_product.dart';
import 'package:worka/features/payments/repository/payments_repository.dart';
import 'package:worka/features/payments/services/web_checkout_flow.dart';
import 'package:worka/features/payments/widgets/money_primary_button.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class CvHighlightPaywallSheet extends StatefulWidget {
  final String cvId;
  const CvHighlightPaywallSheet({super.key, required this.cvId});

  static Future<bool> open(BuildContext context, {required String cvId}) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.72,
        child: CvHighlightPaywallSheet(cvId: cvId),
      ),
    );
    return res == true;
  }

  @override
  State<CvHighlightPaywallSheet> createState() =>
      _CvHighlightPaywallSheetState();
}

class _CvHighlightPaywallSheetState extends State<CvHighlightPaywallSheet> {
  final _repo = PaymentsRepository();
  bool _loading = false;
  PaymentProduct _selected = PaymentProducts.highlightCv;

  static const _items = <PaymentProduct>[
    ...PaymentProducts.cvPromotionPackages,
  ];

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

  DateTime _untilByProduct(String productId) {
    if (productId == PaymentProducts.bump.id) {
      return DateTime.now().add(const Duration(days: 2));
    }
    return DateTime.now().add(const Duration(days: 7));
  }

  Future<void> _applyCvEntitlement(String productId) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Требуется авторизация для применения тарифа.');
    }
    final base = const String.fromEnvironment(
      'WORKA_API_BASE_URL',
      defaultValue: '',
    );
    assert(base.trim().isNotEmpty, 'WORKA_API_BASE_URL is required');
    final normalizedBase = base.endsWith('/api') ? base : '$base/api';
    final uri =
        Uri.parse('$normalizedBase/candidates/cv/${widget.cvId}/entitlements');

    // derive duration from product
    final durationDays =
        productId == PaymentProducts.bump.id ? 2 : 7; // align with _untilByProduct
    final body = {
      'entitlement': productId,
      'durationDays': durationDays,
      'source': 'cv_highlight_paywall',
      'reference': widget.cvId,
    };

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.trim();
      throw StateError(
        'Не удалось применить тариф: '
        '${body.isNotEmpty ? body : 'status=${resp.statusCode}'}',
      );
    }
  }

  Future<void> _buy() async {
    if (AppMode.bypassMonetization && !kIsWeb) {
      await _applyCvEntitlement(_selected.id);
      if (!mounted) return;
      Navigator.pop(context, true);
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _toast('Нужен вход', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      if (kIsWeb) {
        await WebCheckoutFlow.start(
          repository: _repo,
          screenName: 'cv_highlight',
          selectedTariff: _selected.title,
          featureKey: _selected.id,
          amountCents: _selected.cents,
          entityId: widget.cvId,
          ownerType: 'user',
          targetType: 'cv',
        );
        return;
      }
      final checkoutUrl = await _repo.createCheckoutSessionUrl(
        productId: _selected.id,
        amountCents: _selected.cents,
        ownerId: uid,
        ownerType: 'user',
        targetId: widget.cvId,
        targetType: 'cv',
      );
      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened) throw StateError('Не удалось открыть Stripe Checkout');
      if (!mounted) return;
      Navigator.pop(context, false);
      return;
    } catch (e) {
      if (!mounted) return;
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Тарифы',
              style: TextStyle(
                color: WorkaColors.textDark,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Выделить CV',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final p = _items[i];
                  final selected = _selected.id == p.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _selected = p),
                      child: Ink(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? WorkaColors.blue
                                : WorkaColors.fieldBorder,
                            width: selected ? 1.4 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.title,
                                    style: const TextStyle(
                                      color: WorkaColors.textDark,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    p.subtitle,
                                    style: const TextStyle(
                                      color: WorkaColors.textGreyDark,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              p.priceLabel,
                              style: const TextStyle(
                                color: WorkaColors.orange,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: MoneyPrimaryButton(
                text: 'Выбрать',
                onPressed: _buy,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
