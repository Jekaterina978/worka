import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:worka/controllers/paid_entitlements_controller.dart';
import 'package:flutter/material.dart';

import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/repositories/notifications_repository.dart';
import 'package:worka/repositories/response_repository.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:worka/screens/worker_profile_edit_screen.dart';
import 'package:worka/screens/vacancy_review_screen.dart';
import 'package:worka/screens/cv/widgets/cv_card_formatters.dart';
import 'package:worka/widgets/cards/candidate_cv_card.dart';
import 'package:worka/widgets/vacancy_details_view.dart';
import 'package:worka/widgets/vacancy_apply_entry_sheet.dart';
import 'package:worka/features/payments/screens/promote_job_screen.dart';

class VacancyDetailsScreen extends StatefulWidget {
  final String jobId;

  /// Если нужно читать не из jobs (например jobs_test) — передай refOverride.
  final DocumentReference<Map<String, dynamic>>? refOverride;

  /// ✅ testMode = true => в тестовом режиме считаем, что «закрытых функций нет»
  final bool testMode;
  final bool isOwnerView;

  const VacancyDetailsScreen({
    super.key,
    required this.jobId,
    this.refOverride,
    this.testMode = true,
    this.isOwnerView = false,
  });

  @override
  State<VacancyDetailsScreen> createState() => _VacancyDetailsScreenState();
}

class _VacancyDetailsScreenState extends State<VacancyDetailsScreen> {
  final _db = FirebaseFirestore.instance;

  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _jobRef =>
      widget.refOverride ??
      _db.collection(FirestorePaths.vacancies).doc(widget.jobId);

  String _uidOrDev() {
    return AuthGuard.effectiveUidOrNull() ?? '';
  }

  bool _isOwner(Map<String, dynamic> job) {
    final myUid = _uidOrDev().trim().isNotEmpty
        ? _uidOrDev().trim()
        : OwnershipResolver.currentUid();
    final ownership = OwnershipResolver.vacancyOwnership(
      job,
      currentUserId: myUid,
    );
    return ownership.known && ownership.isOwner;
  }

  Future<Map<String, dynamic>?> _loadWorkerProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  bool _profileOk(Map<String, dynamic>? p) {
    if (p == null) return false;

    final fn = (p['firstName'] ?? '').toString().trim();
    final ln = (p['lastName'] ?? '').toString().trim();
    final phone = (p['phone'] ?? '').toString().trim();
    final email = (p['email'] ?? '').toString().trim();
    final gender = (p['gender'] ?? '').toString().trim();
    final bd = p['birthDate'];
    final country = (p['country'] ?? '').toString().trim();

    final hasBirth = bd is Timestamp;
    return fn.isNotEmpty &&
        ln.isNotEmpty &&
        phone.isNotEmpty &&
        email.isNotEmpty &&
        gender.isNotEmpty &&
        hasBirth &&
        country.isNotEmpty;
  }

  Future<void> _openEditJobSheet(
    DocumentReference<Map<String, dynamic>> jobRef,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VacancyReviewScreen(
          jobId: widget.jobId,
          jobRef: jobRef,
          testMode: widget.testMode,
        ),
      ),
    );
  }

  Future<bool?> _openSelectCvSheet({
    required String jobTitle,
    required DocumentReference<Map<String, dynamic>> jobRef,
  }) async {
    final h = MediaQuery.of(context).size.height;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SizedBox(
          height: h * 0.90,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _SelectCvForJobSheet(
              jobId: widget.jobId,
              jobRef: jobRef,
              jobTitle: jobTitle,
              testMode: widget.testMode,
              uidOrDev: _uidOrDev(),
              loadWorkerProfile: _loadWorkerProfile,
              profileOk: _profileOk,
              openProfileEdit: () async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const WorkerProfileEditScreen(isInitialFill: true),
                  ),
                );
                return ok == true;
              },
            ),
          ),
        );
      },
    );
  }

  String _s(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    final t = v.toString().trim();
    return t.isEmpty ? fallback : t;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uidOrDev();

    return Material(
      color: Colors.white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _jobRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            debugPrint('VacancyDetailsScreen job stream error: ${snap.error}');
            final permissionDenied =
                FirebaseDebugDiagnostics.isPermissionDenied(snap.error);
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ошибка: ${snap.error}',
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

          final doc = snap.data!;
          if (!doc.exists) {
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection(FirestorePaths.vacancies)
                  .doc(widget.jobId)
                  .snapshots(),
              builder: (context, groupSnap) {
                if (!groupSnap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final fbDoc = groupSnap.data!;
                if (!fbDoc.exists) {
                  return const Center(child: Text('Вакансия не найдена'));
                }
                return _buildJobView(context, uid, fbDoc);
              },
            );
          }

          return _buildJobView(context, uid, doc);
        },
      ),
    );
  }

  // ── UI refactored: only layout/widgets changed, no business logic touched ──
  Widget _buildJobView(
    BuildContext context,
    String uid,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final paid = context.watch<PaidEntitlementsController>();
    final job = doc.data() ?? {};

    final title = _s(job['title'], fallback: 'Без названия');
    final jobId = widget.jobId.trim();
    if (jobId.isNotEmpty && paid.jobEntitlementsById[jobId] == null) {
      Future.microtask(() => paid.refreshJobEntitlements(jobId));
    }
    final hasHighlight = paid.hasJobFeature(jobId, 'highlight');
    final hasUrgent = paid.hasJobFeature(jobId, 'urgent');
    final hasBump = paid.hasJobFeature(jobId, 'bump');
    final hasShowContacts = paid.hasJobFeature(jobId, 'show_contacts');

    final isOwner = widget.isOwnerView || _isOwner(job);
    final contacts = (job['contacts'] is Map<String, dynamic>)
        ? (job['contacts'] as Map<String, dynamic>)
        : <String, dynamic>{};

    // ── CTA button (logic unchanged) ─────────────────────────────────────────
    Widget bottomButton(bool applied) {
      if (isOwner) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final actions = <Widget>[
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: () => _openEditJobSheet(doc.reference),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: WorkaColors.blue, width: 1.2),
                    foregroundColor: WorkaColors.blue,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: const Text(
                    'Редактировать',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: WorkaColors.blue,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WorkaColors.blue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: const Text(
                    'Готово',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ];
            if (compact) {
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: actions.first),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: actions.last),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: actions.first),
                const SizedBox(width: 12),
                Expanded(child: actions.last),
              ],
            );
          },
        );
      }

      final disabled = applied || _sending;
      final ctaColor = applied ? WorkaColors.blue : WorkaColors.orange;

      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: disabled
              ? null
              : () async {
                  setState(() => _sending = true);
                  try {
                    final ok = await VacancyApplyEntrySheet.open(
                      context,
                      vacancy: job,
                      onSendCvTap: () async {
                        final sent = await _openSelectCvSheet(
                          jobTitle: title,
                          jobRef: doc.reference,
                        );
                        return sent == true;
                      },
                    );
                    if (!mounted) return;
                    if (ok == true) {
                      // ✅ закрываем карточку вакансии и возвращаем в поиск
                      Navigator.pop(context);
                    }
                  } finally {
                    if (mounted) setState(() => _sending = false);
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: ctaColor,
            disabledBackgroundColor: ctaColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            elevation: 0,
          ),
          child: _sending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  applied ? 'Отклик отправлен' : 'Взять работу',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
        ),
      );
    }

    final compactOwnerActions = MediaQuery.of(context).size.width < 360;
    final ctaHeight = isOwner ? (compactOwnerActions ? 156.0 : 90.0) : 56.0;
    final viewData = VacancyDetailsViewData.fromJobMap(job);
    final entitlementChips = <Widget>[];
    if (hasUrgent) {
      entitlementChips.add(_statusChip('Срочно активно', Colors.redAccent));
    }
    if (hasBump) {
      entitlementChips.add(_statusChip('Поднято', Colors.blueGrey));
    }
    if (hasShowContacts) {
      entitlementChips.add(_statusChip('Контакты доступны', Colors.green));
    }
    final hasEntitlementChips = entitlementChips.isNotEmpty;
    final headerHighlightButton = isOwner
        ? (hasHighlight
              ? _statusChip('Выделение активно', WorkaColors.orange)
              : SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PromoteJobScreen(jobCode: widget.jobId),
                          ),
                        ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WorkaColors.orange,
                      side: const BorderSide(
                        color: WorkaColors.orange,
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                    ),
                    child: const Text(
                      'Выделить',
                      style: TextStyle(
                        color: WorkaColors.orange,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ))
        : null;
    final Widget bottomActions = isOwner
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Это ваша вакансия',
                style: TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              if (hasEntitlementChips) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: entitlementChips),
              ],
              const SizedBox(height: 10),
              bottomButton(false),
            ],
          )
        : StreamBuilder<bool>(
            stream: uid.isEmpty
                ? Stream<bool>.value(false)
                : ResponseRepository(_db).hasAppliedStream(
                    jobId: widget.jobId,
                    candidateOwnerId: uid,
                  ),
            builder: (context, rs) {
              final applied = rs.data ?? false;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasShowContacts && contacts.isNotEmpty) ...[
                    _ContactCard(contacts: contacts),
                    const SizedBox(height: 10),
                  ],
                  bottomButton(applied),
                ],
              );
            },
          );

    return VacancyDetailsView(
      data: viewData,
      actionsMode: isOwner
          ? VacancyDetailsActionsMode.employerManage
          : VacancyDetailsActionsMode.workerApply,
      bottomActions: bottomActions,
      headerHighlightAction: headerHighlightButton,
      onBack: () => Navigator.pop(context),
      onClose: () => Navigator.pop(context),
      actionHeight: ctaHeight,
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ====== CV selection sheet (unchanged) ======

class _SelectCvForJobSheet extends StatefulWidget {
  final String jobId;
  final DocumentReference<Map<String, dynamic>> jobRef;
  final String jobTitle;
  final bool testMode;

  final String uidOrDev;

  final Future<Map<String, dynamic>?> Function(String uid) loadWorkerProfile;
  final bool Function(Map<String, dynamic>? profile) profileOk;
  final Future<bool> Function() openProfileEdit;

  const _SelectCvForJobSheet({
    required this.jobId,
    required this.jobRef,
    required this.jobTitle,
    required this.testMode,
    required this.uidOrDev,
    required this.loadWorkerProfile,
    required this.profileOk,
    required this.openProfileEdit,
  });

  @override
  State<_SelectCvForJobSheet> createState() => _SelectCvForJobSheetState();
}

class _SelectCvForJobSheetState extends State<_SelectCvForJobSheet> {
  final _db = FirebaseFirestore.instance;

  bool _sending = false;
  bool _sent = false;

  String? _selectedCvId;

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _cvsStream() {
    final ownerId = widget.uidOrDev.trim();
    if (ownerId.isEmpty) {
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    debugPrint('VacancyDetailsScreen CV stream cvs where ownerId==$ownerId');
    return _db
        .collection(FirestorePaths.cvs)
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((s) {
          return s.docs
              .where((d) => (d.data()['isDeleted'] ?? false) != true)
              .toList();
        });
  }

  Widget _workaCheckbox({required bool value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Checkbox(
        value: value,
        onChanged: (_) => onTap(),
        activeColor: WorkaColors.blue,
        checkColor: Colors.white,
        side: const BorderSide(color: WorkaColors.fieldBorder, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) return WorkaColors.blue;
          return Colors.transparent;
        }),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return WorkaColors.hoverBlueSoft;
          }
          return null;
        }),
      ),
    );
  }

  String _pick(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final k in keys) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  String _cvName(Map<String, dynamic> d) {
    final contacts = (d['contacts'] is Map<String, dynamic>)
        ? (d['contacts'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final full = _pick(contacts, const [
      'name',
    ], fallback: _pick(d, const ['name', 'fullName']));
    if (full.isNotEmpty) return full;
    final first = _pick(contacts, const [
      'firstName',
    ], fallback: d['firstName']?.toString() ?? '');
    final last = _pick(contacts, const [
      'lastName',
    ], fallback: d['lastName']?.toString() ?? '');
    final combined = '$first $last'.trim();
    return combined.isEmpty ? 'Кандидат' : combined;
  }

  int? _cvAge(Map<String, dynamic> d) {
    final raw = d['age'];
    if (raw is num && raw > 0) return raw.toInt();
    final parsed = int.tryParse((raw ?? '').toString().trim());
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  String _cvCity(Map<String, dynamic> d) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final cities = desired['cities'];
    if (cities is List && cities.isNotEmpty) {
      final first = cities.first.toString().trim();
      if (first.isNotEmpty) return first;
    }
    return _pick(desired, const [
      'citiesText',
      'city',
    ], fallback: _pick(d, const ['city']));
  }

  String _cvCountry(Map<String, dynamic> d) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final countries = desired['countries'];
    if (countries is List && countries.isNotEmpty) {
      final first = countries.first.toString().trim();
      if (first.isNotEmpty) return first;
    }
    return _pick(d, const ['country']);
  }

  String _cvSalary(Map<String, dynamic> d) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    return _pick(desired, const [
      'salaryText',
      'salary',
      'salaryFrom',
    ], fallback: _pick(d, const ['salaryText', 'salary']));
  }

  List<String> _cvBadges(Map<String, dynamic> d) {
    final badges = <String>[];
    final languages = (d['languages'] is List)
        ? (d['languages'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];
    final skills = (d['computerSkills'] is Map<String, dynamic>)
        ? (d['computerSkills'] as Map<String, dynamic>)
        : (d['skills'] is Map<String, dynamic>)
        ? (d['skills'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final driving = (d['drivingLicense'] is Map<String, dynamic>)
        ? (d['drivingLicense'] as Map<String, dynamic>)
        : (d['driving'] is Map<String, dynamic>)
        ? (d['driving'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final categoriesRaw = driving['categories'];
    final categories = (categoriesRaw is List)
        ? categoriesRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final legacyLicense = _pick(driving, const ['license']);
    if (categories.isEmpty && legacyLicense.isNotEmpty) {
      categories.add(legacyLicense);
    }
    final selectedRaw = skills['selected'] ?? skills['computerPrograms'];

    badges.addAll(
      buildCandidateBadges(
        languages: languages,
        drivingLicenseCategories: categories,
        hasCar: driving['hasCar'] == true,
        hasTools: d['hasTools'] == true,
        hasWorkwear: d['hasWorkwear'] == true,
        hasComputerSkills: selectedRaw is List && selectedRaw.isNotEmpty,
      ),
    );
    return badges.toSet().take(6).toList();
  }

  Future<void> _send() async {
    if (!AuthGuard.ensureSignedIn(context, message: 'Log in to save')) {
      return;
    }
    final uid = widget.uidOrDev;
    if (uid.isEmpty) {
      _toast('Нужно войти по SMS, чтобы откликнуться.');
      return;
    }

    if (_selectedCvId == null) {
      _toast('Выберите CV.');
      return;
    }

    if (await ResponseRepository(_db).hasAppliedOnce(
      jobId: widget.jobId,
      candidateOwnerId: uid,
      candidateCvId: (_selectedCvId ?? '').toString(),
    )) {
      _toast('Вы уже откликались на эту вакансию.');
      return;
    }

    // 1) профиль
    final profile = await widget.loadWorkerProfile(uid);
    if (!widget.profileOk(profile)) {
      final ok = await widget.openProfileEdit();
      if (!ok) return;
    }
    final profile2 = await widget.loadWorkerProfile(uid);
    if (!widget.profileOk(profile2)) {
      _toast('Заполните профиль полностью.');
      return;
    }

    setState(() => _sending = true);
    try {
      // job snapshot
      final jobSnap = await widget.jobRef.get();
      final job = jobSnap.data() ?? {};
      final employerUid =
          (job['ownerId'] ?? job['ownerUid'] ?? job['employerId'] ?? '')
              .toString()
              .trim();
      final workerOwnerKey =
          FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (workerOwnerKey.isEmpty) {
        _toast('Нужен вход');
        return;
      }

      final duplicate = await ResponseRepository(_db).hasAppliedOnce(
        jobId: widget.jobId,
        candidateOwnerId: workerOwnerKey,
        candidateCvId: (_selectedCvId ?? '').toString(),
      );
      if (duplicate) {
        if (mounted) _toast('Отклик уже отправлен');
        return;
      }

      // Load CV snapshot for letter display resilience.
      Map<String, dynamic> cvData = {};
      if ((_selectedCvId ?? '').isNotEmpty) {
        final cvDoc = await _db
            .collection(FirestorePaths.cvs)
            .doc(_selectedCvId!)
            .get();
        cvData = cvDoc.data() ?? {};
      }

      String f(dynamic v) => (v ?? '').toString().trim();
      List<String> list(dynamic v) {
        if (v is List) return v.map((e) => e.toString()).toList();
        return [];
      }

      final applicationId =
          '${widget.jobId}_${workerOwnerKey}_${(_selectedCvId ?? '').toString()}_apply';
      await ResponseRepository(_db).createApply(
        jobId: widget.jobId,
        jobOwnerId: employerUid,
        candidateCvId: (_selectedCvId ?? '').toString(),
        candidateOwnerId: workerOwnerKey,
        vacancyOwnerType: f(job['ownerType']).isEmpty
            ? 'personal'
            : f(job['ownerType']),
        applicantProfileType: AppMode.currentMode == AccountMode.business
            ? 'business'
            : 'personal',
        applicantNameSnapshot:
            '${f(profile2?['firstName'])} ${f(profile2?['lastName'])}'.trim(),
        applicantEmailSnapshot: f(profile2?['email']),
        applicantPhoneSnapshot: f(profile2?['phone']),
        cvTitleSnapshot: f(cvData['title']).isEmpty
            ? f(cvData['profession'])
            : f(cvData['title']),
        cvLocationSnapshot: f(cvData['location']).isEmpty
            ? f(cvData['country'])
            : f(cvData['location']),
        cvCategorySnapshot: f(cvData['category']),
        cvSkillsSnapshot: list(cvData['skills']),
        vacancySnapshot: Map<String, dynamic>.from(job),
        candidateSnapshot: Map<String, dynamic>.from(profile2 ?? {}),
      );
      if (employerUid.isNotEmpty) {
        await NotificationsRepository(_db).createItem(
          toUserId: employerUid,
          fromUserId: workerOwnerKey,
          type: 'response_received',
          kind: 'response',
          entityId: applicationId,
          payload: {
            'vacancyId': widget.jobId,
            'cvId': (_selectedCvId ?? '').toString(),
            'shortText': 'Новый отклик на вакансию',
          },
        );
      }

      if (!mounted) return;
      setState(() => _sent = true);
    } catch (e) {
      debugPrint('VacancyDetailsScreen _submitApplication error: $e');
      _toast('Ошибка сохранения: $e');
      if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
        _toast(FirebaseDebugDiagnostics.permissionHintText());
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.jobTitle.trim().isEmpty ? 'вакансии' : widget.jobTitle;

    if (_sent) {
      return Material(
        color: Colors.white,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 140),
              children: [
                const SizedBox(height: 6),
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: WorkaColors.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Выбрать CV',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: WorkaColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, true),
                      tooltip: 'Закрыть',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: WorkaColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Отклик отправлен ✅',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: WorkaColors.textDark,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Работодатель получил ваше CV.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: WorkaColors.textGreyDark,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WorkaColors.orange,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: const Text(
                      'Продолжить поиск',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.white,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 140),
            children: [
              const SizedBox(height: 6),
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: WorkaColors.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Выбрать CV для $title',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: WorkaColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    tooltip: 'Закрыть',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: WorkaColors.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                stream: _cvsStream(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _Card(
                      child: Text(
                        'Ошибка: ${snap.error}',
                        style: const TextStyle(color: WorkaColors.textGreyDark),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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
                  final limitedDocs = docs.take(5).toList();
                  if (limitedDocs.isEmpty) {
                    return _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'У вас нет CV',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Сначала создайте CV, затем откликайтесь на вакансии.',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: WorkaColors.textGreyDark,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      for (final d in limitedDocs) ...[
                        CandidateCvCard(
                          mode: CandidateCvCardMode.owner,
                          cvId: d.id,
                          fullName: _cvName(d.data()),
                          age: _cvAge(d.data()),
                          citizenshipCountry: _pick(d.data(), const [
                            'citizenshipCountry',
                            'citizenshipName',
                            'country',
                          ]),
                          profession: _pick(d.data(), const [
                            'title',
                            'profession',
                            'cvTitle',
                          ], fallback: 'CV'),
                          city: _cvCity(d.data()),
                          country: _cvCountry(d.data()),
                          salary: _cvSalary(d.data()),
                          readiness: 'Готов к отклику',
                          badges: _cvBadges(d.data()),
                          topRight: _workaCheckbox(
                            value: _selectedCvId == d.id,
                            onTap: () {
                              setState(() {
                                if (_selectedCvId == d.id) {
                                  _selectedCvId = null;
                                } else {
                                  _selectedCvId = d.id;
                                }
                              });
                            },
                          ),
                          primaryActionLabel: 'Выбрать CV',
                          onPrimaryAction: () {
                            setState(() {
                              if (_selectedCvId == d.id) {
                                _selectedCvId = null;
                              } else {
                                _selectedCvId = d.id;
                              }
                            });
                          },
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          onTap: () {
                            setState(() {
                              if (_selectedCvId == d.id) {
                                _selectedCvId = null;
                              } else {
                                _selectedCvId = d.id;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _sending ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WorkaColors.orange,
                    disabledBackgroundColor: WorkaColors.orange.withValues(
                      alpha: 0.35,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Отправить',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contacts});

  final Map<String, dynamic> contacts;

  String _pick(List<String> keys) {
    for (final k in keys) {
      final v = (contacts[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final phone = _pick(['phone', 'tel', 'contactPhone', 'mobile']);
    final email = _pick(['email', 'contactEmail']);
    final name = _pick(['name', 'contactName', 'fullName']);
    final telegram = _pick(['telegram', 'tg', 'tme']);
    final whatsapp = _pick(['whatsapp', 'wa']);
    final rows = <Widget>[];
    void addRow(String label, String value, IconData icon) {
      if (value.isEmpty) return;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: WorkaColors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label: $value',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: WorkaColors.textGreyDark,
                ),
              ),
            ),
          ],
        ),
      );
      rows.add(const SizedBox(height: 6));
    }

    addRow('Контактное лицо', name, Icons.person_outline);
    addRow('Телефон', phone, Icons.phone_outlined);
    addRow('Email', email, Icons.email_outlined);
    addRow('Telegram', telegram, Icons.telegram);
    addRow('WhatsApp', whatsapp, Icons.chat_bubble_outline);

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.blue.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Контакты работодателя доступны',
            style: TextStyle(
              color: WorkaColors.blue,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ...rows.take(rows.length - 1),
        ],
      ),
    );
  }
}

// ====== Shared helper card ======

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: WorkaColors.fieldBorder),
        boxShadow: [
          BoxShadow(
            blurRadius: 16,
            offset: const Offset(0, 8),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}
