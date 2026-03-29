import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_paths.dart';
import '../theme/worka_colors.dart';
import '../theme/worka_ui_tokens.dart';

enum ResponsePerspective { candidate, employer }

class StatusUi {
  final Color? pillColor;
  final String? label;
  final bool showBell;

  const StatusUi({this.pillColor, this.label, this.showBell = false});
}

StatusUi resolveStatusUi(dynamic rawStatus) {
  final status = (rawStatus ?? 'sent').toString().trim().toLowerCase();
  switch (status) {
    case 'rejected':
      return const StatusUi(pillColor: Colors.red, label: 'Отклонено');
    case 'accepted':
      return const StatusUi(pillColor: WorkaColors.blue, label: 'Принято');
    case 'viewed':
      return const StatusUi();
    case 'postponed':
      return const StatusUi();
    case 'sent':
    case 'pending':
    default:
      return const StatusUi(showBell: true);
  }
}

class ResponseCard extends StatelessWidget {
  const ResponseCard({
    super.key,
    required this.data,
    required this.perspective,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final ResponsePerspective perspective;
  final VoidCallback onTap;
  static final Map<String, Map<String, dynamic>> _jobCache =
      <String, Map<String, dynamic>>{};
  static final Map<String, Map<String, dynamic>> _cvCache =
      <String, Map<String, dynamic>>{};

  static void clearCaches() {
    _jobCache.clear();
    _cvCache.clear();
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  Future<(String title, String subtitle)> _loadPresentation() async {
    final db = FirebaseFirestore.instance;
    final showJob = perspective == ResponsePerspective.candidate;

    if (showJob) {
      final jobId = _s(data['jobId']);
      final snapshotVacancy = (data['vacancySnapshot'] is Map)
          ? Map<String, dynamic>.from(data['vacancySnapshot'] as Map)
          : const <String, dynamic>{};
      if (snapshotVacancy.isNotEmpty) {
        final title = _s(snapshotVacancy['title'], fallback: 'Вакансия');
        final city = _s(
          snapshotVacancy['city'],
          fallback: _s(snapshotVacancy['locationCity']),
        );
        final country = _s(snapshotVacancy['country']);
        final subtitle = [city, country].where((e) => e.isNotEmpty).join(', ');
        return (title, subtitle);
      }
      if (jobId.isNotEmpty) {
        final cached = _jobCache[jobId];
        final m =
            cached ??
            (await db.collection(FirestorePaths.jobs).doc(jobId).get())
                .data() ??
            const <String, dynamic>{};
        if (cached == null && m.isNotEmpty) _jobCache[jobId] = m;
        final title = _s(m['title'], fallback: 'Вакансия');
        final city = _s(m['city']);
        final country = _s(m['country']);
        final subtitle = [city, country].where((e) => e.isNotEmpty).join(', ');
        return (title, subtitle);
      }
      return ('Вакансия', '');
    }

    final snapshotCandidate = (data['candidateSnapshot'] is Map)
        ? Map<String, dynamic>.from(data['candidateSnapshot'] as Map)
        : const <String, dynamic>{};
    if (snapshotCandidate.isNotEmpty) {
      final full = _s(
        snapshotCandidate['name'],
        fallback:
            '${_s(snapshotCandidate['firstName'])} ${_s(snapshotCandidate['lastName'])}'
                .trim(),
      );
      final subtitle = _s(
        snapshotCandidate['position'],
        fallback: _s(snapshotCandidate['email']),
      );
      return (full.isEmpty ? 'Кандидат' : full, subtitle);
    }

    final cvId = _s(data['candidateCvId'], fallback: _s(data['cvId']));
    if (cvId.isNotEmpty) {
      final cached = _cvCache[cvId];
      final m =
          cached ??
          (await db.collection(FirestorePaths.cvs).doc(cvId).get()).data() ??
          const <String, dynamic>{};
      if (cached == null && m.isNotEmpty) _cvCache[cvId] = m;
      final contacts = (m['contacts'] is Map<String, dynamic>)
          ? m['contacts'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final name = _s(
        contacts['name'],
        fallback: _s(m['name'], fallback: 'Кандидат'),
      );
      final desired = (m['desired'] is Map<String, dynamic>)
          ? m['desired'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final subtitle = _s(
        desired['position'],
        fallback: _s(m['title'], fallback: ''),
      );
      return (name, subtitle);
    }
    return ('Кандидат', '');
  }

  @override
  Widget build(BuildContext context) {
    final statusUi = resolveStatusUi(data['status']);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WorkaColors.cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: WorkaColors.divider.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow: WorkaUiShadows.card,
        ),
        child: FutureBuilder<(String title, String subtitle)>(
          future: _loadPresentation(),
          builder: (context, snap) {
            final title = snap.data?.$1 ?? '...';
            final subtitle = snap.data?.$2 ?? '';
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: WorkaColors.textDark,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WorkaColors.textGreyDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (statusUi.pillColor != null && statusUi.label != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusUi.pillColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusUi.label!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                if (statusUi.showBell)
                  const Icon(
                    Icons.notifications_active_rounded,
                    color: WorkaColors.orange,
                    size: 22,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
