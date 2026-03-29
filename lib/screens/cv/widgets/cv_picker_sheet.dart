library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/features/monetization/pricing.dart';
import 'package:worka/screens/cv/cv_wizard_screen.dart';
import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/repositories/cv_repository.dart';

class CvPickResult {
  final String cvId;
  final String title;

  const CvPickResult({required this.cvId, required this.title});
}

/// BottomSheet для выбора CV:
/// - Источник: full CV (cvs/cvs_test)
/// - Фильтр по ownerUid текущего пользователя (или dev в test mode)
/// - Кнопка "Создать новое CV" только если count < workerFreeActiveCvLimit
class CvPickerSheet extends StatelessWidget {
  final bool allowCreate;
  final int maxCv;
  final String? title;

  /// Если хочешь принудительно показать test-коллекцию
  final bool forceTestCollection;

  const CvPickerSheet({
    super.key,
    this.allowCreate = true,
    this.maxCv = MonetizationPricing.workerFreeActiveCvLimit,
    this.title,
    this.forceTestCollection = false,
  });

  static Future<CvPickResult?> open(
    BuildContext context, {
    bool allowCreate = true,
    int maxCv = MonetizationPricing.workerFreeActiveCvLimit,
    String? title,
    bool forceTestCollection = false,
  }) {
    return showModalBottomSheet<CvPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: CvPickerSheet(
            allowCreate: allowCreate,
            maxCv: maxCv,
            title: title,
            forceTestCollection: forceTestCollection,
          ),
        ),
      ),
    );
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final ownerUid = AuthGuard.effectiveUidOrNull() ?? '';

    final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> stream;
    if (ownerUid.isEmpty) {
      stream = Stream.value(
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
    } else {
      stream = CvRepository(db)
          .watchMyCvDocs(testMode: forceTestCollection, userId: ownerUid)
          .map((docs) {
            debugPrint(
              'CvPickerSheet stream ownerUid=$ownerUid total=${docs.length}',
            );
            return docs;
          });
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title ?? 'Выберите CV',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: WorkaColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  debugPrint('CvPickerSheet stream error: ${snap.error}');
                  final permissionDenied =
                      FirebaseDebugDiagnostics.isPermissionDenied(snap.error);
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ошибка загрузки CV: ${snap.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: WorkaColors.textGreyDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (permissionDenied) ...[
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
                  );
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final docs = [...snap.data!];
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

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (docs.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: WorkaColors.fieldBorder),
                        ),
                        child: const Text(
                          'У вас пока нет CV.\nСоздайте новое, чтобы откликнуться.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: WorkaColors.textGreyDark,
                            height: 1.25,
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final d = docs[i];
                          final m = d.data();

                          final t = _s(
                            m['title'],
                            fallback: _s(m['profession'], fallback: 'CV'),
                          );
                          final subtitle = _s(
                            m['summary'],
                            fallback: _s(m['about'], fallback: 'Без описания'),
                          );

                          return _CvTile(
                            title: t,
                            subtitle: subtitle,
                            onTap: () => Navigator.pop(
                              context,
                              CvPickResult(cvId: d.id, title: t),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 12),
                    if (allowCreate)
                      _CreateButton(
                        enabled: docs.length < maxCv,
                        text: docs.length < maxCv
                            ? 'Создать новое CV'
                            : 'Лимит: максимум $maxCv CV',
                        onTap: docs.length < maxCv
                            ? () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    // ✅ чтобы CV создавалось в тестовом режиме
                                    builder: (_) =>
                                        const CvWizardScreen(testMode: true),
                                  ),
                                );
                              }
                            : null,
                      ),
                    const SizedBox(height: 6),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CvTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CvTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WorkaColors.fieldBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, color: WorkaColors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: WorkaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: WorkaColors.textGreyDark,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, color: WorkaColors.textGreyDark),
          ],
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  final bool enabled;
  final String text;
  final VoidCallback? onTap;

  const _CreateButton({
    required this.enabled,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: WorkaColors.fieldBorder, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: enabled ? WorkaColors.textDark : WorkaColors.textGrey,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
