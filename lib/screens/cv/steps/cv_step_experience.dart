import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class CvStepExperience extends StatelessWidget {
  const CvStepExperience({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('Каким был Ваш последний опыт работы?', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text(
            'Расскажите о своем последнем или нынешнем рабочем опыте, используя ключевые слова.',
            textAlign: TextAlign.center,
            style: TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),

          _field('Должность'),
          const SizedBox(height: 12),
          _field('Категория работы', dropdown: true),
          const SizedBox(height: 12),
          _field('Название фирмы'),
          const SizedBox(height: 12),
          _field('Категория организации', dropdown: true),
          const SizedBox(height: 12),

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
              const Text('Еще работаю', style: TextStyle(fontWeight: FontWeight.w700, color: WorkaColors.textGreyDark)),
            ],
          ),
          const SizedBox(height: 12),

          _field('Описание работы и достижения', multiline: true, height: 140),
          const SizedBox(height: 14),
          _field('Общий опыт работы в годах', dropdown: true),

          const SizedBox(height: 14),
          Row(
            children: const [
              Icon(Icons.info_outline, color: WorkaColors.blue),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Сколько лет у Вас всего опыта работы, включая Ваш последний/нынешний опыт работы?',
                  style: TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () {},
              child: const Text('У меня нет опыта работы  ›', style: TextStyle(color: WorkaColors.blue, fontWeight: FontWeight.w800)),
            ),
          )
        ],
      ),
    );
  }

  Widget _field(String label, {bool dropdown = false, bool multiline = false, double height = 56}) {
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
              const Expanded(child: Text('')),
              if (dropdown) const Icon(Icons.keyboard_arrow_down, color: WorkaColors.textGreyDark),
            ],
          ),
        ),
      ],
    );
  }
}
