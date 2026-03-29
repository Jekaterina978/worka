import 'package:flutter/material.dart';
import 'package:worka/features/monetization/pricing.dart';
import 'package:worka/theme/worka_colors.dart';

class PrivatePlansScreen extends StatelessWidget {
  const PrivatePlansScreen({super.key});

  Widget _plan({
    required String title,
    required String subtitle,
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
      child: Text(
        '$title\n$subtitle',
        style: const TextStyle(
          color: WorkaColors.textDark,
          fontWeight: FontWeight.w800,
          height: 1.35,
        ),
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
          'Тарифы для private',
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
            subtitle: '1 active vacancy',
            highlighted: false,
          ),
          _plan(
            title:
                'Private Starter ${MonetizationPricing.eur(MonetizationPricing.privateStarterMonthly)}/mo',
            subtitle: '2 active vacancies • 10 credits/month • 1 bump/month',
            highlighted: true,
          ),
          _plan(
            title:
                'Private Plus ${MonetizationPricing.eur(MonetizationPricing.privatePlusMonthly)}/mo',
            subtitle:
                '3 active vacancies • 20 credits/month • 2 bumps/month • urgent x1/month',
            highlighted: false,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: WorkaColors.fieldBorder),
            ),
            child: const Text(
              'Business/Agency tools (bulk upload, mass messaging, CV database) are coming soon.',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
