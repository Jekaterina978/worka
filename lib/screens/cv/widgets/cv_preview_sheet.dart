import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';

enum CvPreviewAction { edit, save }

class CvPreviewData {
  final String contactsName;
  final String contactsEmail;
  final String contactsPhone;

  final String title;
  final String summary;

  final String desiredCategoryGroup;
  final String desiredPosition;
  final String desiredLocationLabel;
  final String desiredEmploymentType;

  final bool noExperience;
  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> languages;
  final List<Map<String, dynamic>> education;

  const CvPreviewData({
    required this.contactsName,
    required this.contactsEmail,
    required this.contactsPhone,
    required this.title,
    required this.summary,
    required this.desiredCategoryGroup,
    required this.desiredPosition,
    required this.desiredLocationLabel,
    required this.desiredEmploymentType,
    required this.noExperience,
    required this.jobs,
    required this.languages,
    required this.education,
  });
}

class CvPreviewSheet extends StatelessWidget {
  final CvPreviewData data;

  const CvPreviewSheet({super.key, required this.data});

  String _s(String v, {String fallback = '—'}) {
    final t = v.trim();
    return t.isEmpty ? fallback : t;
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.88;

    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            const SizedBox(height: 10),

            // “ручка”
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: WorkaColors.divider,
                borderRadius: BorderRadius.circular(99),
              ),
            ),

            const SizedBox(height: 10),
            const Text(
              'Ваше CV',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: WorkaColors.textDark),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                children: [
                  // ✅ ОДНА большая “карточка поверх экрана” (как ты просила)
                  _BigCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Заголовок (крупно)
                        Text(
                          _s(data.title, fallback: 'CV'),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: WorkaColors.textDark),
                        ),
                        const SizedBox(height: 8),

                        // Контакты (мельче)
                        Wrap(
                          spacing: 14,
                          runSpacing: 8,
                          children: [
                            _MiniInfo(icon: Icons.person_outline, text: _s(data.contactsName)),
                            _MiniInfo(icon: Icons.phone_outlined, text: _s(data.contactsPhone)),
                            _MiniInfo(icon: Icons.mail_outline, text: _s(data.contactsEmail)),
                          ],
                        ),

                        const SizedBox(height: 14),
                        const Divider(height: 1, color: WorkaColors.divider),
                        const SizedBox(height: 14),

                        // Summary
                        const Text('Описание', style: TextStyle(fontWeight: FontWeight.w900, color: WorkaColors.textDark)),
                        const SizedBox(height: 8),
                        Text(
                          _s(data.summary, fallback: 'Без описания'),
                          style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800, height: 1.35),
                        ),

                        const SizedBox(height: 14),
                        const Divider(height: 1, color: WorkaColors.divider),
                        const SizedBox(height: 14),

                        // Desired Job (в конце в ТЗ — но тут в preview лучше показать тоже)
                        const Text('Желаемая работа', style: TextStyle(fontWeight: FontWeight.w900, color: WorkaColors.textDark)),
                        const SizedBox(height: 10),
                        _Line(label: 'Категория', value: _s(data.desiredCategoryGroup)),
                        _Line(label: 'Тип', value: _s(data.desiredEmploymentType)),
                        _Line(label: 'Где работать?', value: _s(data.desiredLocationLabel)),
                        if (data.desiredPosition.trim().isNotEmpty) _Line(label: 'Должность', value: data.desiredPosition.trim()),

                        const SizedBox(height: 14),
                        const Divider(height: 1, color: WorkaColors.divider),
                        const SizedBox(height: 14),

                        // Experience
                        const Text('Опыт работы', style: TextStyle(fontWeight: FontWeight.w900, color: WorkaColors.textDark)),
                        const SizedBox(height: 10),
                        if (data.noExperience)
                          const Text('Нет опыта работы', style: TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800))
                        else
                          _ListBlock(items: data.jobs, emptyText: 'Не указан'),

                        const SizedBox(height: 14),
                        const Divider(height: 1, color: WorkaColors.divider),
                        const SizedBox(height: 14),

                        // Education
                        const Text('Образование', style: TextStyle(fontWeight: FontWeight.w900, color: WorkaColors.textDark)),
                        const SizedBox(height: 10),
                        _ListBlock(items: data.education, emptyText: 'Не указано'),

                        const SizedBox(height: 14),
                        const Divider(height: 1, color: WorkaColors.divider),
                        const SizedBox(height: 14),

                        // Languages
                        const Text('Языки', style: TextStyle(fontWeight: FontWeight.w900, color: WorkaColors.textDark)),
                        const SizedBox(height: 10),
                        _ListBlock(items: data.languages, emptyText: 'Не указаны'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ✅ Кнопки снизу, как ты требовала:
            // Редактировать — белый фон, оранжевый текст
            // Готово — оранжевый фон, белый текст
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, CvPreviewAction.edit),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: WorkaColors.fieldBorder, width: 1.2),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: const Text(
                            'Редактировать',
                            style: TextStyle(color: WorkaColors.orange, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, CvPreviewAction.save),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkaColors.orange,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: const Text(
                            'Готово',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigCard extends StatelessWidget {
  final Widget child;
  const _BigCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WorkaColors.divider),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 6),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: WorkaColors.textGrey),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  const _Line({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value.trim(),
              style: const TextStyle(fontWeight: FontWeight.w900, color: WorkaColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListBlock extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String emptyText;
  const _ListBlock({required this.items, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(emptyText, style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800));
    }

    String joinMap(Map<String, dynamic> m) {
      final parts = <String>[];
      for (final e in m.entries) {
        final v = (e.value ?? '').toString().trim();
        if (v.isNotEmpty) parts.add(v);
      }
      return parts.isEmpty ? '—' : parts.join(' • ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((m) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            joinMap(m),
            style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
          ),
        );
      }).toList(),
    );
  }
}