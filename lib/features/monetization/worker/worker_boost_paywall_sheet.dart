import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:worka/features/monetization/pricing.dart';
import 'package:worka/features/payments/repository/payments_repository.dart';
import 'package:worka/features/payments/services/web_checkout_flow.dart';
import 'package:worka/features/payments/widgets/money_primary_button.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class WorkerBoostPaywallSheet extends StatefulWidget {
  const WorkerBoostPaywallSheet({super.key});

  static Future<void> open(BuildContext context) {
    if (AppMode.bypassMonetization && !kIsWeb) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.76,
        child: WorkerBoostPaywallSheet(),
      ),
    );
  }

  @override
  State<WorkerBoostPaywallSheet> createState() =>
      _WorkerBoostPaywallSheetState();
}

class _WorkerBoostPaywallSheetState extends State<WorkerBoostPaywallSheet> {
  final _payments = PaymentsRepository();
  bool _loading = false;
  String _selected = 'worker_boost_48h';

  static const _products =
      <String, ({String title, double price, String subtitle})>{
        'worker_boost_48h': (
          title: 'Поднять резюме',
          price: MonetizationPricing.boostCv48h,
          subtitle: '48h',
        ),
        'worker_highlight_7d': (
          title: 'Выделить профиль',
          price: MonetizationPricing.highlightProfile7d,
          subtitle: '7 дней',
        ),
        'worker_priority_7d': (
          title: 'Приоритет в поиске',
          price: MonetizationPricing.prioritySearch7d,
          subtitle: '7 дней',
        ),
      };

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

  Future<void> _buy() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) {
      _toast('Нужен вход', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final price = _products[_selected]?.price ?? 0;
      final amountCents = (price * 100).round();
      if (kIsWeb) {
        await WebCheckoutFlow.start(
          repository: _payments,
          screenName: 'worker_boost',
          selectedTariff: _selected,
          featureKey: _selected,
          amountCents: amountCents,
          entityId: uid,
        );
        return;
      }
      final checkoutUrl = await _payments.createCheckoutSessionUrl(
        productId: _selected,
        amountCents: amountCents,
        ownerId: uid,
        ownerType: 'user',
        targetId: uid,
        targetType: 'user',
      );
      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened) throw StateError('Не удалось открыть Stripe Checkout');
      if (!mounted) return;
      Navigator.pop(context);
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
              'Прокачать профиль',
              style: TextStyle(
                color: WorkaColors.textDark,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: _products.entries.map((e) {
                  final selected = _selected == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _selected = e.key),
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
                                    e.value.title,
                                    style: const TextStyle(
                                      color: WorkaColors.textDark,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    e.value.subtitle,
                                    style: const TextStyle(
                                      color: WorkaColors.textGreyDark,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              MonetizationPricing.eur(e.value.price),
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
                }).toList(),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: MoneyPrimaryButton(
                text: 'Оплатить',
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
