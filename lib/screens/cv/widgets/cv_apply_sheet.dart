import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:worka/screens/cv/cv_view_screen.dart';
import 'package:worka/screens/cv/widgets/cv_picker_sheet.dart';
import 'package:worka/screens/cv/cv_wizard_screen.dart';
import 'package:worka/screens/cv/widgets/cv_card_formatters.dart';
import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/repositories/cv_repository.dart';
import 'package:worka/theme/worka_colors.dart';

class CvApplySheet extends StatefulWidget {
  final bool testMode;

  const CvApplySheet({super.key, required this.testMode});

  static Future<CvPickResult?> open(
    BuildContext context, {
    required bool testMode,
  }) {
    return showModalBottomSheet<CvPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: CvApplySheet(testMode: testMode),
      ),
    );
  }

  @override
  State<CvApplySheet> createState() => _CvApplySheetState();
}

class _CvApplySheetState extends State<CvApplySheet> {
  final _db = FirebaseFirestore.instance;

  String? _selectedCvId;
  String _selectedCvTitle = '';

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _fullName(Map<String, dynamic> cv) {
    final contacts = cv['contacts'] is Map
        ? Map<String, dynamic>.from(cv['contacts'] as Map)
        : const <String, dynamic>{};
    final full = _s(
      contacts['name'],
      fallback: _s(cv['fullName'], fallback: _s(cv['name'])),
    );
    if (full.isNotEmpty) return full;
    final first = _s(contacts['firstName'], fallback: _s(cv['firstName']));
    final last = _s(contacts['lastName'], fallback: _s(cv['lastName']));
    final merged = '$first $last'.trim();
    return merged.isNotEmpty ? merged : 'Кандидат';
  }

  String _profession(Map<String, dynamic> cv) {
    final desired = cv['desired'] is Map
        ? Map<String, dynamic>.from(cv['desired'] as Map)
        : const <String, dynamic>{};
    return _s(
      desired['position'],
      fallback: _s(
        cv['title'],
        fallback: _s(cv['profession'], fallback: 'Профессия не указана'),
      ),
    );
  }

  String _city(Map<String, dynamic> cv) {
    final desired = cv['desired'] is Map
        ? Map<String, dynamic>.from(cv['desired'] as Map)
        : const <String, dynamic>{};
    final cities = desired['cities'];
    if (cities is List && cities.isNotEmpty) {
      final value = cities.first.toString().trim();
      if (value.isNotEmpty) return value;
    }
    return _s(desired['citiesText'], fallback: _s(cv['city']));
  }

  String _country(Map<String, dynamic> cv) {
    final desired = cv['desired'] is Map
        ? Map<String, dynamic>.from(cv['desired'] as Map)
        : const <String, dynamic>{};
    final countries = desired['countries'];
    if (countries is List && countries.isNotEmpty) {
      final value = countries.first.toString().trim();
      if (value.isNotEmpty) return value;
    }
    return _s(cv['country']);
  }

  String _countryFlag(String country) {
    final c = country.trim().toLowerCase();
    if (c.contains('estonia') || c.contains('эстони')) return '🇪🇪';
    if (c.contains('sweden') || c.contains('швеци')) return '🇸🇪';
    if (c.contains('finland') || c.contains('финлян')) return '🇫🇮';
    if (c.contains('latvia') || c.contains('латви')) return '🇱🇻';
    if (c.contains('lithuania') || c.contains('литв')) return '🇱🇹';
    if (c.contains('russia') || c.contains('росси')) return '🇷🇺';
    if (c.contains('ukraine') || c.contains('украин')) return '🇺🇦';
    if (c.contains('kazakhstan') || c.contains('казахстан')) return '🇰🇿';
    if (c.contains('uzbekistan') || c.contains('узбекистан')) return '🇺🇿';
    return '';
  }

  String _salary(Map<String, dynamic> cv) {
    final desired = cv['desired'] is Map
        ? Map<String, dynamic>.from(cv['desired'] as Map)
        : const <String, dynamic>{};
    final text = _s(
      cv['salaryText'],
      fallback: _s(
        desired['salaryText'],
        fallback: _s(desired['salary'], fallback: _s(cv['salary'])),
      ),
    );
    if (text.isEmpty) return '€ -';
    if (text.startsWith('€')) return text;
    return '€ ${text.replaceAll('\$', '').trim()}';
  }

  String _location(Map<String, dynamic> cv) {
    final city = _city(cv);
    final country = _country(cv);
    final flag = _countryFlag(country);
    if (city.isEmpty && country.isEmpty) return 'Локация не указана';
    if (city.isEmpty) return '$flag $country'.trim();
    if (country.isEmpty) return city;
    return '$city, ${'$flag $country'.trim()}';
  }

  String _nameAge(Map<String, dynamic> cv) {
    final name = _fullName(cv);
    final age = calculateAgeFromBirthDate(cv['birthDate']);
    if (age == null || age <= 0) return name;
    return '$name, $age';
  }

  String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'U';
    return parts.map((e) => e.substring(0, 1).toUpperCase()).join();
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _cvStream() {
    final ownerUid = AuthGuard.effectiveUidOrNull() ?? '';
    if (ownerUid.isEmpty) {
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    return CvRepository(
      _db,
    ).watchMyCvDocs(testMode: widget.testMode, userId: ownerUid).map((docs) {
      debugPrint(
        'CvApplySheet stream ownerUid=$ownerUid testMode=${widget.testMode} total=${docs.length}',
      );
      return docs;
    });
  }

  Future<DocumentReference<Map<String, dynamic>>> _cvRefForView(
    String cvId,
  ) async {
    return _db.collection(FirestorePaths.cvs).doc(cvId);
  }

  void _toggleSelected(String cvId, String title) {
    setState(() {
      final isSelected = _selectedCvId == cvId;
      if (isSelected) {
        _selectedCvId = null;
        _selectedCvTitle = '';
      } else {
        _selectedCvId = cvId;
        _selectedCvTitle = title;
      }
    });
  }

  Future<void> _openCv(String cvId) async {
    final ref = await _cvRefForView(cvId);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CvViewScreen(
          cvId: cvId,
          testMode: widget.testMode,
          refOverride: ref,
        ),
      ),
    );
  }

  Future<void> _createCv() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CvWizardScreen(testMode: widget.testMode),
      ),
    );
  }

  void _submit() {
    if (_selectedCvId == null) return;
    Navigator.pop(
      context,
      CvPickResult(cvId: _selectedCvId!, title: _selectedCvTitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: WorkaColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: WorkaColors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Выберите CV для отклика',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: WorkaColors.textDark,
                  ),
                ),
              ),
            ),
            Expanded(
              child:
                  StreamBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>
                  >(
                    stream: _cvStream(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        debugPrint('CvApplySheet stream error: ${snap.error}');
                        final permissionDenied =
                            FirebaseDebugDiagnostics.isPermissionDenied(
                              snap.error,
                            );
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Ошибка загрузки CV: ${snap.error}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (permissionDenied && widget.testMode) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    FirebaseDebugDiagnostics.permissionHintText(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: WorkaColors.orange,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }

                      final docs = [...snap.data!];
                      DateTime parseDate(dynamic v) {
                        if (v is Timestamp) return v.toDate();
                        return DateTime.fromMillisecondsSinceEpoch(0);
                      }

                      docs.sort((a, b) {
                        final au = parseDate(a.data()['updatedAt']);
                        final bu = parseDate(b.data()['updatedAt']);
                        if (au != bu) return bu.compareTo(au);
                        final ac = parseDate(a.data()['createdAt']);
                        final bc = parseDate(b.data()['createdAt']);
                        return bc.compareTo(ac);
                      });

                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'У вас пока нет сохранённых CV',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: _createCv,
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: WorkaColors.blue,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text(
                                      'Добавить новое CV',
                                      style: TextStyle(
                                        color: WorkaColors.blue,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final d = docs[i];
                          final m = d.data();
                          final isSelected = _selectedCvId == d.id;
                          final fullName = _fullName(m);
                          final title = _nameAge(m);
                          final profession = _profession(m);
                          final location = _location(m);
                          final salary = _salary(m);
                          return _CvCompactSelectCard(
                            initials: _initials(fullName),
                            title: title,
                            profession: profession,
                            location: location,
                            salary: salary,
                            selected: isSelected,
                            onTap: () => _toggleSelected(d.id, fullName),
                            onOpen: () => _openCv(d.id),
                            onChecked: () => _toggleSelected(d.id, fullName),
                          );
                        },
                      );
                    },
                  ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: WorkaColors.divider.withValues(alpha: 0.6),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _createCv,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: WorkaColors.blue,
                              width: 1.3,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Добавить новое CV',
                            style: TextStyle(
                              color: WorkaColors.blue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _selectedCvId == null ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkaColors.orange,
                            disabledBackgroundColor: WorkaColors.orange
                                .withValues(alpha: 0.35),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Взять работу',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
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

class _CvCompactSelectCard extends StatelessWidget {
  const _CvCompactSelectCard({
    required this.initials,
    required this.title,
    required this.profession,
    required this.location,
    required this.salary,
    required this.selected,
    required this.onTap,
    required this.onOpen,
    required this.onChecked,
  });

  final String initials;
  final String title;
  final String profession;
  final String location;
  final String salary;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onChecked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      hoverColor: WorkaColors.hoverBlue,
      splashColor: WorkaColors.hoverBlueSoft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? WorkaColors.blue : WorkaColors.fieldBorder,
            width: selected ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFEAF0FF),
                shape: BoxShape.circle,
              ),
              child: Text(
                initials,
                style: const TextStyle(
                  color: WorkaColors.blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profession,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    salary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkaColors.orange,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Checkbox(
                  value: selected,
                  activeColor: WorkaColors.blue,
                  checkColor: Colors.white,
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return WorkaColors.blue;
                    }
                    return Colors.white;
                  }),
                  side: const BorderSide(color: WorkaColors.fieldBorder),
                  onChanged: (_) => onChecked(),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpen,
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    color: WorkaColors.blue,
                    size: 18,
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
