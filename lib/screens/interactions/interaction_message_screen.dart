import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'apply_response_screen.dart';
import '../cv/cv_view_screen.dart';
import '../../repositories/response_repository.dart';
import '../../services/auth_guard.dart';
import '../../services/entity_validity.dart';
import '../../services/firestore_paths.dart';
import '../../services/interaction_status.dart';
import '../../features/payments/contact_access_controller.dart';
import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';
import '../../widgets/worka_header.dart';

class InteractionMessageScreen extends StatefulWidget {
  final String title;
  final String messageText;
  final DocumentReference<Map<String, dynamic>>? responseRef;
  final String currentStatus;
  final bool markViewedByEmployer;
  final bool markViewedByApplicant;
  final String? senderStatusOnAccepted;
  final String? senderStatusOnRejected;
  final String? senderStatusOnPostponed;
  final String entityKind;
  final VoidCallback? onOpenAttachment;
  final String? openAttachmentText;

  const InteractionMessageScreen({
    super.key,
    required this.title,
    required this.messageText,
    this.responseRef,
    this.currentStatus = InteractionStatus.pending,
    this.markViewedByEmployer = false,
    this.markViewedByApplicant = false,
    this.senderStatusOnAccepted,
    this.senderStatusOnRejected,
    this.senderStatusOnPostponed,
    this.entityKind = 'offer',
    this.onOpenAttachment,
    this.openAttachmentText,
  });

  static Future<void> open(
    BuildContext context, {
    required String title,
    required String messageText,
    DocumentReference<Map<String, dynamic>>? responseRef,
    String currentStatus = InteractionStatus.pending,
    bool markViewedByEmployer = false,
    bool markViewedByApplicant = false,
    String? senderStatusOnAccepted,
    String? senderStatusOnRejected,
    String? senderStatusOnPostponed,
    String entityKind = 'offer',
    VoidCallback? onOpenAttachment,
    String? openAttachmentText,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: InteractionMessageScreen(
          title: title,
          messageText: messageText,
          responseRef: responseRef,
          currentStatus: currentStatus,
          markViewedByEmployer: markViewedByEmployer,
          markViewedByApplicant: markViewedByApplicant,
          senderStatusOnAccepted: senderStatusOnAccepted,
          senderStatusOnRejected: senderStatusOnRejected,
          senderStatusOnPostponed: senderStatusOnPostponed,
          entityKind: entityKind,
          onOpenAttachment: onOpenAttachment,
          openAttachmentText: openAttachmentText,
        ),
      ),
    );
  }

  static Future<void> showOfferLetterSheet(
    BuildContext context, {
    required String messageText,
    required DocumentReference<Map<String, dynamic>>? offerRef,
    required String currentStatus,
    bool isCandidateView = true,
  }) {
    return open(
      context,
      title: 'Предложение работы',
      messageText: messageText,
      responseRef: offerRef,
      currentStatus: currentStatus,
      markViewedByApplicant: isCandidateView,
      markViewedByEmployer: !isCandidateView,
      senderStatusOnAccepted: 'Кандидат принял ваше предложение',
      senderStatusOnRejected: 'Кандидат отклонил ваше предложение',
      senderStatusOnPostponed: 'Предложение просмотрено кандидатом',
      entityKind: 'offer',
    );
  }

  static Future<void> showResponseLetterSheet(
    BuildContext context, {
    required String messageText,
    required DocumentReference<Map<String, dynamic>>? responseRef,
    required String currentStatus,
    bool isEmployerView = true,
    VoidCallback? onOpenCv,
    String? openAttachmentText,
  }) {
    if (responseRef == null) return Future.value();
    return ApplyResponseScreen.open(
      context,
      responseRef: responseRef,
      onOpenCv: onOpenCv,
    );
  }

  @override
  State<InteractionMessageScreen> createState() =>
      _InteractionMessageScreenState();
}

class _InteractionMessageScreenState extends State<InteractionMessageScreen> {
  final _contactAccess = ContactAccessController.instance;
  String _status = InteractionStatus.pending;
  bool _canChangeStatus = false;
  bool _statusUpdating = false;
  Map<String, dynamic> _doc = const <String, dynamic>{};
  final Map<String, Future<Map<String, dynamic>>> _jobsCache =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<Map<String, dynamic>>> _cvCache =
      <String, Future<Map<String, dynamic>>>{};
  final Map<String, Future<Map<String, dynamic>>> _usersCache =
      <String, Future<Map<String, dynamic>>>{};

  String _normalizeStatus(String status) {
    return InteractionStatus.normalize(status);
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

  Future<Map<String, dynamic>> _loadCv(String cvId) {
    final id = cvId.trim();
    if (id.isEmpty) return Future.value(const <String, dynamic>{});
    return _cvCache.putIfAbsent(id, () async {
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

  String _jobSalaryText(Map<String, dynamic> job) {
    final salaryText = _firstNonEmpty([job['salaryText'], job['salary']]);
    if (salaryText.isNotEmpty) return salaryText;
    final amount = job['salaryAmount'];
    final period = _firstNonEmpty([job['salaryPeriod'], job['salaryType']]);
    final currency = _firstNonEmpty([job['salaryCurrency']], fallback: '€');
    if (amount is num) {
      final int amountInt = amount.round();
      final periodText = period.isEmpty ? '' : ' / $period';
      return '$currency $amountInt$periodText';
    }
    return '';
  }

  Future<Map<String, dynamic>> _hydrateDoc(Map<String, dynamic> doc) async {
    final out = Map<String, dynamic>.from(doc);
    final jobId = _firstNonEmpty([doc['jobId'], doc['vacancyId']]);
    final cvId = _firstNonEmpty([doc['cvId'], doc['candidateCvId']]);
    final candidateOwnerId = _s(doc['candidateOwnerId']);
    final employerOwnerId = _s(doc['employerOwnerId']);

    final futures = <Future<Map<String, dynamic>>>[
      _loadJob(jobId),
      _loadCv(cvId),
      _loadUser(candidateOwnerId),
      _loadUser(employerOwnerId),
    ];
    final linked = await Future.wait(futures);
    final job = linked[0];
    final cv = linked[1];
    final user = linked[2];
    final employerUser = linked[3];

    if (jobId.isNotEmpty && !_isActiveSourceDoc(job)) {
      out['__invalidLinkedSources'] = true;
      return out;
    }
    if (cvId.isNotEmpty && !_isActiveSourceDoc(cv)) {
      out['__invalidLinkedSources'] = true;
      return out;
    }

    final cvContacts = (cv['contacts'] is Map)
        ? Map<String, dynamic>.from(cv['contacts'] as Map)
        : const <String, dynamic>{};
    final vacancySnapshot = (out['vacancySnapshot'] is Map)
        ? Map<String, dynamic>.from(out['vacancySnapshot'] as Map)
        : <String, dynamic>{};
    vacancySnapshot['title'] = _firstNonEmpty([
      job['title'],
      vacancySnapshot['title'],
      out['jobTitle'],
    ]);
    vacancySnapshot['companyName'] = _firstNonEmpty([
      job['companyName'],
      vacancySnapshot['companyName'],
      out['companyName'],
      employerUser['companyName'],
      employerUser['businessName'],
      employerUser['company'],
    ]);
    vacancySnapshot['locationCity'] = _firstNonEmpty([
      job['city'],
      vacancySnapshot['locationCity'],
      out['city'],
    ]);
    vacancySnapshot['locationCountry'] = _firstNonEmpty([
      job['country'],
      vacancySnapshot['locationCountry'],
      out['country'],
    ]);
    vacancySnapshot['workFormat'] = _firstNonEmpty([
      job['workSchedule'],
      job['workScheduleOption'],
      job['employmentType'],
      vacancySnapshot['workFormat'],
      out['workFormat'],
    ]);
    vacancySnapshot['salary'] = _firstNonEmpty([
      _jobSalaryText(job),
      vacancySnapshot['salary'],
      out['salary'],
    ]);
    out['vacancySnapshot'] = vacancySnapshot;
    out['jobTitle'] = vacancySnapshot['title'];
    out['companyName'] = vacancySnapshot['companyName'];
    out['city'] = vacancySnapshot['locationCity'];
    out['country'] = vacancySnapshot['locationCountry'];
    out['workFormat'] = vacancySnapshot['workFormat'];
    out['salary'] = vacancySnapshot['salary'];

    final candidateSnapshot = (out['candidateSnapshot'] is Map)
        ? Map<String, dynamic>.from(out['candidateSnapshot'] as Map)
        : <String, dynamic>{};
    final fullNameFromContacts = [
      _s(cvContacts['firstName']),
      _s(cvContacts['lastName']),
    ].where((e) => e.isNotEmpty).join(' ').trim();
    candidateSnapshot['name'] = _firstNonEmpty([
      cvContacts['name'],
      fullNameFromContacts,
      cv['fullName'],
      user['name'],
      candidateSnapshot['name'],
      out['candidateName'],
    ]);
    candidateSnapshot['email'] = _firstNonEmpty([
      user['email'],
      candidateSnapshot['email'],
      out['candidateEmail'],
    ]);
    candidateSnapshot['phone'] = _firstNonEmpty([
      user['phone'],
      candidateSnapshot['phone'],
      out['candidatePhone'],
    ]);
    candidateSnapshot['avatarUrl'] = _firstNonEmpty([
      cvContacts['avatarUrl'],
      cvContacts['photoUrl'],
      cv['avatarUrl'],
      cv['photoUrl'],
      user['avatarUrl'],
      user['photoUrl'],
      candidateSnapshot['avatarUrl'],
      out['candidateAvatarUrl'],
    ]);
    candidateSnapshot['gender'] = _firstNonEmpty([
      cvContacts['gender'],
      cv['gender'],
      user['gender'],
      candidateSnapshot['gender'],
      out['candidateGender'],
    ]);
    out['candidateSnapshot'] = candidateSnapshot;
    out['candidateName'] = candidateSnapshot['name'];
    out['candidateEmail'] = candidateSnapshot['email'];
    out['candidatePhone'] = candidateSnapshot['phone'];
    out['candidateAvatarUrl'] = candidateSnapshot['avatarUrl'];
    out['candidateGender'] = candidateSnapshot['gender'];
    out['contactEmail'] = _firstNonEmpty([
      job['contactEmail'],
      out['contactEmail'],
      out['email'],
    ]);
    out['contactPhone'] = _firstNonEmpty([
      job['contactPhone'],
      out['contactPhone'],
      out['phone'],
    ]);
    out['cvId'] = _firstNonEmpty([out['cvId'], out['candidateCvId']]);
    out['candidateCvId'] = _firstNonEmpty([out['candidateCvId'], out['cvId']]);
    final candidateAccessId = _candidateAccessId(out);
    final hasCandidateAccess =
        candidateAccessId.isNotEmpty &&
        _contactAccess.hasAccessToCandidateContact(candidateAccessId);
    if (hasCandidateAccess) {
      final unlocked = await _contactAccess.ensureLoadedContactForCandidate(
        candidateAccessId,
      );
      candidateSnapshot['email'] = _s(unlocked?.email);
      candidateSnapshot['phone'] = _s(unlocked?.phone);
      out['candidateEmail'] = _s(unlocked?.email);
      out['candidatePhone'] = _s(unlocked?.phone);
    } else {
      candidateSnapshot['email'] = '';
      candidateSnapshot['phone'] = '';
      out['candidateEmail'] = '';
      out['candidatePhone'] = '';
    }
    return out;
  }

  String _candidateAccessId(Map<String, dynamic> doc) {
    return _firstNonEmpty([
      doc['candidateCvId'],
      doc['cvId'],
      doc['candidateId'],
      doc['candidateSnapshot'] is Map
          ? (doc['candidateSnapshot'] as Map)['cvId']
          : null,
    ]);
  }

  bool _hasUnlockedCandidateAccess() {
    final candidateId = _candidateAccessId(_doc).trim();
    if (candidateId.isEmpty) return false;
    return _contactAccess.hasAccessToCandidateContact(candidateId);
  }

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
    required String initialsFallbackText,
    required String avatarUrl,
    required String gender,
    required double radius,
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
          initialsFallbackText.isEmpty ? 'К' : initialsFallbackText,
          style: TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
            fontSize: (radius * 0.73).clamp(14.0, 18.0).toDouble(),
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

  String get _uid {
    final effective = AuthGuard.effectiveUidOrNull();
    if (effective != null && effective.trim().isNotEmpty) {
      return effective.trim();
    }
    return (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }

  @override
  void initState() {
    super.initState();
    _status = InteractionStatus.isFresh(widget.currentStatus)
        ? InteractionStatus.sent
        : _normalizeStatus(widget.currentStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveAccessAndMarkViewed();
    });
    _contactAccess.bootstrap(uid: _uid).whenComplete(() {
      if (!mounted) return;
      _resolveAccessAndMarkViewed();
    });
  }

  Future<void> _resolveAccessAndMarkViewed() async {
    final ref = widget.responseRef;
    if (ref == null) return;
    final snap = await ref.get();
    final rawDoc = snap.data() ?? const <String, dynamic>{};
    final doc = await _hydrateDoc(rawDoc);
    final type = (doc['type'] ?? '').toString().trim().toLowerCase();
    final status = _normalizeStatus(
      (doc['status'] ?? InteractionStatus.pending).toString(),
    );

    final receiverUid = type == 'apply'
        ? (doc['employerOwnerId'] ?? '').toString().trim()
        : (doc['candidateOwnerId'] ?? '').toString().trim();
    final canChange = _uid.isNotEmpty && _uid == receiverUid;

    if (canChange && InteractionStatus.isFresh(status)) {
      await ResponseRepository(
        FirebaseFirestore.instance,
      ).markViewedIfSent(responseId: ref.id, viewerUid: _uid);
      final refreshed = await ref.get();
      final refreshedDoc = await _hydrateDoc(
        refreshed.data() ?? const <String, dynamic>{},
      );
      final refreshedStatus = _normalizeStatus(
        (refreshedDoc['status'] ?? status).toString(),
      );
      if (!mounted) return;
      setState(() {
        _status = refreshedStatus;
        _canChangeStatus = true;
        _doc = refreshedDoc;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _status = status;
      _canChangeStatus = canChange;
      _doc = doc;
    });
  }

  Future<bool> _confirmStatusChange(String normalized) async {
    final type = (_doc['type'] ?? '').toString().trim().toLowerCase();
    final isAccept = normalized == InteractionStatus.accepted;
    final text = switch ((type, isAccept)) {
      ('apply', true) => 'Вы желаете принять кандидата?',
      ('apply', false) => 'Вы желаете отклонить кандидата?',
      ('offer', true) => 'Вы желаете принять вакансию?',
      ('offer', false) => 'Вы желаете отклонить вакансию?',
      _ => isAccept ? 'Вы желаете принять?' : 'Вы желаете отклонить?',
    };

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

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String get _contactEmail => _s(
    _doc['employerContactsSnapshot']?['email'] ??
        _doc['contactEmail'] ??
        _doc['email'],
  );
  String get _contactPhone => _s(
    _doc['employerContactsSnapshot']?['phone'] ??
        _doc['contactPhone'] ??
        _doc['phone'],
  );

  Future<void> _setStatus(BuildContext context, String status) async {
    final ref = widget.responseRef;
    if (ref == null || !_canChangeStatus || _statusUpdating) return;

    final normalized = _normalizeStatus(status);
    final confirmed = await _confirmStatusChange(normalized);
    if (!confirmed) return;

    if (!mounted) return;
    setState(() => _statusUpdating = true);

    final repo = ResponseRepository(FirebaseFirestore.instance);
    try {
      if (normalized == InteractionStatus.accepted) {
        await repo.accept(responseId: ref.id, actorUid: _uid);
      } else if (normalized == InteractionStatus.rejected) {
        await repo.reject(responseId: ref.id, actorUid: _uid);
      }

      if (!mounted) return;
      setState(() => _status = normalized);
    } finally {
      if (mounted) setState(() => _statusUpdating = false);
    }
  }

  // ── Entity card (job info for offer / candidate info for response) ──
  Widget _buildEntityCard(String status) {
    final isOffer = widget.entityKind == 'offer';
    final title = _s(_doc['vacancySnapshot']?['title'] ?? _doc['jobTitle']);
    final company = _s(
      _doc['vacancySnapshot']?['companyName'] ?? _doc['companyName'],
    );
    final city = _s(_doc['vacancySnapshot']?['locationCity'] ?? _doc['city']);
    final salary = _s(_doc['vacancySnapshot']?['salary'] ?? _doc['salary']);
    final workFormat = _s(
      _doc['vacancySnapshot']?['workFormat'] ?? _doc['workFormat'],
    );
    final candidateName = _s(
      _doc['candidateName'] ?? _doc['candidateSnapshot']?['name'],
    );
    final hasUnlockedCandidateAccess = _hasUnlockedCandidateAccess();
    final candidateEmail = hasUnlockedCandidateAccess
        ? _s(_doc['candidateSnapshot']?['email'] ?? _doc['candidateEmail'])
        : '';
    final candidatePhone = hasUnlockedCandidateAccess
        ? _s(_doc['candidateSnapshot']?['phone'] ?? _doc['candidatePhone'])
        : '';
    final candidateAvatarUrl = _s(
      _doc['candidateSnapshot']?['avatarUrl'] ?? _doc['candidateAvatarUrl'],
    );
    final candidateGender = _s(
      _doc['candidateSnapshot']?['gender'] ?? _doc['candidateGender'],
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD9A8), width: 1.2),
      ),
      padding: const EdgeInsets.all(16),
      child: isOffer
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: WorkaColors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.work_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty ? 'Вакансия' : title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: WorkaColors.textDark,
                            ),
                          ),
                          if (company.isNotEmpty)
                            Text(
                              company,
                              style: const TextStyle(
                                color: WorkaColors.textGreyDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (workFormat.isNotEmpty ||
                    city.isNotEmpty ||
                    salary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (workFormat.isNotEmpty)
                        _infoChip(Icons.schedule_outlined, workFormat),
                      if (city.isNotEmpty)
                        _infoChip(
                          Icons.location_on_outlined,
                          city,
                          color: WorkaColors.orange,
                        ),
                      if (salary.isNotEmpty)
                        _infoChip(Icons.payments_outlined, salary),
                    ],
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _candidateAvatar(
                      initialsFallbackText: candidateName.isNotEmpty
                          ? candidateName[0].toUpperCase()
                          : 'К',
                      avatarUrl: candidateAvatarUrl,
                      gender: candidateGender,
                      radius: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        candidateName.isEmpty ? 'Кандидат' : candidateName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: WorkaColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                if (candidateEmail.isNotEmpty || candidatePhone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  if (candidateEmail.isNotEmpty)
                    _contactRow(Icons.email_outlined, candidateEmail),
                  if (candidatePhone.isNotEmpty)
                    _contactRow(Icons.phone_outlined, candidatePhone),
                ] else ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Контакты скрыты до открытия',
                    style: TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _infoChip(IconData icon, String label, {Color? color}) {
    final fg = color ?? WorkaColors.textGreyDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Для связи с работодателем',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        if (_contactEmail.isNotEmpty)
          _contactRow(Icons.email_outlined, _contactEmail),
        if (_contactPhone.isNotEmpty)
          _contactRow(Icons.phone_outlined, _contactPhone),
      ],
    );
  }

  Widget _contactRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: WorkaColors.textGreyDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
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

  String _applyHeaderTitle(String status) {
    return InteractionStatus.isFresh(status)
        ? 'Новый отклик'
        : 'Отклик на вашу вакансию';
  }

  Widget _applyDecisionBlock(String status) {
    final isAccepted = status == InteractionStatus.accepted;
    final isRejected = status == InteractionStatus.rejected;

    if (isAccepted || isRejected) {
      final text = _canChangeStatus
          ? (isAccepted ? 'Вы приняли кандидатуру' : 'Вы отклонили кандидатуру')
          : (isAccepted
                ? 'Работодатель принял вашу кандидатуру'
                : 'Работодатель отклонил вашу кандидатуру');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: isAccepted ? WorkaColors.blue : Colors.red,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
      );
    }

    if (!_canChangeStatus) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _statusUpdating
                  ? null
                  : () => _setStatus(context, InteractionStatus.rejected),
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
                backgroundColor: Colors.red,
                disabledBackgroundColor: Colors.red.withValues(alpha: 0.45),
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
                  : () => _setStatus(context, InteractionStatus.accepted),
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
      ],
    );
  }

  Widget _buildApplyMessageCard(String status) {
    final jobTitle = _s(_doc['jobTitle'], fallback: 'вашу вакансию');
    final intro = InteractionStatus.isFresh(status)
        ? 'Вы получили новый отклик на вакансию «$jobTitle».'
        : 'Вы получили отклик на вашу вакансию «$jobTitle».';
    final candidateName = _s(
      _doc['candidateName'],
      fallback: _s(_doc['candidateSnapshot']?['name'], fallback: 'Кандидат'),
    );
    final hasUnlockedCandidateAccess = _hasUnlockedCandidateAccess();
    final candidateEmail = hasUnlockedCandidateAccess
        ? _s(_doc['candidateSnapshot']?['email'] ?? _doc['candidateEmail'])
        : '';
    final candidatePhone = hasUnlockedCandidateAccess
        ? _s(_doc['candidateSnapshot']?['phone'] ?? _doc['candidatePhone'])
        : '';
    final candidateAvatarUrl = _s(
      _doc['candidateSnapshot']?['avatarUrl'] ?? _doc['candidateAvatarUrl'],
    );
    final candidateGender = _s(
      _doc['candidateSnapshot']?['gender'] ?? _doc['candidateGender'],
    );
    final initials = candidateName
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();

    return Container(
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
          Text(
            intro,
            style: const TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              height: 1.35,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _candidateAvatar(
                  initialsFallbackText: initials.isEmpty ? 'К' : initials,
                  avatarUrl: candidateAvatarUrl,
                  gender: candidateGender,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidateName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: WorkaColors.textDark,
                        ),
                      ),
                      if (candidateEmail.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _contactRow(Icons.email_outlined, candidateEmail),
                      ],
                      if (candidatePhone.isNotEmpty)
                        _contactRow(Icons.phone_outlined, candidatePhone),
                      if (candidateEmail.isEmpty && candidatePhone.isEmpty) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Контакты скрыты до открытия',
                          style: TextStyle(
                            color: WorkaColors.textGreyDark,
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
          const Text(
            'Кандидат прикрепил своё резюме к этому сообщению.',
            style: TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          if (widget.onOpenAttachment != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onOpenAttachment,
                icon: const Icon(
                  Icons.description_outlined,
                  color: WorkaColors.blue,
                  size: 18,
                ),
                label: const Text('Открыть резюме'),
                style: FilledButton.styleFrom(
                  backgroundColor: WorkaColors.hoverBlueSoft,
                  foregroundColor: WorkaColors.blue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _applyDecisionBlock(status),
        ],
      ),
    );
  }

  String _offerHeaderTitle(String status) {
    if (InteractionStatus.isFresh(status)) {
      return 'Новое предложение\nо работе';
    }
    return 'Предложение\nо работе';
  }

  Widget _offerDecisionBlock(String status) {
    final isAccepted = status == InteractionStatus.accepted;
    final isRejected = status == InteractionStatus.rejected;

    if (isAccepted || isRejected) {
      final text = _canChangeStatus
          ? (isAccepted ? 'Вы приняли вакансию' : 'Вы отклонили вакансию')
          : (isAccepted
                ? 'Кандидат принял вашу вакансию'
                : 'Кандидат отклонил вашу вакансию');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: isAccepted ? WorkaColors.blue : Colors.red,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
      );
    }

    if (!_canChangeStatus) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _statusUpdating
                  ? null
                  : () => _setStatus(context, InteractionStatus.rejected),
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
                backgroundColor: Colors.red,
                disabledBackgroundColor: Colors.red.withValues(alpha: 0.45),
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
                  : () => _setStatus(context, InteractionStatus.accepted),
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

  Widget _buildOfferMessageCard(String status) {
    final title = _s(
      _doc['vacancySnapshot']?['title'] ?? _doc['jobTitle'],
      fallback: 'Вакансия',
    );
    final company = _s(
      _doc['vacancySnapshot']?['companyName'] ?? _doc['companyName'],
      fallback: 'Работодатель',
    );
    final workFormat = _s(
      _doc['vacancySnapshot']?['workFormat'] ?? _doc['workFormat'],
      fallback: 'Полная занятость',
    );
    final city = _s(_doc['vacancySnapshot']?['locationCity'] ?? _doc['city']);
    final country = _s(
      _doc['vacancySnapshot']?['locationCountry'] ?? _doc['country'],
    );
    final location = [city, country].where((e) => e.isNotEmpty).join(', ');
    final salary = _s(
      _doc['vacancySnapshot']?['salary'] ?? _doc['salary'],
      fallback: '€3000 / месяц',
    );
    final email = _contactEmail;
    final phone = _contactPhone;

    return Container(
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
          Builder(
            builder: (_) {
              final cvTitle = _s(
                _doc['cvTitleSnapshot'],
                fallback: _s(_doc['cvTitle']),
              );
              return RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    height: 1.35,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Работодатель заинтересовался Вашим резюме',
                    ),
                    if (cvTitle.isNotEmpty)
                      TextSpan(
                        text: ' «$cvTitle»',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    const TextSpan(
                      text: ' и отправил вам предложение о работе.',
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFD9A8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: WorkaColors.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: WorkaColors.orange.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.work_rounded,
                          color: WorkaColors.orange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: widget.onOpenAttachment == null
                            ? Text(
                                '$title в $company',
                                style: const TextStyle(
                                  color: WorkaColors.textGreyDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  height: 1.25,
                                ),
                              )
                            : InkWell(
                                onTap: widget.onOpenAttachment,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    '$title в $company',
                                    style: const TextStyle(
                                      color: WorkaColors.blue,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      height: 1.25,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: WorkaColors.divider),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      size: 16,
                      color: WorkaColors.textGreyDark,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        location.isEmpty
                            ? workFormat
                            : '$workFormat • $location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WorkaColors.textGreyDark,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      size: 16,
                      color: WorkaColors.textGreyDark,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        salary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WorkaColors.textGreyDark,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Для связи с работодателем',
            style: TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          _contactRow(Icons.email_outlined, email),
          _contactRow(Icons.phone_outlined, phone),
          const SizedBox(height: 10),
          // CV title link — blue, tappable, opens CvViewScreen.
          Builder(
            builder: (ctx) {
              final cvId = _s(
                _doc['cvId'],
                fallback: _s(_doc['candidateCvId']),
              );
              final cvTitle = _s(
                _doc['cvTitleSnapshot'],
                fallback: _s(_doc['cvTitle'], fallback: 'Ваше резюме'),
              );
              if (cvId.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CvViewScreen(
                          cvId: cvId,
                          testMode: false,
                          forceReadOnly: true,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: WorkaColors.blue,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cvTitle,
                          style: const TextStyle(
                            color: WorkaColors.blue,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (widget.onOpenAttachment != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onOpenAttachment,
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: WorkaColors.blue,
                  size: 18,
                ),
                label: const Text('Открыть вакансию'),
                style: FilledButton.styleFrom(
                  backgroundColor: WorkaColors.hoverBlueSoft,
                  foregroundColor: WorkaColors.blue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          if (widget.onOpenAttachment != null) const SizedBox(height: 12),
          _offerDecisionBlock(status),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = _normalizeStatus(_status);
    final isOffer = widget.entityKind == 'offer';
    final isResponse = widget.entityKind == 'response';
    final linkedInvalid = _doc['__invalidLinkedSources'] == true;
    if (linkedInvalid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final appBarTitle = isResponse
        ? _applyHeaderTitle(normalizedStatus)
        : (isOffer ? _offerHeaderTitle(normalizedStatus) : widget.title);

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: appBarTitle,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            trailing: isOffer
                ? Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        onPressed: null,
                        icon: const Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white,
                        ),
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
                  if (isResponse)
                    _buildApplyMessageCard(normalizedStatus)
                  else if (isOffer)
                    _buildOfferMessageCard(normalizedStatus)
                  else ...[
                    Text(
                      widget.messageText.trim(),
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildEntityCard(normalizedStatus),
                    const SizedBox(height: 16),
                    if (_contactEmail.isNotEmpty || _contactPhone.isNotEmpty)
                      _buildContactsSection(),
                    const SizedBox(height: 16),
                    if (widget.onOpenAttachment != null &&
                        (widget.openAttachmentText ?? '').trim().isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.onOpenAttachment,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(widget.openAttachmentText!.trim()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: WorkaColors.blue,
                            side: const BorderSide(color: WorkaColors.blue),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: null,
    );
  }
}
