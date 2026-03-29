import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_paths.dart';
import '../../theme/worka_colors.dart';
import '../../widgets/worka_header.dart';
import 'cv_wizard_screen.dart';
import 'cv_models.dart';

class CvReviewScreen extends StatefulWidget {
  final String cvId;
  final Map<String, dynamic> cv;
  final bool testMode;

  const CvReviewScreen({
    super.key,
    required this.cvId,
    required this.cv,
    this.testMode = false,
  });

  @override
  State<CvReviewScreen> createState() => _CvReviewScreenState();
}

class _CvReviewScreenState extends State<CvReviewScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late Map<String, dynamic> _cv;
  bool _publishing = false;
  bool _inCandidates = false;

  DocumentReference<Map<String, dynamic>> get _cvRef {
    return _db.collection(FirestorePaths.cvs).doc(widget.cvId);
  }

  Future<DocumentReference<Map<String, dynamic>>> _resolveCvRef() async {
    final primary = _cvRef;
    final primarySnap = await primary.get();
    if (primarySnap.exists) return primary;
    return _db.collection(FirestorePaths.cvs).doc(widget.cvId);
  }

  DocumentReference<Map<String, dynamic>> get _candidateRef {
    // ✅ делаем id = cvId, чтобы легко обновлять/удалять
    return _db.collection(FirestorePaths.candidates).doc(widget.cvId);
  }

  @override
  void initState() {
    super.initState();
    _cv = Map<String, dynamic>.from(widget.cv);
    _inCandidates = _extractInCandidates(_cv);
    _loadCandidateFlag();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  bool _extractInCandidates(Map<String, dynamic> cv) {
    final visibility = (cv['visibility'] is Map<String, dynamic>)
        ? (cv['visibility'] as Map<String, dynamic>)
        : <String, dynamic>{};
    return visibility['inCandidates'] == true ||
        cv['publishedInCandidates'] == true ||
        cv['showToEmployers'] == true ||
        cv['inCandidates'] == true;
  }

  Future<void> _reloadCv() async {
    final ref = await _resolveCvRef();
    final snap = await ref.get();
    if (!snap.exists) return;
    final next = snap.data() ?? _cv;
    setState(() {
      _cv = next;
      _inCandidates = _extractInCandidates(next);
    });
  }

  Future<void> _loadCandidateFlag() async {
    try {
      if (_inCandidates) return;
      final snap = await _candidateRef.get();
      if (!mounted) return;
      final inCandidates =
          snap.exists && (snap.data()?['publishedInCandidates'] == true);
      setState(() => _inCandidates = inCandidates);
    } catch (_) {}
  }

  Future<void> _openEditStep(String stepId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CvWizardScreen(
          testMode: widget.testMode,
          initialStepId: stepId,
          existingCvId: widget.cvId,
        ),
      ),
    );

    await _reloadCv();
    if (_inCandidates) {
      // если уже опубликовано — обновим snapshot кандидата
      await _upsertCandidateFromCv();
    }
  }

  Map<String, dynamic> _contacts() =>
      Map<String, dynamic>.from(_cv['contacts'] ?? {});
  List<Map<String, dynamic>> _list(String key) =>
      (_cv[key] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Map<String, dynamic> _desired() =>
      CvDoc.normalizeDesired(Map<String, dynamic>.from(_cv['desired'] ?? {}));

  String _s(dynamic v) => (v ?? '').toString().trim();
  String _contactName(Map<String, dynamic> contacts) {
    final full = _s(contacts['name']);
    if (full.isNotEmpty) return full;
    final first = _s(contacts['firstName']);
    final last = _s(contacts['lastName']);
    final out = '$first $last'.trim();
    return out.isEmpty ? 'Кандидат' : out;
  }

  String _contactPhone(Map<String, dynamic> contacts) {
    final direct = _s(contacts['phone']);
    if (direct.isNotEmpty) return direct;
    final code = _s(contacts['phoneCountryCode']);
    final number = _s(contacts['phoneNumber']);
    return '$code$number'.trim();
  }

  String _birthDateText(dynamic raw) {
    DateTime? date;
    if (raw is Timestamp) date = raw.toDate();
    if (raw is DateTime) date = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      date = DateTime.tryParse(raw.trim());
    }
    if (date == null) return '';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd.$mm.${date.year}';
  }

  Future<void> _upsertCandidateFromCv() async {
    final u = _auth.currentUser;
    await _candidateRef.set({
      'ownerId': u?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'publishedInCandidates': true,
    }, SetOptions(merge: true));
  }

  Future<void> _setInCandidates(bool v) async {
    setState(() => _publishing = true);
    try {
      final cvRef = await _resolveCvRef();
      await cvRef.set({
        'visibility': {'inCandidates': v},
        'publishedInCandidates': v,
        'showToEmployers': v,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (v) {
        await _upsertCandidateFromCv();
        setState(() => _inCandidates = true);
        _toast('Добавлено в кандидаты ✅');
      } else {
        await _candidateRef.set({
          'publishedInCandidates': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        setState(() => _inCandidates = false);
        _toast('Убрано из кандидатов');
      }
    } catch (e) {
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  // -------- UI --------

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts();
    final desired = _desired();
    final desiredCountries = (desired['countries'] is List)
        ? (desired['countries'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final desiredLocation = _s(desired['locationLabel']).isNotEmpty
        ? _s(desired['locationLabel'])
        : desiredCountries.join(', ');

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Ваше CV',
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                children: [
                  _sectionCard(
                    title: 'Профиль',
                    subtitle: [
                      _contactName(contacts),
                      _s(contacts['email']),
                      _contactPhone(contacts),
                      _s(_cv['citizenshipCountry']),
                      _s(_cv['city']),
                      _s(_cv['gender']),
                      _birthDateText(_cv['birthDate']),
                    ].where((e) => e.trim().isNotEmpty).join('\n'),
                    onEdit: () => _openEditStep(CvWizardStepIds.profile),
                  ),
                  const SizedBox(height: 12),

                  _sectionCard(
                    title: 'Заголовок',
                    subtitle: _s(_cv['title']),
                    onEdit: () => _openEditStep(CvWizardStepIds.about),
                  ),
                  const SizedBox(height: 12),

                  _sectionCard(
                    title: 'О себе',
                    subtitle: _s(_cv['summary']),
                    onEdit: () => _openEditStep(CvWizardStepIds.about),
                  ),
                  const SizedBox(height: 12),

                  _sectionCard(
                    title: 'Желаемая работа',
                    subtitle: [
                      if (_s(desired['categoryGroup']).isNotEmpty)
                        'Категория: ${_s(desired['categoryGroup'])}',
                      if (_s(desired['position']).isNotEmpty)
                        'Должность: ${_s(desired['position'])}',
                      if (desiredLocation.isNotEmpty)
                        'Локация: $desiredLocation',
                      if (_s(desired['citiesText']).isNotEmpty)
                        'Города: ${_s(desired['citiesText'])}',
                      if (_s(desired['employmentType']).isNotEmpty)
                        'Тип: ${_s(desired['employmentType'])}',
                    ].join('\n'),
                    onEdit: () => _openEditStep(CvWizardStepIds.jobPreferences),
                  ),
                  const SizedBox(height: 12),

                  _listSection(
                    title: 'Опыт работы',
                    list: _list('experience'),
                    emptyText: 'Не указано',
                    lineBuilder: (m) {
                      final p = _s(m['position']);
                      final c = _s(m['company']);
                      final d = _s(m['description']);
                      final head = [
                        p,
                        c,
                      ].where((e) => e.isNotEmpty).join(' — ');
                      if (head.isEmpty && d.isEmpty) return '';
                      return [head, d].where((e) => e.isNotEmpty).join('\n');
                    },
                    onEdit: () => _openEditStep(CvWizardStepIds.experience),
                  ),
                  const SizedBox(height: 12),

                  _listSection(
                    title: 'Языки',
                    list: _list('languages'),
                    emptyText: 'Не указано',
                    lineBuilder: (m) {
                      final l = _s(m['language']);
                      final lv = _s(m['level']);
                      if (l.isEmpty && lv.isEmpty) return '';
                      return [l, lv].where((e) => e.isNotEmpty).join(' — ');
                    },
                    onEdit: () => _openEditStep(CvWizardStepIds.languages),
                  ),
                  const SizedBox(height: 12),

                  _listSection(
                    title: 'Образование',
                    list: _list('education'),
                    emptyText: 'Не указано',
                    lineBuilder: (m) {
                      final s = _s(m['school']);
                      final sp = _s(m['speciality']);
                      final c = _s(m['country']);
                      return [s, sp, c].where((e) => e.isNotEmpty).join(' • ');
                    },
                    onEdit: () => _openEditStep(CvWizardStepIds.education),
                  ),
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.all(14),
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Показывать работодателям',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: WorkaColors.textDark,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Ваше CV будет доступно работодателям в поиске кандидатов.',
                                style: TextStyle(
                                  color: WorkaColors.textGreyDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        IgnorePointer(
                          ignoring: _publishing,
                          child: Switch(
                            value: _inCandidates,
                            onChanged: (v) => _setInCandidates(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required VoidCallback onEdit,
  }) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.edit, color: WorkaColors.blue),
          ],
        ),
      ),
    );
  }

  Widget _listSection({
    required String title,
    required List<Map<String, dynamic>> list,
    required String emptyText,
    required String Function(Map<String, dynamic>) lineBuilder,
    required VoidCallback onEdit,
  }) {
    final lines = <String>[];
    for (final m in list) {
      final line = lineBuilder(m).trim();
      if (line.isNotEmpty) lines.add(line);
    }

    return _sectionCard(
      title: title,
      subtitle: lines.isEmpty ? emptyText : lines.join('\n\n'),
      onEdit: onEdit,
    );
  }
}
