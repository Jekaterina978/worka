import 'auth_guard.dart';
import 'app_mode.dart';
import 'vacancy_owner_scope_resolver.dart';

class VacancyViewerOwnershipResult {
  const VacancyViewerOwnershipResult({
    required this.known,
    required this.isOwner,
    required this.mode,
    required this.matchedBy,
  });

  final bool known;
  final bool isOwner;

  /// `personal`, `business`, or `unknown`.
  final String mode;

  /// How ownership was determined, or reason for non-match.
  final String matchedBy;
}

class OwnershipResolver {
  OwnershipResolver._();

  static String currentUid() => (AuthGuard.effectiveUidOrNull() ?? '').trim();

  static String ownerFromMap(
    Map<String, dynamic> data, {
    List<String> keys = const <String>[],
  }) {
    final ownerKeys = keys.isEmpty
        ? const <String>['ownerId', 'ownerUid', 'ownerKey']
        : keys;
    for (final key in ownerKeys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String vacancyOwnerIdFromMap(Map<String, dynamic> vacancy) {
    final scope = VacancyOwnerScopeResolver.resolveVacancyOwnerScope(vacancy);
    if (scope.isResolved) return scope.ownerId;
    return ownerFromMap(
      vacancy,
      keys: const <String>[
        'ownerId',
        'ownerUid',
        'employerOwnerId',
        'employerUid',
      ],
    );
  }

  static String cvOwnerIdFromMap(Map<String, dynamic> cv) {
    return ownerFromMap(
      cv,
      keys: const <String>[
        'candidateOwnerId',
        'ownerId',
        'ownerUid',
        'candidateUid',
      ],
    );
  }

  /// Strict vacancy ownership for the **current** profile scope (personal uid vs business company id).
  /// Firebase uid is never treated as a company id.
  static VacancyViewerOwnershipResult resolveVacancyViewerOwnership({
    required String ownerType,
    required String ownerId,
    required String? ownerUid,
    required String? createdByUserId,
    String? companyId,
    String? viewerUid,
  }) {
    final uid = (viewerUid ?? currentUid()).trim();
    final appMode = AppMode.currentMode;
    final companyScope = AppMode.activeCompanyId.trim();

    final ot = ownerType.trim().toLowerCase();
    final oid = ownerId.trim();
    final ouid = (ownerUid ?? '').trim();
    final cby = (createdByUserId ?? '').trim();
    final cid = (companyId ?? '').trim();

    if (ot.isEmpty) {
      return const VacancyViewerOwnershipResult(
        known: false,
        isOwner: false,
        mode: 'unknown',
        matchedBy: 'missing_owner_type',
      );
    }

    if (ot == 'personal' || ot == 'user') {
      if (appMode == AccountMode.business) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: false,
          mode: 'personal',
          matchedBy: 'wrong_app_mode',
        );
      }
      if (uid.isEmpty) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: false,
          mode: 'personal',
          matchedBy: 'no_uid',
        );
      }
      if (oid.isNotEmpty && oid == uid) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: true,
          mode: 'personal',
          matchedBy: 'ownerId',
        );
      }
      if (ouid.isNotEmpty && ouid == uid) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: true,
          mode: 'personal',
          matchedBy: 'ownerUid',
        );
      }
      if (cby.isNotEmpty && cby == uid) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: true,
          mode: 'personal',
          matchedBy: 'createdByUserId',
        );
      }
      return const VacancyViewerOwnershipResult(
        known: true,
        isOwner: false,
        mode: 'personal',
        matchedBy: 'no_match',
      );
    }

    if (ot == 'business' || ot == 'company') {
      if (appMode != AccountMode.business) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: false,
          mode: 'business',
          matchedBy: 'wrong_app_mode',
        );
      }
      if (companyScope.isEmpty) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: false,
          mode: 'business',
          matchedBy: 'no_company_scope',
        );
      }
      if (oid.isNotEmpty && oid == companyScope) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: true,
          mode: 'business',
          matchedBy: 'ownerId',
        );
      }
      if (cid.isNotEmpty && cid == companyScope) {
        return const VacancyViewerOwnershipResult(
          known: true,
          isOwner: true,
          mode: 'business',
          matchedBy: 'companyId',
        );
      }
      return const VacancyViewerOwnershipResult(
        known: true,
        isOwner: false,
        mode: 'business',
        matchedBy: 'no_match',
      );
    }

    return const VacancyViewerOwnershipResult(
      known: false,
      isOwner: false,
      mode: 'unknown',
      matchedBy: 'unsupported_owner_type',
    );
  }

  /// Vacancy document snapshot → ownership for the active viewer (optional uid override for tests/guest flows).
  static VacancyViewerOwnershipResult vacancyViewerOwnership(
    Map<String, dynamic> vacancy, {
    String? viewerUid,
  }) {
    final ot =
        (vacancy['ownerType'] ?? vacancy['vacancyOwnerType'] ?? '').toString();
    var oid =
        (vacancy['ownerId'] ?? vacancy['owner_id'] ?? '').toString().trim();
    final ouid = vacancy['ownerUid']?.toString();
    final cby =
        (vacancy['createdByUserId'] ?? vacancy['createdBy'])?.toString();
    final cid =
        (vacancy['companyId'] ?? vacancy['company_id'] ?? '').toString();

    final normalizedType = ot.trim().toLowerCase();
    if ((normalizedType == 'business' || normalizedType == 'company') &&
        oid.isEmpty &&
        cid.trim().isNotEmpty) {
      oid = cid.trim();
    }

    return resolveVacancyViewerOwnership(
      ownerType: ot,
      ownerId: oid,
      ownerUid: ouid,
      createdByUserId: cby,
      companyId: cid.trim().isNotEmpty ? cid.trim() : null,
      viewerUid: viewerUid,
    );
  }

  static bool vacancyIsOwnedByCurrentViewer(Map<String, dynamic> vacancy) {
    final r = vacancyViewerOwnership(vacancy);
    return r.known && r.isOwner;
  }

  /// Candidate/CV snapshot: ownership is personal Firebase uid vs encoded owner fields (never company conflation).
  static VacancyViewerOwnershipResult cvViewerOwnership(
    Map<String, dynamic> cv, {
    String? viewerUid,
  }) {
    final uid = (viewerUid ?? currentUid()).trim();
    final ownerId = cvOwnerIdFromMap(cv).trim();
    if (ownerId.isEmpty) {
      return const VacancyViewerOwnershipResult(
        known: false,
        isOwner: false,
        mode: 'unknown',
        matchedBy: 'missing_cv_owner',
      );
    }
    if (uid.isEmpty) {
      return const VacancyViewerOwnershipResult(
        known: true,
        isOwner: false,
        mode: 'personal',
        matchedBy: 'no_uid',
      );
    }
    final isOwner = ownerId == uid;
    return VacancyViewerOwnershipResult(
      known: true,
      isOwner: isOwner,
      mode: 'personal',
      matchedBy: isOwner ? 'cv_owner_id' : 'no_match',
    );
  }
}
