import 'package:flutter/material.dart';
import 'package:worka/features/monetization/monetization_i18n.dart';
import 'package:worka/features/monetization/monetization_routes.dart';
import 'package:worka/features/monetization/pricing.dart';
import 'package:worka/features/payments/widgets/money_primary_button.dart';
import 'package:worka/theme/worka_colors.dart';

class WorkerPlansScreen extends StatelessWidget {
  const WorkerPlansScreen({super.key});

  void _openBoost(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamed(MonetizationRoutes.workerBoostProfile);
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
          MonetizationI18n.t(context, 'worker_plus'),
          style: const TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WorkaColors.hoverBlueSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: WorkaColors.fieldBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${MonetizationI18n.t(context, 'worker_plus')} • ${MonetizationPricing.eur(MonetizationPricing.workerPlusMonthly)}/mo',
                  style: const TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• +3 extra CVs\n• 1 boost per week\n• priority ranking in search',
                  style: TextStyle(
                    color: WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: MoneyPrimaryButton(
              text: MonetizationI18n.t(context, 'upgrade'),
              onPressed: () => _openBoost(context),
            ),
          ),
        ],
      ),
    );
  }
}
