import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'employer/create_job_screen.dart';
import '../theme/worka_colors.dart';
import '../widgets/worka_header.dart';

class VacancyReviewScreen extends StatefulWidget {
  const VacancyReviewScreen({
    super.key,
    required this.jobId,
    required this.jobRef,
    required this.testMode,
  });

  final String jobId;
  final DocumentReference<Map<String, dynamic>> jobRef;
  final bool testMode;

  @override
  State<VacancyReviewScreen> createState() => _VacancyReviewScreenState();
}

class _VacancyReviewScreenState extends State<VacancyReviewScreen> {
  String _s(dynamic v, {String fallback = 'Не указано'}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _salary(Map<String, dynamic> m) {
    final text = _s(m['salaryText'], fallback: _s(m['salary'], fallback: ''));
    if (text.isNotEmpty) return text;
    final from = (m['salaryFrom'] ?? '').toString().trim();
    final to = (m['salaryTo'] ?? '').toString().trim();
    final currency = _s(m['salaryCurrency'], fallback: 'EUR');
    final period = _s(m['salaryPeriodRu'], fallback: _s(m['salaryPeriod']));
    if (from.isEmpty && to.isEmpty) return 'Не указано';
    final amount = to.isEmpty ? from : '$from - $to';
    return '$amount $currency${period.isEmpty ? '' : ' / $period'}';
  }

  String _vacancyNumber(Map<String, dynamic> m) {
    final candidates = <String>[
      (m['vacancyNumber'] ?? '').toString().trim(),
      (m['jobNumber'] ?? '').toString().trim(),
      (m['publicId'] ?? '').toString().trim(),
    ];
    for (final value in candidates) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> _openEditStep(int step) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateJobScreen(
          editJobId: widget.jobId,
          editJobRef: widget.jobRef,
          testMode: widget.testMode,
          initialStep: step,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Редактировать вакансию',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
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
                stream: widget.jobRef.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final job = snap.data?.data() ?? const <String, dynamic>{};
                  final vacancyNumber = _vacancyNumber(job);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _EditableBlock(
                        icon: Icons.description_outlined,
                        title: 'Основное',
                        fields: [
                          if (vacancyNumber.isNotEmpty)
                            _FieldPair('Номер вакансии', vacancyNumber),
                          _FieldPair('Название', _s(job['title'])),
                          _FieldPair('Категория', _s(job['category'])),
                          _FieldPair('Описание', _s(job['description'])),
                        ],
                        onEdit: () => _openEditStep(0),
                      ),
                      _EditableBlock(
                        icon: Icons.location_on_outlined,
                        title: 'Локация',
                        fields: [
                          _FieldPair('Страна', _s(job['country'])),
                          _FieldPair('Город', _s(job['city'])),
                        ],
                        onEdit: () => _openEditStep(0),
                      ),
                      _EditableBlock(
                        icon: Icons.payments_outlined,
                        title: 'Условия',
                        fields: [
                          _FieldPair('Зарплата', _salary(job)),
                          _FieldPair(
                            'Тип занятости',
                            _s(
                              job['employmentType'],
                              fallback: _s(job['workSchedule']),
                            ),
                          ),
                        ],
                        onEdit: () => _openEditStep(1),
                      ),
                      _EditableBlock(
                        icon: Icons.checklist_rtl_outlined,
                        title: 'Требования',
                        fields: [
                          _FieldPair('Опыт', _s(job['experience'])),
                          _FieldPair(
                            'Языки',
                            (job['languages'] is List &&
                                    (job['languages'] as List).isNotEmpty)
                                ? (job['languages'] as List)
                                      .map((e) => e.toString())
                                      .join(', ')
                                : 'Не указано',
                          ),
                          _FieldPair(
                            'Вод. права',
                            (job['drivingLicenses'] is List &&
                                    (job['drivingLicenses'] as List).isNotEmpty)
                                ? (job['drivingLicenses'] as List)
                                      .map((e) => e.toString())
                                      .join(', ')
                                : 'Не указано',
                          ),
                        ],
                        onEdit: () => _openEditStep(2),
                      ),
                      _EditableBlock(
                        icon: Icons.business_outlined,
                        title: 'Компания',
                        fields: [
                          _FieldPair('Компания', _s(job['companyName'])),
                          _FieldPair(
                            'Контакт',
                            '${_s(job['contactFirstName'], fallback: '')} ${_s(job['contactLastName'], fallback: '')}'
                                    .trim()
                                    .isEmpty
                                ? 'Не указано'
                                : '${_s(job['contactFirstName'], fallback: '')} ${_s(job['contactLastName'], fallback: '')}'
                                      .trim(),
                          ),
                          _FieldPair('Email', _s(job['email'])),
                          _FieldPair(
                            'Телефон',
                            _s(job['phoneNumber'], fallback: _s(job['phone'])),
                          ),
                        ],
                        onEdit: () => _openEditStep(4),
                      ),
                      _EditableBlock(
                        icon: Icons.star_outline_rounded,
                        title: 'Бонусы',
                        fields: [
                          _FieldPair(
                            'Жильё',
                            job['housingProvided'] == true ? 'Да' : 'Нет',
                          ),
                          _FieldPair(
                            'Транспорт',
                            job['transportProvided'] == true ? 'Да' : 'Нет',
                          ),
                          _FieldPair(
                            'Срочная',
                            job['isUrgent'] == true ? 'Да' : 'Нет',
                          ),
                        ],
                        onEdit: () => _openEditStep(3),
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

class _EditableBlock extends StatelessWidget {
  const _EditableBlock({
    required this.icon,
    required this.title,
    required this.fields,
    required this.onEdit,
  });

  final IconData icon;
  final String title;
  final List<_FieldPair> fields;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: WorkaColors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: WorkaColors.textDark,
                  ),
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, color: WorkaColors.blue),
                tooltip: 'Изменить',
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...fields.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${f.label}: ${f.value}',
                style: const TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldPair {
  const _FieldPair(this.label, this.value);
  final String label;
  final String value;
}
