import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/services/guest_uid_service.dart';
import 'package:worka/screens/cv/cv_wizard_screen.dart';
import 'package:worka/screens/cv/widgets/cv_picker_sheet.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/apply_vacancy_identity_resolver.dart';
import 'package:worka/repositories/response_repository.dart';
import 'package:worka/widgets/vacancy_apply_entry_sheet.dart';
import 'package:worka/widgets/sent_overlay.dart';
import 'package:worka/services/runtime_flow_logger.dart';
import 'package:worka/theme/worka_colors.dart';

import '../widgets/worka_header.dart';

class VacancyScreen extends StatefulWidget {
  final String jobId;

  const VacancyScreen({super.key, required this.jobId});

  @override
  State<VacancyScreen> createState() => _VacancyScreenState();
}

class _VacancyScreenState extends State<VacancyScreen> {
  bool _applied = false;
  bool _applyBusy = false;

  static String _trim(dynamic v) => (v ?? '').toString().trim();

  static Map<String, dynamic> _vacancyPayloadFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = Map<String, dynamic>.from(doc.data() ?? {});
    final id = doc.id;
    if (_trim(data['firestoreId']).isEmpty) data['firestoreId'] = id;
    if (_trim(data['firestore_id']).isEmpty) data['firestore_id'] = id;
    if (_trim(data['id']).isEmpty) data['id'] = id;
    return data;
  }

  static String _vacancyOwnerType(Map<String, dynamic> job) {
    final t = _trim(job['ownerType']).toLowerCase();
    if (t.isEmpty) return 'personal';
    if (t == 'company') return 'business';
    return t;
  }

  /// Canonical apply send — matches `UnifiedVacancyActions.quickApplyToJob` backend path.
  Future<bool> _sendApplyWithCv({
    required BuildContext context,
    required String jobId,
    required Map<String, dynamic> jobData,
  }) async {
    final db = FirebaseFirestore.instance;
    try {
      var uid = (AuthGuard.effectiveUidOrNull() ?? '').trim();
      if (uid.isEmpty) {
        uid = await GuestUidService.getOrCreate();
        AuthGuard.setCachedGuestUid(uid);
      }
      if (uid.isEmpty) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'auth_missing',
          'source': 'vacancy_screen',
        });
        if (!context.mounted) return false;
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const CvWizardScreen(testMode: false)),
        );
        return false;
      }

      final cvSnap = await db
          .collection(FirestorePaths.cvs)
          .where('ownerId', isEqualTo: uid)
          .get();
      RuntimeFlowLogger.mark('APPLY_CV_LIST_QUERY', <String, Object?>{
        'uid': uid,
        'source': 'vacancy_screen',
      });
      final cvs = cvSnap.docs
          .where((d) => (d.data()['isDeleted'] ?? false) != true)
          .toList();
      RuntimeFlowLogger.mark('APPLY_CV_LIST_RESULT', <String, Object?>{
        'count': cvs.length,
        'source': 'vacancy_screen',
      });

      if (cvs.isEmpty) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'cv_list_empty',
          'uid': uid,
          'source': 'vacancy_screen',
        });
        if (!context.mounted) return false;
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const CvWizardScreen(testMode: false)),
        );
        return false;
      }

      if (!context.mounted) return false;
      final picked = await CvPickerSheet.open(
        context,
        title: 'Выберите CV',
        allowCreate: true,
        forceTestCollection: false,
      );
      if (picked == null || picked.cvId.trim().isEmpty) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED_NO_CV', <String, Object?>{
          'jobId': jobId,
          'vacancyId': jobId,
          'userId': uid,
          'sourceScreen': 'vacancy_screen',
        });
        return false;
      }
      final selectedCvId = picked.cvId.trim();
      RuntimeFlowLogger.mark('APPLY_CV_SELECTED', <String, Object?>{
        'cvId': selectedCvId,
        'source': 'vacancy_screen',
      });

      final ownerId = OwnershipResolver.vacancyOwnerIdFromMap(jobData);
      if (ownerId.isEmpty) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'vacancy_owner_missing',
          'vacancyId': jobId,
          'source': 'vacancy_screen',
        });
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось определить владельца вакансии'),
          ),
        );
        return false;
      }

      RuntimeFlowLogger.mark('APPLY_PRECHECK_START', <String, Object?>{
        'source': 'vacancy_screen',
      });
      final resolvedIdentity = ApplyVacancyIdentityResolver.resolve(
        vacancyId: jobId,
        snapshot: jobData,
      );
      ApplyVacancyIdentityResolver.debugLog(
        identity: resolvedIdentity,
        vacancyId: jobId,
        snapshot: jobData,
      );
      if (!resolvedIdentity.isResolved) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'job_id_unresolved',
          'vacancyId': jobId,
          'source': 'vacancy_screen',
        });
        RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
          'ok': false,
          'reason': 'job_id_unresolved',
        });
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Вакансия не синхронизирована. Отклик пока нельзя отправить.',
            ),
          ),
        );
        return false;
      }
      RuntimeFlowLogger.mark('APPLY_PRECHECK_RESULT', <String, Object?>{
        'ok': true,
        'reason': 'ready_to_send',
      });

      final applyResult = await ResponseRepository(db).createApply(
        jobId: jobId,
        jobOwnerId: ownerId,
        candidateCvId: selectedCvId,
        candidateOwnerId: uid,
        vacancyOwnerType: _vacancyOwnerType(jobData),
        applicantProfileType: AuthGuard.isGuestLikeUid(uid)
            ? 'guest'
            : (AppMode.currentMode == AccountMode.business
                  ? 'business'
                  : 'personal'),
        candidateSnapshot: AuthGuard.isGuestLikeUid(uid)
            ? const <String, dynamic>{
                'ownerType': 'guest',
                'isRegistered': false,
                'label': 'Пользователь незарегистрирован',
              }
            : const <String, dynamic>{},
        vacancySnapshot: Map<String, dynamic>.from(jobData),
      );

      if (applyResult.isAlreadyApplied) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CV уже отправлено')),
        );
        return false;
      }
      if (applyResult.isBlocked || applyResult.isFailed) {
        if (!context.mounted) return false;
        final message = applyResult.reason == 'job_id_unresolved'
            ? 'Вакансия не синхронизирована. Отклик пока нельзя отправить.'
            : 'Не удалось отправить отклик. Попробуйте ещё раз.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return false;
      }

      if (!context.mounted) return false;
      await showSentOverlay(context, 'Отклик отправлен');
      return true;
    } catch (e) {
      if ('$e'.contains('job_id_unresolved')) {
        RuntimeFlowLogger.mark('APPLY_BLOCKED', <String, Object?>{
          'reason': 'job_id_unresolved',
          'vacancyId': jobId,
          'source': 'vacancy_screen',
        });
      }
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$e'.contains('job_id_unresolved')
                ? 'Вакансия не синхронизирована. Отклик пока нельзя отправить.'
                : 'Не удалось отправить отклик. Попробуйте ещё раз.',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _onTapApply(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (_applied || _applyBusy) return;
    final vacancyMap = _vacancyPayloadFromDoc(doc);
    setState(() => _applyBusy = true);
    try {
      final ok = await VacancyApplyEntrySheet.open(
        context,
        vacancy: vacancyMap,
        onSendCvTap: () => _sendApplyWithCv(
          context: context,
          jobId: widget.jobId,
          jobData: vacancyMap,
        ),
      );
      if (!mounted) return;
      if (ok == true) setState(() => _applied = true);
    } finally {
      if (mounted) setState(() => _applyBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobRef = FirebaseFirestore.instance.collection('jobs').doc(widget.jobId);

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Вакансия',
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
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: jobRef.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Ошибка: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final doc = snap.data!;
                  if (!doc.exists) {
                    return const Center(child: Text('Вакансия не найдена'));
                  }

                  final data = doc.data() ?? {};

                  String s(dynamic v, {String fallback = ''}) {
                    if (v == null) return fallback;
                    final t = v.toString().trim();
                    return t.isEmpty ? fallback : t;
                  }

                  final title = s(data['title'], fallback: 'Без названия');
                  final companyName = s(
                    data['companyName'],
                    fallback: 'Компания',
                  );
                  final city = s(data['city'], fallback: 'Локация не указана');

                  final salary = s(
                    data['salary'],
                    fallback: 'Зарплата не указана',
                  );

                  final category = s(
                    data['category'],
                    fallback: 'Категория не указана',
                  );
                  final type = s(data['type'], fallback: 'Тип не указан');

                  final salaryFromNum = data['salaryFromNum'];
                  final salaryFromText = (salaryFromNum is num)
                      ? 'от ${salaryFromNum.toInt()}'
                      : null;

                  final description = s(data['description'], fallback: '');
                  final requirements = s(data['requirements'], fallback: '');

                  final isPremium = (data['isPremium'] ?? false) == true;
                  final vacancyOwnership =
                      OwnershipResolver.vacancyViewerOwnership(data);
                  final isOwnerView =
                      vacancyOwnership.known && vacancyOwnership.isOwner;

                  return Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                        children: [
                          _HeaderCard(
                            title: title,
                            companyName: companyName,
                            city: city,
                            salary: salary,
                            isPremium: isPremium,
                          ),
                          const SizedBox(height: 12),

                          _InfoCard(
                            items: [
                              _InfoItem(
                                icon: Icons.category_outlined,
                                label: 'Категория',
                                value: category,
                              ),
                              _InfoItem(
                                icon: Icons.work_outline,
                                label: 'Тип',
                                value: type,
                              ),
                              _InfoItem(
                                icon: Icons.payments_outlined,
                                label: 'Зарплата',
                                value: salaryFromText ?? salary,
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          if (description.isNotEmpty) ...[
                            _SectionCard(title: 'Описание', text: description),
                            const SizedBox(height: 12),
                          ],

                          if (requirements.isNotEmpty) ...[
                            _SectionCard(
                              title: 'Требования',
                              text: requirements,
                            ),
                            const SizedBox(height: 12),
                          ],

                          _CompanyCard(
                            companyName: companyName,
                            onOpen: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Профиль компании'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      if (!isOwnerView)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: SafeArea(
                            minimum: const EdgeInsets.all(16),
                            child: SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: (_applied || _applyBusy)
                                    ? null
                                    : () => _onTapApply(context, doc),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _applied
                                      ? WorkaColors.blue
                                      : WorkaColors.orange,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: _applied
                                      ? WorkaColors.blue
                                      : WorkaColors.orange,
                                  disabledForegroundColor: Colors.white,
                                ),
                                child: _applyBusy
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _applied ? 'Отклик отправлен' : 'Откликнуться',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
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

class _HeaderCard extends StatelessWidget {
  final String title;
  final String companyName;
  final String city;
  final String salary;
  final bool isPremium;

  const _HeaderCard({
    required this.title,
    required this.companyName,
    required this.city,
    required this.salary,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isPremium)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFFFD8B3)),
                    ),
                    child: const Text(
                      'Premium',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFF7A00),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(Icons.apartment, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    companyName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(city)),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    salary,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  _InfoItem({required this.icon, required this.label, required this.value});
}

class _InfoCard extends StatelessWidget {
  final List<_InfoItem> items;

  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: items
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(e.icon, size: 18),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 90,
                        child: Text(
                          e.label,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.value,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _SectionCard extends StatefulWidget {
  final String title;
  final String text;

  const _SectionCard({required this.title, required this.text});

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final maxLines = expanded ? 999 : 7;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              widget.text,
              maxLines: maxLines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? 'Скрыть' : 'Показать больше'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  final String companyName;
  final VoidCallback onOpen;

  const _CompanyCard({required this.companyName, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.apartment),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                companyName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton(onPressed: onOpen, child: const Text('Профиль')),
          ],
        ),
      ),
    );
  }
}
