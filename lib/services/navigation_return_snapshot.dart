import 'package:flutter/foundation.dart';

import '../screens/home/unified_search_filters.dart';

class NavigationReturnSnapshot {
  NavigationReturnSnapshot._();

  static int? _tabIndex;
  static SearchMode _homeMode = SearchMode.vacancies;
  static bool _accountSwitchInProgress = false;
  static String? _accountSwitchOriginRoute;
  static String? _pendingVacancyId;
  static String? _pendingCandidateId;
  static String? _pendingCandidateUid;

  static int? get tabIndex => _tabIndex;
  static SearchMode get homeMode => _homeMode;
  static bool get accountSwitchInProgress => _accountSwitchInProgress;
  static String? get accountSwitchOriginRoute => _accountSwitchOriginRoute;
  static String? get pendingVacancyId => _pendingVacancyId;
  static String? get pendingCandidateId => _pendingCandidateId;
  static String? get pendingCandidateUid => _pendingCandidateUid;

  static void captureTab(int index) {
    _tabIndex = index;
    if (kDebugMode) {
      debugPrint('NavigationReturnSnapshot.captureTab index=$index');
    }
  }

  static void startAccountSwitch({required int tabIndex, String? originRoute}) {
    _tabIndex = tabIndex;
    _accountSwitchInProgress = true;
    _accountSwitchOriginRoute = (originRoute ?? '').trim().isEmpty
        ? null
        : originRoute!.trim();
    if (kDebugMode) {
      debugPrint(
        'NavigationReturnSnapshot.startAccountSwitch tab=$tabIndex origin=$_accountSwitchOriginRoute',
      );
    }
  }

  static void finishAccountSwitch() {
    _accountSwitchInProgress = false;
    _accountSwitchOriginRoute = null;
    if (kDebugMode) {
      debugPrint('NavigationReturnSnapshot.finishAccountSwitch');
    }
  }

  static void setHomeMode(SearchMode mode) {
    _homeMode = mode;
  }

  static void setPendingVacancyDetails(String jobId) {
    _pendingVacancyId = jobId.trim().isEmpty ? null : jobId.trim();
    _pendingCandidateId = null;
    _pendingCandidateUid = null;
  }

  static void setPendingCandidateDetails({
    required String candidateId,
    required String candidateUid,
  }) {
    _pendingCandidateId = candidateId.trim().isEmpty
        ? null
        : candidateId.trim();
    _pendingCandidateUid = candidateUid.trim().isEmpty
        ? null
        : candidateUid.trim();
    _pendingVacancyId = null;
  }

  static void clearPendingDetails() {
    _pendingVacancyId = null;
    _pendingCandidateId = null;
    _pendingCandidateUid = null;
  }
}
