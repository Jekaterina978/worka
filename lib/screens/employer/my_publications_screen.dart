import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/theme/worka_ui_tokens.dart';
import 'package:worka/widgets/worka_header.dart';
import 'package:worka/screens/vacancy_details_screen.dart';
import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/interaction_status.dart';
import 'package:worka/services/firestore_query_debug.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/services/ownership_context.dart';
import 'package:worka/services/entity_validity.dart';
import 'package:worka/services/runtime_flow_logger.dart';
import 'package:worka/services/app_mode.dart' as app_mode;
import 'package:worka/services/apply_vacancy_identity_resolver.dart';
import 'package:worka/services/vacancy_owner_scope_resolver.dart';
import 'package:worka/services/vacancy_runtime_visibility.dart';
import 'package:worka/repositories/jobs_repository.dart';
import 'package:worka/screens/jobs/services/job_draft_storage.dart';
import 'package:worka/features/payments/payments_routes.dart';
import 'package:worka/controllers/paid_entitlements_controller.dart';
import 'package:worka/screens/vacancy_review_screen.dart';
import 'create_job_screen.dart';
import 'widgets/my_publications_sections.dart';
import '../auth/auth_entry_screen.dart';
import '../employer_company_profile_screen.dart';

class MyPublicationsVisibilityResult {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> publishedDocs;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> draftDocs;
  final int droppedCount;
  final int duplicateCount;
  final Map<String, int> reasons;

  const MyPublicationsVisibilityResult({
    required this.publishedDocs,
    required this.draftDocs,
    required this.droppedCount,
    required this.duplicateCount,
    required this.reasons,
  });

  int get visibleCount => publishedDocs.length + draftDocs.length;
}

bool isMyPublicationsHiddenTestItem(Map<String, dynamic> m) {
  final text = <String>[
    (m['title'] ?? '').toString(),
    (m['status'] ?? '').toString(),
    (m['source'] ?? '').toString(),
  ].join(' ').toLowerCase();
  if (text.contains('test') || text.contains('demo') || text.contains('draft')) {
    return true;
  }
  return m['test'] == true || m['draft'] == true;
}

bool _isMyVacancyPublishable(Map<String, dynamic> m) {
  bool containsCopyToken(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('копия') || normalized.contains('copy');
  }

  final title = (m['title'] ?? '').toString().trim();
  if (title.isEmpty || containsCopyToken(title)) return false;
  final category = (m['category'] ?? '').toString().trim();
  if (category.isEmpty) return false;
  final city = (m['city'] ?? '').toString().trim();
  final country = (m['country'] ?? '').toString().trim();
  if (city.isEmpty || country.isEmpty) return false;
  final employment = (m['employmentType'] ?? m['type'] ?? '').toString().trim();
  if (employment.isEmpty) return false;
  final description = (m['description'] ?? '').toString().trim();
  if (description.isEmpty) return false;
  final salaryAmount = m['salaryAmount'] ?? m['salaryFrom'];
  final salaryText = (m['salaryText'] ?? m['salary'] ?? '').toString().trim();
  final hasSalaryAmount = salaryAmount is num && salaryAmount > 0;
  final hasSalaryText = salaryText.isNotEmpty;
  if (!hasSalaryAmount && !hasSalaryText) return false;
  return true;
}

bool isMyPublicationsCanonicalSavedJob(Map<String, dynamic> m) {
  final status = (m['status'] ?? '').toString().trim().toLowerCase();
  final isDraftFlag =
      m['isDraft'] == true ||
      m['isIncomplete'] == true ||
      m['incomplete'] == true ||
      m['draft'] == true ||
      status == 'draft' ||
      status == 'incomplete' ||
      status == 'unfinished';
  if (isDraftFlag) return false;
  final isComplete = m['isComplete'] != false;
  final visibility = m['visibility'];
  final inJobs = visibility is Map
      ? (visibility['inJobs'] == true || visibility['in_jobs'] == true)
      : false;
  final isPublished =
      m['published'] == true || m['publishedInJobs'] == true || inJobs;
  final statusAllowsPublic =
      status.isEmpty || status == 'active' || status == 'published' || status == 'open';
  return isComplete && isPublished && statusAllowsPublic;
}

bool isMyPublicationsIncompleteJob(Map<String, dynamic> m) {
  if (isMyPublicationsCanonicalSavedJob(m)) return false;
  final rawComplete = m['isComplete'];
  if (rawComplete is bool && rawComplete == false) return true;
  final isDraft =
      m['isDraft'] == true ||
      m['isIncomplete'] == true ||
      m['incomplete'] == true ||
      m['draft'] == true ||
      (m['status'] ?? '').toString().trim().toLowerCase() == 'draft' ||
      (m['status'] ?? '').toString().trim().toLowerCase() == 'incomplete' ||
      (m['status'] ?? '').toString().trim().toLowerCase() == 'unfinished';
  if (isDraft) return true;
  return !_isMyVacancyPublishable(m);
}

MyPublicationsVisibilityResult resolveMyPublicationsVisibility(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
  required String ownerId,
}) {
  final reasons = <String, int>{};
  var dropped = 0;
  var duplicate = 0;
  void markReason(String reason) {
    reasons.update(reason, (v) => v + 1, ifAbsent: () => 1);
    dropped += 1;
  }

  final base = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final d in docs) {
    final m = d.data();
    final visibility = VacancyRuntimeVisibility.evaluateRaw(m);
    if (!visibility.visible) {
      markReason('runtime_visibility:${visibility.reason}');
      continue;
    }
    if (!WorkaEntityValidity.isValidOwnerVacancy(m, ownerUid: ownerId)) {
      markReason('invalid_owner_vacancy');
      continue;
    }
    base.add(d);
  }

  final draftDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  final publishedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final d in base) {
    final data = d.data();
    if (isMyPublicationsHiddenTestItem(data)) {
      markReason('hidden_test_item');
      continue;
    }
    if (isMyPublicationsCanonicalSavedJob(data)) {
      publishedDocs.add(d);
      continue;
    }
    if (isMyPublicationsIncompleteJob(data)) {
      draftDocs.add(d);
    } else {
      publishedDocs.add(d);
    }
  }

  final publishedJobCodes = publishedDocs
      .map((d) => (d.data()['jobCode'] ?? d.data()['job_code'] ?? '').toString().trim())
      .where((v) => v.isNotEmpty)
      .toSet();
  final publishedBackendIds = publishedDocs
      .map(
        (d) => (d.data()['backendId'] ?? d.data()['backend_id'] ?? '').toString().trim(),
      )
      .where((v) => v.isNotEmpty)
      .toSet();
  final publishedTitles = publishedDocs
      .map((d) => (d.data()['title'] ?? '').toString().trim().toLowerCase())
      .where((v) => v.isNotEmpty)
      .toSet();

  final dedupedDraftDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final d in draftDocs) {
    final m = d.data();
    final code = (m['jobCode'] ?? m['job_code'] ?? '').toString().trim();
    final backend = (m['backendId'] ?? m['backend_id'] ?? '').toString().trim();
    final title = (m['title'] ?? '').toString().trim().toLowerCase();
    final excluded =
        (code.isNotEmpty && publishedJobCodes.contains(code)) ||
        (backend.isNotEmpty && publishedBackendIds.contains(backend)) ||
        (title.isNotEmpty && publishedTitles.contains(title));
    if (excluded) {
      duplicate += 1;
      markReason('draft_duplicate_of_published');
      continue;
    }
    dedupedDraftDocs.add(d);
  }

  return MyPublicationsVisibilityResult(
    publishedDocs: publishedDocs,
    draftDocs: dedupedDraftDocs,
    droppedCount: dropped,
    duplicateCount: duplicate,
    reasons: reasons,
  );
}

class MyPublicationsScreen extends StatefulWidget {
  final bool testMode;
  final bool showEditActions;

  const MyPublicationsScreen({
    super.key,
    this.testMode = false,
    this.showEditActions = false,
  });

  static void clearGlobalCaches() {
    _MyJobsList.clearGlobalCaches();
  }

  @override
  State<MyPublicationsScreen> createState() => _MyPublicationsScreenState();
}

class _MyPublicationsScreenState extends State<MyPublicationsScreen> {
  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid.trim().isEmpty) {
      return const AuthEntryScreen();
    }
    final uid = user.uid.trim();
    debugPrint(
      'MyPublicationsScreen auth uid=${user.uid} effectiveUid=$uid email=${user.email} anon=${user.isAnonymous}',
    );
    final isBusinessMode =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business;
    final db = FirebaseFirestore.instance;
    final pageTitle = isBusinessMode ? 'Вакансии компании' : 'Мои вакансии';
    if (isBusinessMode && app_mode.AppMode.activeCompanyId.trim().isEmpty) {
      debugPrint(
        '[OWNER_SCOPE_REJECT] resource=job action=list reason=ownership_resolve_failed',
      );
      debugPrint(
        '[BUSINESS_SCOPE_RESOLVE] status=missing action=open_create_business_profile',
      );
      return Scaffold(
        backgroundColor: const Color(0xFF4A6FDB),
        body: Column(
          children: [
            WorkaHeader(
              title: pageTitle,
              leading: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Создайте бизнес-профиль, чтобы публиковать вакансии от компании.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WorkaColors.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EmployerCompanyProfileScreen(),
                        ),
                      ),
                      style: WorkaButtonStyles.primaryBlue(),
                      child: const Text('Создать бизнес-профиль'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    OwnershipResolution ownership;
    try {
      ownership = CanonicalOwnershipResolver.resolveVacancyOwner();
    } catch (_) {
      debugPrint(
        '[OWNER_SCOPE_REJECT] resource=job action=list reason=ownership_resolve_failed',
      );
      return Scaffold(
        backgroundColor: const Color(0xFF4A6FDB),
        body: Column(
          children: [
            WorkaHeader(
              title: pageTitle,
              leading: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Не удалось определить владельца списка вакансий. Обновите профиль.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final ownerId = ownership.ownerId;
    final currentOwnerType = ownership.ownerType;
    debugPrint(
      '[MY_PUBLICATIONS_SCOPE] mode=${app_mode.AppMode.currentMode.name} ownerId=$ownerId ownerType=$currentOwnerType',
    );
    debugPrint(
      '[OWNER_SCOPE_CHECK] resource=vacancy action=my_publications_open mode=${app_mode.AppMode.currentMode.name}',
    );
    final jobsCountStream = JobsRepository(db)
        .watchMyJobs(
          testMode: widget.testMode,
          userId: ownerId,
          ownerType: currentOwnerType,
        )
        .map(
          (docs) => docs
              .where(
                (d) => WorkaEntityValidity.isValidOwnerVacancy(
                  d.data(),
                  ownerUid: ownerId,
                ),
              )
              .length,
        );

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: pageTitle,
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
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: StreamBuilder<int>(
                      stream: jobsCountStream,
                      builder: (context, snap) {
                        return SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateJobScreen(
                                  testMode: widget.testMode,
                                ),
                              ),
                            ),
                            style: WorkaButtonStyles.primaryOrange(),
                            child: const Text(
                              'Добавить вакансию',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: _MyJobsList(
                      ownerId: ownerId,
                      employerUidForStats: ownerId,
                      ownerType: currentOwnerType,
                      testMode: widget.testMode,
                      asInt: _asInt,
                      showAllInDebug: false,
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
}

class _ApplyCounters {
  final int active;
  final int total;

  const _ApplyCounters({required this.active, required this.total});
}

class _MyJobsList extends StatelessWidget {
  static final Map<String, bool> _cvsExistsCache = <String, bool>{};
  static final Set<String> _copyInFlight = <String>{};
  final String ownerId;
  final String employerUidForStats;
  final String ownerType;
  final bool testMode;
  final int Function(dynamic) asInt;
  final bool showAllInDebug;

  const _MyJobsList({
    required this.ownerId,
    required this.employerUidForStats,
    required this.ownerType,
    required this.testMode,
    required this.asInt,
    required this.showAllInDebug,
  });

  static void clearGlobalCaches() {
    _cvsExistsCache.clear();
    _copyInFlight.clear();
  }

  void _toast(BuildContext context, String t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  String _collectionName() {
    return FirestorePaths.vacancies;
  }

  Map<String, _ApplyCounters> _groupApplyCounters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final tmp = <String, List<int>>{};
    final seen = <String>{};
    for (final d in docs) {
      final m = d.data();
      final type = (m['type'] ?? '').toString().trim().toLowerCase();
      if (type != 'apply') continue;
      final jobId = (m['jobId'] ?? m['vacancyId'] ?? '').toString().trim();
      if (jobId.isEmpty) continue;
      final cvId = (m['candidateCvId'] ?? m['cvId'] ?? '').toString().trim();
      final candidateOwner = (m['candidateOwnerId'] ?? '').toString().trim();
      final key = 'apply|$jobId|$candidateOwner|$cvId';
      if (!seen.add(key)) continue;
      final status = InteractionStatus.normalize(
        (m['status'] ?? '').toString().trim(),
      );
      final pair = tmp.putIfAbsent(jobId, () => <int>[0, 0]);
      if (status != InteractionStatus.rejected) pair[0] = pair[0] + 1;
      pair[1] = pair[1] + 1;
    }

    final out = <String, _ApplyCounters>{};
    tmp.forEach((jobId, v) {
      out[jobId] = _ApplyCounters(active: v[0], total: v[1]);
    });
    return out;
  }

  Future<bool> _cvExists(String cvId) async {
    final id = cvId.trim();
    if (id.isEmpty) return false;
    final key = '${FirestorePaths.cvs}/$id';
    final cached = _cvsExistsCache[key];
    if (cached != null) return cached;
    final snap = await FirebaseFirestore.instance
        .collection(FirestorePaths.cvs)
        .doc(id)
        .get();
    final data = snap.data() ?? const <String, dynamic>{};
    final exists = snap.exists && data['isDeleted'] != true;
    _cvsExistsCache[key] = exists;
    return exists;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _validApplyDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      final m = d.data();
      final type = (m['type'] ?? '').toString().trim().toLowerCase();
      if (type != 'apply') continue;
      final jobId = (m['jobId'] ?? m['vacancyId'] ?? '').toString().trim();
      final cvId = (m['candidateCvId'] ?? m['cvId'] ?? '').toString().trim();
      if (jobId.isEmpty || cvId.isEmpty) continue;
      if (!await _cvExists(cvId)) continue;
      out.add(d);
    }
    return out;
  }

  bool _isIndexError(Object? error) {
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return true;
    }
    return (error ?? '').toString().toLowerCase().contains('requires an index');
  }

  String _extractIndexUrl(String message) {
    final regex = RegExp(
      r'https://console\.firebase\.google\.com/\S+',
      caseSensitive: false,
    );
    final match = regex.firstMatch(message);
    if (match == null) return '';
    return match.group(0)?.trim() ?? '';
  }

  bool _isHiddenTestItem(Map<String, dynamic> m) {
    return isMyPublicationsHiddenTestItem(m);
  }

  String _normalizeCopyTitle(String rawTitle) {
    final base = rawTitle
        .trim()
        .replaceFirst(
          RegExp(r'(?:\s*\(копия\)\s*)+$', caseSensitive: false),
          '',
        )
        .trim();
    return '${base.isEmpty ? 'Вакансия' : base} (копия)';
  }

  Future<void> _copyJob(
    BuildContext context,
    String sourceJobId,
    Map<String, dynamic> job,
  ) async {
    if (ownerId.trim().isEmpty) {
      _toast(context, 'Нужен вход');
      return;
    }
    final lockKey = '$ownerId|${sourceJobId.trim()}';
    if (_copyInFlight.contains(lockKey)) return;
    _copyInFlight.add(lockKey);
    final now = FieldValue.serverTimestamp();
    final m = Map<String, dynamic>.from(job);

    final rawTitle = (m['title'] ?? 'Вакансия').toString().trim();
    m['title'] = _normalizeCopyTitle(rawTitle);

    m.remove('id');
    m.remove('docId');
    m.remove('jobId');

    m['createdAt'] = now;
    m['updatedAt'] = now;

    // reset counters/service flags for a real fresh copy
    m['applicationsCount'] = 0;
    m['newApplicationsCount'] = 0;
    m['views'] = 0;
    m['viewsCount'] = 0;
    m['offersCount'] = 0;
    m['responsesCount'] = 0;
    m['newResponsesCount'] = 0;
    m['stats'] = <String, dynamic>{};
    m['statusHistory'] = <dynamic>[];
    m['isDeleted'] = false;
    m['test'] = false;
    m['draft'] = false;
    m['status'] = 'active';
    m['publishedAt'] = now;

    m['ownerId'] = ownerId;
    m['ownerUid'] = ownerId;
    m['ownerType'] = ownerType;
    if (sourceJobId.trim().isNotEmpty) {
      m['copiedFromJobId'] = sourceJobId.trim();
    }

    try {
      final ref = await FirebaseFirestore.instance
          .collection(_collectionName())
          .add(m);
      if (ref.id.trim().isEmpty) {
        throw StateError('copy failed: empty document id');
      }
      if (context.mounted) _toast(context, 'Вакансия скопирована');
    } catch (e) {
      debugPrint('MyPublicationsScreen _copyJob error: $e');
      if (context.mounted) {
        _toast(context, 'Не удалось сохранить изменения.');
        if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
          _toast(context, FirebaseDebugDiagnostics.permissionHintText());
        }
      }
    } finally {
      _copyInFlight.remove(lockKey);
    }
  }

  Future<void> _deleteJob(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Удалить вакансию?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Отмена',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.delete();
      if (context.mounted) _toast(context, 'Вакансия удалена');
    } catch (e) {
      debugPrint('MyPublicationsScreen _deleteJob error: $e');
      if (context.mounted) {
        _toast(context, 'Не удалось сохранить изменения.');
        if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
          _toast(context, FirebaseDebugDiagnostics.permissionHintText());
        }
      }
    }
  }

  Future<void> _moveVacancyToOtherProfile(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> job,
  ) async {
    final targetOwnerType = ownerType == 'business' ? 'personal' : 'business';
    final targetLabel = targetOwnerType == 'business' ? 'бизнес' : 'личный';
    final title = (job['title'] ?? '').toString().trim();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Перенести вакансию?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          title.isNotEmpty
              ? 'Вакансия «$title» будет перенесена в $targetLabel профиль.'
              : 'Вакансия будет перенесена в $targetLabel профиль.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Отмена',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Перенести',
              style: TextStyle(
                color: Color(0xFF4A6FDB),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (targetOwnerType == 'business') {
        final companyId = app_mode.AppMode.activeCompanyId.trim();
        if (companyId.isEmpty) {
          if (context.mounted) {
            _toast(
              context,
              'Выберите бизнес-профиль компании перед переносом вакансии.',
            );
          }
          return;
        }
        await ref.update({
          'ownerType': 'business',
          'owner_type': 'business',
          'ownerId': companyId,
          'owner_id': companyId,
          'companyId': companyId,
          'company_id': companyId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        if (currentUid.isEmpty) {
          if (context.mounted) {
            _toast(context, 'Не удалось определить владельца личного профиля.');
          }
          return;
        }
        await ref.update({
          'ownerType': 'personal',
          'owner_type': 'personal',
          'ownerId': currentUid,
          'owner_id': currentUid,
          'ownerUid': currentUid,
          'owner_uid': currentUid,
          'uid': currentUid,
          'userId': currentUid,
          'createdBy': currentUid,
          'companyId': FieldValue.delete(),
          'company_id': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (context.mounted) {
        _toast(context, 'Вакансия перенесена в $targetLabel профиль');
      }
    } catch (e) {
      debugPrint('MyPublicationsScreen _moveVacancyToOtherProfile error: $e');
      if (context.mounted) {
        _toast(context, 'Не удалось выполнить действие. Попробуйте ещё раз.');
        if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
          _toast(context, FirebaseDebugDiagnostics.permissionHintText());
        }
      }
    }
  }

  Future<void> _markJobApplicationsViewed(String jobId) async {
    if (employerUidForStats.isEmpty && !testMode) return;
    final byEmployer = await FirebaseFirestore.instance
        .collection(FirestorePaths.applications)
        .get();
    for (final d in byEmployer.docs) {
      final m = d.data();
      final type = (m['type'] ?? '').toString().trim().toLowerCase();
      if (type != 'apply') continue;
      final owner = (m['employerOwnerId'] ?? '').toString().trim();
      if (owner != employerUidForStats) continue;
      final vacancyId = (m['vacancyId'] ?? m['jobId'] ?? '').toString().trim();
      final status = InteractionStatus.normalize(
        m['statusEmployer'] ?? m['status'],
      );
      if (vacancyId != jobId) continue;
      if (!InteractionStatus.isFresh(status)) continue;
      await d.reference.update({
        'status': InteractionStatus.viewed,
        'statusEmployer': InteractionStatus.viewed,
        'viewedByEmployer': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!showAllInDebug && ownerId.trim().isEmpty) {
      return const Center(
        child: Text(
          'Войдите, чтобы видеть свои вакансии',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: WorkaColors.textDark,
          ),
        ),
      );
    }

    final normalizedOwnerId = ownerId.trim();
    if (!showAllInDebug && normalizedOwnerId.isEmpty) {
      return const Center(
        child: Text(
          'Войдите, чтобы видеть свои вакансии',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: WorkaColors.textDark,
          ),
        ),
      );
    }
    final db = FirebaseFirestore.instance;
    final stream = JobsRepository(db).watchMyJobs(
      testMode: testMode,
      userId: normalizedOwnerId,
      ownerType: ownerType,
    );
    debugPrint(
      'MyPublications repo stream testMode=$testMode ownerId=$normalizedOwnerId ownerType=$ownerType',
    );

    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          final err = snap.error.toString();
          debugPrint('MyPublicationsScreen jobs stream error: $err');
          final isPermissionDenied =
              FirebaseDebugDiagnostics.isPermissionDenied(err);
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Не удалось загрузить вакансии. Попробуйте позже.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (isPermissionDenied && testMode) ...[
                    const SizedBox(height: 10),
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
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final paid = context.watch<PaidEntitlementsController>();
        final rawDocs = [...snap.data!];
        final visibility = resolveMyPublicationsVisibility(
          rawDocs,
          ownerId: normalizedOwnerId,
        );
        final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
          ...visibility.publishedDocs,
          ...visibility.draftDocs,
        ];
        for (final d in docs) {
          final id = d.id.trim();
          if (id.isNotEmpty && paid.shouldRefreshJobEntitlements(id)) {
            Future.microtask(() => paid.refreshJobEntitlements(id));
          }
        }
        DateTime parseDate(dynamic v) {
          if (v is Timestamp) return v.toDate();
          return DateTime.fromMillisecondsSinceEpoch(0);
        }

        docs.sort((a, b) {
          final am = a.data();
          final bm = b.data();
          final aUrgent =
              (am['paidUrgent'] == true ||
                  am['urgentActiveUntil'] != null ||
                  paid.hasJobFeature(a.id, 'urgent'))
              ? 1
              : 0;
          final bUrgent =
              (bm['paidUrgent'] == true ||
                  bm['urgentActiveUntil'] != null ||
                  paid.hasJobFeature(b.id, 'urgent'))
              ? 1
              : 0;
          if (aUrgent != bUrgent) return bUrgent.compareTo(aUrgent);
          final ap = paid.hasJobFeature(a.id, 'priority') ? 1 : 0;
          final bp = paid.hasJobFeature(b.id, 'priority') ? 1 : 0;
          if (ap != bp) return bp.compareTo(ap);
          final ab = paid.hasJobFeature(a.id, 'bump') ? 1 : 0;
          final bb = paid.hasJobFeature(b.id, 'bump') ? 1 : 0;
          if (ab != bb) return bb.compareTo(ab);
          final ah = paid.hasJobFeature(a.id, 'highlight') ? 1 : 0;
          final bh = paid.hasJobFeature(b.id, 'highlight') ? 1 : 0;
          if (ah != bh) return bh.compareTo(ah);
          final au = parseDate(am['updatedAt']);
          final bu = parseDate(bm['updatedAt']);
          if (au != bu) return bu.compareTo(au);
          final ac = parseDate(am['createdAt']);
          final bc = parseDate(bm['createdAt']);
          return bc.compareTo(ac);
        });
        if (docs.isNotEmpty) {
          debugPrint(
            '[MY_PUBLICATIONS_RESULT] ownerType=$ownerType ownerId=$normalizedOwnerId count=${docs.length}',
          );
        }
        final db2 = FirebaseFirestore.instance;
        final baseApply = db2
            .collection(FirestorePaths.applications)
            .where('type', isEqualTo: 'apply')
            .where('employerOwnerId', isEqualTo: employerUidForStats);
        logQuerySignature(
          'my_publications_apply_stats',
          baseApply,
          collectionPath: FirestorePaths.applications,
          where: <String>[
            'type == apply (String)',
            'employerOwnerId == employerUidForStats (String)',
          ],
        );

        return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: baseApply.snapshots().asyncMap(
            (snap) => _validApplyDocs(snap.docs),
          ),
          builder: (context, statsSnap) {
            if (statsSnap.hasError) {
              final msg = statsSnap.error.toString();
              debugPrint('MyPublicationsScreen apply stats error: $msg');
              final isIndexError = _isIndexError(statsSnap.error);
              final indexUrl = _extractIndexUrl(msg);
              if (isIndexError) {
                debugPrint(
                  '[FirestoreIndexError][my_publications_apply_stats] $msg',
                );
                if (kDebugMode && indexUrl.isNotEmpty) {
                  debugPrint(
                    '[FirestoreIndexError][my_publications_apply_stats][index_url] $indexUrl',
                  );
                }
              }
              return _buildJobsListView(
                context,
                rawDocs,
                const <String, _ApplyCounters>{},
                topBanner: StatsInfoBanner(
                  title: 'Не удалось обновить счётчики откликов.',
                  message:
                      'Список вакансий загружен, попробуйте обновить позже.',
                  onRetry: () => (context as Element).markNeedsBuild(),
                ),
              );
            }
            final statsByJob = statsSnap.hasData
                ? _groupApplyCounters(statsSnap.data!)
                : const <String, _ApplyCounters>{};
            return _buildJobsListView(context, rawDocs, statsByJob);
          },
        );
      },
    );
  }

  Widget _buildJobsListView(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, _ApplyCounters> statsByJob, {
    Widget? topBanner,
  }) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: JobDraftStorage.load(),
      builder: (context, draftSnap) {
        final paid = context.watch<PaidEntitlementsController>();
        DateTime parseCreatedAt(Map<String, dynamic> m) {
          final raw = m['createdAt'];
          if (raw is Timestamp) return raw.toDate();
          return DateTime.fromMillisecondsSinceEpoch(0);
        }

        final draft = draftSnap.data;
        RuntimeFlowLogger.mark('UNFINISHED_JOBS_FILTER_START', <String, Object?>{
          'ownerType': ownerType,
          'ownerId': ownerId,
          'docsCount': docs.length,
          'hasLocalDraft': draft != null,
        });
        final visibility = resolveMyPublicationsVisibility(docs, ownerId: ownerId);
        var hasDraft =
            draft != null &&
            !_isHiddenTestItem(draft) &&
            ((draft['status'] ?? '').toString().trim() == 'unfinished');
        final draftDocs = [...visibility.draftDocs];
        final publishedDocs = [...visibility.publishedDocs];
        final publishedJobCodes = publishedDocs
            .map(
              (d) =>
                  (d.data()['jobCode'] ?? d.data()['job_code'] ?? '')
                      .toString()
                      .trim(),
            )
            .where((v) => v.isNotEmpty)
            .toSet();
        final publishedBackendIds = publishedDocs
            .map(
              (d) =>
                  (d.data()['backendId'] ?? d.data()['backend_id'] ?? '')
                      .toString()
                      .trim(),
            )
            .where((v) => v.isNotEmpty)
            .toSet();
        final publishedTitles = publishedDocs
            .map((d) => (d.data()['title'] ?? '').toString().trim().toLowerCase())
            .where((v) => v.isNotEmpty)
            .toSet();
        if (hasDraft) {
          final localDraft = draft;
          final localCode = (localDraft['jobCode'] ?? localDraft['job_code'] ?? '')
              .toString()
              .trim();
          final localBackend = (localDraft['backendId'] ?? localDraft['backend_id'] ?? '')
              .toString()
              .trim();
          final localTitle = (localDraft['title'] ?? '').toString().trim().toLowerCase();
          if ((localCode.isNotEmpty && publishedJobCodes.contains(localCode)) ||
              (localBackend.isNotEmpty &&
                  publishedBackendIds.contains(localBackend)) ||
              (localTitle.isNotEmpty && publishedTitles.contains(localTitle))) {
            hasDraft = false;
            RuntimeFlowLogger.mark(
              'UNFINISHED_JOBS_FILTER_EXCLUDED_SAVED',
              <String, Object?>{
                'docId': 'local_draft',
                'jobCode': localCode,
                'backendId': localBackend,
                'title': localTitle,
              },
            );
          }
        }
        int byCreatedAtDesc(
          QueryDocumentSnapshot<Map<String, dynamic>> a,
          QueryDocumentSnapshot<Map<String, dynamic>> b,
        ) {
          final ap = paid.hasJobFeature(a.id, 'priority') ? 1 : 0;
          final bp = paid.hasJobFeature(b.id, 'priority') ? 1 : 0;
          if (ap != bp) return bp.compareTo(ap);
          final ab = paid.hasJobFeature(a.id, 'bump') ? 1 : 0;
          final bb = paid.hasJobFeature(b.id, 'bump') ? 1 : 0;
          if (ab != bb) return bb.compareTo(ab);
          final ah = paid.hasJobFeature(a.id, 'highlight') ? 1 : 0;
          final bh = paid.hasJobFeature(b.id, 'highlight') ? 1 : 0;
          if (ah != bh) return bh.compareTo(ah);
          final ac = parseCreatedAt(a.data());
          final bc = parseCreatedAt(b.data());
          return bc.compareTo(ac);
        }

        draftDocs.sort(byCreatedAtDesc);
        publishedDocs.sort(byCreatedAtDesc);
        RuntimeFlowLogger.mark('UNFINISHED_JOBS_RESULT', <String, Object?>{
          'ownerType': ownerType,
          'ownerId': ownerId,
          'publishedCount': publishedDocs.length,
          'draftCount': draftDocs.length,
          'hasLocalDraft': hasDraft,
        });

        if (!hasDraft && draftDocs.isEmpty && publishedDocs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'У вас пока нет вакансий',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: WorkaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Создайте первую вакансию, чтобы получать отклики.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: WorkaColors.textGreyDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        }

        final sections = <Widget>[];

        if (topBanner != null) {
          sections.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: topBanner,
            ),
          );
        }

        if (hasDraft || draftDocs.isNotEmpty) {
          sections.add(
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Незаконченные вакансии',
                  style: TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          );
        }

        if (hasDraft) {
          final localDraft = draft ?? const <String, dynamic>{};
          sections.add(
            DraftJobCard(
              title: (localDraft['title'] ?? '').toString().trim().isEmpty
                  ? 'Новая вакансия'
                  : (localDraft['title'] ?? '').toString().trim(),
              city: (localDraft['city'] ?? '').toString().trim(),
              country: (localDraft['country'] ?? '').toString().trim(),
              onContinue: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateJobScreen(testMode: testMode),
                ),
              ),
            ),
          );
        }

        for (final d in draftDocs) {
          final m = d.data();
          final ref = d.reference;
          sections.add(
            DraftJobCard(
              title: (m['title'] ?? '').toString().trim().isEmpty
                  ? 'Новая вакансия'
                  : (m['title'] ?? '').toString().trim(),
              city: (m['city'] ?? '').toString().trim(),
              country: (m['country'] ?? '').toString().trim(),
              onContinue: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateJobScreen(
                    editJobId: d.id,
                    editJobRef: ref,
                    testMode: testMode,
                  ),
                ),
              ),
            ),
          );
        }

        if (publishedDocs.isNotEmpty) {
          final sectionTitle = ownerType == 'business'
              ? 'Вакансии компании'
              : 'Мои вакансии';
          sections.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  sectionTitle,
                  style: const TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          );
        }

        for (final d in publishedDocs) {
          final m = d.data();
          final visibleAtRender = VacancyRuntimeVisibility.logRenderAttempt(
            source: 'my_publications_screen',
            jobId: d.id,
            rawVacancy: m,
          );
          if (!visibleAtRender) {
            continue;
          }
          final promotionIdentity = ApplyVacancyIdentityResolver.resolve(
            vacancyId: d.id,
            snapshot: m,
          );
          final promotionOwnerScope =
              VacancyOwnerScopeResolver.resolveVacancyOwnerScope(m);
          final promotionScopeDecision = promotionOwnerScope.isResolved
              ? CanonicalOwnershipResolver.resolvePromotionAccess(
                  entityOwnerType: promotionOwnerScope.ownerType,
                  entityOwnerId: promotionOwnerScope.ownerId,
                )
              : PromotionOwnershipDecision.wrongProfile;
          final promotionTargetId = promotionIdentity.isResolved
              ? promotionIdentity.apiJobCode
              : d.id;
          final canPromote =
              promotionOwnerScope.isResolved &&
              promotionIdentity.isResolved &&
              promotionScopeDecision.allowed;
          final promotionBlockedMessage = !promotionIdentity.isResolved
              ? 'Вакансия не синхронизирована. Продвижение пока недоступно.'
              : (!promotionOwnerScope.isResolved
                    ? 'Не удалось определить владельца вакансии для продвижения.'
                    : 'Создано в другом профиле. Переключите профиль.');

          final title = (m['title'] ?? 'Вакансия').toString();
          final vacancyNumber = (m['vacancyNumber'] ?? '').toString().trim();
          final city = (m['city'] ?? '').toString();
          final country = (m['country'] ?? '').toString();
          final salary =
              (m['salaryText'] ?? m['salary'] ?? 'Зарплата не указана')
                  .toString();
          final salaryFrom = m['salaryFrom'] is num
              ? (m['salaryFrom'] as num).toDouble()
              : (m['salaryAmount'] is num
                    ? (m['salaryAmount'] as num).toDouble()
                    : null);
          final salaryTo = m['salaryTo'] is num
              ? (m['salaryTo'] as num).toDouble()
              : null;
          final salaryType = (m['salaryType'] ?? m['salaryPeriod'] ?? 'month')
              .toString();
          final employmentLabel =
              (m['workSchedule'] ??
                      m['workScheduleOption'] ??
                      m['employmentType'] ??
                      m['type'] ??
                      'Полная занятость')
                  .toString();
          final housingProvided = m['housingProvided'] == true;
          final transportProvided = m['transportProvided'] == true;
          final forTeenagers =
              m['forTeenagers'] == true || m['teenFriendly'] == true;
          final forDisabled =
              m['forDisabled'] == true || m['disabledFriendly'] == true;
          final isUrgent =
              (m['isUrgent'] == true) &&
              (m['paidUrgent'] == true || m['urgentActiveUntil'] != null);

          final ref = d.reference;

          sections.add(
            JobCard(
              jobId: d.id,
              title: title,
              vacancyNumber: vacancyNumber,
              ownerUid: OwnershipResolver.vacancyOwnerIdFromMap(m),
              ownerEmail: (m['ownerEmail'] ?? m['email'] ?? '').toString(),
              currentUserUid: ownerId,
              vacancySnapshot: Map<String, dynamic>.from(m),
              city: city,
              country: country,
              salary: salary,
              salaryFrom: salaryFrom,
              salaryTo: salaryTo,
              salaryType: salaryType,
              employmentLabel: employmentLabel,
              housingProvided: housingProvided,
              transportProvided: transportProvided,
              forTeenagers: forTeenagers,
              forDisabled: forDisabled,
              isUrgent: isUrgent,
              onOpen: () async {
                await _markJobApplicationsViewed(d.id);
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VacancyDetailsScreen(
                      jobId: promotionTargetId,
                      refOverride: ref,
                      isOwnerView: true,
                    ),
                  ),
                );
              },
              onHighlight: () =>
                  canPromote
                  ? Navigator.of(context, rootNavigator: true).pushNamed(
                      PaymentsRoutes.promoteJob,
                      arguments: <String, dynamic>{
                        'jobId': promotionTargetId,
                        'ownerType': promotionOwnerScope.ownerType,
                        'ownerId': promotionOwnerScope.ownerId,
                      },
                    )
                  : ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          promotionBlockedMessage,
                        ),
                      ),
                    ),
              promotionLabel: '',
              onAction: (a) async {
                switch (a) {
                  case JobCardAction.edit:
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VacancyReviewScreen(
                          jobId: d.id,
                          jobRef: ref,
                          testMode: testMode,
                        ),
                      ),
                    );
                    break;
                  case JobCardAction.promote:
                    if (!canPromote) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            promotionBlockedMessage,
                          ),
                        ),
                      );
                      break;
                    }
                    Navigator.of(context, rootNavigator: true).pushNamed(
                      PaymentsRoutes.promoteJob,
                      arguments: <String, dynamic>{
                        'jobId': promotionTargetId,
                        'ownerType': promotionOwnerScope.ownerType,
                        'ownerId': promotionOwnerScope.ownerId,
                      },
                    );
                    break;
                  case JobCardAction.copy:
                    await _copyJob(context, d.id, m);
                    break;
                  case JobCardAction.moveProfile:
                    await _moveVacancyToOtherProfile(context, ref, m);
                    break;
                  case JobCardAction.delete:
                    await _deleteJob(context, ref);
                    break;
                }
              },
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 16),
          itemCount: sections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => sections[i],
        );
      },
    );
  }
}
