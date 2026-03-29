import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:worka/services/ownership_resolver.dart';
import '../widgets/worka_header.dart';

class VacancyScreen extends StatelessWidget {
  final String jobId;

  const VacancyScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context) {
    final jobRef = FirebaseFirestore.instance.collection('jobs').doc(jobId);

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Вакансия',
            leading: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: jobRef.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Ошибка: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final doc = snap.data!;
                  if (!doc.exists) {
                    return const Center(child: Text('Вакансия не найдена'));
                  }

                  final data = doc.data() ?? {};

                  String s(dynamic v, {String fallback = ''}) {
                    if (v == null) return fallback;
                    final t = v.toString().trim();
                    return t.isEmpty ? fallback : t;
                  }

                  final title = s(data['title'], fallback: 'Без названия');
                  final companyName = s(
                    data['companyName'],
                    fallback: 'Компания',
                  );
                  final city = s(data['city'], fallback: 'Локация не указана');

                  // У тебя salary может быть строкой ("70€ / день")
                  final salary = s(
                    data['salary'],
                    fallback: 'Зарплата не указана',
                  );

                  // Новые поля (если не добавлены — покажем аккуратно)
                  final category = s(
                    data['category'],
                    fallback: 'Категория не указана',
                  );
                  final type = s(data['type'], fallback: 'Тип не указан');

                  // Если ты добавишь salaryFromNum (number), покажем "от ..."
                  final salaryFromNum = data['salaryFromNum'];
                  final salaryFromText = (salaryFromNum is num)
                      ? 'от ${salaryFromNum.toInt()}'
                      : null;

                  final description = s(data['description'], fallback: '');
                  final requirements = s(data['requirements'], fallback: '');

                  final isPremium = (data['isPremium'] ?? false) == true;
                  final vacancyOwnership = OwnershipResolver.vacancyOwnership(
                    data,
                  );
                  final isOwnerView =
                      vacancyOwnership.known && vacancyOwnership.isOwner;

                  return Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                        children: [
                          _HeaderCard(
                            title: title,
                            companyName: companyName,
                            city: city,
                            salary: salary,
                            isPremium: isPremium,
                          ),
                          const SizedBox(height: 12),

                          _InfoCard(
                            items: [
                              _InfoItem(
                                icon: Icons.category_outlined,
                                label: 'Категория',
                                value: category,
                              ),
                              _InfoItem(
                                icon: Icons.work_outline,
                                label: 'Тип',
                                value: type,
                              ),
                              _InfoItem(
                                icon: Icons.payments_outlined,
                                label: 'Зарплата',
                                value: salaryFromText ?? salary,
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          if (description.isNotEmpty) ...[
                            _SectionCard(title: 'Описание', text: description),
                            const SizedBox(height: 12),
                          ],

                          if (requirements.isNotEmpty) ...[
                            _SectionCard(
                              title: 'Требования',
                              text: requirements,
                            ),
                            const SizedBox(height: 12),
                          ],

                          _CompanyCard(
                            companyName: companyName,
                            onOpen: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Профиль компании'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      // Bottom button
                      if (!isOwnerView)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: SafeArea(
                            minimum: const EdgeInsets.all(16),
                            child: SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Отклик отправлен ✅ (пока заглушка)',
                                      ),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Взять работу',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String title;
  final String companyName;
  final String city;
  final String salary;
  final bool isPremium;

  const _HeaderCard({
    required this.title,
    required this.companyName,
    required this.city,
    required this.salary,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isPremium)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFFFD8B3)),
                    ),
                    child: const Text(
                      'Premium',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFF7A00),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(Icons.apartment, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    companyName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(city)),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    salary,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  _InfoItem({required this.icon, required this.label, required this.value});
}

class _InfoCard extends StatelessWidget {
  final List<_InfoItem> items;

  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: items
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(e.icon, size: 18),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 90,
                        child: Text(
                          e.label,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.value,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _SectionCard extends StatefulWidget {
  final String title;
  final String text;

  const _SectionCard({required this.title, required this.text});

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final maxLines = expanded ? 999 : 7;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              widget.text,
              maxLines: maxLines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? 'Скрыть' : 'Показать больше'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  final String companyName;
  final VoidCallback onOpen;

  const _CompanyCard({required this.companyName, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.apartment),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                companyName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton(onPressed: onOpen, child: const Text('Профиль')),
          ],
        ),
      ),
    );
  }
}
