import 'package:flutter/material.dart';
import 'package:worka/features/monetization/pricing.dart';
import 'package:worka/features/payments/widgets/money_primary_button.dart';
import 'package:worka/theme/worka_colors.dart';

class BoostProfilePaywallScreen extends StatelessWidget {
  const BoostProfilePaywallScreen({super.key});

  void _comingSoon(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Скоро'),
        backgroundColor: WorkaColors.textDark,
      ),
    );
  }

  Widget _card({
    required String title,
    required String price,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MoneyPrimaryButton(
            text: price,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Прокачать профиль',
          style: TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          _card(
            title: 'Поднять резюме',
            price: MonetizationPricing.eur(MonetizationPricing.boostCv48h),
            subtitle: '48h',
            onTap: () => _comingSoon(context),
          ),
          _card(
            title: 'Выделить профиль',
            price: MonetizationPricing.eur(
              MonetizationPricing.highlightProfile7d,
            ),
            subtitle: '7 дней',
            onTap: () => _comingSoon(context),
          ),
          _card(
            title: 'Приоритет в поиске',
            price: MonetizationPricing.eur(
              MonetizationPricing.prioritySearch7d,
            ),
            subtitle: '7 дней',
            onTap: () => _comingSoon(context),
          ),
          _card(
            title: 'Верификация профиля',
            price: MonetizationPricing.eur(MonetizationPricing.verifiedProfile),
            subtitle: 'единоразово',
            onTap: () => _comingSoon(context),
          ),
        ],
      ),
    );
  }
}
