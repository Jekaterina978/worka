import 'package:flutter/material.dart';

import 'package:worka/screens/cv/cv_models.dart';
import 'package:worka/theme/worka_colors.dart';

class CvViewBody extends StatelessWidget {
  final String cvId;
  final Map<String, dynamic> data;
  final bool showInCandidates;
  final EdgeInsetsGeometry padding;

  const CvViewBody({
    super.key,
    required this.cvId,
    required this.data,
    this.showInCandidates = false,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 16),
  });

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  Map<String, dynamic> _map(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  List<String> _stringList(dynamic v) {
    if (v is! List) return const <String>[];
    return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }

  bool _inCandidates(Map<String, dynamic> m) {
    final vis = (m['visibility'] is Map<String, dynamic>)
        ? (m['visibility'] as Map<String, dynamic>)
        : <String, dynamic>{};
    return (vis['inCandidates'] ?? false) == true;
  }

  String _location(Map<String, dynamic> desired) {
    final label = _s(desired['locationLabel']);
    if (label.isNotEmpty) return label;

    final citiesText = _s(desired['citiesText']);
    if (citiesText.isNotEmpty) return citiesText;

    final countries = _stringList(desired['countries']);
    if (countries.isNotEmpty) return countries.join(', ');

    final city = _s(data['city']);
    final country = _s(data['country']);
    final out = [city, country].where((e) => e.isNotEmpty).join(', ');
    return out;
  }

  String _primaryRole(CvDoc cv, Map<String, dynamic> desired) {
    return _s(
      desired['position'] ?? desired['categoryGroup'] ?? desired['category'] ?? cv.title,
      fallback: 'Кандидат',
    );
  }

  List<String> _skills(Map<String, dynamic> skills, CvDoc cv) {
    final out = <String>{};

    out.addAll(_stringList(skills['computerPrograms']));

    final computerText = _s(skills['computer']);
    if (computerText.isNotEmpty) {
      out.addAll(
        computerText
            .split(RegExp(r'[,;/]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    }

    for (final lang in cv.languages) {
      final language = _s(lang['language']);
      final level = _s(lang['level']);
      if (language.isNotEmpty && level.isNotEmpty) {
        out.add('$language · $level');
      } else if (language.isNotEmpty) {
        out.add(language);
      }
    }

    return out.toList();
  }

  List<Map<String, dynamic>> _experienceList(CvDoc cv) {
    return cv.experience
        .where((m) => m.values.any((v) => _s(v).isNotEmpty))
        .toList();
  }

  List<Widget> _chips({
    required bool inCandidates,
    required bool hasContacts,
    required int expCount,
    required bool availableNow,
  }) {
    final items = <Widget>[];

    if (inCandidates) {
      items.add(_MetaChip(icon: Icons.work_outline, text: 'Open to work'));
    }
    if (hasContacts) {
      items.add(_MetaChip(icon: Icons.verified_outlined, text: 'Verified'));
    }
    if (expCount > 0) {
      items.add(_MetaChip(icon: Icons.timeline_rounded, text: '$expCount exp'));
    }
    if (availableNow) {
      items.add(_MetaChip(icon: Icons.bolt_outlined, text: 'Available now'));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final cv = CvDoc(id: cvId, data: data);
    final contacts = cv.contacts;
    final desired = cv.desired;
    final skills = _map(data['skills']);

    final displayName = _s(contacts['name'], fallback: cv.title.isEmpty ? 'Кандидат' : cv.title);
    final role = _primaryRole(cv, desired);
    final location = _location(desired);
    final about = _s(data['about'], fallback: cv.summary);

    final inCandidates = _inCandidates(data);
    final exp = _experienceList(cv);
    final skillItems = _skills(skills, cv);

    final hasContacts = _s(contacts['email']).isNotEmpty || _s(contacts['phone']).isNotEmpty;
    final availableNow = data['availableNow'] == true;

    final chips = _chips(
      inCandidates: showInCandidates ? inCandidates : true,
      hasContacts: hasContacts,
      expCount: exp.length,
      availableNow: availableNow,
    );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileHeader(
            name: displayName,
            role: role,
            location: location,
            chips: chips,
          ),
          const SizedBox(height: 14),
          if (about.isNotEmpty) ...[
            _SectionCard(
              title: 'About me',
              child: Text(
                about,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: WorkaColors.textGreyDark,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (exp.isNotEmpty) ...[
            _SectionCard(
              title: 'Experience',
              child: Column(
                children: exp.map((e) => _ExperienceTile(item: e)).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (skillItems.isNotEmpty)
            _SectionCard(
              title: 'Skills',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: skillItems
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: WorkaColors.hoverBlueSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: WorkaColors.fieldBorder),
                          ),
                          child: Text(
                            s,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: WorkaColors.textDark,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String role;
  final String location;
  final List<Widget> chips;

  const _ProfileHeader({
    required this.name,
    required this.role,
    required this.location,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'U'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .where((e) => e.isNotEmpty)
            .take(2)
            .map((e) => e.substring(0, 1).toUpperCase())
            .join();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: WorkaColors.blue,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      role,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperienceTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ExperienceTile({required this.item});

  String _s(dynamic v) {
    final t = (v ?? '').toString().trim();
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final company = _s(item['company']);
    final position = _s(item['position']);
    final country = _s(item['country']);
    final start = _s(item['from'] ?? item['start'] ?? item['startDate']);
    final end = _s(item['to'] ?? item['end'] ?? item['endDate']);
    final period = [start, end].where((e) => e.isNotEmpty).join(' - ');

    final title = position.isNotEmpty ? position : (company.isNotEmpty ? company : 'Опыт');
    final subtitle = [company, country].where((e) => e.isNotEmpty).join(' • ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: WorkaColors.textDark,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: WorkaColors.textGreyDark,
              ),
            ),
          ],
          if (period.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              period,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: WorkaColors.textGrey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: WorkaColors.textDark,
              fontSize: 15.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
