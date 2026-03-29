import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_paths.dart';
import '../../services/interaction_status.dart';
import '../../theme/worka_colors.dart';
import '../../widgets/worka_header.dart';
import 'cv_wizard_screen.dart';
import '../interactions/offers_list_screen.dart';
import 'widgets/cv_profile_view.dart';

class CvViewScreen extends StatefulWidget {
  final String cvId;

  /// Если нужно читать CV не из стандартного места — можно передать refOverride.
  /// (например, для кандидатов/работодателей, если CV лежит в другой коллекции)
  final DocumentReference<Map<String, dynamic>>? refOverride;

  /// ✅ тестовый режим (разрешаем открывать CV без SMS/логина)
  final bool testMode;
  final bool startEditing;
  final String? statusFooterText;
  final bool forceReadOnly;

  const CvViewScreen({
    super.key,
    required this.cvId,
    this.refOverride,
    this.testMode = true,
    this.startEditing = false,
    this.statusFooterText,
    this.forceReadOnly = false,
  });

  @override
  State<CvViewScreen> createState() => _CvViewScreenState();
}

class _CvViewScreenState extends State<CvViewScreen> {
  late CvViewerMode _mode;

  // ✅ для тестов без логина
  static const bool kBypassAuthForDev = true;
  static const String kDevUid = 'dev';

  @override
  void initState() {
    super.initState();
    _mode = widget.startEditing
        ? CvViewerMode.ownerEdit
        : CvViewerMode.ownerView;
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _uidOrDev() {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null) return authUid;
    return (widget.testMode && kBypassAuthForDev) ? kDevUid : '';
  }

  bool _isOwnerUid(String ownerUid) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) return ownerUid.isNotEmpty && ownerUid == myUid;

    // ✅ testMode без логина: считаем владельцем (чтобы работали кнопки “Редактировать/Готово”)
    return widget.testMode && kBypassAuthForDev;
  }

  DocumentReference<Map<String, dynamic>> _defaultRef(String uidOrDev) {
    return FirebaseFirestore.instance
        .collection(FirestorePaths.cvs)
        .doc(widget.cvId);
  }

  Future<void> _openEditSection(CvSection section) async {
    final stepId = switch (section) {
      CvSection.header => CvWizardStepIds.profile,
      CvSection.title => CvWizardStepIds.about,
      CvSection.about => CvWizardStepIds.about,
      CvSection.desiredJob => CvWizardStepIds.jobPreferences,
      CvSection.experience => CvWizardStepIds.experience,
      CvSection.education => CvWizardStepIds.education,
      CvSection.languages => CvWizardStepIds.languages,
      CvSection.computerSkills => CvWizardStepIds.computerSkills,
      CvSection.driving => CvWizardStepIds.drivingLicense,
    };

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CvWizardScreen(
          testMode: widget.testMode,
          initialStepId: stepId,
          existingCvId: widget.cvId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uidOrDev();
    if (uid.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            'Нужен вход',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    final ref = widget.refOverride ?? _defaultRef(uid);

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'CV',
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
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: ref.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (!snap.data!.exists) {
                    return const Center(child: Text('CV не найдено'));
                  }

                  final data = snap.data!.data() ?? <String, dynamic>{};

                  final ownerUid = _s(data['ownerUid']);
                  final isOwner =
                      !widget.forceReadOnly && _isOwnerUid(ownerUid);
                  final statusFooter = (widget.statusFooterText ?? '').trim();
                  final showStatusFooter = statusFooter.isNotEmpty;

                  return Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 170),
                        children: [
                          CvProfileView(
                            cvId: widget.cvId,
                            cv: data,
                            mode: isOwner ? _mode : CvViewerMode.employer,
                            showSensitiveContacts: isOwner,
                            onEditSection: _mode == CvViewerMode.ownerEdit
                                ? _openEditSection
                                : null,
                          ),
                          const SizedBox(height: 2),

                          // ✅ Предложения, привязанные к этому CV (как было)
                          if (!widget.forceReadOnly)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                              child: _OffersForCvBlock(
                                uid: uid,
                                cvId: widget.cvId,
                                testMode: widget.testMode,
                              ),
                            ),
                        ],
                      ),

                      // ✅ ВЛАДЕЛЕЦ: снизу кнопки “Редактировать / Готово”
                      if (isOwner)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: SafeArea(
                            minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                            child: _mode == CvViewerMode.ownerEdit
                                ? SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: OutlinedButton(
                                      onPressed: () => setState(
                                        () => _mode = CvViewerMode.ownerView,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: WorkaColors.fieldBorder,
                                          width: 1.2,
                                        ),
                                        backgroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Готово',
                                        style: TextStyle(
                                          color: WorkaColors.orange,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compact =
                                          constraints.maxWidth < 360;
                                      final actions = <Widget>[
                                        SizedBox(
                                          height: 56,
                                          child: ElevatedButton(
                                            onPressed: () => setState(
                                              () => _mode =
                                                  CvViewerMode.ownerEdit,
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  WorkaColors.orange,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                              ),
                                            ),
                                            child: const Text(
                                              'Редактировать',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 56,
                                          child: OutlinedButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                color: WorkaColors.fieldBorder,
                                                width: 1.2,
                                              ),
                                              backgroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                              ),
                                            ),
                                            child: const Text(
                                              'Готово',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: WorkaColors.orange,
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
                                            SizedBox(
                                              width: double.infinity,
                                              child: actions.first,
                                            ),
                                            const SizedBox(height: 10),
                                            SizedBox(
                                              width: double.infinity,
                                              child: actions.last,
                                            ),
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
                                  ),
                          ),
                        ),
                      if (!isOwner && showStatusFooter)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: SafeArea(
                            minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: WorkaColors.divider),
                              ),
                              child: Text(
                                statusFooter,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: WorkaColors.textGreyDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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

// =====================
// Offers (как было)
// =====================

class _OffersForCvBlock extends StatelessWidget {
  final String uid;
  final String cvId;
  final bool testMode;

  const _OffersForCvBlock({
    required this.uid,
    required this.cvId,
    required this.testMode,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.jobOffers)
          .where('type', isEqualTo: 'offer')
          .where('candidateOwnerId', isEqualTo: uid)
          .where('candidateCvId', isEqualTo: cvId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OffersListScreen(
                  testMode: testMode,
                  workerUid: uid,
                  cvId: cvId,
                ),
              ),
            ),
            child: const Text(
              'Пока нет предложений',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Предложения',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: WorkaColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            ...docs.map((d) {
              final m = d.data();
              final status = InteractionStatus.normalize(m['status']);
              final jobTitle = (m['jobTitle'] ?? 'Вакансия').toString();
              final company = (m['companyName'] ?? '').toString();

              final isNew = InteractionStatus.isFresh(status);
              final isViewed = InteractionStatus.isViewedLike(status);

              final statusColor = isNew
                  ? WorkaColors.orange
                  : (isViewed ? WorkaColors.blue : WorkaColors.textGreyDark);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: WorkaColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            jobTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: WorkaColors.textDark,
                            ),
                          ),
                        ),
                        Text(
                          _statusLabel(status),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                    if (company.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        company,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: WorkaColors.textGreyDark,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  static String _statusLabel(String s) {
    switch (InteractionStatus.normalize(s)) {
      case InteractionStatus.pending:
        return 'Отправлено';
      case InteractionStatus.viewed:
      case InteractionStatus.postponed:
        return 'Просмотрено';
      case InteractionStatus.accepted:
        return 'Принято';
      case InteractionStatus.rejected:
        return 'Отклонено';
      default:
        return '—';
    }
  }
}
