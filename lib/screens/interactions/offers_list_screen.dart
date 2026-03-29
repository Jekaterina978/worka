import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../repositories/notifications_repository.dart';
import '../../services/entity_validity.dart';
import '../../services/firestore_paths.dart';
import '../../services/interaction_card_status.dart';
import '../../services/interaction_status.dart';
import '../../services/ownership_resolver.dart';
import '../../theme/worka_colors.dart';
import '../../widgets/cards/candidate_list_card.dart';
import '../../widgets/cards/candidate_cv_card.dart';
import '../../widgets/cards/vacancy_list_card.dart';
import '../../widgets/firestore_query_error_state.dart';
import '../../widgets/worka_header.dart';
import '../../widgets/status_pill_badge.dart';
import '../cv/cv_view_screen.dart';
import '../employer/search/widgets/vacancy_details_sheet.dart';
import '../../widgets/worka_job_card.dart';
import '../../services/candidate_age.dart';
import 'interaction_message_screen.dart';
import '../auth/auth_entry_screen.dart';

class OffersListScreen extends StatefulWidget {
  final bool testMode;
  final String workerUid;
  final String? employerUid;
  final String? cvId;

  /// Optional profile type filter ('personal' or 'business').
  /// When set, only offers matching this profile type are shown.
  /// Empty string = show all (backwards compatible).
  final String profileType;

  const OffersListScreen({
    super.key,
    required this.testMode,
    required this.workerUid,
    this.employerUid,
    this.cvId,
    this.profileType = '',
  });

  @override
  State<OffersListScreen> createState() => _OffersListScreenState();
}

class _OffersListScreenState extends State<OffersListScreen> {
  bool _markedRead = false;
  final Map<String, Future<Map<String, dynamic>>> _jobCache =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<Map<String, dynamic>>> _cvCache =
      <String, Future<Map<String, dynamic>>>{};

  Query<Map<String, dynamic>> buildResponsesQuery({
    required String type,
    required String field,
    required String uid,
  }) {
    return FirebaseFirestore.instance
        .collection(FirestorePaths.jobOffers)
        .where('type', isEqualTo: type)
        .where(field, isEqualTo: uid);
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _normalizedStatus(Map<String, dynamic> m) {
    // Always use the unified 'status' field as source of truth
    final raw = _s(m['status'], fallback: InteractionStatus.sent);
    return InteractionStatus.normalize(raw);
  }

  String _offerEmployerOwnerId(Map<String, dynamic> m) {
    return _s(
      m['employerOwnerId'],
      fallback: _s(
        m['vacancyOwnerId'],
        fallback: _s(
          m['employerId'],
          fallback: _s(m['employerUid'], fallback: _s(m['vacancyOwnerKey'])),
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
  _mergedOffersStream({required String uid, required bool isEmployerView}) {
    final primary = FirebaseFirestore.instance.collection(
      FirestorePaths.jobOffers,
    );
    final queries = <Query<Map<String, dynamic>>>[
      primary
          .where('type', isEqualTo: 'offer')
          .where(
            isEmployerView ? 'employerOwnerId' : 'candidateOwnerId',
            isEqualTo: uid,
          ),
      primary
          .where('type', isEqualTo: 'offer')
          .where(
            isEmployerView ? 'employerUid' : 'candidateUid',
            isEqualTo: uid,
          ),
      primary
          .where('type', isEqualTo: 'offer')
          .where(isEmployerView ? 'employerId' : 'candidateId', isEqualTo: uid),
      primary
          .where('type', isEqualTo: 'offer')
          .where(
            isEmployerView ? 'vacancyOwnerKey' : 'candidateOwnerKey',
            isEqualTo: uid,
          ),
    ];
    if (isEmployerView) {
      queries.add(
        primary
            .where('type', isEqualTo: 'offer')
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

  String? _employerOfferStatusFooter(String status) {
    final normalized = InteractionStatus.normalize(status);
    if (normalized == InteractionStatus.accepted) {
      return 'Кандидат принял вашу вакансию';
    }
    if (normalized == InteractionStatus.rejected) {
      return 'Кандидат отклонил вашу вакансию';
    }
    if (normalized == InteractionStatus.viewed ||
        normalized == InteractionStatus.postponed) {
      return 'Просмотрено';
    }
    return null;
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
    if (id.isEmpty) return Future.value(const <String, dynamic>{});
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
          ? InteractionStatusContext.employerOffers
          : InteractionStatusContext.workerOffers,
    );
    return StatusPillBadge(
      label: presentation.label,
      backgroundColor: presentation.backgroundColor,
    );
  }

  bool _isPlaceholder(String v) {
    final lower = v.toLowerCase();
    return lower == 'не указано' || lower == 'не указан' || lower == 'n/a';
  }

  String _cleanVal(String v) => _isPlaceholder(v) ? '' : v;

  bool _isValidOfferDoc(Map<String, dynamic> m) {
    return WorkaEntityValidity.isValidOffer(m);
  }

  bool _isEmployerOwner(Map<String, dynamic> m, String uid) {
    if (uid.isEmpty) return false;
    return _s(m['employerOwnerId']) == uid ||
        _s(m['vacancyOwnerId']) == uid ||
        _s(m['employerId']) == uid ||
        _s(m['employerUid']) == uid ||
        _s(m['vacancyOwnerKey']) == uid;
  }

  bool _isCandidateOwner(Map<String, dynamic> m, String uid) {
    if (uid.isEmpty) return false;
    return _s(m['candidateOwnerId']) == uid ||
        _s(m['candidateId']) == uid ||
        _s(m['candidateUid']) == uid ||
        _s(m['candidateOwnerKey']) == uid;
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

  String _offerDedupeKey(Map<String, dynamic> m) {
    final jobId = _s(m['jobId'], fallback: _s(m['vacancyId']));
    final cvId = _s(m['candidateCvId'], fallback: _s(m['cvId']));
    final employerOwnerId = _offerEmployerOwnerId(m);
    return 'offer|$jobId|$employerOwnerId|$cvId';
  }

  String _offerMessage({
    required Map<String, dynamic> response,
    required Map<String, dynamic> job,
  }) {
    String firstNonEmpty(Iterable<dynamic> values, {String fallback = ''}) {
      for (final value in values) {
        final normalized = _s(value);
        if (normalized.isNotEmpty) return normalized;
      }
      return fallback;
    }

    final text = _s(response['messageText']);
    if (text.isNotEmpty) return text;
    final title = firstNonEmpty([
      job['title'],
      (response['vacancySnapshot'] is Map)
          ? (response['vacancySnapshot'] as Map)['title']
          : null,
      response['jobTitle'],
    ], fallback: 'вакансию');
    final employerSnap = (response['employerContactsSnapshot'] is Map)
        ? Map<String, dynamic>.from(response['employerContactsSnapshot'] as Map)
        : const <String, dynamic>{};
    final businessSnap = (employerSnap['business'] is Map)
        ? Map<String, dynamic>.from(employerSnap['business'] as Map)
        : const <String, dynamic>{};
    final vacancySnap = (response['vacancySnapshot'] is Map)
        ? Map<String, dynamic>.from(response['vacancySnapshot'] as Map)
        : const <String, dynamic>{};
    final company = [
      _s(job['companyName']),
      _s(vacancySnap['companyName']),
      _s(businessSnap['companyName']),
      _s(businessSnap['company']),
      _s(employerSnap['companyName']),
    ].firstWhere((e) => e.isNotEmpty, orElse: () => 'Работодатель');
    final city = firstNonEmpty([
      job['city'],
      vacancySnap['locationCity'],
      response['city'],
    ]);
    final country = firstNonEmpty([
      job['country'],
      vacancySnap['locationCountry'],
      response['country'],
    ]);
    final salary = firstNonEmpty([
      job['salaryText'],
      job['salary'],
      vacancySnap['salary'],
      response['salary'],
    ], fallback: 'По договорённости');
    final location = [city, country].where((e) => e.isNotEmpty).join(', ');
    return 'Вам отправлено предложение работы.\n\n'
        'Вакансия: $title\n'
        'Компания: $company\n'
        'Локация: ${location.isEmpty ? '—' : location}\n'
        'Зарплата: $salary\n\n'
        'Откройте CV/письмо и примите решение.';
  }

  Future<void> _markNotificationsReadIfNeeded() async {
    if (_markedRead) return;
    final isEmployerView =
        widget.employerUid != null && widget.employerUid!.trim().isNotEmpty;
    final uidRaw = isEmployerView
        ? widget.employerUid!.trim()
        : widget.workerUid.trim();
    final resolvedUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final uid = uidRaw.isNotEmpty ? uidRaw : resolvedUid;
    if (uid.isEmpty) return;
    _markedRead = true;
    await NotificationsRepository(FirebaseFirestore.instance).markReadByType(
      uid,
      const ['offer_received', 'offer_sent', 'status_changed'],
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

  Widget _buildOffersList(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docsIn,
    required bool isEmployerView,
  }) {
    return FutureBuilder<List<_ResolvedOfferEntry>>(
      future: _resolveValidOfferEntries(docsIn, isEmployerView: isEmployerView),
      builder: (context, resolvedSnap) {
        if (!resolvedSnap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final docs = resolvedSnap.data ?? const <_ResolvedOfferEntry>[];
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Пока нет предложений',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: WorkaColors.textGreyDark,
              ),
            ),
          );
        }
        return _buildResolvedOffersList(
          context,
          docs: docs,
          isEmployerView: isEmployerView,
        );
      },
    );
  }

  Future<List<_ResolvedOfferEntry>> _resolveValidOfferEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docsIn, {
    required bool isEmployerView,
  }) async {
    final expectedUid = _s(
      widget.employerUid ?? widget.workerUid,
      fallback: (FirebaseAuth.instance.currentUser?.uid ?? '').trim(),
    );
    final seen = <String>{};
    final docs = docsIn.where((d) {
      final m = d.data();
      if (widget.cvId != null &&
          widget.cvId!.trim().isNotEmpty &&
          (m['candidateCvId'] ?? m['cvId'] ?? '').toString().trim() !=
              widget.cvId!.trim()) {
        return false;
      }
      if (!_isValidOfferDoc(m)) {
        debugPrint(
          'OffersListScreen skip invalid offer doc=${d.reference.path}',
        );
        return false;
      }
      final ownerMatches = isEmployerView
          ? _isEmployerOwner(m, expectedUid)
          : _isCandidateOwner(m, expectedUid);
      if (!ownerMatches) return false;
      // Profile type filter — skip only when doc has explicit non-matching value.
      // Null/empty in doc = legacy record, pass through for backwards compat.
      if (widget.profileType.isNotEmpty) {
        final profileField = isEmployerView
            ? (m['employerType'] ?? '').toString().trim()
            : (m['recipientProfileType'] ?? '').toString().trim();
        if (profileField.isNotEmpty && profileField != widget.profileType) {
          return false;
        }
      }
      final key = _offerDedupeKey(m);
      if (!seen.add(key)) return false;
      return true;
    }).toList();
    final out = <_ResolvedOfferEntry>[];
    for (final doc in docs) {
      final m = doc.data();
      final jobId = (m['jobId'] ?? m['vacancyId'] ?? '').toString().trim();
      final cvId = (m['candidateCvId'] ?? m['cvId'] ?? '').toString().trim();
      if (jobId.isEmpty || cvId.isEmpty) continue;
      final loaded = await Future.wait<Map<String, dynamic>>([
        _loadJob(jobId),
        _loadCv(cvId),
      ]);
      final job = loaded.isNotEmpty ? loaded[0] : const <String, dynamic>{};
      final cv = loaded.length > 1 ? loaded[1] : const <String, dynamic>{};
      if (job['__missing'] == true || cv['__missing'] == true) continue;
      if (isEmployerView) {
        if (_vacancyOwnerId(job) != expectedUid) continue;
      } else {
        if (_cvOwnerId(cv) != expectedUid) continue;
      }
      out.add(
        _ResolvedOfferEntry(responseDoc: doc, response: m, job: job, cv: cv),
      );
    }
    out.sort(
      (a, b) => _updatedAt(b.response).compareTo(_updatedAt(a.response)),
    );
    return out;
  }

  Widget _buildResolvedOffersList(
    BuildContext context, {
    required List<_ResolvedOfferEntry> docs,
    required bool isEmployerView,
  }) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (_, i) {
              final item = docs[i];
              final m = item.response;
              final status = _normalizedStatus(m);
              final jobId = (m['jobId'] ?? m['vacancyId'] ?? '')
                  .toString()
                  .trim();
              final cvId = (m['candidateCvId'] ?? m['cvId'] ?? '')
                  .toString()
                  .trim();
              if (!isEmployerView) {
                final job = item.job;
                Future<void> onOpen() async {
                  await InteractionMessageScreen.open(
                    context,
                    title: 'Предложение работы',
                    messageText: _offerMessage(response: m, job: job),
                    responseRef: item.responseDoc.reference,
                    currentStatus: status,
                    markViewedByApplicant: !isEmployerView,
                    markViewedByEmployer: isEmployerView,
                    senderStatusOnAccepted: 'Кандидат принял ваше предложение',
                    senderStatusOnRejected:
                        'Кандидат отклонил ваше предложение',
                    entityKind: 'offer',
                    onOpenAttachment: jobId.isEmpty
                        ? null
                        : () {
                            VacancyDetailsSheet.open(
                              context,
                              jobId: jobId,
                              asWorker: false,
                              testMode: widget.testMode,
                            );
                          },
                    openAttachmentText: jobId.isEmpty
                        ? null
                        : 'Открыть вакансию',
                  );
                }

                final salaryFrom = (job['salaryFrom'] is num)
                    ? (job['salaryFrom'] as num).toDouble()
                    : ((job['salaryAmount'] is num)
                          ? (job['salaryAmount'] as num).toDouble()
                          : null);
                final salaryTo = (job['salaryTo'] is num)
                    ? (job['salaryTo'] as num).toDouble()
                    : null;
                return VacancyListCard(
                  mode: WorkaJobCardMode.readonlyStatus,
                  title: _s(job['title']),
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
                  topRightReservedWidth: 48,
                  topRight: _statusIndicator(status, isEmployerView: false),
                  onTap: onOpen,
                );
              }
              final cv = item.cv;
              void onOpen() {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CvViewScreen(
                      cvId: cvId,
                      testMode: widget.testMode,
                      statusFooterText: _employerOfferStatusFooter(status),
                      forceReadOnly: true,
                    ),
                  ),
                );
              }

              final contacts = (cv['contacts'] is Map)
                  ? Map<String, dynamic>.from(cv['contacts'])
                  : const <String, dynamic>{};
              final desired = (cv['desired'] is Map)
                  ? Map<String, dynamic>.from(cv['desired'])
                  : const <String, dynamic>{};
              final name = [
                _cleanVal(_s(contacts['name'])),
                _cleanVal(
                  '${_s(contacts['firstName'])} ${_s(contacts['lastName'])}'
                      .trim(),
                ),
              ].firstWhere((e) => e.isNotEmpty, orElse: () => 'Кандидат');
              final profession = [
                _cleanVal(_s(desired['position'])),
                _cleanVal(_s(cv['title'])),
                _cleanVal(_s(desired['categoryGroup'])),
              ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
              final city = _s(desired['citiesText']).split(',').first.trim();
              final countries = (desired['countries'] is List)
                  ? (desired['countries'] as List)
                        .map((e) => e.toString().trim())
                        .where((e) => e.isNotEmpty)
                        .toList()
                  : <String>[];
              final location = [
                city,
                countries.isEmpty ? '' : countries.first,
              ].where((e) => e.isNotEmpty).join(', ');
              final languages = (cv['languages'] is List)
                  ? (cv['languages'] as List)
                        .whereType<Map>()
                        .map(
                          (e) => (e['language'] ?? e['name'] ?? '')
                              .toString()
                              .trim(),
                        )
                        .where((e) => e.isNotEmpty)
                        .take(2)
                        .join(' • ')
                  : '';
              final experience = _s(desired['experience']);
              final category = _s(
                desired['categoryGroup'],
                fallback: _s(desired['category']),
              );
              final ageText = CandidateAge.fromMap(cv);
              return CandidateListCard(
                margin: EdgeInsets.zero,
                onTap: onOpen,
                name: name,
                ageText: ageText,
                birthDate: cv['birthDate'] ?? m['birthDate'],
                citizenshipCountry: _s(
                  cv['citizenshipCountry'],
                  fallback: _s(
                    cv['citizenshipName'],
                    fallback: _s(cv['country']),
                  ),
                ),
                profession: profession,
                location: location,
                category: category,
                language: languages,
                languagesData: (cv['languages'] is List)
                    ? (cv['languages'] as List)
                          .whereType<Map>()
                          .map((e) => Map<String, dynamic>.from(e))
                          .toList()
                    : const <Map<String, dynamic>>[],
                experience: experience,
                hasTools: cv['hasTools'] == true,
                hasWorkwear: cv['hasWorkwear'] == true,
                hasComputerSkills: cv['hasComputerSkills'] == true,
                candidateData: cv,
                statusBadge: _statusIndicator(status, isEmployerView: true),
                modeOverride: CandidateCvCardMode.offerStatus,
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (resolvedUid.isEmpty) {
      return const AuthEntryScreen();
    }
    final isEmployerView =
        widget.employerUid != null && widget.employerUid!.trim().isNotEmpty;
    _markNotificationsReadIfNeeded();
    final uidRaw = (isEmployerView ? widget.employerUid! : widget.workerUid)
        .trim();
    final uid = uidRaw.isNotEmpty ? uidRaw : resolvedUid;
    final merged = _mergedOffersStream(
      uid: uid,
      isEmployerView: isEmployerView,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: isEmployerView ? 'Мои предложения' : 'Вам предлагают',
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
                          debugPrint(
                            '[FirestoreIndexError][offers_list_ordered] $msg',
                          );
                          return _errorState(msg, showDebugIndexBanner: true);
                        }
                        return _errorState(msg);
                      }
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      return _buildOffersList(
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

class _ResolvedOfferEntry {
  const _ResolvedOfferEntry({
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
