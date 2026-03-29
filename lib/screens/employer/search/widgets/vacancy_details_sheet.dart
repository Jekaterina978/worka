import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:worka/screens/cv/widgets/cv_apply_sheet.dart';
import 'package:worka/repositories/notifications_repository.dart';
import 'package:worka/repositories/response_repository.dart';
import 'package:worka/services/favorites_bus.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:worka/widgets/vacancy_details_view.dart';
import 'package:worka/widgets/sent_overlay.dart';
import 'package:worka/widgets/vacancy_apply_entry_sheet.dart';

class VacancyDetailsSheet extends StatefulWidget {
  final String jobId;
  final bool asWorker;
  final bool isOwnerView;
  final bool testMode;
  final String? statusFooterText;

  const VacancyDetailsSheet({
    super.key,
    required this.jobId,
    this.asWorker = true,
    this.isOwnerView = false,
    this.testMode = true,
    this.statusFooterText,
  });

  static Future<void> open(
    BuildContext context, {
    required String jobId,
    bool asWorker = true,
    bool isOwnerView = false,
    bool testMode = true,
    String? statusFooterText,
  }) {
    final safeJobId = jobId.trim();
    if (safeJobId.isEmpty) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Не удалось открыть вакансию')),
      );
      return Future.value();
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: VacancyDetailsSheet(
          jobId: safeJobId,
          asWorker: asWorker,
          isOwnerView: isOwnerView,
          testMode: testMode,
          statusFooterText: statusFooterText,
        ),
      ),
    );
  }

  @override
  State<VacancyDetailsSheet> createState() => _VacancyDetailsSheetState();
}

class _VacancyDetailsSheetState extends State<VacancyDetailsSheet> {
  final _db = FirebaseFirestore.instance;

  static const String kDevUid = 'dev';

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  String _s(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    final t = v.toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _workerIdOrEmpty() {
    return AuthGuard.effectiveUidOrNull() ?? '';
  }

  String _workerOwnerKey() {
    return AuthGuard.effectiveUidOrNull() ?? '';
  }

  bool _isOwner(Map<String, dynamic> job) {
    final ownership = OwnershipResolver.vacancyOwnership(
      job,
      currentUserId: _workerOwnerKey().trim(),
    );
    return ownership.known && ownership.isOwner;
  }

  Future<bool> _openApplyFlow(Map<String, dynamic> job) async {
    try {
      final sent = await VacancyApplyEntrySheet.open(
        context,
        vacancy: job,
        onSendCvTap: () async {
          if (!AuthGuard.ensureSignedIn(context)) return false;
          final workerId = _workerIdOrEmpty();
          final workerOwnerKey = _workerOwnerKey();
          if (workerId.isEmpty) {
            _toast('Нужно войти по SMS');
            return false;
          }

          final picked = await CvApplySheet.open(
            context,
            testMode: widget.testMode,
          );
          if (picked == null) return false;

          debugPrint(
            'VacancyDetailsSheet apply save jobId=${widget.jobId} cvId=${picked.cvId}',
          );
          final employerUid = _s(
            job['ownerId'],
            fallback: _s(
              job['ownerKey'],
              fallback: _s(
                job['ownerUid'],
                fallback: widget.testMode ? kDevUid : '',
              ),
            ),
          );
          final duplicate = await ResponseRepository(_db).hasAppliedOnce(
            jobId: widget.jobId,
            candidateOwnerId: workerOwnerKey,
            candidateCvId: picked.cvId,
          );
          if (duplicate) {
            if (!mounted) return false;
            _toast('Отклик уже отправлен');
            return false;
          }

          final applicationId =
              '${widget.jobId}_${workerOwnerKey}_${picked.cvId}_apply';
          await ResponseRepository(_db).createApply(
            jobId: widget.jobId,
            jobOwnerId: employerUid,
            candidateCvId: picked.cvId,
            candidateOwnerId: workerOwnerKey,
          );
          debugPrint(
            'VacancyDetailsSheet application saved ${FirestorePaths.applications}/$applicationId',
          );
          if (employerUid.isNotEmpty) {
            await NotificationsRepository(_db).createItem(
              toUserId: employerUid,
              fromUserId: workerOwnerKey,
              type: 'response_received',
              kind: 'response',
              entityId: applicationId,
              payload: {
                'vacancyId': widget.jobId,
                'cvId': picked.cvId,
                'shortText': 'Новый отклик на вакансию',
              },
            );
          }

          if (!mounted) return false;
          FavoritesBus.notify();
          await showSentOverlay(context, 'Отклик отправлен');
          return true;
        },
      );
      if (sent && mounted) Navigator.pop(context);
      return sent;
    } catch (e) {
      debugPrint('VacancyDetailsSheet _openApplyFlow error: $e');
      _toast('Ошибка сохранения: $e');
      if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
        _toast(FirebaseDebugDiagnostics.permissionHintText());
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeJobId = widget.jobId.trim();
    if (safeJobId.isEmpty) {
      return const Material(
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Не удалось открыть вакансию',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final workerId = _workerIdOrEmpty();
    final appliedStream = workerId.isEmpty
        ? Stream<bool>.value(false)
        : _db
              .collection(FirestorePaths.applications)
              .where('applicantId', isEqualTo: workerId)
              .where('vacancyId', isEqualTo: widget.jobId)
              .where(
                'status',
                whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
              )
              .limit(1)
              .snapshots()
              .map((s) {
                if (kDebugMode) {
                  debugPrint(
                    'VacancyDetailsSheet applied badge uid=$workerId vacancyId=${widget.jobId} count=${s.docs.length}',
                  );
                }
                return s.docs.isNotEmpty;
              });

    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection(FirestorePaths.vacancies)
              .doc(safeJobId)
              .snapshots(),
          builder: (context, jobSnap) {
            if (jobSnap.hasError) {
              debugPrint(
                'VacancyDetailsSheet job stream error: ${jobSnap.error}',
              );
              final permissionDenied =
                  FirebaseDebugDiagnostics.isPermissionDenied(jobSnap.error);
              return _errorState(
                'Ошибка загрузки вакансии: ${jobSnap.error}',
                showRulesHint: permissionDenied && widget.testMode,
              );
            }
            if (!jobSnap.hasData) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final doc = jobSnap.data!;
            if (!doc.exists) {
              return const Center(child: Text('Вакансия не найдена'));
            }

            final job = doc.data() ?? <String, dynamic>{};
            final data = VacancyDetailsViewData.fromJobMap(job);
            final isOwner = widget.isOwnerView || _isOwner(job);

            return StreamBuilder<bool>(
              stream: appliedStream,
              builder: (context, respSnap) {
                if (respSnap.hasError) {
                  debugPrint(
                    'VacancyDetailsSheet hasApplied stream error: ${respSnap.error}',
                  );
                  return _errorState(
                    'Ошибка загрузки откликов: ${respSnap.error}',
                  );
                }
                final alreadyApplied = respSnap.data ?? false;
                final statusFooter = (widget.statusFooterText ?? '').trim();
                final showStatusFooter = statusFooter.isNotEmpty;

                final Widget? bottomActions = isOwner
                    ? Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: WorkaColors.blue,
                                    width: 1.2,
                                  ),
                                  foregroundColor: WorkaColors.blue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: const Text(
                                  'Редактировать',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: WorkaColors.blue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: const Text(
                                  'Готово',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : showStatusFooter
                    ? Container(
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
                      )
                    : (widget.asWorker
                          ? (alreadyApplied
                                ? Container(
                                    width: double.infinity,
                                    height: 56,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: WorkaColors.divider,
                                      ),
                                    ),
                                    child: const Text(
                                      'Отклик отправлен',
                                      style: TextStyle(
                                        color: WorkaColors.textGreyDark,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  )
                                : SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: () => _openApplyFlow(job),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: WorkaColors.orange,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Взять работу',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ))
                          : null);

                return VacancyDetailsView(
                  data: data,
                  actionsMode: isOwner
                      ? VacancyDetailsActionsMode.employerManage
                      : (widget.asWorker
                            ? VacancyDetailsActionsMode.workerApply
                            : VacancyDetailsActionsMode.none),
                  bottomActions: bottomActions,
                  onBack: () => Navigator.pop(context),
                  onClose: () => Navigator.pop(context),
                  actionHeight: 56,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _errorState(String message, {bool showRulesHint = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (showRulesHint) ...[
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
}
