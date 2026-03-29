import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class CvStepLanguages extends StatelessWidget {
  const CvStepLanguages({super.key});

  @override
  Widget build(BuildContext context) {
    // Заглушка “как на скрине”: язык + звёзды + сохранить
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Владение языками', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),

          const Text('Язык', style: TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
          const SizedBox(height: 8),
          _dropdownBox(''),

          const SizedBox(height: 18),
          _starsBlock('Слушание'),
          const SizedBox(height: 16),
          _starsBlock('Чтение'),
          const SizedBox(height: 16),
          _starsBlock('Коммуникация'),
          const SizedBox(height: 16),
          _starsBlock('Презентация'),
          const SizedBox(height: 16),
          _starsBlock('Владение письменной речью'),

          const SizedBox(height: 18),
          Row(
            children: const [
              Icon(Icons.add_circle_outline, color: WorkaColors.textGreyDark),
              SizedBox(width: 10),
              Text('Дополнительная информация', style: TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropdownBox(String value) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: WorkaColors.textDark))),
          const Icon(Icons.keyboard_arrow_down, color: WorkaColors.textGreyDark),
        ],
      ),
    );
  }

  Widget _starsBlock(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
        const SizedBox(height: 10),
        Row(
          children: List.generate(
            6,
            (_) => const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.star_border, color: WorkaColors.textGreyDark, size: 28),
            ),
          ),
        ),
      ],
    );
  }
}
