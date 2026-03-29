import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/candidate_age.dart';
import '../../services/entity_validity.dart';
import '../../services/firestore_paths.dart';
import '../../services/interaction_card_status.dart';
import '../../services/interaction_status.dart';
import '../../services/ownership_resolver.dart';
import '../../theme/worka_colors.dart';
import '../../utils/country_display_formatter.dart';
import '../../widgets/cards/candidate_list_card.dart';
import '../../widgets/cards/candidate_cv_card.dart';
import '../../widgets/cards/vacancy_list_card.dart';
import '../../widgets/firestore_query_error_state.dart';
import '../../widgets/worka_header.dart';
import '../../widgets/status_pill_badge.dart';
import '../../widgets/worka_job_card.dart';
import '../cv/cv_view_screen.dart';
import '../employer/search/widgets/vacancy_details_sheet.dart';
import 'interaction_message_screen.dart';
import '../auth/auth_entry_screen.dart';

class ApplicationsListScreen extends StatefulWidget {
  const ApplicationsListScreen({
    super.key,
    required this.testMode,
    required this.jobId,
    required this.employerUid,
    this.candidateUid,
    this.profileType = '',
  });

  final bool testMode;
  final String jobId;
  final String employerUid;
  final String? candidateUid;

  /// Optional profile type filter ('personal' or 'business').
  /// When set, only applications matching this profile type are shown.
  /// Empty string = show all (backwards compatible).
  final String profileType;

  @override
  State<ApplicationsListScreen> createState() => _ApplicationsListScreenState();
}

class _ApplicationsListScreenState extends State<ApplicationsListScreen> {
  final Map<String, Future<Map<String, dynamic>>> _jobCache =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<Map<String, dynamic>>> _cvCache =
      <String, Future<Map<String, dynamic>>>{};
  String _statusFilter = 'all';

  Query<Map<String, dynamic>> buildResponsesQuery({
    required String type,
    required String field,
    required String uid,
  }) {
    return FirebaseFirestore.instance
        .collection(FirestorePaths.applications)
        .where('type', isEqualTo: type)
        .where(field, isEqualTo: uid);
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _normalizedStatus(Map<String, dynamic> m) {
    final raw = _s(m['status'], fallback: InteractionStatus.sent);
    return InteractionStatus.normalize(raw);
  }

  String _applyCandidateOwnerId(Map<String, dynamic> m) {
    return _s(
      m['candidateOwnerId'],
      fallback: _s(
        m['candidateId'],
        fallback: _s(
          m['candidateUid'],
          fallback: _s(m['applicantId'], fallback: _s(m['candidateOwnerKey'])),
        ),
      ),
    );
  }

  DateTime _updatedAt(Map<String, dynamic> m) {
    final ts = m['updatedAt'] ?? m['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _mergedAppliesStream({required String uid, required bool isEmployerView}) {
    final primary = FirebaseFirestore.instance.collection(
      FirestorePaths.applications,
    );
    final queries = <Query<Map<String, dynamic>>>[
      primary
          .where('type', isEqualTo: 'apply')
          .where(
            isEmployerView ? 'employerOwnerId' : 'candidateOwnerId',
            isEqualTo: uid,
          ),
      primary
          .where('type', isEqualTo: 'apply')
          .where(
            isEmployerView ? 'employerUid' : 'candidateUid',
            isEqualTo: uid,
          ),
      primary
          .where('type', isEqualTo: 'apply')
          .where(isEmployerView ? 'employerId' : 'candidateId', isEqualTo: uid),
      primary
          .where('type', isEqualTo: 'apply')
          .where(
            isEmployerView ? 'vacancyOwnerKey' : 'candidateOwnerKey',
            isEqualTo: uid,
          ),
      if (!isEmployerView)
        primary
            .where('type', isEqualTo: 'apply')
            .where('applicantId', isEqualTo: uid),
    ];
    if (isEmployerView) {
      queries.add(
        primary
            .where('type', isEqualTo: 'apply')
            .where('vacancyOwnerId', isEqualTo: uid),
      );
    }

    final controller =
        StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>();
    final buckets =
        List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.generate(
          queries.length,
          (_) => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
        );
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emit() {
      final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final list in buckets) {
        for (final doc in list) {
          merged[doc.id] = doc;
        }
      }
      final out = merged.values.toList()
        ..sort((a, b) => _updatedAt(b.data()).compareTo(_updatedAt(a.data())));
      controller.add(out);
    }

    for (var i = 0; i < queries.length; i++) {
      subs.add(
        queries[i].snapshots().listen((snap) {
          buckets[i] = snap.docs;
          emit();
        }, onError: controller.addError),
      );
    }

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  bool _isPlaceholder(String v) {
    final lower = v.toLowerCase();
    return lower == 'не указано' || lower == 'не указан' || lower == 'n/a';
  }

  String _cleanVal(String v) => _isPlaceholder(v) ? '' : v;

  bool _isEmployerOwner(Map<String, dynamic> m, String uid) {
    if (uid.isEmpty) return false;
    return _s(m['employerOwnerId']) == uid ||
        _s(m['vacancyOwnerId']) == uid ||
        _s(m['employerId']) == uid ||
        _s(m['employerUid']) == uid ||
        _s(m['vacancyOwnerKey']) == uid;
  }

  String _vacancyOwnerId(Map<String, dynamic> m) {
    return _s(
      m['ownerId'],
      fallback: _s(
        m['ownerUid'],
        fallback: _s(
          m['ownerKey'],
          fallback: _s(m['vacancyOwnerId'], fallback: _s(m['employerOwnerId'])),
        ),
      ),
    );
  }

  String _cvOwnerId(Map<String, dynamic> m) {
    return _s(
      m['ownerId'],
      fallback: _s(
        m['ownerUid'],
        fallback: _s(
          m['candidateOwnerId'],
          fallback: _s(m['candidateId'], fallback: _s(m['candidateUid'])),
        ),
      ),
    );
  }

  bool _isValidApplyDoc(Map<String, dynamic> m) {
    return WorkaEntityValidity.isValidResponse(m);
  }

  String _applyDedupeKey(Map<String, dynamic> m) {
    final jobId = _s(m['jobId'], fallback: _s(m['vacancyId']));
    final cvId = _s(m['candidateCvId'], fallback: _s(m['cvId']));
    final candidateOwnerId = _applyCandidateOwnerId(m);
    return 'apply|$jobId|$candidateOwnerId|$cvId';
  }

  Future<Map<String, dynamic>> _loadJob(String jobId) {
    final id = jobId.trim();
    if (id.isEmpty) return Future.value(const <String, dynamic>{});
    return _jobCache.putIfAbsent(id, () async {
      final candidates = <String>[
        FirestorePaths.jobsCol(testMode: widget.testMode),
      ];
      if (!candidates.contains(FirestorePaths.jobs)) {
        candidates.add(FirestorePaths.jobs);
      }
      if (!candidates.contains(FirestorePaths.vacancies)) {
        candidates.add(FirestorePaths.vacancies);
      }
      for (final collection in candidates) {
        final snap = await FirebaseFirestore.instance
            .collection(collection)
            .doc(id)
            .get();
        if (!snap.exists) continue;
        final data = snap.data() ?? const <String, dynamic>{};
        if (data['isDeleted'] == true) {
          return const <String, dynamic>{'__missing': true};
        }
        return data;
      }
      return const <String, dynamic>{'__missing': true};
    });
  }

  Future<Map<String, dynamic>> _loadCv(String cvId) {
    final id = cvId.trim();
    if (id.isEmpty) {
      return Future.value(const <String, dynamic>{'__missing': true});
    }
    return _cvCache.putIfAbsent(id, () async {
      final candidates = <String>[
        FirestorePaths.cvsCol(testMode: widget.testMode),
      ];
      if (!candidates.contains(FirestorePaths.cvs)) {
        candidates.add(FirestorePaths.cvs);
      }
      for (final collection in candidates) {
        final snap = await FirebaseFirestore.instance
            .collection(collection)
            .doc(id)
            .get();
        if (!snap.exists) continue;
        final data = snap.data() ?? const <String, dynamic>{};
        if (data['isDeleted'] == true) {
          return const <String, dynamic>{'__missing': true};
        }
        return data;
      }
      return const <String, dynamic>{'__missing': true};
    });
  }

  Widget? _statusIndicator(String status, {required bool isEmployerView}) {
    final presentation = InteractionCardStatusResolver.presentation(
      status,
      context: isEmployerView
          ? InteractionStatusContext.employerApplications
          : InteractionStatusContext.workerApplications,
    );
    return StatusPillBadge(
      label: presentation.label,
      backgroundColor: presentation.backgroundColor,
    );
  }

  String? _workerApplyStatusFooter(String status) {
    final normalized = InteractionStatus.normalize(status);
    if (normalized == InteractionStatus.accepted) {
      return 'Работодатель принял вашу кандидатуру';
    }
    if (normalized == InteractionStatus.rejected) {
      return 'Работодатель отклонил вашу кандидатуру';
    }
    if (normalized == InteractionStatus.viewed ||
        normalized == InteractionStatus.postponed) {
      return 'Работодатель просмотрел ваш отклик';
    }
    return null;
  }

  void _openApplyResponse(
    DocumentReference<Map<String, dynamic>> responseRef,
    Map<String, dynamic> response,
  ) {
    final cvId = _s(response['candidateCvId'], fallback: _s(response['cvId']));
    InteractionMessageScreen.showResponseLetterSheet(
      context,
      messageText: '',
      responseRef: responseRef,
      currentStatus: _normalizedStatus(response),
      isEmployerView: true,
      onOpenCv: cvId.isEmpty
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CvViewScreen(
                    cvId: cvId,
                    testMode: widget.testMode,
                    forceReadOnly: true,
                  ),
                ),
              );
            },
      openAttachmentText: 'Открыть резюме',
    );
  }

  Widget _buildAppliesList(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docsIn,
    required bool isEmployerView,
  }) {
    return FutureBuilder<List<_ResolvedApplyEntry>>(
      future: _resolveValidApplyEntries(
        docsIn,
        isEmployerView: isEmployerView,
        requiredJobId: widget.jobId.trim(),
      ),
      builder: (context, resolvedSnap) {
        if (!resolvedSnap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final resolved = resolvedSnap.data ?? const <_ResolvedApplyEntry>[];
        if (resolved.isEmpty) {
          return Center(
            child: Text(
              isEmployerView ? 'Пока нет откликов' : 'Пока нет откликов',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: WorkaColors.textGreyDark,
              ),
            ),
          );
        }
        if (isEmployerView && widget.jobId.trim().isEmpty) {
          return _buildEmployerGroupedByVacancy(context, resolved);
        }
        return _buildResolvedApplyItems(
          context,
          entries: resolved,
          isEmployerView: isEmployerView,
        );
      },
    );
  }

  Future<List<_ResolvedApplyEntry>> _resolveValidApplyEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docsIn, {
    required bool isEmployerView,
    required String requiredJobId,
  }) async {
    final expectedOwner = isEmployerView
        ? widget.employerUid.trim()
        : (widget.candidateUid ?? '').trim();
    final resolvedOwner = expectedOwner.isNotEmpty
        ? expectedOwner
        : (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final seen = <String>{};
    final docs = docsIn.where((d) {
      final m = d.data();
      final docJobId = _s(m['jobId'], fallback: _s(m['vacancyId']));
      if (requiredJobId.isNotEmpty && docJobId != requiredJobId) {
        return false;
      }
      if (!_isValidApplyDoc(m)) return false;
      if (isEmployerView) {
        if (!_isEmployerOwner(m, resolvedOwner)) return false;
      } else {
        final itemOwner = _applyCandidateOwnerId(m);
        if (itemOwner.isEmpty || itemOwner != resolvedOwner) return false;
      }
      // Profile type filter — skip only when doc has explicit non-matching value.
      // Null/empty in doc = legacy record, pass through for backwards compat.
      if (widget.profileType.isNotEmpty) {
        final profileField = isEmployerView
            ? (m['vacancyOwnerType'] ?? '').toString().trim()
            : (m['applicantProfileType'] ?? '').toString().trim();
        if (profileField.isNotEmpty && profileField != widget.profileType) {
          return false;
        }
      }
      final key = _applyDedupeKey(m);
      if (!seen.add(key)) return false;
      return true;
    }).toList();
    final resolved = <_ResolvedApplyEntry>[];
    for (final responseDoc in docs) {
      final m = responseDoc.data();
      final jobId = _s(m['jobId'], fallback: _s(m['vacancyId']));
      final cvId = _s(m['candidateCvId'], fallback: _s(m['cvId']));
      if (jobId.isEmpty || cvId.isEmpty) continue;
      final loaded = await Future.wait<Map<String, dynamic>>([
        _loadJob(jobId),
        _loadCv(cvId),
      ]);
      final job = loaded.isNotEmpty ? loaded[0] : const <String, dynamic>{};
      final cv = loaded.length > 1 ? loaded[1] : const <String, dynamic>{};
      if (job['__missing'] == true || cv['__missing'] == true) continue;
      if (isEmployerView) {
        if (_vacancyOwnerId(job) != resolvedOwner) continue;
      } else {
        if (_cvOwnerId(cv) != resolvedOwner) continue;
      }
      resolved.add(
        _ResolvedApplyEntry(
          responseDoc: responseDoc,
          response: m,
          job: job,
          cv: cv,
        ),
      );
    }
    resolved.sort(
      (a, b) => _updatedAt(b.response).compareTo(_updatedAt(a.response)),
    );
    return resolved;
  }

  Widget _buildEmployerGroupedByVacancy(
    BuildContext context,
    List<_ResolvedApplyEntry> entries,
  ) {
    final groupsMap = <String, List<_ResolvedApplyEntry>>{};
    for (final entry in entries) {
      final jobId = _s(
        entry.response['jobId'],
        fallback: _s(entry.response['vacancyId']),
      );
      if (jobId.isEmpty) continue;
      groupsMap.putIfAbsent(jobId, () => <_ResolvedApplyEntry>[]).add(entry);
    }
    final groups = groupsMap.entries.map((e) {
      final sorted = [...e.value]
        ..sort(
          (a, b) => _updatedAt(b.response).compareTo(_updatedAt(a.response)),
        );
      return _VacancyApplyGroup(
        jobId: e.key,
        entries: sorted,
        latestAt: _updatedAt(sorted.first.response),
      );
    }).toList()..sort((a, b) => b.latestAt.compareTo(a.latestAt));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final group = groups[i];
        final job = group.entries.first.job;
        final title = _s(job['title'], fallback: 'Вакансия');
        final country = _s(job['country'], fallback: _s(job['countryName']));
        final flag = CountryDisplayFormatter.countryFlagOnly(
          country,
          euAsToken: false,
        );
        final vacancyNumber = _s(
          job['vacancyNumber'],
          fallback: _s(job['jobNumber']),
        );
        final hasNumber = vacancyNumber.isNotEmpty;
        final titleWithFlag = '$title ${flag.trim()}'.trim();

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ApplicationsListScreen(
                  testMode: widget.testMode,
                  jobId: group.jobId,
                  employerUid: widget.employerUid,
                  candidateUid: widget.candidateUid,
                ),
              ),
            );
          },
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: WorkaColors.fieldBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.2,
                    ),
                    children: [
                      if (hasNumber)
                        TextSpan(
                          text: vacancyNumber,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      if (hasNumber)
                        const TextSpan(
                          text: ' • ',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      TextSpan(
                        text: titleWithFlag,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: const [
                          Positioned(
                            top: 4,
                            child: Icon(
                              Icons.mail_outline_rounded,
                              size: 16,
                              color: WorkaColors.textGrey,
                            ),
                          ),
                          Positioned(
                            top: -1,
                            child: Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 12,
                              color: Color(0xFFE53935),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${group.entries.length} кандидатов',
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResolvedApplyItems(
    BuildContext context, {
    required List<_ResolvedApplyEntry> entries,
    required bool isEmployerView,
  }) {
    final visibleEntries = _applyStatusFilter(entries);
    final vacancyTitle = entries.isEmpty
        ? ''
        : _s(entries.first.job['title'], fallback: 'Вакансия');
    final headerBlock = (isEmployerView && widget.jobId.trim().isNotEmpty)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vacancyTitle,
                  style: const TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statusChip('all', 'Все (${entries.length})'),
                    _statusChip('new', 'Новые'),
                    _statusChip(InteractionStatus.viewed, 'Просмотрено'),
                    _statusChip(InteractionStatus.accepted, 'Принято'),
                    _statusChip(InteractionStatus.rejected, 'Отклонено'),
                  ],
                ),
              ],
            ),
          )
        : const SizedBox.shrink();
    if (visibleEntries.isEmpty) {
      return Column(
        children: [
          headerBlock,
          const Expanded(
            child: Center(
              child: Text(
                'Пока нет кандидатов',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: WorkaColors.textGreyDark,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        headerBlock,
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: visibleEntries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (_, i) {
              final entry = visibleEntries[i];
              final m = entry.response;
              final cv = entry.cv;
              final job = entry.job;
              final status = _normalizedStatus(m);
              if (!isEmployerView) {
                final salaryFrom = (job['salaryFrom'] is num)
                    ? (job['salaryFrom'] as num).toDouble()
                    : ((job['salaryAmount'] is num)
                          ? (job['salaryAmount'] as num).toDouble()
                          : null);
                final salaryTo = (job['salaryTo'] is num)
                    ? (job['salaryTo'] as num).toDouble()
                    : null;
                final jobId = _s(m['jobId'], fallback: _s(m['vacancyId']));
                final noLanguageRequired =
                    job['noLanguageRequired'] == true ||
                    _s(job['language']).toLowerCase() == 'без языка';
                final noExperienceRequired =
                    _s(job['experience']).toLowerCase().contains('без') &&
                        _s(job['experience']).toLowerCase().contains('опыт') ||
                    _s(job['experienceRequired']).toLowerCase() ==
                        'no_experience';
                return VacancyListCard(
                  key: ValueKey(entry.responseDoc.id),
                  mode: WorkaJobCardMode.readonlyStatus,
                  title: _s(job['title'], fallback: 'Вакансия'),
                  city: _s(job['city']),
                  country: _s(job['country']),
                  salaryFrom: salaryFrom,
                  salaryTo: salaryTo,
                  salaryType: _s(
                    job['salaryType'],
                    fallback: _s(job['salaryPeriod'], fallback: 'month'),
                  ),
                  salaryTextFallback: _s(
                    job['salaryText'],
                    fallback: _s(job['salary'], fallback: 'По договорённости'),
                  ),
                  employmentLabel: _s(
                    job['workSchedule'],
                    fallback: _s(
                      job['workScheduleOption'],
                      fallback: _s(
                        job['employmentType'],
                        fallback: _s(job['type'], fallback: 'Полная занятость'),
                      ),
                    ),
                  ),
                  housingProvided: job['housingProvided'] == true,
                  transportProvided: job['transportProvided'] == true,
                  forTeenagers:
                      job['forTeenagers'] == true ||
                      job['teenFriendly'] == true,
                  forDisabled:
                      job['forDisabled'] == true ||
                      job['disabledFriendly'] == true,
                  isUrgent:
                      (job['isUrgent'] == true) &&
                      (job['paidUrgent'] == true ||
                          job['urgentActiveUntil'] != null),
                  jobId: jobId,
                  ownerUid: OwnershipResolver.vacancyOwnerIdFromMap(job),
                  ownerEmail: _s(
                    job['ownerEmail'],
                    fallback: _s(
                      job['email'],
                      fallback: _s(job['contactEmail']),
                    ),
                  ),
                  showApply: false,
                  noLanguageRequired: noLanguageRequired,
                  noExperienceRequired: noExperienceRequired,
                  topRightReservedWidth: 48,
                  topRight: _statusIndicator(status, isEmployerView: false),
                  onTap: jobId.isEmpty
                      ? null
                      : () {
                          VacancyDetailsSheet.open(
                            context,
                            jobId: jobId,
                            asWorker: true,
                            testMode: widget.testMode,
                            statusFooterText: _workerApplyStatusFooter(status),
                          );
                        },
                );
              }
              final contacts = (cv['contacts'] is Map)
                  ? Map<String, dynamic>.from(cv['contacts'] as Map)
                  : const <String, dynamic>{};
              final desired = (cv['desired'] is Map)
                  ? Map<String, dynamic>.from(cv['desired'] as Map)
                  : const <String, dynamic>{};
              final countries = (desired['countries'] is List)
                  ? (desired['countries'] as List)
                        .map((e) => e.toString().trim())
                        .where((e) => e.isNotEmpty)
                        .toList()
                  : <String>[];
              final city = _s(
                desired['citiesText'],
                fallback: _s(cv['city'], fallback: _s(contacts['city'])),
              );
              final subtitle = [
                city,
                if (countries.isNotEmpty) countries.first,
              ].where((e) => e.isNotEmpty).join(', ');
              final name = [
                _cleanVal(_s(contacts['name'])),
                _cleanVal(
                  '${_s(contacts['firstName'])} ${_s(contacts['lastName'])}'
                      .trim(),
                ),
              ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
              final profession = [
                _cleanVal(_s(desired['position'])),
                _cleanVal(_s(cv['title'])),
                _cleanVal(_s(desired['categoryGroup'])),
              ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
              final category = _s(
                desired['categoryGroup'],
                fallback: _s(desired['category']),
              );
              final language = (cv['languages'] is List)
                  ? (cv['languages'] as List)
                        .whereType<Map>()
                        .map(
                          (e) => (e['language'] ?? e['name'] ?? '').toString(),
                        )
                        .where((e) => e.trim().isNotEmpty)
                        .take(2)
                        .join(' • ')
                  : '';
              final experience = _s(
                desired['experience'],
                fallback: _s(cv['experienceLabel']),
              );
              final ageText = CandidateAge.fromMap(cv);
              return _ApplyListTile(
                key: ValueKey(entry.responseDoc.id),
                name: name.isEmpty ? 'Кандидат' : name,
                ageText: ageText,
                title: profession.isEmpty ? 'Кандидат' : profession,
                subtitle: subtitle,
                category: category,
                language: language,
                experience: experience,
                trailing: _statusIndicator(status, isEmployerView: true),
                modeOverride: CandidateCvCardMode.incomingApplicationStatus,
                candidateData: cv,
                citizenshipCountry: _s(
                  cv['citizenshipCountry'],
                  fallback: _s(cv['citizenshipName']),
                ),
                birthDate: cv['birthDate'],
                onTap: () => _openApplyResponse(entry.responseDoc.reference, m),
              );
            },
          ),
        ),
      ],
    );
  }

  List<_ResolvedApplyEntry> _applyStatusFilter(
    List<_ResolvedApplyEntry> entries,
  ) {
    if (_statusFilter == 'all') return entries;
    if (_statusFilter == 'new') {
      return entries
          .where((e) => InteractionStatus.isFresh(e.response['status']))
          .toList();
    }
    return entries
        .where(
          (e) =>
              InteractionStatus.normalize(e.response['status']) ==
              _statusFilter,
        )
        .toList();
  }

  Widget _statusChip(String key, String label) {
    final selected = _statusFilter == key;
    return InkWell(
      onTap: () => setState(() => _statusFilter = key),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? WorkaColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? WorkaColors.blue : WorkaColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : WorkaColors.textGreyDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  bool _isIndexError(Object? error) {
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return true;
    }
    final msg = (error ?? '').toString().toLowerCase();
    return msg.contains('requires an index');
  }

  Widget _errorState(String message, {bool showDebugIndexBanner = false}) {
    return FirestoreQueryErrorState(
      message: message,
      isIndexError: showDebugIndexBanner,
      onRetry: () => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (resolvedUid.isEmpty) {
      return const AuthEntryScreen();
    }
    final isEmployerView =
        widget.employerUid.trim().isNotEmpty &&
        (widget.candidateUid ?? '').trim().isEmpty;
    final uidRaw = isEmployerView
        ? widget.employerUid.trim()
        : (widget.candidateUid ?? '').trim();
    final uid = uidRaw.isNotEmpty ? uidRaw : resolvedUid;

    if (uid.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            'Требуется авторизация',
            style: TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    final merged = _mergedAppliesStream(
      uid: uid,
      isEmployerView: isEmployerView,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: isEmployerView
                ? (widget.jobId.trim().isNotEmpty
                      ? 'Кандидаты на вакансию'
                      : 'Кандидаты')
                : 'Кандидаты',
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
              child:
                  StreamBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>
                  >(
                    stream: merged,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        final msg = snap.error.toString();
                        if (_isIndexError(snap.error)) {
                          return _errorState(msg, showDebugIndexBanner: true);
                        }
                        return _errorState(msg);
                      }
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      return _buildAppliesList(
                        context,
                        docsIn: snap.data!,
                        isEmployerView: isEmployerView,
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

class _ResolvedApplyEntry {
  const _ResolvedApplyEntry({
    required this.responseDoc,
    required this.response,
    required this.job,
    required this.cv,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> responseDoc;
  final Map<String, dynamic> response;
  final Map<String, dynamic> job;
  final Map<String, dynamic> cv;
}

class _VacancyApplyGroup {
  const _VacancyApplyGroup({
    required this.jobId,
    required this.entries,
    required this.latestAt,
  });

  final String jobId;
  final List<_ResolvedApplyEntry> entries;
  final DateTime latestAt;
}

class _ApplyListTile extends StatelessWidget {
  const _ApplyListTile({
    super.key,
    required this.name,
    this.ageText = '',
    required this.title,
    required this.subtitle,
    required this.category,
    required this.language,
    required this.experience,
    this.trailing,
    this.modeOverride,
    this.candidateData,
    this.citizenshipCountry = '',
    this.birthDate,
    required this.onTap,
  });

  final String name;
  final String ageText;
  final String title;
  final String subtitle;
  final String category;
  final String language;
  final String experience;
  final Widget? trailing;
  final CandidateCvCardMode? modeOverride;
  final Map<String, dynamic>? candidateData;
  final String citizenshipCountry;
  final dynamic birthDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CandidateListCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      name: name,
      ageText: ageText,
      profession: title,
      location: subtitle,
      category: category,
      language: language,
      experience: experience,
      candidateData: candidateData,
      citizenshipCountry: citizenshipCountry,
      birthDate: birthDate,
      statusBadge: trailing,
      modeOverride: modeOverride,
    );
  }
}
