import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/theme/worka_colors.dart';

import '../models/payment_product.dart';
import '../payments_i18n.dart';
import '../repository/payments_repository.dart';
import '../services/web_checkout_flow.dart';
import '../widgets/money_primary_button.dart';
import '../widgets/payment_package_tile.dart';
import 'verification_upload_screen.dart';

class VerifiedEmployerPaywallScreen extends StatefulWidget {
  const VerifiedEmployerPaywallScreen({super.key});

  @override
  State<VerifiedEmployerPaywallScreen> createState() =>
      _VerifiedEmployerPaywallScreenState();
}

class _VerifiedEmployerPaywallScreenState
    extends State<VerifiedEmployerPaywallScreen> {
  final _repo = PaymentsRepository();
  bool _loading = false;

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

  Future<void> _pay() async {
    if (AppMode.bypassMonetization && !kIsWeb) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => const VerificationUploadScreen()),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      const checkoutProduct = PaymentProducts.verification;
      if (kIsWeb) {
        await WebCheckoutFlow.start(
          repository: _repo,
          screenName: 'verified_employer',
          selectedTariff: checkoutProduct.title,
          featureKey: checkoutProduct.id,
          amountCents: checkoutProduct.cents,
          entityId: 'verification',
        );
        return;
      }
      final checkoutUrl = await _repo.createCheckoutSessionUrl(
        productId: checkoutProduct.id,
        amountCents: checkoutProduct.cents,
        ownerType: 'employer',
        targetType: 'verification',
        targetId: 'verification',
      );
      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened) throw StateError('Не удалось открыть Stripe Checkout');
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      return;
    } catch (e) {
      if (!mounted) return;
      _toast('${PaymentsI18n.t(context, 'failed')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          PaymentsI18n.t(context, 'verification'),
          style: const TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          children: [
            PaymentPackageTile(
              product: PaymentProducts.verification,
              selected: true,
              onTap: () {},
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'После оплаты загрузите документы компании. Статус будет обновлён после проверки.',
                style: TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: MoneyPrimaryButton(
                text: '${PaymentsI18n.t(context, 'pay')} ${PaymentProducts.verification.priceLabel}',
                onPressed: _pay,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
