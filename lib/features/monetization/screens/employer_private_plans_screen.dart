import 'package:flutter/material.dart';
import 'package:worka/features/monetization/pricing.dart';
import 'package:worka/theme/worka_colors.dart';

class EmployerPrivatePlansScreen extends StatelessWidget {
  const EmployerPrivatePlansScreen({super.key});

  Widget _plan({
    required String title,
    required String price,
    required List<String> features,
    required bool highlighted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? WorkaColors.hoverBlueSoft : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? WorkaColors.blue : WorkaColors.fieldBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title • $price/mo',
            style: const TextStyle(
              color: WorkaColors.textDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $f',
                style: const TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
          'Private employer plans',
          style: TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          _plan(
            title: 'Private Free',
            price: '€ 0',
            features: const [
              '1 active vacancy',
              'up to 10 responses',
              'contacts via credits only',
            ],
            highlighted: false,
          ),
          _plan(
            title: 'Private Starter',
            price: MonetizationPricing.eur(
              MonetizationPricing.privateStarterMonthly,
            ),
            features: const [
              'up to 2 active vacancies',
              '10 credits / month',
              '1 bump / month',
            ],
            highlighted: true,
          ),
          _plan(
            title: 'Private Plus',
            price: MonetizationPricing.eur(
              MonetizationPricing.privatePlusMonthly,
            ),
            features: const [
              'up to 3 active vacancies',
              '20 credits / month',
              '2 bumps / month',
              'urgent x1 / month',
            ],
            highlighted: false,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: WorkaColors.fieldBorder),
            ),
            child: const Text(
              'Business / Agency plans are locked for now.\nTap notify and we will enable mass-hiring tools later.',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
