import 'package:flutter/material.dart';

import '../widgets/primary_pill_button.dart';
import '../widgets/profile_card.dart';
import '../widgets/secondary_pill_button.dart';

class NewResponseScreen extends StatelessWidget {
  const NewResponseScreen({super.key});

  static const _bg = Colors.white;
  static const _white = Colors.white;
  static const _title = Color(0xFF3F73F1);
  static const _textPrimary = Color(0xFF1F2430);
  static const _textSecondary = Color(0xFF8A93A3);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromRGBO(0, 0, 0, 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _HeaderRow(
                            onBack: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Вы получили новый отклик на вакансию «Сварщик».',
                            style: TextStyle(
                              fontSize: 18,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const ProfileCard(
                            initials: 'LF',
                            name: 'Лев Фролов',
                            subtitle: 'Lev Frolov',
                            email: 'lev.frolov@gmail.com',
                            phone: '+7 999 123-45-67',
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Кандидат прикрепил своё резюме к этому сообщению.',
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: _textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEFF3FF),
                                foregroundColor: const Color(0xFF3F73F1),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              icon: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3F73F1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.description_outlined, size: 16, color: Colors.white),
                              ),
                              label: const Text(
                                'Открыть резюме',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: SecondaryPillButton(
                                  label: 'Отклонить',
                                  icon: Icons.close,
                                  onPressed: () {},
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: PrimaryPillButton(
                                  label: 'Принять',
                                  icon: Icons.check,
                                  onPressed: () {},
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: NewResponseScreen._textPrimary),
        ),
        const Expanded(
          child: Text(
            'Новый отклик',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: NewResponseScreen._title,
            ),
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded, color: NewResponseScreen._textPrimary),
        ),
      ],
    );
  }
}
