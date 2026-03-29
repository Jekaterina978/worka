import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/theme/worka_ui_tokens.dart';
import 'package:worka/widgets/worka_header.dart';
import 'package:worka/screens/vacancy_details_screen.dart';
import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/interaction_status.dart';
import 'package:worka/services/firestore_query_debug.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/services/profile_completion.dart';
import 'package:worka/services/entity_validity.dart';
import 'package:worka/services/app_mode.dart' as app_mode;
import 'package:worka/repositories/jobs_repository.dart';
import 'package:worka/widgets/cards/vacancy_list_card.dart';
import 'package:worka/widgets/card_more_menu_button.dart';
import 'package:worka/widgets/worka_job_card.dart';
import 'package:worka/screens/jobs/services/job_draft_storage.dart';
import 'package:worka/features/payments/payments_routes.dart';
import 'package:worka/screens/vacancy_review_screen.dart';
import 'create_job_screen.dart';
import '../auth/auth_entry_screen.dart';

enum JobCardAction { edit, promote, copy, moveProfile, delete }

class MyPublicationsScreen extends StatefulWidget {
  final bool testMode;
  final bool showEditActions;

  const MyPublicationsScreen({
    super.key,
    this.testMode = true,
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
    final ownerUid = uid;
    final db = FirebaseFirestore.instance;
    final currentOwnerType =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business
        ? 'business'
        : 'personal';
    final jobsCountStream = JobsRepository(db)
        .watchMyJobs(
          testMode: widget.testMode,
          userId: ownerUid,
          ownerType: currentOwnerType,
        )
        .map(
          (docs) => docs
              .where(
                (d) => WorkaEntityValidity.isValidOwnerVacancy(
                  d.data(),
                  ownerUid: ownerUid,
                ),
              )
              .length,
        );

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Мои вакансии',
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
                        if (ownerUid.isEmpty) {
                          return SizedBox(
                            height: 56,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: null,
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
                        }

                        return StreamBuilder<
                          DocumentSnapshot<Map<String, dynamic>>
                        >(
                          stream: db
                              .collection('users')
                              .doc(ownerUid)
                              .snapshots(),
                          builder: (context, userSnap) {
                            final userData =
                                userSnap.data?.data() ??
                                const <String, dynamic>{};
                            final businessComplete = isBusinessComplete(
                              userData,
                            );
                            final disabled = !businessComplete;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 56,
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: disabled
                                        ? null
                                        : () => Navigator.push(
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
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: _MyJobsList(
                      uid: uid,
                      employerUidForStats: ownerUid,
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
  final String? uid;
  final String employerUidForStats;
  final String ownerType;
  final bool testMode;
  final int Function(dynamic) asInt;
  final bool showAllInDebug;

  const _MyJobsList({
    required this.uid,
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

  bool _containsCopyToken(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('копия') || normalized.contains('copy');
  }

  bool _isVacancyPublishable(Map<String, dynamic> m) {
    final title = (m['title'] ?? '').toString().trim();
    if (title.isEmpty) return false;
    if (_containsCopyToken(title)) return false;

    final category = (m['category'] ?? '').toString().trim();
    if (category.isEmpty) return false;

    final city = (m['city'] ?? '').toString().trim();
    final country = (m['country'] ?? '').toString().trim();
    if (city.isEmpty || country.isEmpty) return false;

    final employment = (m['employmentType'] ?? m['type'] ?? '')
        .toString()
        .trim();
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

  bool _isIncompleteJob(Map<String, dynamic> m) {
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
    return !_isVacancyPublishable(m);
  }

  bool _isHiddenTestItem(Map<String, dynamic> m) {
    final text = <String>[
      (m['title'] ?? '').toString(),
      (m['status'] ?? '').toString(),
      (m['source'] ?? '').toString(),
    ].join(' ').toLowerCase();
    if (text.contains('test') ||
        text.contains('demo') ||
        text.contains('draft')) {
      return true;
    }
    return m['test'] == true || m['draft'] == true;
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

  bool _isRenderableVacancyDoc(Map<String, dynamic> m) {
    if ((m['isDeleted'] ?? false) == true) return false;
    final status = (m['status'] ?? '').toString().trim().toLowerCase();
    if (status == 'deleted' || status == 'archived' || status == 'removed') {
      return false;
    }
    if (m['deletedAt'] != null) return false;
    return true;
  }

  Future<void> _copyJob(
    BuildContext context,
    String sourceJobId,
    Map<String, dynamic> job,
  ) async {
    if ((uid?.trim() ?? '').isEmpty) {
      _toast(context, 'Нужен вход');
      return;
    }
    final lockKey = '${uid ?? ''}|${sourceJobId.trim()}';
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

    m['ownerId'] = uid;
    m['ownerUid'] = uid;
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
        _toast(context, 'Ошибка сохранения: $e');
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
        _toast(context, 'Ошибка сохранения: $e');
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
      await ref.update({
        'ownerType': targetOwnerType,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        _toast(context, 'Вакансия перенесена в $targetLabel профиль');
      }
    } catch (e) {
      debugPrint('MyPublicationsScreen _moveVacancyToOtherProfile error: $e');
      if (context.mounted) {
        _toast(context, 'Ошибка: $e');
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
    if (!showAllInDebug && (uid == null || uid!.trim().isEmpty)) {
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

    final ownerUid = uid?.trim() ?? '';
    if (!showAllInDebug && ownerUid.isEmpty) {
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
    final stream = JobsRepository(
      db,
    ).watchMyJobs(testMode: testMode, userId: ownerUid, ownerType: ownerType);
    debugPrint(
      'MyPublications repo stream testMode=$testMode ownerUid=$ownerUid',
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
                    'Ошибка загрузки: $err',
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

        final docs = [...snap.data!];
        docs.retainWhere((d) {
          final m = d.data();
          if (!_isRenderableVacancyDoc(m)) return false;
          return WorkaEntityValidity.isValidOwnerVacancy(m, ownerUid: ownerUid);
        });
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
                docs,
                const <String, _ApplyCounters>{},
                topBanner: _StatsInfoBanner(
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
            return _buildJobsListView(context, docs, statsByJob);
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
        DateTime parseCreatedAt(Map<String, dynamic> m) {
          final raw = m['createdAt'];
          if (raw is Timestamp) return raw.toDate();
          return DateTime.fromMillisecondsSinceEpoch(0);
        }

        final draft = draftSnap.data;
        final hasDraft =
            draft != null &&
            !_isHiddenTestItem(draft) &&
            ((draft['status'] ?? '').toString().trim() == 'unfinished');
        final draftDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final publishedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in docs) {
          final data = d.data();
          if (_isHiddenTestItem(data)) continue;
          if (_isIncompleteJob(data)) {
            draftDocs.add(d);
          } else {
            publishedDocs.add(d);
          }
        }
        int byCreatedAtDesc(
          QueryDocumentSnapshot<Map<String, dynamic>> a,
          QueryDocumentSnapshot<Map<String, dynamic>> b,
        ) {
          final ac = parseCreatedAt(a.data());
          final bc = parseCreatedAt(b.data());
          return bc.compareTo(ac);
        }

        draftDocs.sort(byCreatedAtDesc);
        publishedDocs.sort(byCreatedAtDesc);

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
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreateJobScreen(testMode: testMode),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WorkaColors.orange,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Создать вакансию',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
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
          sections.add(
            _DraftJobCard(
              title: (draft['title'] ?? '').toString().trim().isEmpty
                  ? 'Новая вакансия'
                  : (draft['title'] ?? '').toString().trim(),
              city: (draft['city'] ?? '').toString().trim(),
              country: (draft['country'] ?? '').toString().trim(),
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
            _DraftJobCard(
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
          sections.add(
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Мои вакансии',
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

        for (final d in publishedDocs) {
          final m = d.data();

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
            _JobCard(
              jobId: d.id,
              title: title,
              vacancyNumber: vacancyNumber,
              ownerUid: OwnershipResolver.vacancyOwnerIdFromMap(m),
              ownerEmail: (m['ownerEmail'] ?? m['email'] ?? '').toString(),
              currentUserUid: uid?.trim() ?? '',
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
                      jobId: d.id,
                      refOverride: ref,
                      isOwnerView: true,
                    ),
                  ),
                );
              },
              onHighlight: () =>
                  Navigator.of(context, rootNavigator: true).pushNamed(
                    PaymentsRoutes.promoteJob,
                    arguments: <String, dynamic>{'jobId': d.id},
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
                    Navigator.of(context, rootNavigator: true).pushNamed(
                      PaymentsRoutes.promoteJob,
                      arguments: <String, dynamic>{'jobId': d.id},
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

class _StatsInfoBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _StatsInfoBanner({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: WorkaColors.textDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: onRetry,
                child: const Text(
                  'Повторить',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftJobCard extends StatelessWidget {
  final String title;
  final String city;
  final String country;
  final VoidCallback onContinue;

  const _DraftJobCard({
    required this.title,
    required this.city,
    required this.country,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final location = [
      city.trim(),
      country.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WorkaColors.fieldBorder),
        boxShadow: WorkaUiShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.edit_outlined,
                color: WorkaColors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Не закончено',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: WorkaColors.orange,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onContinue,
                child: const Text(
                  'Дополнить',
                  style: TextStyle(
                    color: WorkaColors.blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: WorkaColors.textDark,
            ),
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              location,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: WorkaColors.textGreyDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final String jobId;
  final String title;
  final String vacancyNumber;
  final String ownerUid;
  final String ownerEmail;
  final String currentUserUid;
  final String city;
  final String country;
  final String salary;
  final double? salaryFrom;
  final double? salaryTo;
  final String salaryType;
  final String employmentLabel;
  final bool housingProvided;
  final bool transportProvided;
  final bool forTeenagers;
  final bool forDisabled;
  final bool isUrgent;
  final VoidCallback onOpen;
  final VoidCallback onHighlight;
  final String promotionLabel;
  final ValueChanged<JobCardAction> onAction;

  const _JobCard({
    required this.jobId,
    required this.title,
    required this.vacancyNumber,
    required this.ownerUid,
    required this.ownerEmail,
    required this.currentUserUid,
    required this.city,
    required this.country,
    required this.salary,
    required this.salaryFrom,
    required this.salaryTo,
    required this.salaryType,
    required this.employmentLabel,
    required this.housingProvided,
    required this.transportProvided,
    required this.forTeenagers,
    required this.forDisabled,
    required this.isUrgent,
    required this.onOpen,
    required this.onHighlight,
    required this.promotionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final ownership = OwnershipResolver.byOwnerId(
      ownerUid,
      currentUserId: currentUserUid,
    );
    final isOwner = ownership.known && ownership.isOwner;
    return VacancyListCard(
      mode: WorkaJobCardMode.owner,
      title: title,
      vacancyNumber: vacancyNumber,
      showVacancyNumberInOwnerView: true,
      city: city,
      country: country,
      salaryFrom: salaryFrom,
      salaryTo: salaryTo,
      salaryType: salaryType,
      salaryTextFallback: salary,
      employmentLabel: employmentLabel,
      housingProvided: housingProvided,
      transportProvided: transportProvided,
      forTeenagers: forTeenagers,
      forDisabled: forDisabled,
      isUrgent: isUrgent,
      jobId: jobId,
      ownerUid: ownerUid,
      ownerEmail: ownerEmail,
      onTap: onOpen,
      showApply: false,
      salaryTrailing: isOwner
          ? SizedBox(
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.17),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: OutlinedButton(
                  onPressed: onHighlight,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: WorkaColors.orange,
                    side: const BorderSide(
                      color: WorkaColors.orange,
                      width: 1.2,
                    ),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'Продвижение вакансии',
                    style: TextStyle(
                      color: WorkaColors.orange,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            )
          : null,
      footerLeading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (promotionLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: WorkaColors.hoverBlueSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: WorkaColors.fieldBorder),
              ),
              child: Text(
                promotionLabel,
                style: const TextStyle(
                  color: WorkaColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      topRight: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CardMoreMenuButton(
            items: [
              CardMenuItem(
                label: 'Изменить',
                onTap: () => onAction(JobCardAction.edit),
              ),
              CardMenuItem(
                label: 'Продвинуть',
                onTap: () => onAction(JobCardAction.promote),
              ),
              CardMenuItem(
                label: 'Копировать',
                onTap: () => onAction(JobCardAction.copy),
              ),
              CardMenuItem(
                label: 'Перенести в другой профиль',
                onTap: () => onAction(JobCardAction.moveProfile),
              ),
              CardMenuItem(
                label: 'Удалить',
                onTap: () => onAction(JobCardAction.delete),
              ),
            ],
          ),
        ],
      ),
      topRightReservedWidth: 92,
    );
  }
}
