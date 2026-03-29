import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

class CvStepTitle extends StatelessWidget {
  const CvStepTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('Название CV и краткое изложение', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text(
            'Создайте заголовок CV и напишите краткое изложение о своем рабочем опыте, целях, достижениях.',
            textAlign: TextAlign.center,
            style: TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),

          Align(
            alignment: Alignment.centerLeft,
            child: Text('Заголовок', style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
          ),
          const SizedBox(height: 8),
          _input(height: 56),

          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Краткое вступление', style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark)),
          ),
          const SizedBox(height: 8),
          _input(height: 140, multiline: true),

          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Отличный пример: ...',
              style: TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input({required double height, bool multiline = false}) {
    return SizedBox(
      height: height,
      child: TextField(
        maxLines: multiline ? null : 1,
        expands: multiline,
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
    );
  }
}
