import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../repositories/response_repository.dart';
import '../vacancy_details_screen.dart';
import '../../services/auth_guard.dart';
import '../../services/entity_validity.dart';
import '../../services/firestore_paths.dart';
import '../../services/interaction_status.dart';
import '../../features/payments/contact_access_controller.dart';
import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';
import '../../widgets/worka_header.dart';

class ApplyResponseScreen extends StatefulWidget {
  const ApplyResponseScreen({
    super.key,
    required this.responseRef,
    this.onOpenCv,
  });

  final DocumentReference<Map<String, dynamic>> responseRef;
  final VoidCallback? onOpenCv;

  static Future<void> open(
    BuildContext context, {
    required DocumentReference<Map<String, dynamic>> responseRef,
    VoidCallback? onOpenCv,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ApplyResponseScreen(
          responseRef: responseRef,
          onOpenCv: onOpenCv,
        ),
      ),
    );
  }

  @override
  State<ApplyResponseScreen> createState() => _ApplyResponseScreenState();
}

class _ApplyResponseScreenState extends State<ApplyResponseScreen> {
  final _contactAccess = ContactAccessController.instance;
  final Set<String> _loadingUnlockedContactIds = <String>{};
  bool _statusUpdating = false;
  bool _openedAsSent = false;
  bool _openedAsSentResolved = false;
  bool _viewedRequested = false;
  late final String _viewerUid;

  final Map<String, Future<Map<String, dynamic>>> _jobsCache =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<Map<String, dynamic>>> _usersCache =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<Map<String, dynamic>>> _cvByIdCache =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<Map<String, dynamic>>> _cvByOwnerCache =
      <String, Future<Map<String, dynamic>>>{};

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _firstNonEmpty(Iterable<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final normalized = _s(value);
      if (normalized.isNotEmpty && !_isPlaceholderValue(normalized)) {
        return normalized;
      }
    }
    return fallback;
  }

  bool _isPlaceholderValue(String value) {
    final lower = value.toLowerCase();
    return lower == 'не указано' ||
        lower == 'не указан' ||
        lower == 'не указана' ||
        lower == 'not specified' ||
        lower == 'n/a' ||
        lower == '-';
  }

  bool _isActiveSourceDoc(Map<String, dynamic> data) {
    if (data.isEmpty) return false;
    return data['isDeleted'] != true && data['deleted'] != true;
  }

  String _candidateAccessId(
    Map<String, dynamic> response,
    Map<String, dynamic> cv,
  ) {
    return _firstNonEmpty([
      response['candidateCvId'],
      response['cvId'],
      response['candidateId'],
      cv['cvId'],
      cv['id'],
    ]);
  }

  bool _hasUnlockedCandidateAccess(
    Map<String, dynamic> response,
    Map<String, dynamic> cv,
  ) {
    final candidateId = _candidateAccessId(response, cv).trim();
    if (candidateId.isEmpty) return false;
    return _contactAccess.hasAccessToCandidateContact(candidateId);
  }

  void _warmUnlockedCandidateContact(String candidateId) {
    final id = candidateId.trim();
    if (id.isEmpty || _loadingUnlockedContactIds.contains(id)) return;
    _loadingUnlockedContactIds.add(id);
    _contactAccess
        .ensureLoadedContactForCandidate(id)
        .whenComplete(() {
          _loadingUnlockedContactIds.remove(id);
          if (!mounted) return;
          setState(() {});
        });
  }

  String _normalizeStatus(String status) => InteractionStatus.normalize(status);

  String? _sanitizeAvatarUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    const invalid = <String>{
      '',
      '-',
      'null',
      'undefined',
      'n/a',
      'placeholder',
    };
    final normalized = value.toLowerCase();
    if (invalid.contains(normalized)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final http = uri.scheme == 'http' || uri.scheme == 'https';
    if (!http || uri.host.trim().isEmpty) return null;
    return value;
  }

  Widget _candidateAvatar({
    required String initials,
    required String? avatarUrl,
    required String gender,
    double radius = 25,
  }) {
    final url = _sanitizeAvatarUrl(avatarUrl);
    final normalizedGender = gender.trim().toLowerCase();
    final bool isMale =
        normalizedGender == 'male' ||
        normalizedGender == 'мужской' ||
        normalizedGender == 'муж' ||
        normalizedGender == 'm';
    final bool isFemale =
        normalizedGender == 'female' ||
        normalizedGender == 'женский' ||
        normalizedGender == 'жен' ||
        normalizedGender == 'f';
    final String? genderAsset = isMale
        ? 'assets/avatars/male.png'
        : (isFemale ? 'assets/avatars/female.png' : null);
    final size = radius * 2;

    Widget initialsFallback() {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
            fontSize: (radius * 0.68).clamp(14.0, 19.0).toDouble(),
          ),
        ),
      );
    }

    Widget genderFallback() {
      if (genderAsset == null) return initialsFallback();
      return Image.asset(
        genderAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initialsFallback(),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF0FF),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: url != null
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => genderFallback(),
              )
            : genderFallback(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _viewerUid = AuthGuard.isDebugOpenAllEnabled
        ? (AuthGuard.effectiveUidOrNull() ?? '').trim()
        : (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    _bootstrapOpenState();
    _contactAccess.bootstrap(uid: _viewerUid).whenComplete(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<Map<String, dynamic>> _loadJob(String jobId) {
    final id = jobId.trim();
    if (id.isEmpty) return Future.value(const <String, dynamic>{});
    return _jobsCache.putIfAbsent(id, () async {
      final snap = await FirebaseFirestore.instance
          .collection(FirestorePaths.jobs)
          .doc(id)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      if (!_isActiveSourceDoc(data)) return const <String, dynamic>{};
      if (!WorkaEntityValidity.isValidPublicVacancy(data)) {
        return const <String, dynamic>{};
      }
      return data;
    });
  }

  Future<Map<String, dynamic>> _loadUser(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return Future.value(const <String, dynamic>{});
    return _usersCache.putIfAbsent(id, () async {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .get();
      return snap.data() ?? const <String, dynamic>{};
    });
  }

  DateTime _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<Map<String, dynamic>> _loadCvById(String cvId) {
    final id = cvId.trim();
    if (id.isEmpty) return Future.value(const <String, dynamic>{});
    return _cvByIdCache.putIfAbsent(id, () async {
      final snap = await FirebaseFirestore.instance
          .collection(FirestorePaths.cvs)
          .doc(id)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      if (!_isActiveSourceDoc(data)) return const <String, dynamic>{};
      if (!WorkaEntityValidity.isValidPublicCv(data)) {
        return const <String, dynamic>{};
      }
      return data;
    });
  }

  Future<Map<String, dynamic>> _loadLatestCvByOwner(String ownerId) {
    final id = ownerId.trim();
    if (id.isEmpty) return Future.value(const <String, dynamic>{});
    return _cvByOwnerCache.putIfAbsent(id, () async {
      final snap = await FirebaseFirestore.instance
          .collection(FirestorePaths.cvs)
          .where('ownerId', isEqualTo: id)
          .get();

      final docs = snap.docs.where((d) {
        final data = d.data();
        final deleted = data['deleted'] == true || data['isDeleted'] == true;
        return !deleted;
      }).toList();

      if (docs.isEmpty) return const <String, dynamic>{};

      docs.sort((a, b) {
        final da = a.data();
        final db = b.data();
        final aPrimary = da['isPrimary'] == true ? 1 : 0;
        final bPrimary = db['isPrimary'] == true ? 1 : 0;
        if (aPrimary != bPrimary) return bPrimary.compareTo(aPrimary);
        final au = _ts(da['updatedAt'] ?? da['createdAt']);
        final bu = _ts(db['updatedAt'] ?? db['createdAt']);
        return bu.compareTo(au);
      });

      final data = docs.first.data();
      if (!_isActiveSourceDoc(data)) return const <String, dynamic>{};
      if (!WorkaEntityValidity.isValidPublicCv(data)) {
        return const <String, dynamic>{};
      }
      return data;
    });
  }

  Future<Map<String, dynamic>> _loadCvForResponse(
    Map<String, dynamic> response,
  ) async {
    final explicitCvId = _s(
      response['cvId'],
      fallback: _s(response['candidateCvId']),
    );
    if (explicitCvId.isNotEmpty) {
      final cv = await _loadCvById(explicitCvId);
      if (cv.isNotEmpty) return cv;
    }

    final candidateOwnerId = _s(response['candidateOwnerId']);
    return _loadLatestCvByOwner(candidateOwnerId);
  }

  Future<void> _bootstrapOpenState() async {
    if (_openedAsSentResolved) return;
    final snap = await widget.responseRef.get();
    final response = snap.data() ?? const <String, dynamic>{};
    final status = _normalizeStatus(_s(response['status']));
    _openedAsSent = status == InteractionStatus.sent;
    _openedAsSentResolved = true;

    final employerOwnerId = _s(response['employerOwnerId']);
    final employerId = _s(response['employerId']);
    final isRecipient =
        _viewerUid.isNotEmpty &&
        (_viewerUid == employerOwnerId || _viewerUid == employerId);

    if (isRecipient && _openedAsSent && !_viewedRequested) {
      _viewedRequested = true;
      await ResponseRepository(FirebaseFirestore.instance).markViewedIfSent(
        responseId: widget.responseRef.id,
        viewerUid: _viewerUid,
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _confirmAction({required bool accept}) async {
    final text = accept
        ? 'Вы желаете принять кандидата?'
        : 'Вы желаете отклонить кандидата?';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Подтверждение',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text(text, style: const TextStyle(fontSize: 16, height: 1.35)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WorkaColors.blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Да',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_statusUpdating) return;
    final accept = newStatus == InteractionStatus.accepted;
    final confirmed = await _confirmAction(accept: accept);
    if (!confirmed || !mounted) return;
    setState(() => _statusUpdating = true);
    final repo = ResponseRepository(FirebaseFirestore.instance);
    try {
      if (accept) {
        await repo.accept(
          responseId: widget.responseRef.id,
          actorUid: _viewerUid,
        );
      } else {
        await repo.reject(
          responseId: widget.responseRef.id,
          actorUid: _viewerUid,
        );
      }
    } finally {
      if (mounted) setState(() => _statusUpdating = false);
    }
  }

  void _openVacancyFromSheet(String jobId) {
    final id = jobId.trim();
    if (id.isEmpty) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VacancyDetailsScreen(jobId: id)));
  }

  String _initials(String name) {
    final out = name
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();
    return out.isEmpty ? 'К' : out;
  }

  Widget _openResumeButton() {
    if (widget.onOpenCv == null) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: widget.onOpenCv,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: WorkaColors.blue,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              color: Color(0xFF3B82F6),
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'Открыть резюме',
              style: TextStyle(
                color: Color(0xFF3B82F6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decisionArea({required String status, required bool canDecide}) {
    final isAccepted = status == InteractionStatus.accepted;
    final isRejected = status == InteractionStatus.rejected;

    if (isAccepted || isRejected) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: isAccepted ? WorkaColors.blue : Colors.red,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          isAccepted ? 'Вы приняли кандидатуру' : 'Вы отклонили кандидатуру',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      );
    }

    if (!canDecide) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _statusUpdating
                  ? null
                  : () => _updateStatus(InteractionStatus.rejected),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              label: const Text(
                'Отклонить',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.orange,
                disabledBackgroundColor: WorkaColors.orange.withValues(
                  alpha: 0.45,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _statusUpdating
                  ? null
                  : () => _updateStatus(InteractionStatus.accepted),
              icon: const Icon(Icons.check_rounded, color: Colors.white),
              label: const Text(
                'Принять',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.blue,
                disabledBackgroundColor: WorkaColors.blue.withValues(
                  alpha: 0.45,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _cvPosition(Map<String, dynamic> cv) {
    final desired = (cv['desired'] is Map)
        ? Map<String, dynamic>.from(cv['desired'])
        : const <String, dynamic>{};
    return _s(
      desired['position'],
      fallback: _s(
        cv['title'],
        fallback: _s(
          desired['categoryGroup'],
          fallback: _s(desired['category']),
        ),
      ),
    );
  }

  String _cvCategory(Map<String, dynamic> cv) {
    final desired = (cv['desired'] is Map)
        ? Map<String, dynamic>.from(cv['desired'])
        : const <String, dynamic>{};
    return _s(desired['categoryGroup'], fallback: _s(desired['category']));
  }

  String _cvLocation(Map<String, dynamic> cv) {
    final desired = (cv['desired'] is Map)
        ? Map<String, dynamic>.from(cv['desired'])
        : const <String, dynamic>{};
    final fromLabel = _s(cv['locationLabel']);
    if (fromLabel.isNotEmpty) return fromLabel;
    final fromCitiesText = _s(desired['citiesText']);
    if (fromCitiesText.isNotEmpty) return fromCitiesText;
    final fromCity = _s(cv['city'], fallback: _s(cv['location']));
    if (fromCity.isNotEmpty) return fromCity;
    final countriesRaw = desired['countries'];
    if (countriesRaw is List) {
      final list = countriesRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list.join(', ');
    }
    return '';
  }

  String _cvSkills(Map<String, dynamic> cv) {
    final parts = <String>[];

    final raw = cv['skills'];
    if (raw is List) {
      parts.addAll(
        raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
      );
    } else if (raw is String && raw.trim().isNotEmpty) {
      parts.add(raw.trim());
    }

    // Driving license categories
    final dlRaw = cv['drivingLicense'];
    if (dlRaw is Map) {
      final cats = dlRaw['categories'];
      if (cats is List) {
        parts.addAll(
          cats.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
        );
      }
    } else if (dlRaw is List) {
      parts.addAll(
        dlRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
      );
    }

    // Languages
    final langsRaw = cv['languages'];
    if (langsRaw is List) {
      for (final l in langsRaw) {
        if (l is Map) {
          final lang = _s(l['language'] ?? l['name']);
          if (lang.isNotEmpty) parts.add(lang);
        }
      }
    }

    return parts.isEmpty ? '' : parts.join(', ');
  }

  Widget _metaLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: WorkaColors.textGreyDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_openedAsSentResolved) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.responseRef.snapshots(),
      builder: (context, responseSnap) {
        if (!responseSnap.hasData) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final response = responseSnap.data!.data() ?? const <String, dynamic>{};
        if (response.isEmpty) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: SizedBox.shrink(),
          );
        }

        final responseStatus = _normalizeStatus(_s(response['status']));

        final candidateOwnerId = _s(response['candidateOwnerId']);
        final employerOwnerId = _s(response['employerOwnerId']);
        final employerId = _s(response['employerId']);
        final isRecipient =
            _viewerUid.isNotEmpty &&
            (_viewerUid == employerOwnerId || _viewerUid == employerId);
        final canDecide =
            isRecipient &&
            (responseStatus == InteractionStatus.sent ||
                responseStatus == InteractionStatus.viewed);

        final isNewForRecipient =
            responseStatus == InteractionStatus.sent && isRecipient;
        final titleText = isNewForRecipient
            ? 'Новый отклик'
            : 'Отклик на вашу вакансию';

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: Future.wait([
            _loadJob(
              _firstNonEmpty([response['jobId'], response['vacancyId']]),
            ),
            _loadUser(candidateOwnerId),
            _loadCvForResponse(response),
          ]),
          builder: (context, linkedSnap) {
            final linked = linkedSnap.data ?? const <Map<String, dynamic>>[];
            final job = linked.isNotEmpty
                ? linked[0]
                : const <String, dynamic>{};
            final candidate = linked.length > 1
                ? linked[1]
                : const <String, dynamic>{};
            final cv = linked.length > 2
                ? linked[2]
                : const <String, dynamic>{};
            final candidateAccessId = _candidateAccessId(response, cv).trim();
            final hasUnlockedCandidateAccess = _hasUnlockedCandidateAccess(
              response,
              cv,
            );
            final unlockedContact = hasUnlockedCandidateAccess
                ? _contactAccess.contactForCandidate(candidateAccessId)
                : null;
            if (hasUnlockedCandidateAccess && unlockedContact == null) {
              _warmUnlockedCandidateContact(candidateAccessId);
            }

            final hasValidLinkedSources =
                _isActiveSourceDoc(job) && _isActiveSourceDoc(cv);
            if (!hasValidLinkedSources) {
              return const Scaffold(
                backgroundColor: Colors.white,
                body: SizedBox.shrink(),
              );
            }

            final cvContacts = (cv['contacts'] is Map)
                ? Map<String, dynamic>.from(cv['contacts'] as Map)
                : const <String, dynamic>{};
            final jobTitle = _firstNonEmpty([
              job['title'],
              response['vacancySnapshot'] is Map
                  ? (response['vacancySnapshot'] as Map)['title']
                  : null,
              response['jobTitle'],
            ], fallback: 'Вакансия');
            final introPrefix = isNewForRecipient
                ? 'Вы получили новый отклик на вакансию «'
                : 'Вы получили отклик на вакансию «';
            final jobId = _firstNonEmpty([
              response['jobId'],
              response['vacancyId'],
            ]);

            final candidateFirstName = _firstNonEmpty([
              cvContacts['firstName'],
              cv['firstName'],
              candidate['firstName'],
            ]);
            final candidateLastName = _firstNonEmpty([
              cvContacts['lastName'],
              cv['lastName'],
              candidate['lastName'],
            ]);
            final nameFromParts = [
              candidateFirstName,
              candidateLastName,
            ].where((e) => e.isNotEmpty).join(' ').trim();
            final candidateName = _firstNonEmpty([
              cvContacts['name'],
              nameFromParts,
              cv['fullName'],
              candidate['name'],
              response['candidateSnapshot'] is Map
                  ? (response['candidateSnapshot'] as Map)['name']
                  : null,
              response['candidateName'],
            ], fallback: 'Кандидат');

            // Age from birthDate
            final birthDateRaw =
                cvContacts['birthDate'] ??
                cv['birthDate'] ??
                candidate['birthDate'];
            int? candidateAge;
            if (birthDateRaw != null) {
              DateTime? birthDate;
              if (birthDateRaw is Timestamp) {
                birthDate = birthDateRaw.toDate();
              } else if (birthDateRaw is String &&
                  birthDateRaw.trim().isNotEmpty) {
                birthDate = DateTime.tryParse(birthDateRaw.trim());
              }
              if (birthDate != null) {
                final now = DateTime.now();
                int age = now.year - birthDate.year;
                final hadBirthday =
                    now.month > birthDate.month ||
                    (now.month == birthDate.month && now.day >= birthDate.day);
                if (!hadBirthday) age -= 1;
                if (age > 0) candidateAge = age;
              }
            }
            final candidateDisplayName = candidateAge != null
                ? '$candidateName, $candidateAge'
                : candidateName;

            // Initials from first/last name
            final initialsFirst = candidateFirstName.isNotEmpty
                ? candidateFirstName[0].toUpperCase()
                : '';
            final initialsLast = candidateLastName.isNotEmpty
                ? candidateLastName[0].toUpperCase()
                : '';
            final candidateInitials = (initialsFirst + initialsLast).isNotEmpty
                ? initialsFirst + initialsLast
                : _initials(candidateName);
            final candidateEmail = hasUnlockedCandidateAccess
                ? _s(unlockedContact?.email)
                : '';
            final candidatePhone = hasUnlockedCandidateAccess
                ? _s(unlockedContact?.phone)
                : '';
            final candidateAvatarUrl = _firstNonEmpty([
              cvContacts['avatarUrl'],
              cvContacts['photoUrl'],
              cv['avatarUrl'],
              cv['photoUrl'],
              candidate['avatarUrl'],
              candidate['photoUrl'],
              response['candidateSnapshot'] is Map
                  ? (response['candidateSnapshot'] as Map)['avatarUrl']
                  : null,
            ]);
            final candidateGender = _firstNonEmpty([
              cvContacts['gender'],
              cv['gender'],
              candidate['gender'],
              response['candidateSnapshot'] is Map
                  ? (response['candidateSnapshot'] as Map)['gender']
                  : null,
            ]);

            final position = _cvPosition(cv);
            final category = _cvCategory(cv);
            final location = _cvLocation(cv);
            final skills = _cvSkills(cv);

            final showBell = isNewForRecipient;

            return Scaffold(
              backgroundColor: const Color(0xFF4A6FDB),
              body: Column(
                children: [
                  WorkaHeader(
                    title: titleText,
                    leading: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    trailing: showBell
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  onPressed: null,
                                  icon: const Icon(
                                    Icons.notifications_none_rounded,
                                  ),
                                  color: Colors.white,
                                ),
                                Positioned(
                                  right: 12,
                                  top: 10,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: WorkaColors.orange,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : null,
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
                          Container(
                            key: ValueKey(widget.responseRef.id),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: WorkaColors.divider),
                              boxShadow: WorkaUiShadows.card,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      color: WorkaColors.textGreyDark,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      height: 1.35,
                                    ),
                                    children: [
                                      TextSpan(text: introPrefix),
                                      TextSpan(
                                        text: jobTitle,
                                        style: TextStyle(
                                          color: jobId.isNotEmpty
                                              ? const Color(0xFF3B82F6)
                                              : WorkaColors.textGreyDark,
                                          fontWeight: jobId.isNotEmpty
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          decoration: jobId.isNotEmpty
                                              ? TextDecoration.underline
                                              : TextDecoration.none,
                                        ),
                                        recognizer: jobId.isNotEmpty
                                            ? (TapGestureRecognizer()
                                                ..onTap = () =>
                                                    _openVacancyFromSheet(
                                                      jobId,
                                                    ))
                                            : null,
                                      ),
                                      const TextSpan(text: '».'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: WorkaColors.hoverBlueSoft,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _candidateAvatar(
                                        radius: 25,
                                        initials: candidateInitials,
                                        avatarUrl: candidateAvatarUrl,
                                        gender: candidateGender,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              candidateDisplayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                                color: WorkaColors.textDark,
                                              ),
                                            ),
                                            if (candidateEmail.isNotEmpty ||
                                                candidatePhone.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              if (candidateEmail.isNotEmpty)
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.email_outlined,
                                                      size: 16,
                                                      color: WorkaColors
                                                          .textGreyDark,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        candidateEmail,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: WorkaColors
                                                              .textGreyDark,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              if (candidatePhone.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.phone_outlined,
                                                      size: 16,
                                                      color: WorkaColors
                                                          .textGreyDark,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        candidatePhone,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: WorkaColors
                                                              .textGreyDark,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ] else ...[
                                              const SizedBox(height: 8),
                                              const Text(
                                                'Контакты скрыты до открытия',
                                                style: TextStyle(
                                                  color: WorkaColors
                                                      .textGreyDark,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF4E8),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFFFD9A8),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Карточка кандидата',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: WorkaColors.textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      _metaLine(
                                        Icons.badge_outlined,
                                        'Позиция',
                                        position.isEmpty ? '—' : position,
                                      ),
                                      _metaLine(
                                        Icons.work_outline_rounded,
                                        'Категория',
                                        category.isEmpty ? '—' : category,
                                      ),
                                      _metaLine(
                                        Icons.location_on_outlined,
                                        'Где работать?',
                                        location.isEmpty ? '—' : location,
                                      ),
                                      _metaLine(
                                        Icons.tips_and_updates_outlined,
                                        'Навыки',
                                        skills.isEmpty ? '—' : skills,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Кандидат прикрепил своё резюме к этому сообщению.',
                                  style: TextStyle(
                                    color: WorkaColors.textGreyDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                if (widget.onOpenCv != null) ...[
                                  const SizedBox(height: 12),
                                  _openResumeButton(),
                                ],
                                const SizedBox(height: 12),
                                _decisionArea(
                                  status: responseStatus,
                                  canDecide: canDecide,
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
          },
        );
      },
    );
  }
}
