import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class CvStepEducation extends StatelessWidget {
  const CvStepEducation({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Высший уровень Вашего образования', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('Пожалуйста, выберите свой высший уровень образования.', style: TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),

          _field('Высший уровень образования'),
          const SizedBox(height: 12),
          _field('Учебное заведение'),
          const SizedBox(height: 12),
          _field('Специальность'),
          const SizedBox(height: 12),
          _field('Дополнительная специальность'),
          const SizedBox(height: 12),
          _field('Государство', dropdown: true, value: 'Эстония'),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(child: _field('Начало', dropdown: true)),
              const SizedBox(width: 12),
              Expanded(child: _field('Окончено', dropdown: true)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(value: false, onChanged: (_) {}, activeColor: WorkaColors.blue),
              const Text('Еще учусь', style: TextStyle(fontWeight: FontWeight.w700, color: WorkaColors.textGreyDark)),
              const SizedBox(width: 18),
              Checkbox(value: false, onChanged: (_) {}, activeColor: WorkaColors.blue),
              const Text('Неоконченное', style: TextStyle(fontWeight: FontWeight.w700, color: WorkaColors.textGreyDark)),
            ],
          ),

          const SizedBox(height: 12),
          _field('Дополнительная информация', multiline: true, height: 120),
        ],
      ),
    );
  }

  Widget _field(String label, {bool dropdown = false, String value = '', bool multiline = false, double height = 56}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
        const SizedBox(height: 8),
        Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: WorkaColors.fieldBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: WorkaColors.textDark),
                ),
              ),
              if (dropdown) const Icon(Icons.keyboard_arrow_down, color: WorkaColors.textGreyDark),
              if (!dropdown && multiline) const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}
