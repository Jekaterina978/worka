import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/worka_colors.dart';
import '../../theme/worka_ui_tokens.dart';
import '../../services/app_mode.dart' as app_mode;
import '../../config/admin_config.dart';
import '../../services/response_stats_service.dart';
import '../../services/firebase_debug_diagnostics.dart';
import '../../services/firestore_paths.dart';
import '../../services/interaction_status.dart';
import '../../services/entity_validity.dart';
import '../../repositories/cv_repository.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../features/monetization/pricing.dart';
import '../../features/monetization/worker/cv_highlight_paywall_sheet.dart';
import '../../features/monetization/worker/worker_cv_limit_paywall_sheet.dart';
import '../../features/monetization/worker/worker_entitlements_repository.dart';
import '../../widgets/card_more_menu_button.dart';
import '../../widgets/cards/candidate_cv_card.dart';
import '../auth/auth_entry_screen.dart';
import 'services/cv_draft_storage.dart';
import 'cv_wizard_screen.dart';
import 'cv_view_screen.dart';
import 'widgets/cv_card_formatters.dart';

class MyCvsScreen extends StatelessWidget {
  final bool testMode;
  final bool embeddedInShell;
  final VoidCallback? onBack;
  const MyCvsScreen({
    super.key,
    this.testMode = true,
    this.embeddedInShell = false,
    this.onBack,
  });

  static void clearGlobalCaches() {
    _MyCvsList.clearGlobalCaches();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.uid).trim().isEmpty) {
      return const AuthEntryScreen();
    }
    final uid = user.uid;
    final cvsCountStream = CvRepository(FirebaseFirestore.instance)
        .watchMyCvDocs(testMode: testMode, userId: uid.trim())
        .map((docs) {
          return docs
              .where(
                (d) =>
                    WorkaEntityValidity.isValidOwnerCv(d.data(), ownerUid: uid),
              )
              .length;
        });

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      if (onBack != null) {
                        onBack!.call();
                        return;
                      }
                      Navigator.maybePop(context);
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Мои CV',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ProfileAvatarButton(testMode: testMode),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: _MyCvsList(
                uid: uid,
                testMode: testMode,
                showAllInDebug: false,
                canSave: true,
                cvsCountStream: cvsCountStream,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CvListItem {
  final String id;
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> ref;
  final bool isTest;

  _CvListItem({
    required this.id,
    required this.data,
    required this.ref,
    required this.isTest,
  });
}

class _CvCardPayload {
  final String fullName;
  final int? age;
  final dynamic birthDate;
  final String citizenshipCountry;
  final String profession;
  final String city;
  final String country;
  final String salary;
  final String readiness;
  final List<String> badges;

  const _CvCardPayload({
    required this.fullName,
    required this.age,
    required this.birthDate,
    required this.citizenshipCountry,
    required this.profession,
    required this.city,
    required this.country,
    required this.salary,
    required this.readiness,
    required this.badges,
  });
}

class _MyCvsList extends StatelessWidget {
  static final Map<String, bool> _jobsExistsCache = <String, bool>{};
  final String? uid;
  final bool testMode;
  final bool showAllInDebug;
  final bool canSave;
  final Stream<int> cvsCountStream;

  const _MyCvsList({
    required this.uid,
    required this.testMode,
    required this.showAllInDebug,
    required this.canSave,
    required this.cvsCountStream,
  });

  static void clearGlobalCaches() {
    _jobsExistsCache.clear();
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: WorkaColors.textDark),
    );
  }

  CollectionReference<Map<String, dynamic>> _targetCvCollection() {
    final db = FirebaseFirestore.instance;
    return db.collection(FirestorePaths.cvs);
  }

  Future<void> _copyCv(BuildContext context, _CvListItem item) async {
    if ((uid?.trim() ?? '').isEmpty) {
      _toast(context, 'Нужен вход');
      return;
    }
    try {
      final m = Map<String, dynamic>.from(item.data);
      final title = _s(m['title'], fallback: 'CV');
      m['title'] = '$title (копия)';
      m['ownerId'] = uid;
      m['ownerUid'] = uid;
      m['isDeleted'] = false;
      m['test'] = false;
      m['createdAt'] = FieldValue.serverTimestamp();
      m['updatedAt'] = FieldValue.serverTimestamp();
      final ref = await _targetCvCollection().add(m);
      debugPrint('MyCvs copy -> ${_targetCvCollection().path}/${ref.id}');
      if (context.mounted) _toast(context, 'CV скопировано');
    } catch (e) {
      debugPrint('MyCvsScreen _copyCv error: $e');
      if (context.mounted) {
        _toast(context, 'Ошибка сохранения: $e');
        if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
          _toast(context, FirebaseDebugDiagnostics.permissionHintText());
        }
      }
    }
  }

  Future<void> _deleteCv(BuildContext context, _CvListItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Удалить CV?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Отмена',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await item.ref.delete();
      if (context.mounted) _toast(context, 'CV удалено');
    } catch (e) {
      debugPrint('MyCvsScreen _deleteCv error: $e');
      if (context.mounted) {
        _toast(context, 'Ошибка сохранения: $e');
        if (FirebaseDebugDiagnostics.isPermissionDenied(e)) {
          _toast(context, FirebaseDebugDiagnostics.permissionHintText());
        }
      }
    }
  }

  Stream<List<_CvListItem>> _stream() {
    final db = FirebaseFirestore.instance;
    final owner = uid?.trim() ?? '';
    final stream = CvRepository(
      db,
    ).watchMyCvDocs(testMode: testMode, userId: owner);
    debugPrint('MyCvs repo stream testMode=$testMode owner=$owner');

    return stream.map((s) {
      final items = s
          .where((d) {
            final m = d.data();
            return WorkaEntityValidity.isValidOwnerCv(m, ownerUid: owner);
          })
          .map(
            (d) => _CvListItem(
              id: d.id,
              data: d.data(),
              ref: d.reference,
              isTest: d.data()['test'] == true,
            ),
          )
          .toList();
      DateTime parseDate(dynamic v) {
        if (v is Timestamp) return v.toDate();
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      items.sort((a, b) {
        final aUpdated = parseDate(a.data['updatedAt']);
        final bUpdated = parseDate(b.data['updatedAt']);
        if (aUpdated != bUpdated) return bUpdated.compareTo(aUpdated);
        final aCreated = parseDate(a.data['createdAt']);
        final bCreated = parseDate(b.data['createdAt']);
        return bCreated.compareTo(aCreated);
      });

      return items;
    });
  }

  Stream<int> _workerCvLimitStream() {
    final owner = uid?.trim() ?? '';
    if (owner.isEmpty) {
      return Stream<int>.value(MonetizationPricing.workerFreeActiveCvLimit);
    }
    return WorkerEntitlementsRepository(
      FirebaseFirestore.instance,
    ).watch(owner).map((e) => e.activeCvLimit);
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _pick(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final k in keys) {
      final v = _s(data[k]);
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  String _cleanDisplayText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.toLowerCase();
    const hiddenValues = <String>{
      'не указано',
      'не указана',
      'не указан',
      'нет',
      'n/a',
      '-',
      'зарплата не указана',
      'salary not specified',
    };
    if (hiddenValues.contains(normalized)) return '';
    return trimmed;
  }

  int? _intFrom(dynamic raw) {
    if (raw is num) return raw.toInt();
    final parsed = int.tryParse((raw ?? '').toString().trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String _fullName(Map<String, dynamic> d) {
    final contacts = (d['contacts'] is Map<String, dynamic>)
        ? (d['contacts'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final name = _pick(contacts, const [
      'name',
      'fullName',
    ], fallback: _pick(d, const ['name', 'fullName']));
    if (name.trim().isNotEmpty) return name.trim();
    final first = _pick(contacts, const [
      'firstName',
    ], fallback: d['firstName']?.toString() ?? '');
    final last = _pick(contacts, const [
      'lastName',
    ], fallback: d['lastName']?.toString() ?? '');
    final combined = '$first $last'.trim();
    return combined.isEmpty ? 'Кандидат' : combined;
  }

  int? _age(Map<String, dynamic> d) {
    final direct = _intFrom(d['age']);
    if (direct != null) return direct;
    final contacts = (d['contacts'] is Map<String, dynamic>)
        ? (d['contacts'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final fromContacts = _intFrom(contacts['age']);
    if (fromContacts != null) return fromContacts;
    final rawDate = d['birthDate'] ?? contacts['birthDate'];
    return calculateAgeFromBirthDate(rawDate);
  }

  dynamic _birthDate(Map<String, dynamic> d) {
    final contacts = (d['contacts'] is Map<String, dynamic>)
        ? (d['contacts'] as Map<String, dynamic>)
        : <String, dynamic>{};
    return d['birthDate'] ?? contacts['birthDate'];
  }

  String _citizenship(Map<String, dynamic> d) {
    final contacts = (d['contacts'] is Map<String, dynamic>)
        ? (d['contacts'] as Map<String, dynamic>)
        : <String, dynamic>{};
    return _cleanDisplayText(
      _pick(
        d,
        const ['citizenshipCountry', 'citizenshipName', 'citizenship'],
        fallback: _pick(contacts, const [
          'citizenshipCountry',
          'citizenshipName',
          'citizenship',
        ]),
      ),
    );
  }

  String _city(Map<String, dynamic> d) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final cities = desired['cities'];
    if (cities is List && cities.isNotEmpty) {
      final first = cities.first.toString().trim();
      if (first.isNotEmpty) return _cleanDisplayText(first);
    }
    return _cleanDisplayText(
      _pick(desired, const [
        'citiesText',
        'city',
      ], fallback: _pick(d, const ['city'])),
    );
  }

  String _country(Map<String, dynamic> d) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final countries = desired['countries'];
    if (countries is List && countries.isNotEmpty) {
      final first = countries.first.toString().trim();
      if (first.isNotEmpty) return _cleanDisplayText(first);
    }
    return _cleanDisplayText(_pick(d, const ['country']));
  }

  String _salary(Map<String, dynamic> d) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    String symbolFromCode(String code) {
      final upper = code.trim().toUpperCase();
      if (upper == 'USD') return r'$';
      return '€';
    }

    String periodLabel(String value) {
      final lower = value.trim().toLowerCase();
      if (lower == 'hour') return 'час';
      if (lower == 'day') return 'день';
      return 'месяц';
    }

    final fromDesired = _pick(desired, const [
      'salaryText',
      'salaryAmountText',
      'salary',
      'salaryFrom',
    ]);
    if (_cleanDisplayText(fromDesired).isNotEmpty) {
      return _cleanDisplayText(fromDesired);
    }
    final amount = _cleanDisplayText(
      _pick(desired, const ['salaryAmount', 'salaryExpected']),
    );
    final currencyCode = _cleanDisplayText(
      _pick(desired, const ['salaryCurrency']),
    );
    final period = _cleanDisplayText(_pick(desired, const ['salaryPeriod']));
    final symbol = symbolFromCode(currencyCode);
    if (amount.isNotEmpty) {
      final periodPart = period.isNotEmpty ? ' / ${periodLabel(period)}' : '';
      return '$symbol $amount$periodPart';
    }
    final fallback = _cleanDisplayText(
      _pick(d, const ['salaryText', 'salaryAmountText', 'salary']),
    );
    return fallback.isNotEmpty ? fallback : '$symbol -';
  }

  String _readiness(Map<String, dynamic> d) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    return _cleanDisplayText(
      _pick(desired, const [
        'readiness',
        'startTime',
        'availabilityText',
        'availability',
        'employmentType',
      ]),
    );
  }

  List<String> _badges(Map<String, dynamic> d) {
    final langs = (d['languages'] is List)
        ? (d['languages'] as List)
        : const [];
    final skills = (d['computerSkills'] is Map<String, dynamic>)
        ? (d['computerSkills'] as Map<String, dynamic>)
        : (d['skills'] is Map<String, dynamic>)
        ? (d['skills'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final driving = (d['drivingLicense'] is Map<String, dynamic>)
        ? (d['drivingLicense'] as Map<String, dynamic>)
        : (d['driving'] is Map<String, dynamic>)
        ? (d['driving'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final selectedRaw = skills['selected'] ?? skills['computerPrograms'];
    final categoriesRaw = driving['categories'];
    final categories = (categoriesRaw is List)
        ? categoriesRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final legacyLicense = _pick(driving, const ['license']);
    if (categories.isEmpty && legacyLicense.isNotEmpty) {
      categories.add(legacyLicense);
    }
    final normalizedLangs = <Map<String, dynamic>>[];
    for (final entry in langs) {
      if (entry is Map) {
        normalizedLangs.add(Map<String, dynamic>.from(entry));
        continue;
      }
      if (entry is String && entry.trim().isNotEmpty) {
        final raw = entry.trim();
        final parts = raw.split(RegExp(r'\s+'));
        normalizedLangs.add(<String, dynamic>{
          'language': parts.first,
          'level': parts.length > 1 ? parts.skip(1).join(' ') : '',
        });
      }
    }
    final result = buildCandidateBadges(
      languages: normalizedLangs,
      drivingLicenseCategories: categories,
      hasCar: driving['hasCar'] == true,
      hasTools: d['hasTools'] == true,
      hasWorkwear: d['hasWorkwear'] == true,
      hasComputerSkills: selectedRaw is List && selectedRaw.isNotEmpty,
    );
    final exp = d['experience'];
    if (exp is List && exp.isNotEmpty) {
      result.add(
        '${exp.length} ${exp.length == 1 ? 'год опыта' : 'года опыта'}',
      );
    }
    return result.toSet().take(6).toList();
  }

  _CvCardPayload _mapCardPayload(
    Map<String, dynamic> d, {
    required bool isIncomplete,
  }) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final profession = isIncomplete
        ? _pick(d, const ['profession', 'title', 'cvTitle'])
        : _pick(desired, const [
            'position',
          ], fallback: _pick(d, const ['profession', 'title', 'cvTitle']));
    final countriesRaw = desired['countries'] ?? d['countriesWanted'];
    final countries = (countriesRaw is List)
        ? countriesRaw
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
        : <String>[];
    final country = countries.isEmpty ? _country(d) : countries.first;

    return _CvCardPayload(
      fullName: _fullName(d),
      age: _age(d),
      birthDate: _birthDate(d),
      citizenshipCountry: _citizenship(d),
      profession: profession,
      city: _city(d),
      country: country,
      salary: _salary(d),
      readiness: _readiness(d),
      badges: _badges(d),
    );
  }

  bool _isCvIncomplete(Map<String, dynamic> d) {
    final desired = (d['desired'] is Map<String, dynamic>)
        ? (d['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final contacts = (d['contacts'] is Map<String, dynamic>)
        ? (d['contacts'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final title = _pick(d, const ['title', 'profession', 'cvTitle']);
    bool containsCopyToken(String value) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return false;
      return normalized.contains('копия') || normalized.contains('copy');
    }

    final hasLocation =
        ((desired['countries'] is List) &&
            (desired['countries'] as List).isNotEmpty) ||
        _s(d['country']).isNotEmpty ||
        _s(d['city']).isNotEmpty;
    final hasContact =
        _s(contacts['phone']).isNotEmpty ||
        _s(contacts['phoneNumber']).isNotEmpty ||
        _s(contacts['email']).isNotEmpty ||
        _s(d['phone']).isNotEmpty ||
        _s(d['email']).isNotEmpty;
    final hasDesiredCategory =
        _s(desired['categoryGroup']).isNotEmpty ||
        _s(desired['category']).isNotEmpty;
    final hasEmploymentType =
        ((desired['employmentTypes'] is List) &&
            (desired['employmentTypes'] as List).isNotEmpty) ||
        _s(desired['employmentType']).isNotEmpty;

    final derivedComplete =
        title.isNotEmpty &&
        hasContact &&
        hasLocation &&
        hasDesiredCategory &&
        hasEmploymentType;

    final status = (d['status'] ?? d['cvStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final markedIncomplete =
        d['isDraft'] == true ||
        d['isIncomplete'] == true ||
        d['incomplete'] == true ||
        (d['isComplete'] is bool && d['isComplete'] == false) ||
        status == 'draft' ||
        status == 'unfinished' ||
        status == 'incomplete';

    final publishBlockedByTitle = containsCopyToken(title);
    if (publishBlockedByTitle) return true;
    if (!derivedComplete) return true;
    if (markedIncomplete) return true;
    return false;
  }

  bool _isHiddenTestItem(Map<String, dynamic> d) {
    final text = <String>[
      _pick(d, const ['title', 'profession', 'cvTitle']),
      _s(d['status']),
      _s(d['source']),
    ].join(' ').toLowerCase();
    if (text.contains('test') ||
        text.contains('demo') ||
        text.contains('draft')) {
      return true;
    }
    // Don't hide based on d['test'] alone — it reflects the UI testMode flag,
    // not whether it's real user data. Real user CVs have source=='user'.
    return d['draft'] == true || _s(d['status']).toLowerCase() == 'draft';
  }

  Future<bool> _existsCached({
    required String collection,
    required String id,
    required Map<String, bool> cache,
  }) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;
    final key = '$collection/$cleanId';
    final cached = cache[key];
    if (cached != null) return cached;
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .doc(cleanId)
        .get();
    final data = snap.data() ?? const <String, dynamic>{};
    final exists = snap.exists && data['isDeleted'] != true;
    cache[key] = exists;
    return exists;
  }

  Future<bool> _isValidResponse(Map<String, dynamic> m) async {
    final type = (m['type'] ?? '').toString().trim().toLowerCase();
    final jobId = (m['jobId'] ?? '').toString().trim();
    final cvId = (m['candidateCvId'] ?? m['cvId'] ?? '').toString().trim();
    if (jobId.isEmpty || cvId.isEmpty) return false;
    if (type == 'offer' ||
        type == 'apply' ||
        type == 'application' ||
        type == 'response') {
      return _existsCached(
        collection: FirestorePaths.jobs,
        id: jobId,
        cache: _jobsExistsCache,
      );
    }
    return false;
  }

  Stream<({Map<String, ResponseStats> byCv, ResponseStats all})>
  _offersStatsByCv(String ownerKey) {
    return FirebaseFirestore.instance
        .collection(FirestorePaths.jobOffers)
        .snapshots()
        .asyncMap((snap) async {
          final byCvMutable = <String, List<int>>{};
          int allFresh = 0;
          int allTotal = 0;
          final seen = <String>{};
          bool isMine(Map<String, dynamic> m) {
            final candidateId = (m['candidateOwnerId'] ?? '').toString().trim();
            return candidateId == ownerKey;
          }

          for (final d in snap.docs) {
            final m = d.data();
            final type = (m['type'] ?? '').toString().trim().toLowerCase();
            if (type != 'offer') continue;
            if (!isMine(m)) continue;
            if (!await _isValidResponse(m)) continue;
            final jobId = (m['jobId'] ?? '').toString().trim();
            final cvId = (m['candidateCvId'] ?? m['cvId'] ?? '')
                .toString()
                .trim();
            final employerOwner = (m['employerOwnerId'] ?? '')
                .toString()
                .trim();
            final key = 'offer|$jobId|$employerOwner|$cvId';
            if (!seen.add(key)) continue;
            final sideStatus = m['status'];
            final isFresh = InteractionStatus.isFresh(sideStatus);
            allTotal += 1;
            if (isFresh) allFresh += 1;
            if (cvId.isEmpty) continue;
            final pair = byCvMutable.putIfAbsent(cvId, () => <int>[0, 0]);
            pair[1] = pair[1] + 1;
            if (isFresh) pair[0] = pair[0] + 1;
          }

          final byCv = <String, ResponseStats>{};
          byCvMutable.forEach((cvId, pair) {
            byCv[cvId] = ResponseStats(fresh: pair[0], total: pair[1]);
          });

          return (
            byCv: byCv,
            all: ResponseStats(fresh: allFresh, total: allTotal),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    if (uid == null || uid!.trim().isEmpty) {
      return const Center(
        child: Text(
          'Войдите, чтобы видеть свои CV',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: WorkaColors.textDark,
          ),
        ),
      );
    }

    return ValueListenableBuilder<app_mode.AccountMode>(
      valueListenable: app_mode.AppMode.modeNotifier,
      builder: (context, mode, _) {
        if (mode == app_mode.AccountMode.business) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.work_off_outlined,
                    size: 56,
                    color: WorkaColors.textGreyDark,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Переключитесь на личный профиль для работы с CV',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: WorkaColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return _buildContent(context);
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return StreamBuilder<List<_CvListItem>>(
      stream: _stream(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('MyCvsScreen stream error: ${snap.error}');
          final permissionDenied = FirebaseDebugDiagnostics.isPermissionDenied(
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
                      fontWeight: FontWeight.w800,
                      color: WorkaColors.textGreyDark,
                    ),
                  ),
                  if (permissionDenied && testMode) ...[
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
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final items = snap.data ?? const <_CvListItem>[];

        final ownerUidForStats = uid!.trim();

        return StreamBuilder<
          ({Map<String, ResponseStats> byCv, ResponseStats all})
        >(
          stream: _offersStatsByCv(ownerUidForStats),
          builder: (context, statsSnap) {
            final incompleteItems = <_CvListItem>[];
            final completeItems = <_CvListItem>[];
            for (final it in items) {
              if (_isHiddenTestItem(it.data)) continue;
              if (_isCvIncomplete(it.data)) {
                incompleteItems.add(it);
              } else {
                completeItems.add(it);
              }
            }

            return FutureBuilder<Map<String, dynamic>?>(
              future: CvDraftStorage.load(),
              builder: (context, draftSnap) {
                final localDraft = draftSnap.data;
                final sections = <Widget>[
                  StreamBuilder<int>(
                    stream: cvsCountStream,
                    builder: (context, countSnap) {
                      final count = countSnap.data ?? 0;
                      return StreamBuilder<int>(
                        stream: _workerCvLimitStream(),
                        builder: (context, limitSnap) {
                          final limit =
                              limitSnap.data ??
                              MonetizationPricing.workerFreeActiveCvLimit;
                          final disabledByLimit =
                              !AdminConfig.isAdmin() && count >= limit;
                          final disabled = !canSave;
                          return _UploadCvCard(
                            disabled: disabled,
                            disabledByLimit: disabledByLimit,
                            limit: limit,
                            onAdd: () {
                              if (app_mode.AppMode.currentMode ==
                                  app_mode.AccountMode.business) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Создание CV доступно только в личном профиле.',
                                    ),
                                    action: SnackBarAction(
                                      label: 'Переключить',
                                      onPressed: () => app_mode.AppMode.setMode(
                                        app_mode.AccountMode.personal,
                                      ),
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (disabledByLimit) {
                                WorkerCvLimitPaywallSheet.open(context);
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CvWizardScreen(testMode: testMode),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ];

                if (localDraft != null || incompleteItems.isNotEmpty) {
                  sections.add(
                    const Text(
                      'Незаконченные CV',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: WorkaColors.textDark,
                      ),
                    ),
                  );
                }

                if (localDraft != null) {
                  sections.add(
                    _DraftCvCard(
                      title: _s(localDraft['title'], fallback: 'Новое CV'),
                      onContinue: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CvWizardScreen(testMode: testMode),
                        ),
                      ),
                      onDelete: () async {
                        await CvDraftStorage.clear();
                        if (context.mounted) {
                          (context as Element).markNeedsBuild();
                        }
                      },
                    ),
                  );
                }

                for (final it in incompleteItems) {
                  final d = it.data;
                  final card = _mapCardPayload(d, isIncomplete: true);
                sections.add(
                  CandidateCvCard(
                    mode: CandidateCvCardMode.owner,
                    cvId: it.id,
                    fullName: card.fullName,
                    age: card.age,
                    citizenshipCountry: card.citizenshipCountry,
                      profession: card.profession,
                      city: card.city,
                      country: card.country,
                      salary: card.salary,
                      readiness: card.readiness,
                      badges: card.badges,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CvViewScreen(
                            cvId: it.id,
                            refOverride: it.ref,
                            testMode: testMode,
                            startEditing: true,
                          ),
                        ),
                      ),
                      menuItems: [
                        CardMenuItem(
                          label: 'Изменить',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CvViewScreen(
                                cvId: it.id,
                                refOverride: it.ref,
                                testMode: testMode,
                                startEditing: true,
                              ),
                            ),
                          ),
                        ),
                        CardMenuItem(
                          label: 'Копировать',
                          onTap: () => _copyCv(context, it),
                        ),
                        CardMenuItem(
                          label: 'Удалить',
                          onTap: () => _deleteCv(context, it),
                        ),
                      ],
                      primaryActionLabel: 'Дополнить',
                      onPrimaryAction: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CvViewScreen(
                            cvId: it.id,
                            refOverride: it.ref,
                            testMode: testMode,
                            startEditing: true,
                          ),
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  );
                }

                sections.add(
                  const Text(
                    'Мои CV',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: WorkaColors.textDark,
                    ),
                  ),
                );

                if (completeItems.isEmpty) {
                  sections.add(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: WorkaColors.divider),
                      ),
                      child: const Text(
                        'Пока нет CV',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: WorkaColors.textGreyDark,
                        ),
                      ),
                    ),
                  );
                }

                for (final it in completeItems) {
                  final d = it.data;
                  final card = _mapCardPayload(d, isIncomplete: false);
                  final currentUserUid = uid?.trim() ?? '';
                  final currentUserEmail =
                      (FirebaseAuth.instance.currentUser?.email ?? '')
                          .trim()
                          .toLowerCase();
                  final cvOwnerId = (d['ownerId'] ?? '').toString().trim();
                  final cvOwnerUid = (d['ownerUid'] ?? '').toString().trim();
                  final cvOwnerEmail =
                      (d['ownerEmail'] ?? d['email'] ?? d['contactEmail'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();
                  final canHighlight =
                      (currentUserUid.isNotEmpty &&
                          (cvOwnerId == currentUserUid ||
                              cvOwnerUid == currentUserUid)) ||
                      (currentUserEmail.isNotEmpty &&
                          cvOwnerEmail.isNotEmpty &&
                          currentUserEmail == cvOwnerEmail);
                sections.add(
                  CandidateCvCard(
                    mode: CandidateCvCardMode.owner,
                    cvId: it.id,
                    fullName: card.fullName,
                    age: card.age,
                    citizenshipCountry: card.citizenshipCountry,
                      profession: card.profession,
                      city: card.city,
                      country: card.country,
                      salary: card.salary,
                      readiness: card.readiness,
                      badges: card.badges,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CvViewScreen(
                            cvId: it.id,
                            refOverride: it.ref,
                            testMode: testMode,
                          ),
                        ),
                      ),
                      menuItems: [
                        CardMenuItem(
                          label: 'Изменить',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CvViewScreen(
                                cvId: it.id,
                                refOverride: it.ref,
                                testMode: testMode,
                                startEditing: true,
                              ),
                            ),
                          ),
                        ),
                        CardMenuItem(
                          label: 'Копировать',
                          onTap: () => _copyCv(context, it),
                        ),
                        CardMenuItem(
                          label: 'Удалить',
                          onTap: () => _deleteCv(context, it),
                        ),
                      ],
                      primaryActionLabel: 'Выделить CV',
                      onPrimaryAction: canHighlight
                          ? () => CvHighlightPaywallSheet.open(
                              context,
                              cvId: it.id,
                            )
                          : null,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                  itemCount: sections.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => sections[i],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _UploadCvCard extends StatelessWidget {
  final bool disabled;
  final bool disabledByLimit;
  final int limit;
  final VoidCallback onAdd;

  const _UploadCvCard({
    required this.disabled,
    required this.disabledByLimit,
    required this.limit,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 50,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: disabled ? null : onAdd,
            style: WorkaButtonStyles.primaryOrange(),
            child: Text(
              disabledByLimit
                  ? 'Добавить CV (лимит $limit/$limit)'
                  : 'Добавить CV',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: WorkaColors.divider),
            boxShadow: WorkaUiShadows.card,
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFEAF0FF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_upload_rounded,
                    color: WorkaColors.blue,
                    size: 26,
                  ),
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Загрузите своё резюме',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: WorkaColors.textDark,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'PDF, DOC, DOCX до 10 МБ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WorkaColors.textGreyDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DraftCvCard extends StatelessWidget {
  final String title;
  final VoidCallback onContinue;
  final VoidCallback onDelete;

  const _DraftCvCard({
    required this.title,
    required this.onContinue,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WorkaColors.divider),
        boxShadow: WorkaUiShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.edit_outlined,
                color: WorkaColors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Не закончено',
                style: TextStyle(
                  color: WorkaColors.orange,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onContinue,
                style: OutlinedButton.styleFrom(
                  foregroundColor: WorkaColors.blue,
                  side: const BorderSide(color: WorkaColors.blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text(
                  'Дополнить',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: WorkaColors.textDark,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onDelete,
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
