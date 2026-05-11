import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:worka/controllers/paid_entitlements_controller.dart';
import 'package:flutter/material.dart';

import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/services/guest_uid_service.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/repositories/notifications_repository.dart';
import 'package:worka/repositories/response_repository.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/services/runtime_flow_logger.dart';
import 'package:worka/services/apply_vacancy_identity_resolver.dart';
import 'package:worka/services/ownership_context.dart';
import 'package:worka/services/vacancy_owner_scope_resolver.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:worka/screens/worker_profile_edit_screen.dart';
import 'package:worka/screens/cv/cv_wizard_screen.dart';
import 'package:worka/screens/vacancy_review_screen.dart';
import 'package:worka/widgets/vacancy_details_view.dart';
import 'package:worka/widgets/vacancy_apply_entry_sheet.dart';
import 'package:worka/features/payments/screens/promote_job_screen.dart';
import 'package:worka/screens/widgets/vacancy_select_cv_sheet_sections.dart';
import 'widgets/vacancy_details_widgets.dart';

class VacancyDetailsScreen extends StatefulWidget {
  final String jobId;

  /// Если нужно читать не из jobs (например jobs_test) — передай refOverride.
  final DocumentReference<Map<String, dynamic>>? refOverride;

  /// testMode = true => в тестовом режиме считаем, что «закрытых функций нет»
  final bool testMode;
  final bool isOwnerView;

  const VacancyDetailsScreen({
    super.key,
    required this.jobId,
    this.refOverride,
    this.testMode = false,
    this.isOwnerView = false,
  });

  @override
  State<VacancyDetailsScreen> createState() => _VacancyDetailsScreenState();
}

class _VacancyDetailsScreenState extends State<VacancyDetailsScreen> {
  final _db = FirebaseFirestore.instance;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _refreshJobEntitlementsIfNeeded();
  }

  @override
  void didUpdateWidget(covariant VacancyDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId.trim() != widget.jobId.trim()) {
      _refreshJobEntitlementsIfNeeded();
    }
  }

  void _refreshJobEntitlementsIfNeeded() {
    final jobId = widget.jobId.trim();
    if (jobId.isEmpty) return;
    final paid = PaidEntitlementsController.instance;
    if (paid.shouldRefreshJobEntitlements(jobId)) {
      Future.microtask(() => paid.refreshJobEntitlements(jobId));
    }
  }

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
    final r = OwnershipResolver.vacancyViewerOwnership(
      job,
      viewerUid: myUid,
    );
    return r.known && r.isOwner;
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
    String resolvedUid() => (AuthGuard.effectiveUidOrNull() ?? '').trim();

    var uid = resolvedUid();
    if (uid.isEmpty) {
      uid = await GuestUidService.getOrCreate();
      AuthGuard.setCachedGuestUid(uid);
      RuntimeFlowLogger.mark('APPLY_AUTH_CONTINUATION_START', <String, Object?>{
        'stage': 'guest_ready',
        'uid': uid,
        'vacancyId': widget.jobId,
      });
    } else {
      RuntimeFlowLogger.mark('APPLY_AUTH_CONTINUATION_START', <String, Object?>{
        'stage': 'auth_ready',
        'uid': uid,
        'vacancyId': widget.jobId,
      });
    }

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
                      'Не удалось загрузить вакансию. Попробуйте позже.',
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
    final hasHighlight = paid.hasJobFeature(jobId, 'highlight');
    final hasUrgent = paid.hasJobFeature(jobId, 'urgent');
    final hasPriority = paid.hasJobFeature(jobId, 'priority');
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

      final nav = Navigator.of(context);
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: disabled
              ? null
              : () async {
                  setState(() => _sending = true);
                  try {
                    RuntimeFlowLogger.mark('APPLY_ENTRY_OPEN', <String, Object?>{
                      'vacancyId': widget.jobId,
                      'source': 'vacancy_details_screen.bottom_cta',
                    });
                    final ok = await VacancyApplyEntrySheet.open(
                      nav.context,
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
                      nav.pop();
                    } else {
                      ScaffoldMessenger.of(nav.context).showSnackBar(
                        const SnackBar(
                          content: Text('Не удалось отправить CV. Повторите.'),
                        ),
                      );
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
                  applied ? 'Отклик отправлен' : 'Откликнуться',
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
    final promotionIdentity = ApplyVacancyIdentityResolver.resolve(
      vacancyId: widget.jobId,
      snapshot: job,
    );
    final promotionOwnerScope = VacancyOwnerScopeResolver.resolveVacancyOwnerScope(
      job,
    );
    final promotionTargetId = promotionIdentity.isResolved
        ? promotionIdentity.apiJobCode
        : widget.jobId.trim();
    final promotionBlockedMessage = !promotionIdentity.isResolved
        ? 'Вакансия не синхронизирована. Продвижение пока недоступно.'
        : (!promotionOwnerScope.isResolved
              ? 'Не удалось определить владельца вакансии для продвижения.'
              : PromotionOwnershipDecision.mismatchMessage);
    final entitlementChips = <Widget>[];
    if (hasUrgent) {
      entitlementChips.add(
        const VacancyStatusChip(text: 'СРОЧНО', color: Color(0xFFB45309)),
      );
    }
    if (hasPriority) {
      entitlementChips.add(
        const VacancyStatusChip(text: 'Приоритет', color: Color(0xFF6D28D9)),
      );
    }
    if (hasBump) {
      entitlementChips.add(
        const VacancyStatusChip(text: 'Поднято', color: Color(0xFF2563EB)),
      );
    }
    if (hasShowContacts) {
      entitlementChips.add(
        const VacancyStatusChip(
          text: 'Контакты доступны',
          color: Color(0xFF15803D),
        ),
      );
    }
    final hasEntitlementChips = entitlementChips.isNotEmpty;
    final headerHighlightButton = isOwner
        ? (hasHighlight
              ? const VacancyStatusChip(
                  text: 'Выделено',
                  color: WorkaColors.orange,
                )
              : SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: () {
                      if (!promotionIdentity.isResolved ||
                          !promotionOwnerScope.isResolved) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(promotionBlockedMessage)),
                        );
                        return;
                      }
                      final decision =
                          CanonicalOwnershipResolver.resolvePromotionAccess(
                            entityOwnerType: promotionOwnerScope.ownerType,
                            entityOwnerId: promotionOwnerScope.ownerId,
                          );
                      if (!decision.allowed) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(promotionBlockedMessage)),
                        );
                        return;
                      }
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) => PromoteJobScreen(
                            jobCode: promotionTargetId,
                            ownerType: promotionOwnerScope.ownerType,
                            ownerId: promotionOwnerScope.ownerId,
                          ),
                        ),
                      );
                    },
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
                    VacancyContactCard(contacts: contacts),
                    const SizedBox(height: 10),
                  ] else if (hasShowContacts) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F7EE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Text(
                        'Контакты открыты, но работодатель пока не добавил контактные данные.',
                        style: TextStyle(
                          color: WorkaColors.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
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

  // _statusChip migrated to VacancyStatusChip widget (see widgets/vacancy_details_widgets.dart)
}

// ====== CV selection sheet (unchanged) ======

class _SelectCvForJobSheet extends StatefulWidget {
  final String jobId;
  final DocumentReference<Map<String, dynamic>> jobRef;
  final String jobTitle;
  final bool testMode;

  final Future<Map<String, dynamic>?> Function(String uid) loadWorkerProfile;
  final bool Function(Map<String, dynamic>? profile) profileOk;
  final Future<bool> Function() openProfileEdit;

  const _SelectCvForJobSheet({
    required this.jobId,
    required this.jobRef,
    required this.jobTitle,
    required this.testMode,
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
  bool _sentAsGuest = false;

  String? _selectedCvId;

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  String _resolveAuthUid() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = (user == null || user.isAnonymous)
        ? (AuthGuard.effectiveUidOrNull() ?? '')
        : user.uid.trim();
    RuntimeFlowLogger.mark('AUTH_UID_RESOLVE', <String, Object?>{
      'source': 'firebase',
      'uid': uid,
    });
    return uid;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _cvsStream() {
    final ownerId = _resolveAuthUid();
    RuntimeFlowLogger.mark('APPLY_CV_LIST_QUERY', <String, Object?>{
      'uid': ownerId,
    });
    if (ownerId.isEmpty) {
      RuntimeFlowLogger.mark('CV_REPOSITORY_QUERY', <String, Object?>{
        'uid': ownerId,
        'scope': 'selector',
        'empty_uid': true,
      });
      RuntimeFlowLogger.mark('CV_REPOSITORY_RESULT', <String, Object?>{
        'uid': ownerId,
        'count': 0,
        'scope': 'selector',
      });
      RuntimeFlowLogger.mark('APPLY_CV_LIST_RESULT', <String, Object?>{
        'count': 0,
      });
      return Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    }
    RuntimeFlowLogger.mark('CV_REPOSITORY_QUERY', <String, Object?>{
      'uid': ownerId,
      'scope': 'selector',
    });
    return _db
        .collection(FirestorePaths.cvs)
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((s) {
          final docs = s.docs
              .where((d) => (d.data()['isDeleted'] ?? false) != true)
              .toList();
          RuntimeFlowLogger.mark('CV_REPOSITORY_RESULT', <String, Object?>{
            'uid': ownerId,
            'count': docs.length,
            'scope': 'selector',
          });
          RuntimeFlowLogger.mark('APPLY_CV_LIST_RESULT', <String, Object?>{
            'count': docs.length,
          });
          return docs;
        });
  }

  // _workaCheckbox migrated to WorkaCheckbox widget (see widgets/vacancy_details_widgets.dart)

  Future<void> _send() async {
    RuntimeFlowLogger.mark('APPLY_SEND_TAP', <String, Object?>{
      'vacancyId': widget.jobId,
      'cvId': (_selectedCvId ?? '').toString(),
    });
    RuntimeFlowLogger.mark('APPLY_PRECHECK_START', <String, Object?>{});

    bool profileHasApplyMinimum(Map<String, dynamic>? profile) {
      if (profile == null) return false;
      final firstName = (profile['firstName'] ?? '').toString().trim();
      final lastName = (profile['lastName'] ?? '').toString().trim();
      final fullName = (profile['fullName'] ?? profile['name'] ?? '')
          .toString()
          .trim();
      final email = (profile['email'] ?? '').toString().trim();
      final phone = (profile['phone'] ?? '').toString().trim();
      final hasName =
          fullName.isNotEmpty || firstName.isNotEmpty || lastName.isNotEmpty;
      final hasContact = email.isNotEmpty || phone.isNotEmpty;
      return hasName && hasContact;
    }

    Map<String, dynamic> hydrateProfileFromCv(
      Map<String, dynamic>? profile,
      Map<String, dynamic> cv,
    ) {
      final base = Map<String, dynamic>.from(
        profile ?? const <String, dynamic>{},
      );
      String pickString(List<dynamic> values) {
        for (final value in values) {
          final text = (value ?? '').toString().trim();
          if (text.isNotEmpty) return text;
        }
        return '';
      }

      final contacts = (cv['contacts'] is Map)
          ? Map<String, dynamic>.from(cv['contacts'] as Map)
          : const <String, dynamic>{};
      final fullName = pickString([cv['fullName'], cv['name'], cv['title']]);
      final nameParts = fullName
          .split(RegExp(r'\s+'))
          .where((v) => v.isNotEmpty)
          .toList();
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName = nameParts.length > 1
          ? nameParts.sublist(1).join(' ')
          : '';

      if ((base['firstName'] ?? '').toString().trim().isEmpty &&
          firstName.isNotEmpty) {
        base['firstName'] = firstName;
      }
      if ((base['lastName'] ?? '').toString().trim().isEmpty &&
          lastName.isNotEmpty) {
        base['lastName'] = lastName;
      }
      if ((base['fullName'] ?? base['name'] ?? '').toString().trim().isEmpty &&
          fullName.isNotEmpty) {
        base['fullName'] = fullName;
      }
      if ((base['email'] ?? '').toString().trim().isEmpty) {
        final email = pickString([cv['email'], contacts['email']]);
        if (email.isNotEmpty) base['email'] = email;
      }
      if ((base['phone'] ?? '').toString().trim().isEmpty) {
        final phone = pickString([
          cv['phone'],
          cv['phoneNumber'],
          contacts['phone'],
          contacts['phoneNumber'],
        ]);
        if (phone.isNotEmpty) base['phone'] = phone;
      }
      return base;
    }

    var uid = _resolveAuthUid();
    if (uid.isEmpty) {
      uid = await GuestUidService.getOrCreate();
      AuthGuard.setCachedGuestUid(uid);
      RuntimeFlowLogger.mark('APPLY_AUTH_CONTINUATION_START', <String, Object?>{
        'stage': 'guest_ready',
        'uid': uid,
        'vacancyId': widget.jobId,
      });
    }

    if (uid.isEmpty) {
      RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
        'reason': 'auth_missing_after_restore',
      });
      RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
        'ok': false,
        'reason': 'auth_missing_after_restore',
      });
      _toast('Создайте CV, чтобы откликнуться.');
      return;
    }
    final isGuestCandidate = AuthGuard.isGuestLikeUid(uid);

    // Guest-first: open CV flow; auth will be required inside CV save/send.
    if (_selectedCvId == null) {
      RuntimeFlowLogger.mark('APPLY_BLOCKED_NO_CV', <String, Object?>{
        'jobId': widget.jobId,
        'vacancyId': widget.jobId,
        'userId': uid,
        'sourceScreen': 'vacancy_details_screen',
      });
      RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
        'ok': false,
        'reason': 'cv_not_selected',
      });
      _toast('Выберите CV.');
      return;
    }
    final selectedCvId = (_selectedCvId ?? '').trim();
    if (selectedCvId.isEmpty) {
      RuntimeFlowLogger.mark('APPLY_BLOCKED_NO_CV', <String, Object?>{
        'jobId': widget.jobId,
        'vacancyId': widget.jobId,
        'userId': uid,
        'sourceScreen': 'vacancy_details_screen',
      });
      _toast('Выберите CV.');
      return;
    }

    if (await ResponseRepository(_db).hasAppliedOnce(
      jobId: widget.jobId,
      candidateOwnerId: uid,
        candidateCvId: selectedCvId,
    )) {
      RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
        'reason': 'duplicate_application',
      });
      RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
        'ok': false,
        'reason': 'duplicate_application',
      });
      _toast('Вы уже откликались на эту вакансию.');
      return;
    }

    Map<String, dynamic> cvData = {};
    if ((_selectedCvId ?? '').isNotEmpty) {
      final cvDoc = await _db
          .collection(FirestorePaths.cvs)
          .doc(_selectedCvId!)
          .get();
      cvData = cvDoc.data() ?? {};
    }

    // 1) профиль
    Map<String, dynamic>? profile;
    Map<String, dynamic>? profile2;
    if (!isGuestCandidate) {
      profile = await widget.loadWorkerProfile(uid);
    }
    if (!isGuestCandidate && !widget.profileOk(profile)) {
      final ok = await widget.openProfileEdit();
      if (!ok) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'profile_edit_cancelled',
        });
        RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
          'ok': false,
          'reason': 'profile_edit_cancelled',
        });
        _toast('Профиль не заполнен — отклик не отправлен.');
        return;
      }
    }
    if (!isGuestCandidate) {
      profile2 = await widget.loadWorkerProfile(uid);
    }
    if (!isGuestCandidate && !widget.profileOk(profile2)) {
      final hydrated = hydrateProfileFromCv(profile2, cvData);
      final hydratedOk =
          widget.profileOk(hydrated) || profileHasApplyMinimum(hydrated);
      RuntimeFlowLogger.mark('APPLY_PROFILE_HYDRATE_FROM_CV', <String, Object?>{
        'ok': hydratedOk,
      });
      if (!hydratedOk) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'profile_incomplete_after_hydrate',
        });
        RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
          'ok': false,
          'reason': 'profile_incomplete_after_hydrate',
        });
        _toast('Заполните профиль полностью.');
        return;
      }
      profile2 = hydrated;
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
      final workerOwnerKey = uid;
      RuntimeFlowLogger.mark('APPLY_SCOPE_CHECK', <String, Object?>{
        'mode': isGuestCandidate ? 'guest' : AppMode.currentMode.name,
        'uid': workerOwnerKey,
      });
      if (!isGuestCandidate && AppMode.currentMode != AccountMode.personal) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'mode_not_personal',
        });
        RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
          'ok': false,
          'reason': 'mode_not_personal',
        });
        debugPrint(
          '[OWNER_SCOPE_REJECT] resource=application action=send required=personal current=${AppMode.currentMode.name}',
        );
        _toast(
          'Отклик доступен только в личном профиле. Переключитесь в личный профиль и повторите.',
        );
        return;
      }
      if (workerOwnerKey.isEmpty) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'worker_owner_key_empty',
        });
        RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
          'ok': false,
          'reason': 'worker_owner_key_empty',
        });
        _toast(
          'Войдите или зарегистрируйтесь через email или телефон. После входа действие продолжится автоматически.',
        );
        return;
      }
      RuntimeFlowLogger.mark('APPLY_CV_SELECTED', <String, Object?>{
        'cvId': selectedCvId,
      });

      final duplicate = await ResponseRepository(_db).hasAppliedOnce(
        jobId: widget.jobId,
        candidateOwnerId: workerOwnerKey,
        candidateCvId: selectedCvId,
      );
      if (duplicate) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'duplicate_application_recheck',
        });
        RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
          'ok': false,
          'reason': 'duplicate_application_recheck',
        });
        if (mounted) _toast('CV уже отправлено');
        return;
      }

      String f(dynamic v) => (v ?? '').toString().trim();
      List<String> list(dynamic v) {
        if (v is List) return v.map((e) => e.toString()).toList();
        return [];
      }

      final applicationId =
          '${widget.jobId}_${workerOwnerKey}_${selectedCvId}_apply';
      final resolvedIdentity = ApplyVacancyIdentityResolver.resolve(
        vacancyId: widget.jobId,
        snapshot: job,
      );
      ApplyVacancyIdentityResolver.debugLog(
        identity: resolvedIdentity,
        vacancyId: widget.jobId,
        snapshot: job,
      );
      if (!resolvedIdentity.isResolved) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'job_id_unresolved',
          'vacancyId': widget.jobId,
        });
        RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
          'ok': false,
          'reason': 'job_id_unresolved',
        });
        _toast('Вакансия не синхронизирована. Отклик пока нельзя отправить.');
        return;
      }
      RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
        'ok': true,
        'reason': 'ready_to_send',
      });
      RuntimeFlowLogger.mark('APPLY_SEND_START', <String, Object?>{
        'vacancyId': widget.jobId,
        'uid': workerOwnerKey,
        'cvId': selectedCvId,
      });
      RuntimeFlowLogger.mark('APPLY_REPOSITORY_CALL', <String, Object?>{
        'vacancyId': widget.jobId,
        'cvId': selectedCvId,
      });
      final applyResult = await ResponseRepository(_db).createApply(
        jobId: widget.jobId,
        jobOwnerId: employerUid,
        candidateCvId: selectedCvId,
        candidateOwnerId: workerOwnerKey,
        vacancyOwnerType: f(job['ownerType']).isEmpty
            ? 'personal'
            : f(job['ownerType']),
        applicantProfileType: isGuestCandidate ? 'guest' : 'personal',
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
        candidateSnapshot: Map<String, dynamic>.from(
          isGuestCandidate
              ? <String, dynamic>{
                  'ownerType': 'guest',
                  'isRegistered': false,
                  'label': 'Пользователь незарегистрирован',
                }
              : (profile2 ?? {}),
        ),
      );
      if (applyResult.isAlreadyApplied) {
        RuntimeFlowLogger.mark('APPLY_SEND_RESULT', <String, Object?>{
          'status': 'already_applied',
          'vacancyId': widget.jobId,
        });
        _toast('CV уже отправлено');
        return;
      }
      if (applyResult.isBlocked || applyResult.isFailed) {
        RuntimeFlowLogger.mark('APPLY_SEND_RESULT', <String, Object?>{
          'status': 'error',
          'vacancyId': widget.jobId,
          'reason': applyResult.reason,
          'error': applyResult.error,
        });
        if (applyResult.reason == 'job_id_unresolved') {
          _toast('Вакансия не синхронизирована. Отклик пока нельзя отправить.');
        } else {
          _toast('Не удалось отправить отклик. Попробуйте ещё раз.');
        }
        return;
      }
      if (employerUid.isNotEmpty) {
        await NotificationsRepository(_db).createItem(
          toUserId: employerUid,
          fromUserId: workerOwnerKey,
          type: 'response_received',
          kind: 'response',
          entityId: applicationId,
          payload: {
            'vacancyId': widget.jobId,
            'cvId': selectedCvId,
            'shortText': 'Новый отклик на вакансию',
          },
        );
      }

      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentAsGuest = isGuestCandidate;
      });
      RuntimeFlowLogger.mark('APPLY_SEND_RESULT', <String, Object?>{
        'status': 'success',
        'vacancyId': widget.jobId,
      });
    } catch (e) {
      debugPrint('VacancyDetailsScreen _submitApplication error: $e');
      if ('$e'.contains('job_id_unresolved')) {
        _toast('Вакансия не синхронизирована. Отклик пока нельзя отправить.');
      } else {
        _toast('Не удалось отправить отклик. Попробуйте ещё раз.');
      }
      RuntimeFlowLogger.mark('APPLY_REPOSITORY_RETURN', <String, Object?>{
        'status': 'error',
        'message': e.toString(),
      });
      RuntimeFlowLogger.mark('APPLY_SEND_RESULT', <String, Object?>{
        'status': 'error',
        'body': e.toString(),
      });
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
      return VacancySelectCvSentStateView(
        guestApplied: _sentAsGuest,
        onClose: () => Navigator.pop(context, true),
      );
    }

    return VacancySelectCvPickerView(
      title: title,
      cvsStream: _cvsStream(),
      selectedCvId: _selectedCvId,
      onToggleSelection: (id) {
        setState(() {
          if (_selectedCvId == id) {
            _selectedCvId = null;
          } else {
            _selectedCvId = id;
          }
        });
        RuntimeFlowLogger.mark('APPLY_CV_SELECTED', <String, Object?>{
          'cvId': (_selectedCvId ?? '').toString(),
        });
      },
      onClose: () => Navigator.pop(context, false),
      onCreateCv: () async {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => CvWizardScreen(testMode: widget.testMode),
          ),
        );
        if (!mounted) return;
        setState(() {});
      },
      sending: _sending,
      onSend: _send,
    );
  }
}
