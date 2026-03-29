import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:worka/screens/employer/create_job_screen.dart';
import 'package:worka/screens/employer_type_screen.dart';
import 'package:worka/services/app_mode.dart' as app_mode;
import 'package:worka/repositories/notifications_repository.dart';
import 'package:worka/repositories/response_repository.dart';
import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/theme/worka_colors.dart';

class OfferJobPickerSheet extends StatefulWidget {
  final String candidateUid;
  final String candidateCvId;
  final bool testMode;
  final Map<String, dynamic>? candidateData;
  final VoidCallback? onOfferSent;

  const OfferJobPickerSheet({
    super.key,
    required this.candidateUid,
    this.candidateCvId = '',
    this.testMode = true,
    this.candidateData,
    this.onOfferSent,
  });

  static Future<bool?> open(
    BuildContext context, {
    required String candidateUid,
    String candidateCvId = '',
    bool testMode = true,
    Map<String, dynamic>? candidateData,
    VoidCallback? onOfferSent,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: OfferJobPickerSheet(
          candidateUid: candidateUid,
          candidateCvId: candidateCvId,
          testMode: testMode,
          candidateData: candidateData,
          onOfferSent: onOfferSent,
        ),
      ),
    );
  }

  @override
  State<OfferJobPickerSheet> createState() => _OfferJobPickerSheetState();
}

class _OfferJobPickerSheetState extends State<OfferJobPickerSheet> {
  final _db = FirebaseFirestore.instance;
  String? _selectedJobId;
  String? _selectedJobOwnerId;
  String? _pendingAutoSelectJobId;
  bool _sending = false;

  void _toggleSelectedJob(String jobId, {required String ownerId}) {
    setState(() {
      if (_selectedJobId == jobId) {
        _selectedJobId = null;
        _selectedJobOwnerId = null;
      } else {
        _selectedJobId = jobId;
        _selectedJobOwnerId = ownerId;
      }
    });
  }

  bool _containsCopyToken(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('копия') || normalized.contains('copy');
  }

  bool _isSelectableVacancy(Map<String, dynamic> m) {
    if ((m['isDeleted'] ?? false) == true) return false;
    if ((m['isDraft'] ?? false) == true || (m['draft'] ?? false) == true) {
      return false;
    }
    if ((m['isComplete'] is bool) && m['isComplete'] == false) return false;
    if ((m['incomplete'] ?? false) == true) return false;
    if ((m['publishedInMarketplace'] is bool) &&
        m['publishedInMarketplace'] == false) {
      return false;
    }
    if ((m['published'] is bool) && m['published'] == false) return false;
    if ((m['isPublished'] is bool) && m['isPublished'] == false) return false;
    final status = (m['status'] ?? '').toString().trim().toLowerCase();
    if (status == 'draft' ||
        status == 'deleted' ||
        status == 'archived' ||
        status == 'unfinished' ||
        status == 'incomplete' ||
        status == 'unpublished') {
      return false;
    }
    final title = _s(m['title']);
    if (_containsCopyToken(title)) return false;
    return title.isNotEmpty;
  }

  String get _employerUid {
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final uid = (authUid?.isNotEmpty == true)
        ? authUid!
        : (AuthGuard.effectiveUidOrNull() ?? '').trim();
    return uid;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _jobsStream() {
    final activeOwnerType =
        app_mode.AppMode.currentMode == app_mode.AccountMode.business
        ? 'business'
        : 'personal';
    return _db.collection(FirestorePaths.vacancies).snapshots().map((source) {
      final docs = [...source.docs];
      docs.retainWhere((d) {
        final m = d.data();
        final isOwner = _vacancyOwnerId(m) == _employerUid;
        if (!isOwner) return false;
        // Filter by active account type (personal / business).
        final vOwnerType = (m['ownerType'] ?? 'personal').toString().trim();
        if (vOwnerType != activeOwnerType) return false;
        return _isSelectableVacancy(m);
      });
      DateTime parseDate(dynamic v) =>
          v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      docs.sort((a, b) {
        final au = parseDate(a.data()['updatedAt']);
        final bu = parseDate(b.data()['updatedAt']);
        if (au != bu) return bu.compareTo(au);
        final ac = parseDate(a.data()['createdAt']);
        final bc = parseDate(b.data()['createdAt']);
        return bc.compareTo(ac);
      });
      debugPrint(
        'OfferJobPickerSheet jobs stream testMode=${widget.testMode} uid=$_employerUid: ${docs.length}',
      );
      return docs;
    });
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _vacancyOwnerId(Map<String, dynamic> data) {
    return _s(
      data['ownerId'],
      fallback: _s(data['ownerUid'], fallback: _s(data['ownerKey'])),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: WorkaColors.textDark),
    );
  }

  Future<void> _createJob() async {
    final hasEmployerRole = await _ensureEmployerRoleOrOpenOnboarding();
    if (!hasEmployerRole) return;
    if (!mounted) return;
    final result = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CreateJobScreen(testMode: widget.testMode),
      ),
    );
    if (!mounted) return;
    final createdJobId = (result is String) ? result.trim() : '';
    setState(() {
      // Force picker rebuild after returning so stream/list refreshes immediately.
      _pendingAutoSelectJobId = createdJobId.isNotEmpty ? createdJobId : null;
    });
  }

  Future<bool> _ensureEmployerRoleOrOpenOnboarding() async {
    final uid = _employerUid;
    if (uid.isEmpty) {
      _toast('Нужен вход');
      return false;
    }
    try {
      final userSnap = await _db.collection('users').doc(uid).get();
      final m = userSnap.data() ?? const <String, dynamic>{};
      final rawRoles = m['roles'];
      final roles = <String>{};
      if (rawRoles is Iterable) {
        for (final r in rawRoles) {
          final v = (r ?? '').toString().trim().toLowerCase();
          if (v.isNotEmpty) roles.add(v);
        }
      }
      final hasEmployer =
          roles.contains('employer_private') ||
          roles.contains('employer_company') ||
          roles.contains('employer');
      if (hasEmployer) return true;

      _toast('Сначала заполните профиль работодателя');
      if (!mounted) return false;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => EmployerTypeScreen(testMode: widget.testMode),
        ),
      );
      return false;
    } catch (e) {
      debugPrint('OfferJobPickerSheet employer role check failed: $e');
      _toast('Не удалось проверить профиль работодателя');
      return false;
    }
  }

  Future<void> _sendOffer() async {
    if (_sending || _selectedJobId == null) return;
    if (!AuthGuard.ensureSignedIn(context)) return;
    final hasEmployerRole = await _ensureEmployerRoleOrOpenOnboarding();
    if (!hasEmployerRole) return;
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final employerUid = (authUid?.isNotEmpty == true)
        ? authUid!
        : (AuthGuard.effectiveUidOrNull() ?? '').trim();
    if (employerUid.isEmpty) {
      _toast('Нужен вход');
      return;
    }
    // Block self-offer: employer cannot offer a job to their own CV.
    if (widget.candidateUid.trim() == employerUid) {
      _toast('Нельзя отправить предложение самому себе');
      return;
    }

    setState(() => _sending = true);
    try {
      final candidateUid = widget.candidateUid.trim();
      final jobId = _selectedJobId!;
      final candidate = widget.candidateData ?? const <String, dynamic>{};
      final cvId = _s(widget.candidateCvId, fallback: _s(candidate['cvId']));
      final selectedJobOwnerId = (_selectedJobOwnerId ?? '').trim();
      if (candidateUid.isEmpty || cvId.isEmpty || selectedJobOwnerId.isEmpty) {
        _toast('Выберите кандидата и CV');
        return;
      }
      if (selectedJobOwnerId != employerUid) {
        _toast('Можно отправлять предложение только по своим вакансиям');
        return;
      }
      final exists = await ResponseRepository(_db).hasOfferedOnce(
        jobId: jobId,
        candidateOwnerId: candidateUid,
        candidateCvId: cvId,
        employerOwnerId: employerUid,
      );
      if (exists) {
        _toast('Предложение уже отправлено');
        return;
      }
      final offerId = 'offer_${employerUid}_${jobId}_$candidateUid';

      // Load vacancy and employer profile snapshots for letter display resilience.
      final jobDoc = await _db
          .collection(FirestorePaths.vacancies)
          .doc(jobId)
          .get();
      final jobData = jobDoc.data() ?? {};
      if (!jobDoc.exists || !_isSelectableVacancy(jobData)) {
        if (_containsCopyToken(_s(jobData['title']))) {
          _toast('Исправьте название вакансии');
        } else {
          _toast(
            'Для предложения доступна только опубликованная вакансия без слова «копия»',
          );
        }
        return;
      }
      if (_vacancyOwnerId(jobData) != employerUid) {
        _toast('Можно отправлять предложение только по своим вакансиям');
        return;
      }
      Map<String, dynamic> cvData = {};
      if (cvId.isNotEmpty) {
        final cvDoc = await _db.collection(FirestorePaths.cvs).doc(cvId).get();
        cvData = cvDoc.data() ?? {};
      }
      final employerDoc = await _db.collection('users').doc(employerUid).get();
      final employerProfile = employerDoc.data() ?? {};

      final activeOwnerType =
          app_mode.AppMode.currentMode == app_mode.AccountMode.business
          ? 'business'
          : 'personal';

      await ResponseRepository(_db).createOffer(
        candidateOwnerId: candidateUid,
        candidateCvId: cvId,
        employerOwnerId: employerUid,
        jobId: jobId,
        jobOwnerId: selectedJobOwnerId,
        vacancyOwnerType: _s(jobData['ownerType']).isEmpty
            ? 'personal'
            : _s(jobData['ownerType']),
        employerType: activeOwnerType,
        cvTitleSnapshot: _s(cvData['title']).isEmpty
            ? _s(cvData['profession'])
            : _s(cvData['title']),
        cvLocationSnapshot: _s(cvData['location']).isEmpty
            ? _s(cvData['country'])
            : _s(cvData['location']),
        cvCategorySnapshot: _s(cvData['category']),
        cvSkillsSnapshot: (cvData['skills'] is List)
            ? (cvData['skills'] as List).map((e) => e.toString()).toList()
            : [],
        candidateNameSnapshot:
            '${_s(candidate['firstName'])} ${_s(candidate['lastName'])}'.trim(),
        candidateEmailSnapshot: _s(candidate['email']),
        candidatePhoneSnapshot: _s(candidate['phone']),
        vacancySnapshot: Map<String, dynamic>.from(jobData),
        candidateSnapshot: Map<String, dynamic>.from(candidate),
        employerContactsSnapshot: Map<String, dynamic>.from(employerProfile),
        recipientProfileType: 'personal',
      );
      debugPrint(
        'OfferJobPickerSheet offer saved -> ${FirestorePaths.jobOffers}/$offerId',
      );
      if (candidateUid.isNotEmpty) {
        await NotificationsRepository(_db).createItem(
          toUserId: candidateUid,
          fromUserId: employerUid,
          type: 'offer_received',
          kind: 'offer',
          entityId: offerId,
          payload: {
            'vacancyId': jobId,
            'cvId': cvId,
            'shortText': 'Новое предложение работы',
          },
        );
      }

      widget.onOfferSent?.call();
      if (mounted) {
        _toast('Предложение отправлено');
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('OfferJobPickerSheet _sendOffer error: $e');
      _toast('Ошибка сохранения: $e');
      if (FirebaseDebugDiagnostics.isPermissionDenied(e) && mounted) {
        _toast(FirebaseDebugDiagnostics.permissionHintText());
      } else if (e.toString().contains('Failed to fetch')) {
        _toast('Сетевой доступ к API недоступен. Проверьте CORS и вход.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCandidateUid = widget.candidateUid.trim();
    final selectedCandidateCvId = _s(
      widget.candidateCvId,
      fallback: _s((widget.candidateData ?? const <String, dynamic>{})['cvId']),
    );
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final employerUid = (authUid?.isNotEmpty == true)
        ? authUid!
        : (AuthGuard.effectiveUidOrNull() ?? '').trim();
    final canSend =
        _selectedJobId != null &&
        (_selectedJobOwnerId ?? '').trim().isNotEmpty &&
        !_sending &&
        selectedCandidateUid.isNotEmpty &&
        selectedCandidateCvId.isNotEmpty &&
        employerUid.isNotEmpty;

    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(
                'Выбрать вакансию для данного кандидата',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: WorkaColors.textDark,
                ),
              ),
            ),
            Expanded(
              child:
                  StreamBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>
                  >(
                    stream: _jobsStream(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        debugPrint(
                          'OfferJobPickerSheet jobs stream error: ${snap.error}',
                        );
                        final permissionDenied =
                            FirebaseDebugDiagnostics.isPermissionDenied(
                              snap.error,
                            );
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Ошибка загрузки: ${snap.error}',
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

                      final docs = snap.data!;
                      final pendingId = (_pendingAutoSelectJobId ?? '').trim();
                      if (pendingId.isNotEmpty) {
                        QueryDocumentSnapshot<Map<String, dynamic>>? pendingDoc;
                        for (final doc in docs) {
                          if (doc.id == pendingId) {
                            pendingDoc = doc;
                            break;
                          }
                        }
                        if (pendingDoc != null) {
                          final matchedDoc = pendingDoc;
                          final pendingData = matchedDoc.data();
                          final pendingDocId = matchedDoc.id;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _selectedJobId = pendingDocId;
                              _selectedJobOwnerId = _s(
                                _vacancyOwnerId(pendingData),
                                fallback: _employerUid,
                              );
                              _pendingAutoSelectJobId = null;
                            });
                          });
                        }
                      }
                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Нет доступных вакансий для предложения',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: _sending ? null : _createJob,
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: WorkaColors.blue,
                                        width: 1.2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text(
                                      'Создать вакансию',
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final d = docs[i];
                          final m = d.data();
                          final selected = d.id == _selectedJobId;
                          final title = _s(m['title'], fallback: 'Вакансия');
                          final city = _s(m['city']);
                          final country = _s(m['country']);
                          final salary = _s(
                            m['salaryText'],
                            fallback: _s(
                              m['salary'],
                              fallback: 'Зарплата не указана',
                            ),
                          );
                          final location = [
                            city,
                            country,
                          ].where((e) => e.isNotEmpty).join(', ');

                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _toggleSelectedJob(
                              d.id,
                              ownerId: _s(
                                _vacancyOwnerId(m),
                                fallback: _employerUid,
                              ),
                            ),
                            child: Ink(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? WorkaColors.blue
                                      : WorkaColors.fieldBorder,
                                  width: selected ? 1.4 : 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            color: WorkaColors.textDark,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        if (location.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            location,
                                            style: const TextStyle(
                                              color: WorkaColors.textGreyDark,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          salary,
                                          style: const TextStyle(
                                            color: WorkaColors.textGreyDark,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Checkbox(
                                    value: selected,
                                    onChanged: (_) => _toggleSelectedJob(
                                      d.id,
                                      ownerId: _s(
                                        _vacancyOwnerId(m),
                                        fallback: _employerUid,
                                      ),
                                    ),
                                    activeColor: WorkaColors.blue,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton(
                        onPressed: _sending ? null : _createJob,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: WorkaColors.orange,
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Создать вакансию',
                          style: TextStyle(
                            color: WorkaColors.orange,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: canSend ? _sendOffer : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.orange,
                          disabledBackgroundColor: WorkaColors.fieldBorder,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Предложить',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
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
