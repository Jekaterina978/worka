import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:worka/features/monetization/pricing.dart';
import 'package:worka/features/payments/repository/payments_repository.dart';
import 'package:worka/features/payments/services/web_checkout_flow.dart';
import 'package:worka/features/payments/widgets/money_primary_button.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class WorkerCvLimitPaywallSheet extends StatefulWidget {
  const WorkerCvLimitPaywallSheet({super.key});

  static Future<bool> open(BuildContext context) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.72,
        child: WorkerCvLimitPaywallSheet(),
      ),
    );
    return res == true;
  }

  @override
  State<WorkerCvLimitPaywallSheet> createState() =>
      _WorkerCvLimitPaywallSheetState();
}

class _WorkerCvLimitPaywallSheetState extends State<WorkerCvLimitPaywallSheet> {
  final _payments = PaymentsRepository();
  bool _loading = false;
  String _selected = 'worker_plus_month';

  static const _products =
      <String, ({String title, double price, String subtitle})>{
        'worker_cv_plus3_month': (
          title: '+3 CV',
          price: MonetizationPricing.workerCvPlus3Monthly,
          subtitle: 'monthly',
        ),
        'worker_cv_unlimited_month': (
          title: 'Unlimited CV',
          price: MonetizationPricing.workerCvUnlimitedMonthly,
          subtitle: 'monthly',
        ),
        'worker_plus_month': (
          title: 'Worker Plus',
          price: MonetizationPricing.workerPlusMonthly,
          subtitle: '+3 CV + 1 boost/week',
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
          screenName: 'worker_cv_limit',
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
              'Добавьте больше CV',
              style: TextStyle(
                color: WorkaColors.textDark,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Бесплатно доступно ${MonetizationPricing.workerFreeActiveCvLimit} активных CV.',
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: _products.entries.map((e) {
                  final selected = _selected == e.key;
                  final price = MonetizationPricing.eur(e.value.price);
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
                              price,
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
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: MoneyPrimaryButton(
                text: 'Оплатить',
                onPressed: _buy,
                isLoading: _loading,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text(
                  'Отмена',
                  style: TextStyle(
                    color: WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w800,
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
