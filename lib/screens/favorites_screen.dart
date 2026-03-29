import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/worka_colors.dart';

import '../common/favorites_bus.dart'; // ✅ ВАЖНО: новый путь
import 'vacancy_details_screen.dart';

class FavoritesGoHomeNotification extends Notification {}

enum FavoritesTab { vacancies, candidates }
enum FavoritesEntry { worker, employer }

class FavoritesScreen extends StatefulWidget {
  final FavoritesEntry entry;
  final bool embeddedInShell;

  const FavoritesScreen({
    super.key,
    this.entry = FavoritesEntry.worker,
    this.embeddedInShell = false,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late FavoritesTab _tab;

  StreamSubscription<void>? _sub;
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();

    // ✅ работодатель по умолчанию на "Кандидаты"
    _tab = widget.entry == FavoritesEntry.employer ? FavoritesTab.candidates : FavoritesTab.vacancies;

    _sub = FavoritesBus.stream.listen((_) {
      if (!mounted) return;
      setState(() => _reloadToken++);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _clearCurrentTab() async {
    final uid = _auth.currentUser?.uid;

    if (_tab == FavoritesTab.vacancies) {
      // local
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_LocalVacancyFavoritesState.prefsKey);

      // remote
      if (uid != null) {
        final col = _db.collection('users').doc(uid).collection('favorites');
        final snap = await col.get();
        final batch = _db.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    } else {
      // candidates
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_LocalCandidateFavoritesState.prefsKey);
      await prefs.remove(_LocalCandidateFavoritesState.prefsKeyLegacy);

      if (uid != null) {
        final col = _db.collection('users').doc(uid).collection('favoritesCandidates');
        final snap = await col.get();
        final batch = _db.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }

    FavoritesBus.notify();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Очищено'), backgroundColor: WorkaColors.textDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;

    // ✅ СЛАЙДЕР ДОЛЖЕН БЫТЬ ВСЕГДА (как ты просила)
    final canSeeCandidates = widget.entry == FavoritesEntry.employer;

    final Widget body = (_tab == FavoritesTab.vacancies)
        ? (uid == null
            ? _LocalVacancyFavorites(key: ValueKey('vac_local_$_reloadToken'), db: _db)
            : _RemoteVacancyFavorites(db: _db, uid: uid))
        : (uid == null
            ? _LocalCandidateFavorites(
                key: ValueKey('cand_local_$_reloadToken'),
                db: _db,
                entry: widget.entry,
              )
            : _RemoteCandidateFavorites(db: _db, uid: uid, entry: widget.entry));

    return Scaffold(
      backgroundColor: WorkaColors.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: WorkaColors.bg,
        surfaceTintColor: WorkaColors.bg,
        centerTitle: true,
        title: const Text(
          'Избранное',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: WorkaColors.textDark),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),

          // ✅ всегда рисуем слайдер
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SegmentSwitch(
              left: 'Вакансии',
              right: 'Кандидаты',
              leftSelected: _tab == FavoritesTab.vacancies,
              onLeft: () => setState(() => _tab = FavoritesTab.vacancies),
              onRight: () => setState(() => _tab = FavoritesTab.candidates),
              // если работник — кандидатов показывать нельзя
              rightDisabled: !canSeeCandidates,
            ),
          ),
          const SizedBox(height: 12),

          Expanded(child: body),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _clearCurrentTab,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WorkaColors.orange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text('Очистить', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ======================
/// VACANCIES — REMOTE (logged in)
/// users/{uid}/favorites/{jobId}
/// ======================
class _RemoteVacancyFavorites extends StatelessWidget {
  final FirebaseFirestore db;
  final String uid;

  const _RemoteVacancyFavorites({required this.db, required this.uid});

  @override
  Widget build(BuildContext context) {
    final favStream = db.collection('users').doc(uid).collection('favorites').snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: favStream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Ошибка: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final favDocs = snap.data!.docs.toList();
        favDocs.sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          final da = (ta is Timestamp) ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final dbb = (tb is Timestamp) ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          return dbb.compareTo(da);
        });

        if (favDocs.isEmpty) {
          return const _EmptyState(
            title: 'Избранное пустое',
            subtitle: 'Нажимайте на ⭐ в вакансиях, чтобы сохранять.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          itemCount: favDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final fav = favDocs[i];
            final data = fav.data();
            final jobId = fav.id;

            final hasInline = (data['title'] != null) ||
                (data['city'] != null) ||
                (data['salaryText'] != null) ||
                (data['salary'] != null);

            if (hasInline) {
              return _VacancyCard(
                title: _s(data['title'], fallback: 'Вакансия'),
                location: _formatLocation(data['city'], data['country']),
                salary: _s(data['salaryText'] ?? data['salary'], fallback: 'Зарплата не указана'),
                onOpen: () => _openDetails(context, jobId),
                onRemove: () => _removeFavorite(jobId: jobId),
              );
            }

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: db.collection('jobs').doc(jobId).get(),
              builder: (context, jobSnap) {
                if (!jobSnap.hasData) return const _VacancyCardSkeleton();

                final job = jobSnap.data!;
                if (!job.exists) {
                  return _VacancyCard(
                    title: 'Вакансия недоступна',
                    location: '—',
                    salary: '—',
                    onOpen: () => _openDetails(context, jobId),
                    onRemove: () => _removeFavorite(jobId: jobId),
                  );
                }

                final m = job.data() ?? {};
                return _VacancyCard(
                  title: _s(m['title'], fallback: 'Вакансия'),
                  location: _formatLocation(m['city'], m['country']),
                  salary: _s(m['salaryText'] ?? m['salary'], fallback: 'Зарплата не указана'),
                  onOpen: () => _openDetails(context, jobId),
                  onRemove: () => _removeFavorite(jobId: jobId),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _removeFavorite({required String jobId}) async {
    await db.collection('users').doc(uid).collection('favorites').doc(jobId).delete();
    FavoritesBus.notify();
  }

  void _openDetails(BuildContext context, String jobId) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => VacancyDetailsScreen(jobId: jobId)));
  }
}

/// ======================
/// VACANCIES — LOCAL (not logged in)
/// prefs: worka_favorites_job_ids
/// ======================
class _LocalVacancyFavorites extends StatefulWidget {
  final FirebaseFirestore db;
  const _LocalVacancyFavorites({super.key, required this.db});

  @override
  State<_LocalVacancyFavorites> createState() => _LocalVacancyFavoritesState();
}

class _LocalVacancyFavoritesState extends State<_LocalVacancyFavorites> {
  static const String prefsKey = 'worka_favorites_job_ids';

  bool _loading = true;
  List<String> _ids = [];
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _jobs = [];

  @override
  void initState() {
    super.initState();
    _loadLocalAndFetch();
  }

  Future<void> _loadLocalAndFetch() async {
    setState(() {
      _loading = true;
      _jobs.clear();
    });

    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(prefsKey) ?? const <String>[]).toList();
    _ids = ids;

    if (ids.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    final chunks = _chunk(ids, 10);
    for (final chunk in chunks) {
      final snap = await widget.db.collection('jobs').where(FieldPath.documentId, whereIn: chunk).get();
      _jobs.addAll(snap.docs);
    }

    _jobs.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _removeLocal(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    _ids.remove(jobId);
    await prefs.setStringList(prefsKey, _ids);

    setState(() {
      _jobs.removeWhere((d) => d.id == jobId);
    });

    FavoritesBus.notify();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_ids.isEmpty) {
      return const _EmptyState(
        title: 'Избранное пустое',
        subtitle: 'Нажимайте на ⭐ в вакансиях, чтобы сохранять.',
      );
    }

    if (_jobs.isEmpty) {
      return const _EmptyState(
        title: 'Нет доступных вакансий',
        subtitle: 'Похоже, сохранённые вакансии удалены или скрыты.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      itemCount: _jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final d = _jobs[i];
        final m = d.data();

        return _VacancyCard(
          title: _s(m['title'], fallback: 'Вакансия'),
          location: _formatLocation(m['city'], m['country']),
          salary: _s(m['salaryText'] ?? m['salary'], fallback: 'Зарплата не указана'),
          onOpen: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VacancyDetailsScreen(jobId: d.id)),
          ),
          onRemove: () => _removeLocal(d.id),
        );
      },
    );
  }
}

/// ======================
/// CANDIDATES — REMOTE (logged in)
/// users/{uid}/favoritesCandidates/{candidateId}
/// ======================
class _RemoteCandidateFavorites extends StatelessWidget {
  final FirebaseFirestore db;
  final String uid;
  final FavoritesEntry entry;

  const _RemoteCandidateFavorites({
    required this.db,
    required this.uid,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    if (entry != FavoritesEntry.employer) {
      return const _EmptyState(
        title: 'Избранные кандидаты',
        subtitle: 'Кандидаты появляются здесь только у работодателя.',
      );
    }

    final stream = db.collection('users').doc(uid).collection('favoritesCandidates').snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Ошибка: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final favDocs = snap.data!.docs.toList();
        favDocs.sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          final da = (ta is Timestamp) ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final dbb = (tb is Timestamp) ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          return dbb.compareTo(da);
        });

        if (favDocs.isEmpty) {
          return const _EmptyState(
            title: 'Пока пусто',
            subtitle: 'Добавляйте кандидатов в избранное через ⭐ в поиске кандидатов.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          itemCount: favDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final fav = favDocs[i];
            final data = fav.data();
            final candidateId = fav.id;

            final hasInline = (data['name'] != null) || (data['profession'] != null) || (data['city'] != null);

            if (hasInline) {
              return _CandidateCard(
                name: _s(data['name'], fallback: 'Кандидат'),
                profession: _s(data['profession'], fallback: ''),
                location: _formatLocation(data['city'], data['country']),
                onRemove: () => _remove(candidateId),
                onOpen: () => _openCandidateStub(context),
              );
            }

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: db.collection('candidates').doc(candidateId).get(),
              builder: (context, candSnap) {
                if (!candSnap.hasData) return const _CandidateCardSkeleton();

                final cand = candSnap.data!;
                if (!cand.exists) {
                  return _CandidateCard(
                    name: 'Кандидат недоступен',
                    profession: '',
                    location: '—',
                    onRemove: () => _remove(candidateId),
                    onOpen: () => _openCandidateStub(context),
                  );
                }

                final c = cand.data() ?? {};
                return _CandidateCard(
                  name: _s(c['name'], fallback: 'Кандидат'),
                  profession: _s(c['profession'], fallback: ''),
                  location: _formatLocation(c['city'], c['country']),
                  onRemove: () => _remove(candidateId),
                  onOpen: () => _openCandidateStub(context),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _remove(String id) async {
    await db.collection('users').doc(uid).collection('favoritesCandidates').doc(id).delete();
    FavoritesBus.notify();
  }

  void _openCandidateStub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Открытие карточки кандидата можно подключить позже'),
        backgroundColor: WorkaColors.textDark,
      ),
    );
  }
}

/// ======================
/// CANDIDATES — LOCAL (not logged in)
/// prefs: worka_favorites_candidate_ids (stringList)
/// legacy: worka_favorites_candidate_ids (string json)
/// ======================
class _LocalCandidateFavorites extends StatefulWidget {
  final FirebaseFirestore db;
  final FavoritesEntry entry;

  const _LocalCandidateFavorites({super.key, required this.db, required this.entry});

  @override
  State<_LocalCandidateFavorites> createState() => _LocalCandidateFavoritesState();
}

class _LocalCandidateFavoritesState extends State<_LocalCandidateFavorites> {
  static const String prefsKey = 'worka_favorites_candidate_ids';
  static const String prefsKeyLegacy = 'worka_favorites_candidate_ids';

  bool _loading = true;
  List<String> _ids = [];
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _cands = [];

  @override
  void initState() {
    super.initState();
    _loadLocalAndFetch();
  }

  Future<void> _loadLocalAndFetch() async {
    setState(() {
      _loading = true;
      _cands.clear();
    });

    final prefs = await SharedPreferences.getInstance();

    final list = prefs.getStringList(prefsKey);
    if (list != null) {
      _ids = list.toList();
    } else {
      final raw = prefs.getString(prefsKeyLegacy);
      if (raw != null) {
        try {
          final decoded = (jsonDecode(raw) as List).cast<String>();
          _ids = decoded.toList();
        } catch (_) {
          _ids = [];
        }
      }
    }

    if (_ids.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    final chunks = _chunk(_ids, 10);
    for (final chunk in chunks) {
      final snap = await widget.db.collection('candidates').where(FieldPath.documentId, whereIn: chunk).get();
      _cands.addAll(snap.docs);
    }

    _cands.sort((a, b) => _ids.indexOf(a.id).compareTo(_ids.indexOf(b.id)));

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _removeLocal(String id) async {
    final prefs = await SharedPreferences.getInstance();
    _ids.remove(id);

    await prefs.setStringList(prefsKey, _ids);
    await prefs.setString(prefsKeyLegacy, jsonEncode(_ids)); // legacy compat

    setState(() {
      _cands.removeWhere((d) => d.id == id);
    });

    FavoritesBus.notify();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entry != FavoritesEntry.employer) {
      return const _EmptyState(
        title: 'Избранные кандидаты',
        subtitle: 'Кандидаты появляются здесь только у работодателя.',
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_ids.isEmpty) {
      return const _EmptyState(
        title: 'Пока пусто',
        subtitle: 'Добавляйте кандидатов в избранное через ⭐ в поиске кандидатов.',
      );
    }

    if (_cands.isEmpty) {
      return const _EmptyState(
        title: 'Нет доступных кандидатов',
        subtitle: 'Похоже, сохранённые кандидаты удалены или скрыты.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      itemCount: _cands.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final d = _cands[i];
        final c = d.data();

        return _CandidateCard(
          name: _s(c['name'], fallback: 'Кандидат'),
          profession: _s(c['profession'], fallback: ''),
          location: _formatLocation(c['city'], c['country']),
          onRemove: () => _removeLocal(d.id),
          onOpen: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Открытие карточки кандидата можно подключить позже'),
                backgroundColor: WorkaColors.textDark,
              ),
            );
          },
        );
      },
    );
  }
}

/// ======================
/// UI
/// ======================
class _SegmentSwitch extends StatelessWidget {
  final String left;
  final String right;
  final bool leftSelected;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  /// ✅ если true — правая вкладка видна, но не кликается
  final bool rightDisabled;

  const _SegmentSwitch({
    required this.left,
    required this.right,
    required this.leftSelected,
    required this.onLeft,
    required this.onRight,
    this.rightDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: WorkaColors.sliderGrey,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            alignment: leftSelected ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: (MediaQuery.of(context).size.width - 32) / 2,
              height: 52,
              decoration: BoxDecoration(
                color: WorkaColors.blue,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onLeft,
                  child: Center(
                    child: Text(
                      left,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: leftSelected ? Colors.white : WorkaColors.textGreyDark,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: rightDisabled ? null : onRight,
                  child: Center(
                    child: Text(
                      right,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: !leftSelected ? Colors.white : WorkaColors.textGreyDark,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== Cards etc (без изменений) =====

class _VacancyCard extends StatelessWidget {
  final String title;
  final String location;
  final String salary;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _VacancyCard({
    required this.title,
    required this.location,
    required this.salary,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WorkaColors.divider),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.06),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: -4,
              child: IconButton(
                tooltip: 'Удалить из избранного',
                onPressed: onRemove,
                icon: Icon(Icons.star_rounded, color: WorkaColors.starYellow),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: WorkaColors.textDark)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: WorkaColors.textGrey),
                      const SizedBox(width: 6),
                      Expanded(child: Text(location, style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.payments_outlined, size: 16, color: WorkaColors.textGrey),
                      const SizedBox(width: 6),
                      Expanded(child: Text(salary, style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VacancyCardSkeleton extends StatelessWidget {
  const _VacancyCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 98,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WorkaColors.divider),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final String name;
  final String profession;
  final String location;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _CandidateCard({
    required this.name,
    required this.profession,
    required this.location,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WorkaColors.divider),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.06),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: -4,
              child: IconButton(
                tooltip: 'Удалить из избранного',
                onPressed: onRemove,
                icon: Icon(Icons.star_rounded, color: WorkaColors.starYellow),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: WorkaColors.textDark)),
                  if (profession.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(profession, style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: WorkaColors.textGrey),
                      const SizedBox(width: 6),
                      Expanded(child: Text(location, style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w700))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateCardSkeleton extends StatelessWidget {
  const _CandidateCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WorkaColors.divider),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// helpers
String _s(dynamic v, {required String fallback}) {
  final t = (v ?? '').toString().trim();
  return t.isEmpty ? fallback : t;
}

String _formatLocation(dynamic city, dynamic country) {
  final c = _s(city, fallback: '');
  final co = _s(country, fallback: '');
  if (c.isEmpty && co.isEmpty) return 'Локация не указана';
  if (c.isEmpty) return co;
  if (co.isEmpty) return c;
  return '$c, $co';
}

List<List<T>> _chunk<T>(List<T> list, int size) {
  if (list.isEmpty) return const [];
  final out = <List<T>>[];
  for (int i = 0; i < list.length; i += size) {
    out.add(list.sublist(i, min(i + size, list.length)));
  }
  return out;
}
