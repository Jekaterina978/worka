import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/theme/worka_ui_tokens.dart';
import 'package:worka/services/response_stats_service.dart';
import 'package:worka/services/firebase_debug_diagnostics.dart';
import 'package:worka/services/auth_controller.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/services/app_mode.dart' as session_mode;
import 'package:worka/services/navigation_return_snapshot.dart';
import 'package:worka/services/profile_completion.dart';
import 'package:worka/services/user_role_prefs.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/interaction_status.dart';
import 'package:worka/services/entity_validity.dart';
import 'package:worka/repositories/cv_repository.dart';
import 'package:worka/repositories/jobs_repository.dart';
import 'package:worka/account/account_switcher_screen.dart';
import 'package:worka/widgets/profile_avatar_button.dart';
import 'package:worka/widgets/worka_header.dart';
import 'package:worka/widgets/worka_standard_screen_layout.dart';
import 'package:worka/features/payments/models/employer_payment_models.dart';
import 'package:worka/features/payments/domain/models/credits_models.dart';
import 'package:worka/features/payments/payments_routes.dart';
import 'package:worka/features/payments/repository/payments_repository.dart';
import 'package:worka/features/payments/contact_access_controller.dart';
import 'package:worka/features/payments/screens/contact_unlock_paywall_sheet.dart';

import 'cv/my_cvs_screen.dart';

import 'employer/my_publications_screen.dart';
import 'worker_profile_edit_screen.dart';
import 'employer_company_profile_screen.dart';
import 'interactions/offers_list_screen.dart';
import 'interactions/applications_list_screen.dart';
import 'auth/auth_entry_screen.dart';
part 'profile/profile_screen_helpers.dart';
part 'profile/profile_content_section.dart';
part 'profile/profile_stat_widgets.dart';
part 'profile/profile_menu_widgets.dart';
part 'profile/profile_avatar_widget.dart';
part 'profile/profile_header_widgets.dart';
part 'profile/widgets/profile_header_section.dart';
part 'profile/widgets/profile_actions_section.dart';
part 'profile/widgets/profile_account_section.dart';
part 'profile/widgets/profile_payment_section.dart';
part 'profile/widgets/profile_logout_section.dart';

enum _AvatarGender { female, male, unknown }

enum _ProfileMenuAction { editProfile, switchAccount, logout }

class ProfileScreen extends StatefulWidget {
  final bool testMode;
  final bool embeddedInShell;
  final VoidCallback? onOpenMyCvs;
  const ProfileScreen({
    super.key,
    this.testMode = true,
    this.embeddedInShell = false,
    this.onOpenMyCvs,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with _ProfileScreenHelpers {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _paymentsRepo = PaymentsRepository();
  String _sessionUid = '';
  final Map<String, bool> _jobExistsCache = <String, bool>{};
  final Map<String, bool> _cvExistsCache = <String, bool>{};
  final Map<String, String> _jobOwnerCache = <String, String>{};
  final Map<String, String> _cvOwnerCache = <String, String>{};
  Future<EmployerMe>? _employerMeFuture;

  bool _tabReady = false;
  ProfileTab _selectedTab = ProfileTab.personal;

  void _refreshEmployerMeFuture() {
    _employerMeFuture = _paymentsRepo.getEmployerMe();
  }

  Future<void> _openContactPackageSheet() async {
    final purchased = await ContactUnlockPaywallSheet.open(
      context,
      entryPoint: 'profile_credits_cta',
      mode: PaywallMode.creditsOnly,
    );
    if (!purchased) return;
    if (!mounted) return;
    setState(_refreshEmployerMeFuture);
  }

  bool _isPersonalProfileComplete(Map<String, dynamic> profile) {
    final personal = profile['personal'] is Map
        ? Map<String, dynamic>.from(profile['personal'] as Map)
        : const <String, dynamic>{};
    final contacts = profile['contacts'] is Map
        ? Map<String, dynamic>.from(profile['contacts'] as Map)
        : const <String, dynamic>{};

    String pick(List<String> keys, {Map<String, dynamic>? from}) {
      final src = from ?? profile;
      for (final key in keys) {
        final v = _s(src[key]);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final firstName = [
      pick(const ['firstName'], from: personal),
      pick(const ['firstName']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final lastName = [
      pick(const ['lastName'], from: personal),
      pick(const ['lastName']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final fallbackName = [
      pick(const ['name'], from: personal),
      pick(const ['name']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final hasName =
        (firstName.isNotEmpty && lastName.isNotEmpty) ||
        fallbackName.isNotEmpty;

    final email = [
      pick(const ['email'], from: personal),
      pick(const ['email'], from: contacts),
      pick(const ['email']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final phone = [
      pick(const ['phone', 'phoneNumber'], from: personal),
      pick(const ['phone', 'phoneNumber'], from: contacts),
      pick(const ['phone', 'phoneNumber']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final hasContact = email.isNotEmpty || phone.isNotEmpty;

    final profession = [
      pick(const [
        'profession',
        'title',
        'position',
        'specialization',
        'jobTitle',
        'desiredPosition',
      ], from: personal),
      pick(const [
        'profession',
        'title',
        'position',
        'specialization',
        'jobTitle',
        'desiredPosition',
      ]),
      pick(const ['category'], from: personal),
      pick(const ['category']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final hasProfession = profession.isNotEmpty;

    final location = [
      pick(const ['locationLabel'], from: personal),
      pick(const ['location'], from: personal),
      pick(const ['locationLabel']),
      pick(const ['location']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final country = [
      pick(const ['country', 'countryName'], from: personal),
      pick(const ['country', 'countryName']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final city = [
      pick(const ['city'], from: personal),
      pick(const ['city']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final hasLocation =
        location.isNotEmpty || (country.isNotEmpty && city.isNotEmpty);

    return hasName && hasContact && hasProfession && hasLocation;
  }

  @override
  void initState() {
    super.initState();
    _sessionUid = AuthController.instance.currentUid ?? '';
    _refreshEmployerMeFuture();
    AuthController.instance.uidListenable.addListener(_onAuthUidChanged);
    session_mode.AppMode.modeNotifier.addListener(_onAppModeChanged);
    _restoreLastTab();
  }

  @override
  void dispose() {
    AuthController.instance.uidListenable.removeListener(_onAuthUidChanged);
    session_mode.AppMode.modeNotifier.removeListener(_onAppModeChanged);
    super.dispose();
  }

  void _onAppModeChanged() {
    final newTab =
        session_mode.AppMode.currentMode == session_mode.AccountMode.business
        ? ProfileTab.business
        : ProfileTab.personal;
    if (newTab == _selectedTab) return;
    if (!mounted) return;
    setState(() => _selectedTab = newTab);
  }

  void _onAuthUidChanged() {
    final nextUid = AuthController.instance.currentUid ?? '';
    if (nextUid == _sessionUid) return;
    if (kDebugMode) {
      debugPrint(
        'ProfileScreen auth uid changed $_sessionUid -> $nextUid, rebuilding profile state',
      );
    }
    _sessionUid = nextUid;
    if (!mounted) return;
    setState(() {
      _refreshEmployerMeFuture();
    });
  }

  Future<void> _restoreLastTab() async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = (prefs.getString(kLastProfileTabKey) ?? '').trim();
    final role = await UserRolePrefs.getSelectedRole();
    final roleTab = role == UserRolePrefs.employer ? 'business' : 'personal';
    final sessionTab =
        session_mode.AppMode.currentMode == session_mode.AccountMode.business
        ? 'business'
        : 'personal';
    final raw = persisted.isNotEmpty
        ? persisted
        : (role == null ? sessionTab : roleTab);
    if (!mounted) return;
    setState(() {
      _selectedTab = profileTabFromValue(raw);
      _tabReady = true;
    });
  }

  Future<void> _setTab(ProfileTab tab) async {
    if (_selectedTab == tab) return;
    session_mode.AppMode.setMode(
      tab == ProfileTab.business
          ? session_mode.AccountMode.business
          : session_mode.AccountMode.personal,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLastProfileTabKey, profileTabToValue(tab));
    if (!mounted) return;
    setState(() => _selectedTab = tab);
  }

  void _openMyCvs() {
    if (widget.onOpenMyCvs != null) {
      if (kDebugMode) {
        debugPrint(
          '[ProfileScreen] openMyCvs via embedded callback (no push). '
          'embeddedInShell=${widget.embeddedInShell}',
        );
      }
      widget.onOpenMyCvs!.call();
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[ProfileScreen] openMyCvs via Navigator.push. '
        'embeddedInShell=${widget.embeddedInShell}',
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MyCvsScreen(testMode: widget.testMode)),
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileStream(String uid) {
    final clean = uid.trim();
    if (clean.isEmpty) return null;
    return _db.collection('users').doc(clean).snapshots();
  }

  Widget _buildProfileContent({
    required bool isBusiness,
    required Map<String, dynamic> profile,
    required String uid,
    required String businessUid,
    required String name,
    required String email,
    required String phone,
    required String location,
    required String companyName,
    required String employerType,
  }) {
    return buildProfileContentUI(
      this,
      isBusiness: isBusiness,
      profile: profile,
      uid: uid,
      businessUid: businessUid,
      name: name,
      email: email,
      phone: phone,
      location: location,
      companyName: companyName,
      employerType: employerType,
    );
  }

  Future<void> _openPersonalFillFlow() async {
    await _setTab(ProfileTab.personal);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const WorkerProfileEditScreen(isInitialFill: true),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openEditProfileFlow() async {
    if (_selectedTab == ProfileTab.business) {
      await _openBusinessFillFlow();
      return;
    }
    await _openPersonalFillFlow();
  }

  Future<void> _openSwitchAccount() async {
    if (!mounted) return;
    final routeName = ModalRoute.of(context)?.settings.name;
    NavigationReturnSnapshot.startAccountSwitch(
      tabIndex: 2,
      originRoute: routeName,
    );
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const AccountSwitcherScreen()));
  }

  Future<void> _logout() async {
    try {
      debugPrint('[AUTH] signOut requested from ProfileScreen');
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось выйти: $e'),
          backgroundColor: WorkaColors.textDark,
        ),
      );
    }
  }

  Future<void> _openBusinessFillFlow() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EmployerCompanyProfileScreen()),
    );
    if (mounted) setState(() {});
  }

  Widget _profileMenuButton({Color iconColor = WorkaColors.textGreyDark}) {
    return ProfileMenuButton(
      iconColor: iconColor,
      onEditProfile: _openEditProfileFlow,
      onSwitchAccount: _openSwitchAccount,
      onLogout: _logout,
    );
  }

  Stream<int> _cvCount(String? uid) {
    if (uid == null || uid.isEmpty) return Stream.value(0);
    return CvRepository(
      _db,
    ).watchMyCvDocs(testMode: widget.testMode, userId: uid).map((docs) {
      final count = docs.where((d) {
        final m = d.data();
        if (!WorkaEntityValidity.isValidOwnerCv(m, ownerUid: uid)) return false;
        return WorkaEntityValidity.isValidPublicCv(m);
      }).length;
      return count;
    });
  }

  Stream<int> _jobsCount(String? uid, {String? ownerType}) {
    if (uid == null || uid.isEmpty) return Stream.value(0);
    return JobsRepository(_db)
        .watchMyJobs(
          testMode: widget.testMode,
          userId: uid,
          ownerType: ownerType,
        )
        .map((docs) {
          final count = docs.where((d) {
            final m = d.data();
            if (!WorkaEntityValidity.isValidOwnerVacancy(m, ownerUid: uid)) {
              return false;
            }
            return WorkaEntityValidity.isValidPublicVacancy(m);
          }).length;
          return count;
        });
  }

  Stream<ResponseStats> _offersStats(String? uid, {String profileType = ''}) {
    final candidateUid = uid?.trim() ?? '';
    if (candidateUid.isEmpty) {
      return Stream.value(const ResponseStats(fresh: 0, total: 0));
    }
    return _mergedOffersStream(
      uid: candidateUid,
      isEmployerView: false,
    ).asyncMap(
      (docs) => _calcOfferStatsForListAsync(
        docs,
        isEmployerView: false,
        expectedOwnerUid: candidateUid,
        profileType: profileType,
      ),
    );
  }

  Stream<ResponseStats> _employerOffersSentStats(
    String? uid, {
    String profileType = '',
  }) {
    final employerUid = uid?.trim() ?? '';
    if (employerUid.isEmpty) {
      return Stream.value(const ResponseStats(fresh: 0, total: 0));
    }
    return _mergedOffersStream(uid: employerUid, isEmployerView: true).asyncMap(
      (docs) => _calcOfferStatsForListAsync(
        docs,
        isEmployerView: true,
        expectedOwnerUid: employerUid,
        profileType: profileType,
      ),
    );
  }

  Stream<ResponseStats> _employerApplicationsStats(
    String? uid, {
    String? ownerType,
  }) {
    final employerUid = uid?.trim() ?? '';
    if (employerUid.isEmpty) {
      return Stream.value(const ResponseStats(fresh: 0, total: 0));
    }
    final ownerTypeClean = ownerType?.trim() ?? '';
    if (ownerTypeClean.isNotEmpty) {
      return _employerApplicationsStatsForOwnerType(
        employerUid,
        ownerType: ownerTypeClean,
      );
    }
    return _mergedApplicationsStream(
      uid: employerUid,
      isEmployerView: true,
    ).asyncMap(
      (docs) =>
          _calcApplyStatsForListAsync(docs, expectedEmployerUid: employerUid),
    );
  }

  Stream<ResponseStats> _workerResponsesSentStats(
    String? uid, {
    String profileType = 'personal',
  }) {
    final candidateUid = uid?.trim() ?? '';
    if (candidateUid.isEmpty) {
      return Stream.value(const ResponseStats(fresh: 0, total: 0));
    }
    return _mergedApplicationsStream(
      uid: candidateUid,
      isEmployerView: false,
    ).asyncMap(
      (docs) => _calcApplyStatsForListAsync(
        docs,
        expectedCandidateUid: candidateUid,
        profileType: profileType,
      ),
    );
  }

  Stream<int> _creditsState(String uid) async* {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      yield 0;
      return;
    }
    try {
      final wallet =
          await ContactAccessController.instance.getWallet(uid: cleanUid);
      yield wallet.balance;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProfileScreen] _creditsState failed: $e');
      }
      yield ContactAccessController.instance.creditsBalance;
    }
  }

  Stream<Set<String>> _visibleJobIdsStream(
    String? uid, {
    required String ownerType,
  }) {
    final ownerUid = uid?.trim() ?? '';
    if (ownerUid.isEmpty) return Stream.value(const <String>{});
    return JobsRepository(_db)
        .watchMyJobs(
          testMode: widget.testMode,
          userId: ownerUid,
          ownerType: ownerType,
        )
        .map((docs) {
          final ids = <String>{};
          for (final d in docs) {
            final m = d.data();
            final ownerId = (m['ownerId'] ?? '').toString().trim();
            final ownerUidDoc = (m['ownerUid'] ?? '').toString().trim();
            if (!(ownerId == ownerUid || ownerUidDoc == ownerUid)) continue;
            if (!WorkaEntityValidity.isValidPublicVacancy(m)) continue;
            ids.add(d.id);
          }
          return ids;
        });
  }

  Future<ResponseStats> _calcApplyStatsForJobIds(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> jobIds,
    String expectedEmployerUid,
  ) async {
    if (jobIds.isEmpty) return const ResponseStats(fresh: 0, total: 0);
    var total = 0;
    var fresh = 0;
    for (final doc in docs) {
      final m = doc.data();
      if (!_isValidApplyDoc(m)) continue;
      final jobId = _safe(m['jobId']).isNotEmpty
          ? _safe(m['jobId'])
          : _safe(m['vacancyId']);
      if (!jobIds.contains(jobId)) continue;
      if (_applyEmployerOwnerId(m) != expectedEmployerUid) continue;
      final cvId = _safe(m['candidateCvId']).isNotEmpty
          ? _safe(m['candidateCvId'])
          : _safe(m['cvId']);
      if (cvId.isEmpty) continue;
      final linkedEmployer = await _linkedOwnerId(
        collection: FirestorePaths.jobs,
        id: jobId,
        cache: _jobOwnerCache,
      );
      if (linkedEmployer != expectedEmployerUid) continue;
      final cvExists = await _docExists(
        collection: FirestorePaths.cvs,
        id: cvId,
        cache: _cvExistsCache,
      );
      if (!cvExists) continue;
      total += 1;
      if (InteractionStatus.isFresh(_normalizedInteractionStatus(m))) {
        fresh += 1;
      }
    }
    return ResponseStats(fresh: fresh, total: total);
  }

  Stream<ResponseStats> _employerApplicationsStatsForOwnerType(
    String? uid, {
    required String ownerType,
  }) {
    final employerUid = uid?.trim() ?? '';
    if (employerUid.isEmpty) {
      return Stream.value(const ResponseStats(fresh: 0, total: 0));
    }
    final controller = StreamController<ResponseStats>();
    Set<String> jobIds = const <String>{};
    List<QueryDocumentSnapshot<Map<String, dynamic>>> applyDocs =
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    late final StreamSubscription jobsSub;
    late final StreamSubscription appsSub;

    Future<void> emit() async {
      controller.add(
        await _calcApplyStatsForJobIds(applyDocs, jobIds, employerUid),
      );
    }

    jobsSub = _visibleJobIdsStream(employerUid, ownerType: ownerType).listen((
      ids,
    ) {
      jobIds = ids;
      emit();
    }, onError: controller.addError);

    appsSub = _mergedApplicationsStream(uid: employerUid, isEmployerView: true)
        .listen((docs) {
          applyDocs = docs;
          emit();
        }, onError: controller.addError);

    controller.onCancel = () async {
      await jobsSub.cancel();
      await appsSub.cancel();
    };
    return controller.stream;
  }

  Stream<ResponseStats> _candidateApplicationsStats(
    String? uid, {
    String profileType = '',
  }) {
    final candidateUid = uid?.trim() ?? '';
    if (candidateUid.isEmpty) {
      return Stream.value(const ResponseStats(fresh: 0, total: 0));
    }
    return _mergedApplicationsStream(
      uid: candidateUid,
      isEmployerView: false,
    ).asyncMap(
      (docs) => _calcApplyStatsForListAsync(
        docs,
        expectedCandidateUid: candidateUid,
        profileType: profileType,
      ),
    );
  }

  String _safe(dynamic v) => (v ?? '').toString().trim();

  DateTime _interactionUpdatedAt(Map<String, dynamic> m) {
    final ts = m['createdAt'] ?? m['updatedAt'];
    if (ts is Timestamp) return ts.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _normalizedInteractionStatus(Map<String, dynamic> m) {
    final raw = _safe(m['status']);
    return InteractionStatus.normalize(
      raw.isEmpty ? InteractionStatus.sent : raw,
    );
  }

  bool _isValidApplyDoc(Map<String, dynamic> m) {
    return WorkaEntityValidity.isValidResponse(m);
  }

  bool _isValidOfferDoc(Map<String, dynamic> m) {
    return WorkaEntityValidity.isValidOffer(m);
  }

  String _applyEmployerOwnerId(Map<String, dynamic> m) {
    return _safe(m['employerOwnerId']).isNotEmpty
        ? _safe(m['employerOwnerId'])
        : _safe(m['vacancyOwnerId']);
  }

  String _applyCandidateOwnerId(Map<String, dynamic> m) {
    return _safe(m['candidateOwnerId']).isNotEmpty
        ? _safe(m['candidateOwnerId'])
        : _safe(m['candidateUid']);
  }

  String _offerEmployerOwnerId(Map<String, dynamic> m) {
    return _safe(m['employerOwnerId']).isNotEmpty
        ? _safe(m['employerOwnerId'])
        : _safe(m['vacancyOwnerId']);
  }

  String _offerCandidateOwnerId(Map<String, dynamic> m) {
    return _safe(m['candidateOwnerId']).isNotEmpty
        ? _safe(m['candidateOwnerId'])
        : _safe(m['candidateUid']);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _mergedQueryStream(
    List<Query<Map<String, dynamic>>> queries,
  ) {
    final controller =
        StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>();
    final buckets =
        List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.generate(
          queries.length,
          (_) => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
        );
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emit() {
      final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final list in buckets) {
        for (final doc in list) {
          merged[doc.id] = doc;
        }
      }
      final out = merged.values.toList()
        ..sort(
          (a, b) => _interactionUpdatedAt(
            b.data(),
          ).compareTo(_interactionUpdatedAt(a.data())),
        );
      controller.add(out);
    }

    for (var i = 0; i < queries.length; i++) {
      subs.add(
        queries[i].snapshots().listen((snap) {
          buckets[i] = snap.docs;
          emit();
        }, onError: controller.addError),
      );
    }

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _mergedApplicationsStream({
    required String uid,
    required bool isEmployerView,
  }) {
    final primary = _db.collection(FirestorePaths.applications);
    final queries = <Query<Map<String, dynamic>>>[
      primary
          .where('type', isEqualTo: 'apply')
          .where(
            isEmployerView ? 'employerOwnerId' : 'candidateOwnerId',
            isEqualTo: uid,
          ),
      primary
          .where('type', isEqualTo: 'apply')
          .where(
            isEmployerView ? 'employerUid' : 'candidateUid',
            isEqualTo: uid,
          ),
    ];
    if (isEmployerView) {
      queries.add(
        primary
            .where('type', isEqualTo: 'apply')
            .where('vacancyOwnerId', isEqualTo: uid),
      );
    }
    return _mergedQueryStream(queries);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _mergedOffersStream({required String uid, required bool isEmployerView}) {
    final primary = _db.collection(FirestorePaths.jobOffers);
    final queries = <Query<Map<String, dynamic>>>[
      primary
          .where('type', isEqualTo: 'offer')
          .where(
            isEmployerView ? 'employerOwnerId' : 'candidateOwnerId',
            isEqualTo: uid,
          ),
      primary
          .where('type', isEqualTo: 'offer')
          .where(
            isEmployerView ? 'employerUid' : 'candidateUid',
            isEqualTo: uid,
          ),
    ];
    if (isEmployerView) {
      queries.add(
        primary
            .where('type', isEqualTo: 'offer')
            .where('vacancyOwnerId', isEqualTo: uid),
      );
    }
    return _mergedQueryStream(queries);
  }

  Future<ResponseStats> _calcApplyStatsForListAsync(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    String expectedEmployerUid = '',
    String expectedCandidateUid = '',
    String profileType = '',
  }) async {
    var total = 0;
    var fresh = 0;
    for (final doc in docs) {
      final m = doc.data();
      if (!_isValidApplyDoc(m)) continue;
      if (expectedEmployerUid.isNotEmpty &&
          _applyEmployerOwnerId(m) != expectedEmployerUid) {
        continue;
      }
      if (expectedCandidateUid.isNotEmpty &&
          _applyCandidateOwnerId(m) != expectedCandidateUid) {
        continue;
      }
      // Profile type filter (backwards compat: missing field = pass through).
      if (profileType.isNotEmpty) {
        final profileField = expectedEmployerUid.isNotEmpty
            ? (m['vacancyOwnerType'] ?? '').toString().trim()
            : (m['applicantProfileType'] ?? '').toString().trim();
        if (profileField.isNotEmpty && profileField != profileType) continue;
      }
      final jobId = _safe(m['jobId']).isNotEmpty
          ? _safe(m['jobId'])
          : _safe(m['vacancyId']);
      final cvId = _safe(m['candidateCvId']).isNotEmpty
          ? _safe(m['candidateCvId'])
          : _safe(m['cvId']);
      if (jobId.isEmpty || cvId.isEmpty) continue;
      final jobExists = await _docExists(
        collection: FirestorePaths.jobs,
        id: jobId,
        cache: _jobExistsCache,
      );
      if (!jobExists) continue;
      final cvExists = await _docExists(
        collection: FirestorePaths.cvs,
        id: cvId,
        cache: _cvExistsCache,
      );
      if (!cvExists) continue;
      if (expectedEmployerUid.isNotEmpty) {
        final linkedOwner = await _linkedOwnerId(
          collection: FirestorePaths.jobs,
          id: jobId,
          cache: _jobOwnerCache,
        );
        if (linkedOwner != expectedEmployerUid) continue;
      }
      if (expectedCandidateUid.isNotEmpty) {
        final linkedOwner = await _linkedOwnerId(
          collection: FirestorePaths.cvs,
          id: cvId,
          cache: _cvOwnerCache,
        );
        if (linkedOwner != expectedCandidateUid) continue;
      }
      total += 1;
      if (InteractionStatus.isFresh(_normalizedInteractionStatus(m))) {
        fresh += 1;
      }
    }
    return ResponseStats(fresh: fresh, total: total);
  }

  Future<bool> _docExists({
    required String collection,
    required String id,
    required Map<String, bool> cache,
  }) async {
    final clean = id.trim();
    if (clean.isEmpty) return false;
    final key = '$collection/$clean';
    final cached = cache[key];
    if (cached != null) return cached;
    final snap = await _db.collection(collection).doc(clean).get();
    final data = snap.data() ?? const <String, dynamic>{};
    final validByCollection = collection == FirestorePaths.jobs
        ? WorkaEntityValidity.isValidPublicVacancy(data)
        : (collection == FirestorePaths.cvs
              ? WorkaEntityValidity.isValidPublicCv(data)
              : (data['isDeleted'] != true));
    final exists = snap.exists && validByCollection;
    cache[key] = exists;
    return exists;
  }

  Future<String> _linkedOwnerId({
    required String collection,
    required String id,
    required Map<String, String> cache,
  }) async {
    final clean = id.trim();
    if (clean.isEmpty) return '';
    final key = '$collection/$clean';
    final cached = cache[key];
    if (cached != null) return cached;
    final snap = await _db.collection(collection).doc(clean).get();
    final data = snap.data() ?? const <String, dynamic>{};
    if (!snap.exists || data['isDeleted'] == true) {
      cache[key] = '';
      return '';
    }
    final owner = WorkaEntityValidity.resolveOwnerId(
      data,
      keys: const <String>[
        'ownerId',
        'ownerUid',
        'ownerKey',
        'employerOwnerId',
        'candidateOwnerId',
        'employerUid',
        'candidateUid',
      ],
    );
    cache[key] = owner;
    return owner;
  }

  Future<ResponseStats> _calcOfferStatsForListAsync(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool isEmployerView,
    required String expectedOwnerUid,
    String profileType = '',
  }) async {
    var total = 0;
    var fresh = 0;
    for (final doc in docs) {
      final m = doc.data();
      if (!_isValidOfferDoc(m)) continue;
      final jobId = _safe(m['jobId']);
      final cvId = _safe(m['candidateCvId']).isNotEmpty
          ? _safe(m['candidateCvId'])
          : _safe(m['cvId']);
      final isResponseOwnerMatch = isEmployerView
          ? _offerEmployerOwnerId(m) == expectedOwnerUid
          : _offerCandidateOwnerId(m) == expectedOwnerUid;
      if (!isResponseOwnerMatch) continue;
      // Profile type filter (backwards compat: missing field = pass through).
      if (profileType.isNotEmpty) {
        final profileField = isEmployerView
            ? (m['employerType'] ?? '').toString().trim()
            : (m['recipientProfileType'] ?? '').toString().trim();
        if (profileField.isNotEmpty && profileField != profileType) continue;
      }

      // Match OffersListScreen rendering: skip orphaned records that are hidden.
      if (jobId.isEmpty || cvId.isEmpty) continue;
      final jobExists = await _docExists(
        collection: FirestorePaths.jobs,
        id: jobId,
        cache: _jobExistsCache,
      );
      if (!jobExists) continue;
      final cvExists = await _docExists(
        collection: FirestorePaths.cvs,
        id: cvId,
        cache: _cvExistsCache,
      );
      if (!cvExists) continue;
      final linkedOwner = await _linkedOwnerId(
        collection: isEmployerView ? FirestorePaths.jobs : FirestorePaths.cvs,
        id: isEmployerView ? jobId : cvId,
        cache: isEmployerView ? _jobOwnerCache : _cvOwnerCache,
      );
      if (linkedOwner != expectedOwnerUid) continue;

      total += 1;
      if (InteractionStatus.isFresh(_normalizedInteractionStatus(m))) {
        fresh += 1;
      }
    }
    return ResponseStats(fresh: fresh, total: total);
  }

  String _initialsFrom(String text, {String fallback = '?'}) {
    final clean = text.trim();
    if (clean.isEmpty) return fallback;
    final parts = clean
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return fallback;
    String firstChar(String s) => s.isEmpty ? '' : s.substring(0, 1);
    if (parts.length == 1) return firstChar(parts.first).toUpperCase();
    return (firstChar(parts[0]) + firstChar(parts[1])).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (!_tabReady) {
      return ProfileHeaderSection(
        leading: _profileMenuButton(),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final user = _auth.currentUser;
    final uid = AuthGuard.resolveDataUid(testMode: widget.testMode);
    if (user == null) {
      return const AuthEntryScreen();
    }
    final businessUid = uid;
    if (kDebugMode) {
      debugPrint(
        'ProfileScreen build authUid=${user.uid} effectiveUid=$uid email=${user.email} anon=${user.isAnonymous}',
      );
    }

    final profileStream = _profileStream(uid);
    if (profileStream == null) {
      if (kDebugMode) {
        debugPrint(
          'ProfileScreen fallback: profileStream is null for uid="$uid"',
        );
      }
      return ProfileHeaderSection(
        leading: _profileMenuButton(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Профиль временно недоступен.\nПопробуйте обновить экран.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return ProfileHeaderSection(
            leading: _profileMenuButton(),
            body: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (kDebugMode) {
          debugPrint(
            'ProfileScreen userDoc state hasData=${snap.hasData} exists=${snap.data?.exists} uid=$uid',
          );
        }
        if (snap.hasError) {
          debugPrint('ProfileScreen loadProfile error: ${snap.error}');
          final permissionDenied = FirebaseDebugDiagnostics.isPermissionDenied(
            snap.error,
          );
          final errorBody = Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ошибка загрузки профиля: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (permissionDenied && widget.testMode) ...[
                    const SizedBox(height: 10),
                    Text(
                      FirebaseDebugDiagnostics.permissionHintText(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: WorkaColors.accentOrange,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
          return ProfileHeaderSection(
            leading: _profileMenuButton(),
            body: errorBody,
          );
        }
        final profile = snap.data?.data() ?? <String, dynamic>{};
        if (snap.connectionState == ConnectionState.active &&
            snap.hasData &&
            snap.data?.exists == false &&
            profile.isEmpty &&
            kDebugMode) {
          debugPrint('ProfileScreen empty profile document for uid=$uid');
        }

        final firstName = _s(profile['firstName'] ?? profile['name']);
        final lastName = _s(profile['lastName']);
        final fullName = ('$firstName $lastName').trim();
        final isTestAnon = uid.trim().isEmpty && widget.testMode;
        final name = isTestAnon
            ? 'Тестовый профиль'
            : (fullName.isEmpty
                  ? _s(user.displayName, fallback: '')
                  : fullName);

        final email = isTestAnon
            ? ''
            : (_s(profile['email']).isNotEmpty
                  ? _s(profile['email'])
                  : _s(user.email, fallback: ''));
        final phone = isTestAnon
            ? ''
            : (_s(profile['phone']).isNotEmpty
                  ? _s(profile['phone'])
                  : _s(user.phoneNumber, fallback: ''));
        final location = isTestAnon
            ? ''
            : _s(profile['location'], fallback: '');
        final personalProfileCompletedFlag =
            (profile['personalProfileCompleted'] ?? false) == true;
        final isPersonalProfileComplete = _isPersonalProfileComplete(profile);
        if (kDebugMode &&
            personalProfileCompletedFlag != isPersonalProfileComplete) {
          debugPrint(
            'ProfileScreen personal completion mismatch: '
            'flag=$personalProfileCompletedFlag fields=$isPersonalProfileComplete',
          );
        }
        final businessMap = profile['business'] is Map
            ? Map<String, dynamic>.from(profile['business'] as Map)
            : const <String, dynamic>{};
        final companyName = _s(
          profile['companyName'],
          fallback: _s(businessMap['companyName']),
        );
        final employerType = _s(
          profile['employerType'],
          fallback: _s(businessMap['employerType']),
        );
        return _buildProfileContent(
          isBusiness: _selectedTab == ProfileTab.business,
          profile: profile,
          uid: uid,
          businessUid: businessUid.isEmpty ? uid : businessUid,
          name: name,
          email: email,
          phone: phone,
          location: location,
          companyName: companyName,
          employerType: employerType,
        );
      },
    );
  }
}
