import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/widgets/worka_condition_icons.dart';

enum VacancyDetailsActionsMode { workerApply, employerManage, none }

class VacancyDetailsViewData {
  final String title;
  final String company;
  final String location;
  final String salary;
  final String category;
  final String employmentType;
  final String experience;
  final String summary;
  final List<String> responsibilities;
  final List<String> requirements;
  final List<String> physicalDemands;
  final List<String> benefits;
  final List<Widget> descriptionBlocks;
  final JobConditions conditions;

  const VacancyDetailsViewData({
    required this.title,
    required this.company,
    required this.location,
    required this.salary,
    required this.category,
    required this.employmentType,
    required this.experience,
    required this.summary,
    required this.responsibilities,
    required this.requirements,
    required this.physicalDemands,
    required this.benefits,
    required this.descriptionBlocks,
    required this.conditions,
  });

  static String _s(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    final t = v.toString().trim();
    return t.isEmpty ? fallback : t;
  }

  static List<String> _splitBulletItems(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return const <String>[];
    final lines = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final out = <String>[];
    for (final l in lines) {
      final item = l.replaceFirst(RegExp(r'^[-*•]\s*'), '').trim();
      if (item.isNotEmpty) out.add(item);
    }
    return out;
  }

  static const Set<String> _flagMarkers = <String>{
    '🇩🇪',
    '🇪🇪',
    '🇵🇱',
    '🇫🇮',
    '🇸🇪',
    '🇬🇧',
    '🇺🇦',
    '🇪🇺',
  };

  static bool _startsWithAny(String line, List<String> markers) {
    final trimmed = line.trimLeft();
    return markers.any((m) => trimmed.startsWith(m));
  }

  static String _stripLeadingMarker(String line, List<String> markers) {
    final trimmed = line.trimLeft();
    for (final marker in markers) {
      if (trimmed.startsWith(marker)) {
        return trimmed.substring(marker.length).trim();
      }
    }
    return trimmed;
  }

  static bool _isBulletLine(String line) {
    final trimmed = line.trimLeft();
    return trimmed.startsWith('•') ||
        trimmed.startsWith('-') ||
        trimmed.startsWith('*') ||
        trimmed.startsWith('—');
  }

  static _IconLineData? _parseIconLine(String line) {
    final raw = line.trim();
    if (raw.isEmpty) return null;

    if (_flagMarkers.any((f) => raw.startsWith(f))) {
      final flag = _flagMarkers.firstWhere((f) => raw.startsWith(f));
      final content = raw.substring(flag.length).trim();
      return _IconLineData(flagEmoji: flag, text: content);
    }

    if (_startsWithAny(raw, const ['💶', '💰'])) {
      return _IconLineData(
        icon: Icons.payments_outlined,
        text: _stripLeadingMarker(raw, const ['💶', '💰']),
      );
    }
    if (_startsWithAny(raw, const ['⏰', '🕒'])) {
      return _IconLineData(
        icon: Icons.schedule,
        text: _stripLeadingMarker(raw, const ['⏰', '🕒']),
      );
    }
    if (_startsWithAny(raw, const ['📄', '🪪'])) {
      return _IconLineData(
        icon: Icons.description_outlined,
        text: _stripLeadingMarker(raw, const ['📄', '🪪']),
      );
    }
    if (_startsWithAny(raw, const ['🏠'])) {
      return _IconLineData(
        icon: Icons.home_outlined,
        text: _stripLeadingMarker(raw, const ['🏠']),
      );
    }
    if (_startsWithAny(raw, const ['🚗'])) {
      return _IconLineData(
        icon: Icons.directions_car_outlined,
        text: _stripLeadingMarker(raw, const ['🚗']),
      );
    }
    if (_startsWithAny(raw, const ['🚌'])) {
      return _IconLineData(
        icon: Icons.directions_bus_outlined,
        text: _stripLeadingMarker(raw, const ['🚌']),
      );
    }

    return null;
  }

  static List<Widget> parseDescriptionToBlocks(String text) {
    final input = text.trim();
    if (input.isEmpty) return const <Widget>[];

    final widgets = <Widget>[];
    final parts = input
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    for (final part in parts) {
      final lines = part
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (lines.isEmpty) continue;

      final bulletItems = <String>[];
      final iconLines = <_IconLineData>[];
      final paragraphLines = <String>[];

      for (final line in lines) {
        final iconLine = _parseIconLine(line);
        if (iconLine != null) {
          iconLines.add(iconLine);
          continue;
        }
        if (_isBulletLine(line)) {
          bulletItems.add(line.replaceFirst(RegExp(r'^[•\-*—]\s*'), '').trim());
          continue;
        }
        paragraphLines.add(line);
      }

      if (iconLines.isNotEmpty) {
        widgets.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < iconLines.length; i++) ...[
                _IconLineRow(data: iconLines[i]),
                if (i != iconLines.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        );
      }

      if (bulletItems.isNotEmpty) {
        widgets.add(_BulletList(items: bulletItems));
      }

      if (paragraphLines.isNotEmpty) {
        widgets.add(_Paragraph(paragraphLines.join('\n')));
      }
    }

    return widgets;
  }

  static _JobTextSections _extractSectionsFromBlob(String text) {
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String current = 'description';
    final buckets = <String, List<String>>{
      'description': <String>[],
      'responsibilities': <String>[],
      'requirements': <String>[],
      'physical': <String>[],
      'benefits': <String>[],
      'salary': <String>[],
    };

    bool isHeader(String line, List<String> keys) {
      final l = line.toLowerCase();
      return keys.any((k) => l.startsWith(k));
    }

    for (final line in lines) {
      if (isHeader(line, const [
        'responsibilities:',
        'обязанности:',
        'задачи:',
      ])) {
        current = 'responsibilities';
        continue;
      }
      if (isHeader(line, const ['requirements:', 'требования:'])) {
        current = 'requirements';
        continue;
      }
      if (isHeader(line, const ['benefits:', 'условия:', 'преимущества:'])) {
        current = 'benefits';
        continue;
      }
      if (isHeader(line, const [
        'physical demands:',
        'физические нагрузки:',
        'нагрузки:',
      ])) {
        current = 'physical';
        continue;
      }
      if (isHeader(line, const ['salary:', 'зарплата:'])) {
        current = 'salary';
        continue;
      }
      buckets[current]!.add(line);
    }

    return _JobTextSections(
      description: buckets['description']!.join('\n').trim(),
      responsibilities: buckets['responsibilities']!,
      requirements: buckets['requirements']!,
      physicalDemands: buckets['physical']!,
      benefits: buckets['benefits']!,
      salaryLines: buckets['salary']!,
    );
  }

  factory VacancyDetailsViewData.fromJobMap(Map<String, dynamic> job) {
    final employer = (job['employer'] is Map<String, dynamic>)
        ? (job['employer'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final title = _s(job['title'], fallback: 'Без названия');
    final company = _s(
      employer['companyName'] ?? job['companyName'],
      fallback: 'Работодатель',
    );
    final city = _s(job['city'], fallback: 'Локация не указана');
    final country = _s(job['country'], fallback: '');
    final location = [
      city,
      country,
    ].where((e) => e.trim().isNotEmpty).join(', ');
    final salary = _s(
      job['salaryText'] ?? job['salary'],
      fallback: 'Зарплата не указана',
    );
    final category = _s(job['category'], fallback: 'Категория не указана');
    final workScheduleOption = _s(job['workScheduleOption'], fallback: '');
    final workScheduleCustom = _s(job['workScheduleCustom'], fallback: '');
    final workSchedule = _s(job['workSchedule'], fallback: '');
    final fallbackType = _s(
      job['type'] ?? job['employmentType'],
      fallback: 'Тип не указан',
    );
    String type = fallbackType;
    if (workScheduleOption.isNotEmpty) {
      if (workScheduleOption == 'Другое') {
        final custom = workScheduleCustom.isNotEmpty
            ? workScheduleCustom
            : workSchedule;
        type = custom.isNotEmpty ? custom : 'Другое';
      } else {
        type = workScheduleOption;
      }
    } else if (workSchedule.isNotEmpty) {
      type = workSchedule;
    }
    final exp = _s(job['experience'], fallback: '');
    final summary = _s(job['summary'] ?? job['about'], fallback: '');

    final desc = _s(job['description'], fallback: '');
    final directResponsibilities = _s(job['responsibilities'], fallback: '');
    final directRequirements = _s(job['requirements'], fallback: '');
    final directBenefits = _s(job['benefits'], fallback: '');
    final directPhysical = _s(job['physicalDemands'], fallback: '');

    final parsed = _extractSectionsFromBlob(desc);
    final responsibilities = directResponsibilities.isNotEmpty
        ? _splitBulletItems(directResponsibilities)
        : parsed.responsibilities;
    final requirements = directRequirements.isNotEmpty
        ? _splitBulletItems(directRequirements)
        : parsed.requirements;
    final physicalDemands = directPhysical.isNotEmpty
        ? _splitBulletItems(directPhysical)
        : parsed.physicalDemands;
    final benefits = directBenefits.isNotEmpty
        ? _splitBulletItems(directBenefits)
        : parsed.benefits;

    return VacancyDetailsViewData(
      title: title,
      company: company,
      location: location,
      salary: salary,
      category: category,
      employmentType: type,
      experience: exp,
      summary: summary,
      responsibilities: responsibilities,
      requirements: requirements,
      physicalDemands: physicalDemands,
      benefits: benefits,
      descriptionBlocks: parseDescriptionToBlocks(parsed.description),
      conditions: JobConditions(
        housingProvided: (job['housingProvided'] ?? false) == true,
        transportProvided: (job['transportProvided'] ?? false) == true,
        forTeenagers: (job['teenFriendly'] ?? false) == true,
        forDisabled:
            (job['forDisabled'] ?? job['disabilityFriendly'] ?? false) == true,
      ),
    );
  }
}

class VacancyDetailsView extends StatelessWidget {
  final VacancyDetailsViewData data;
  final VacancyDetailsActionsMode actionsMode;
  final Widget? bottomActions;
  final Widget? headerHighlightAction;
  final String title;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  final double actionHeight;
  final double headerActionWidth;
  final double headerActionHeight;

  const VacancyDetailsView({
    super.key,
    required this.data,
    required this.actionsMode,
    required this.onBack,
    this.onClose,
    this.bottomActions,
    this.headerHighlightAction,
    this.title = 'Вакансия',
    this.actionHeight = 56,
    this.headerActionWidth = 132,
    this.headerActionHeight = 38,
  });

  @override
  Widget build(BuildContext context) {
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final hasBottom = bottomActions != null;

    final Widget headerActionSlot =
        headerHighlightAction ??
        IgnorePointer(
          child: Opacity(
            opacity: 0,
            child: OutlinedButton(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: WorkaColors.orange),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              child: const Text(
                'Выделить',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: hasBottom
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(height: actionHeight, child: bottomActions),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(
                      Icons.arrow_back,
                      color: WorkaColors.textDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: WorkaColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose ?? onBack,
                    icon: const Icon(Icons.close, color: WorkaColors.textDark),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  (hasBottom ? actionHeight + 24 : 24) + safeAreaBottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.title,
                                style: const TextStyle(
                                  fontSize: 28,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  color: WorkaColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                data.company,
                                style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                  color: WorkaColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 1),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      size: 16,
                                      color: WorkaColors.textGreyDark,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      data.location.isEmpty
                                          ? 'Локация не указана'
                                          : data.location,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                        color: WorkaColors.textGreyDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: headerActionWidth,
                          height: headerActionHeight,
                          child: headerActionSlot,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _Section(title: 'Зарплата', child: _Paragraph(data.salary)),
                    const SizedBox(height: 24),
                    _Section(
                      title: 'Детали',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Paragraph('Категория: ${data.category}'),
                          const SizedBox(height: 8),
                          _Paragraph('График: ${data.employmentType}'),
                          if (data.experience.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _Paragraph('Опыт: ${data.experience}'),
                          ],
                        ],
                      ),
                    ),
                    if (data.descriptionBlocks.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _Section(
                        title: 'Описание',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              int i = 0;
                              i < data.descriptionBlocks.length;
                              i++
                            ) ...[
                              data.descriptionBlocks[i],
                              if (i != data.descriptionBlocks.length - 1)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (data.responsibilities.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _Section(
                        title: 'Обязанности',
                        child: _BulletList(items: data.responsibilities),
                      ),
                    ],
                    if (data.requirements.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _Section(
                        title: 'Требования',
                        child: _BulletList(items: data.requirements),
                      ),
                    ],
                    if (data.benefits.isNotEmpty ||
                        data.conditions.housingProvided ||
                        data.conditions.transportProvided ||
                        data.conditions.forTeenagers ||
                        data.conditions.forDisabled) ...[
                      const SizedBox(height: 24),
                      _Section(
                        title: 'Benefits',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (data.benefits.isNotEmpty)
                              _BulletList(items: data.benefits),
                            if (data.conditions.housingProvided ||
                                data.conditions.transportProvided ||
                                data.conditions.forTeenagers ||
                                data.conditions.forDisabled) ...[
                              if (data.benefits.isNotEmpty)
                                const SizedBox(height: 12),
                              WorkaConditionIcons(
                                conditions: data.conditions,
                                size: 34,
                                iconSize: 20,
                                spacing: 10,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (data.physicalDemands.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _Section(
                        title: 'Физические нагрузки',
                        child: _BulletList(items: data.physicalDemands),
                      ),
                    ],
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

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: WorkaColors.textDark,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.trim(),
      style: const TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color: WorkaColors.textDark,
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    color: WorkaColors.textGreyDark,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.trim(),
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: WorkaColors.textGreyDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _IconLineData {
  final IconData? icon;
  final String? flagEmoji;
  final String text;

  const _IconLineData({this.icon, this.flagEmoji, required this.text});
}

class _IconLineRow extends StatelessWidget {
  final _IconLineData data;
  const _IconLineRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.flagEmoji != null)
          SizedBox(
            width: 22,
            child: Text(
              data.flagEmoji!,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
          )
        else
          SizedBox(
            width: 22,
            child: Icon(
              data.icon ?? Icons.info_outline,
              size: 16,
              color: WorkaColors.textGreyDark,
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            data.text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: WorkaColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _JobTextSections {
  final String description;
  final List<String> responsibilities;
  final List<String> requirements;
  final List<String> physicalDemands;
  final List<String> benefits;
  final List<String> salaryLines;

  const _JobTextSections({
    required this.description,
    required this.responsibilities,
    required this.requirements,
    required this.physicalDemands,
    required this.benefits,
    required this.salaryLines,
  });
}
