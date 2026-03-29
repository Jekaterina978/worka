import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';
import '../../../features/monetization/pricing.dart';

class CvStepDesiredJob extends StatelessWidget {
  const CvStepDesiredJob({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Какую работу Вы ищете?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            'Почти готово! Расскажите, какую работу Вы ищете. Если Вы ищете работу в нескольких сферах, Вы можете создать до ${MonetizationPricing.workerFreeActiveCvLimit} разных CV.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),

          _field('Категория'),
          const SizedBox(height: 12),
          _field('Должность'),
          const SizedBox(height: 12),
          _field('Уровень'),
          const SizedBox(height: 12),
          _field('Местонахождения'),
          const SizedBox(height: 12),
          _field('Тип работы'),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _field(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: WorkaColors.fieldBorder),
          ),
          child: Row(
            children: [
              const Expanded(child: Text('')),
              const Icon(
                Icons.keyboard_arrow_down,
                color: WorkaColors.textGreyDark,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
