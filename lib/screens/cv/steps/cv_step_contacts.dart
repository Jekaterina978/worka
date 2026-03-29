import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class CvStepContacts extends StatelessWidget {
  const CvStepContacts({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Введите контактные данные', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Эти данные будут отображаться в вашем CV.', style: TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),

          _field('Имя *'),
          const SizedBox(height: 12),
          _field('Фамилия *'),
          const SizedBox(height: 12),
          _field('Эл. почта *'),
          const SizedBox(height: 12),
          _field('Телефон *'),
          const SizedBox(height: 12),

          const Text('Дата рождения *', style: TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _dropdownBox('Месяц')),
              const SizedBox(width: 10),
              SizedBox(width: 90, child: _dropdownBox('День')),
              const SizedBox(width: 10),
              SizedBox(width: 110, child: _dropdownBox('Год')),
            ],
          ),
          const SizedBox(height: 10),
          _check('Скрыть в CV'),

          const SizedBox(height: 16),
          const Text('Пол *', style: TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
          const SizedBox(height: 8),
          _dropdownBox('женщина'),

          const SizedBox(height: 10),
          _check('Скрыть в CV'),

          const SizedBox(height: 16),
          const Text('Язык общения *', style: TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
          const SizedBox(height: 8),
          _dropdownBox('русский'),
        ],
      ),
    );
  }

  Widget _field(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WorkaColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
            ),
          ),
        ),
      ],
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

  Widget _check(String text) {
    return Row(
      children: [
        Checkbox(value: false, onChanged: (_) {}, activeColor: WorkaColors.blue),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: WorkaColors.textGreyDark)),
      ],
    );
  }
}
