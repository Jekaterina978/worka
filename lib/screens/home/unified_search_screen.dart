import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worka/repositories/jobs_repository.dart';
import 'package:worka/features/payments/contact_access_controller.dart';
import 'package:worka/features/payments/models/employer_payment_models.dart';
import 'package:worka/features/payments/screens/contact_unlock_paywall_sheet.dart';
import 'package:worka/features/payments/ux/monetization_behavior_nudges.dart';
import 'package:worka/features/payments/usecases/unlock_candidate_contact_use_case.dart';
import 'package:worka/screens/add_cv_screen.dart';
import 'package:worka/screens/candidates/widgets/candidate_filters_screen.dart';
import 'package:worka/screens/employer/search/widgets/candidate_details_sheet.dart';
import 'package:worka/screens/employer/search/widgets/vacancy_details_sheet.dart';
import 'package:worka/screens/employer/search/models/candidate_filters.dart';
import 'package:worka/screens/search/models/search_filters.dart';
import 'package:worka/screens/search/widgets/filters_sheet.dart';
import 'package:worka/screens/search/widgets/search_filters_config.dart';
import 'package:worka/screens/cv/widgets/cv_picker_sheet.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/auth_guard.dart';
import 'package:worka/services/auth_controller.dart';
import 'package:worka/services/favorites_bus.dart';
import 'package:worka/services/navigation_return_snapshot.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/services/public_cv_sanitizer.dart';
import 'package:worka/services/entity_validity.dart';
import 'package:worka/repositories/response_repository.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:worka/theme/worka_ui_tokens.dart';
import 'package:worka/widgets/burger_drawer.dart';
import 'package:worka/widgets/cards/candidate_list_card.dart';
import 'package:worka/widgets/cards/vacancy_list_card.dart';
import 'package:worka/widgets/favorite_star_button.dart';
import 'package:worka/widgets/worka_job_card.dart';
import 'package:worka/widgets/ui/filter_chip_row.dart';
import 'package:worka/widgets/ui/search_bar.dart' as ui;
import 'package:worka/widgets/candidate_offer_sent_badge.dart';
import 'package:worka/widgets/sent_overlay.dart';
import 'package:worka/widgets/app_background_layout.dart';
import 'package:worka/widgets/profile_avatar_button.dart';
import 'package:worka/utils/country_display_formatter.dart';
import 'package:worka/widgets/vacancy_apply_entry_sheet.dart';

import 'unified_search_filters.dart';

class UnifiedSearchScreen extends StatefulWidget {
  final bool testMode;

  const UnifiedSearchScreen({super.key, this.testMode = true});

  @override
  State<UnifiedSearchScreen> createState() => _UnifiedSearchScreenState();
}

class _UnifiedSearchScreenState extends State<UnifiedSearchScreen>
    with AutomaticKeepAliveClientMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ContactAccessController _contactAccess =
      ContactAccessController.instance;
  final UnlockCandidateContactUseCase _unlockCandidateContact =
      UnlockCandidateContactUseCase();
  final MonetizationBehaviorNudges _nudges =
      MonetizationBehaviorNudges.instance;

  final TextEditingController _qCtrl = TextEditingController();
  final FocusNode _qFocus = FocusNode();
  final ScrollController _vacanciesScroll = ScrollController();
  final ScrollController _candidatesScroll = ScrollController();
  bool _collapsed = false;

  UnifiedSearchFilters _state = UnifiedSearchFilters.initial();
  final _VacancySort _vacancySort = _VacancySort.best;

  bool _showSuggest = false;

  static const _prefsKey = 'worka_favorites_job_ids';
  static const _prefsCandidatesKey = 'worka_favorites_candidate_ids';
  static const _prefsUiStateKeyBase = 'worka_unified_search_ui_state_v1';
  Set<String> _localFav = {};
  Set<String> _remoteFav = {};
  Set<String> _localCandidateFav = {};
  Set<String> _remoteCandidateFav = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _remoteCandidateFavSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingSub;
  StreamSubscription<void>? _favoritesBusSub;
  final Map<String, CandidateContact> _openedContacts =
      <String, CandidateContact>{};
  String _sessionUid = '';
  Timer? _persistDebounce;
  late final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _jobsStreamRef;
  late final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _candidatesStreamRef;
  bool _showViewedContactsNudge = false;
  bool _showIncomingInteractionNudge = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sessionUid = AuthController.instance.currentUid ?? '';
    _jobsStreamRef = _createJobsStream();
    _candidatesStreamRef = _createCandidatesStream();
    AuthController.instance.uidListenable.addListener(_onAuthUidChanged);
    _state = _state.copyWith(mode: NavigationReturnSnapshot.homeMode);
    _restoreUiState();
    _loadLocalFav();
    _listenRemoteFav();
    _loadLocalCandidateFav();
    _listenRemoteCandidateFav();
    _loadOpenedContacts();
    _initNudges();
    _listenIncomingInteractions();
    _favoritesBusSub = FavoritesBus.stream.listen((_) {
      _reloadFavoritesState();
    });

    _qFocus.addListener(() {
      if (!_qFocus.hasFocus) setState(() => _showSuggest = false);
    });

    _qCtrl.addListener(() {
      final t = _qCtrl.text.trim();
      setState(() => _showSuggest = t.isNotEmpty && _qFocus.hasFocus);
      _schedulePersistUiState();
    });
    _vacanciesScroll.addListener(_updateCollapsedFromActiveScroll);
    _candidatesScroll.addListener(_updateCollapsedFromActiveScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCollapsedFromActiveScroll();
      _restorePendingDetailsIfAny();
    });
  }

  @override
  void dispose() {
    AuthController.instance.uidListenable.removeListener(_onAuthUidChanged);
    _vacanciesScroll.removeListener(_updateCollapsedFromActiveScroll);
    _candidatesScroll.removeListener(_updateCollapsedFromActiveScroll);
    _remoteFavSub?.cancel();
    _remoteCandidateFavSub?.cancel();
    _incomingSub?.cancel();
    _favoritesBusSub?.cancel();
    _persistDebounce?.cancel();
    _qCtrl.dispose();
    _qFocus.dispose();
    _vacanciesScroll.dispose();
    _candidatesScroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> _encodeSearchFilters(SearchFilters f) {
    return <String, dynamic>{
      'countries': f.countries.toList(),
      'cityLabel': f.cityLabel,
      'categories': f.categories.toList(),
      'employment': f.employment.toList(),
      'experience': f.experience.toList(),
      'languages': f.languages.toList(),
      'salaryAmount': f.salaryAmount,
      'salaryPeriod': f.salaryPeriod,
      'salaryCurrency': f.salaryCurrency,
      'salaryFromEur': f.salaryFromEur,
      'housing': f.housing,
      'transport': f.transport,
      'teen': f.teen,
      'disability': f.disability,
      'helpsWithDocuments': f.helpsWithDocuments,
      'noLanguageRequired': f.noLanguageRequired,
    };
  }

  SearchFilters _decodeSearchFilters(dynamic raw) {
    if (raw is! Map) return SearchFilters.initial();
    final map = Map<String, dynamic>.from(raw);
    Set<String> asSet(String key) {
      final v = map[key];
      if (v is! List) return <String>{};
      return v.map((e) => e.toString()).toSet();
    }

    double? asDouble(String key) {
      final v = map[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    bool asBool(String key) => map[key] == true;
    final city = (map['cityLabel'] ?? '').toString().trim();
    final salaryPeriod = (map['salaryPeriod'] ?? '').toString().trim();
    final salaryCurrency = (map['salaryCurrency'] ?? '').toString().trim();

    return SearchFilters(
      countries: asSet('countries'),
      cityLabel: city.isEmpty ? null : city,
      categories: asSet('categories'),
      employment: asSet('employment'),
      experience: asSet('experience'),
      languages: asSet('languages'),
      salaryAmount: asDouble('salaryAmount'),
      salaryPeriod: salaryPeriod.isEmpty ? 'В месяц' : salaryPeriod,
      salaryCurrency: salaryCurrency.isEmpty ? 'EUR' : salaryCurrency,
      salaryFromEur: asDouble('salaryFromEur'),
      housing: asBool('housing'),
      transport: asBool('transport'),
      teen: asBool('teen'),
      disability: asBool('disability'),
      helpsWithDocuments: asBool('helpsWithDocuments'),
      noLanguageRequired: asBool('noLanguageRequired'),
    );
  }

  Map<String, dynamic> _encodeCandidateFilters(CandidateFilters f) {
    return <String, dynamic>{
      'countries': f.countries.toList(),
      'cityLabel': f.cityLabel,
      'categories': f.categories.toList(),
      'languages': f.languages.toList(),
      'experience': f.experience.toList(),
      'employment': f.employment.toList(),
      'documents': f.documents.toList(),
      'readyToRelocate': f.readyToRelocate,
      'hasDriverLicense': f.hasDriverLicense,
      'hasCar': f.hasCar,
    };
  }

  CandidateFilters _decodeCandidateFilters(dynamic raw) {
    if (raw is! Map) return CandidateFilters.initial();
    final map = Map<String, dynamic>.from(raw);
    Set<String> asSet(String key) {
      final v = map[key];
      if (v is! List) return <String>{};
      return v.map((e) => e.toString()).toSet();
    }

    final city = (map['cityLabel'] ?? '').toString().trim();
    return CandidateFilters(
      countries: asSet('countries'),
      cityLabel: city.isEmpty ? null : city,
      categories: asSet('categories'),
      languages: asSet('languages'),
      experience: asSet('experience'),
      employment: asSet('employment'),
      documents: asSet('documents'),
      readyToRelocate: map['readyToRelocate'] == true,
      hasDriverLicense: map['hasDriverLicense'] == true,
      hasCar: map['hasCar'] == true,
    );
  }

  Map<String, dynamic> _encodeUiState() {
    return <String, dynamic>{
      'mode': _state.mode.name,
      'query': _qCtrl.text,
      'vacancy': _encodeSearchFilters(_state.vacancy),
      'candidate': _encodeCandidateFilters(_state.candidate),
      'savedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _persistUiState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _uiStateKeyForSession(),
      jsonEncode(_encodeUiState()),
    );
  }

  void _schedulePersistUiState() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 220), () {
      _persistUiState();
    });
  }

  Future<void> _restoreUiState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_uiStateKeyForSession());
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final modeRaw = (map['mode'] ?? '').toString().trim();
      final mode = modeRaw == SearchMode.candidates.name
          ? SearchMode.candidates
          : SearchMode.vacancies;
      final query = (map['query'] ?? '').toString();
      final vacancy = _decodeSearchFilters(map['vacancy']);
      final candidate = _decodeCandidateFilters(map['candidate']);

      if (!mounted) return;
      setState(() {
        _state = UnifiedSearchFilters(
          mode: mode,
          vacancy: vacancy,
          candidate: candidate,
        );
        _qCtrl.text = query;
        _qCtrl.selection = TextSelection.collapsed(offset: _qCtrl.text.length);
      });
      NavigationReturnSnapshot.setHomeMode(mode);
    } catch (_) {
      // Ignore corrupted local UI state.
    }
  }

  void _updateCollapsedFromActiveScroll() {
    final active = _state.mode == SearchMode.vacancies
        ? _vacanciesScroll
        : _candidatesScroll;
    final shouldCollapse = active.hasClients && active.offset > 60;
    if (shouldCollapse != _collapsed && mounted) {
      setState(() => _collapsed = shouldCollapse);
    }
  }

  void _onAuthUidChanged() {
    final nextUid = AuthController.instance.currentUid ?? '';
    if (nextUid == _sessionUid) return;
    if (kDebugMode) {
      debugPrint(
        'UnifiedSearchScreen auth uid changed $_sessionUid -> $nextUid, resetting favorites state',
      );
    }
    _sessionUid = nextUid;
    _remoteFavSub?.cancel();
    _remoteCandidateFavSub?.cancel();
    if (!mounted) return;
    setState(() {
      _remoteFav = <String>{};
      _localFav = <String>{};
      _remoteCandidateFav = <String>{};
      _localCandidateFav = <String>{};
      _showSuggest = false;
    });
    _loadLocalFav();
    _listenRemoteFav();
    _loadLocalCandidateFav();
    _listenRemoteCandidateFav();
    _loadOpenedContacts();
    _restoreUiState();
  }

  Future<void> _reloadFavoritesState() async {
    await Future.wait([_loadLocalFav(), _loadLocalCandidateFav()]);
    _listenRemoteFav();
    _listenRemoteCandidateFav();
  }

  Future<void> _loadOpenedContacts() async {
    await _contactAccess.bootstrap(uid: _auth.currentUser?.uid);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _initNudges() async {
    await _nudges.bootstrap(uid: _auth.currentUser?.uid ?? 'guest');
    if (!mounted) return;
    setState(() {
      _showViewedContactsNudge = _nudges.shouldShowViewedContactsNudge;
    });
  }

  void _listenIncomingInteractions() {
    final uid = (_auth.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) return;
    _incomingSub?.cancel();
    _incomingSub = _db
        .collection(FirestorePaths.applications)
        .where('employerOwnerId', isEqualTo: uid)
        .where('status', whereIn: const ['sent', 'viewed'])
        .limit(1)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _showIncomingInteractionNudge =
                snap.docs.isNotEmpty &&
                _nudges.shouldShowIncomingInteractionNudge;
          });
        });
  }

  Future<void> _onViewedWithoutUnlock(String candidateId) async {
    await _nudges.registerViewedWithoutUnlock(candidateId);
    if (!mounted) return;
    setState(() {
      _showViewedContactsNudge = _nudges.shouldShowViewedContactsNudge;
    });
  }

  Future<void> _dismissViewedContactsNudge() async {
    await _nudges.markViewedNudgeShown();
    if (!mounted) return;
    setState(() => _showViewedContactsNudge = false);
  }

  Future<void> _dismissIncomingNudge() async {
    await _nudges.markIncomingNudgeShown();
    if (!mounted) return;
    setState(() => _showIncomingInteractionNudge = false);
  }

  Future<void> _openNudgePaywall({
    required String entryPoint,
    required Future<void> Function() markShown,
  }) async {
    await markShown();
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await ContactUnlockPaywallSheet.open(
      context,
      entryPoint: entryPoint,
      mode: PaywallMode.creditsOnly,
    );
  }

  Widget _nudgeBanner({
    required String text,
    required String entryPoint,
    required Future<void> Function() onDismiss,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WorkaColors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: WorkaColors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: WorkaColors.textDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                _openNudgePaywall(entryPoint: entryPoint, markShown: onDismiss),
            child: const Text(
              'Открыть контакты',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: WorkaColors.textGreyDark,
            ),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : WorkaColors.textDark,
      ),
    );
  }

  Future<void> _handleContactTap({
    required String candidateId,
    required String candidateName,
    required VoidCallback openDetails,
  }) async {
    await _showContactBottomSheet(
      candidateId: candidateId,
      candidateName: candidateName,
      openDetails: openDetails,
    );
  }

  Future<void> _showContactBottomSheet({
    required String candidateId,
    required String candidateName,
    required VoidCallback openDetails,
  }) async {
    if (!mounted) return;
    CandidateContact? contact =
        _openedContacts[candidateId] ??
        _contactAccess.contactForCandidate(candidateId);
    var hasAccess = _contactAccess.hasAccess(candidateId);
    if (hasAccess && contact == null) {
      contact = await _contactAccess.ensureLoadedContactForCandidate(
        candidateId,
      );
      if (contact != null) {
        _openedContacts[candidateId] = contact;
      }
    }
    if (!mounted) return;
    var loading = false;
    var creditsLeft = _contactAccess.creditsBalance;

    String maskPhone(String value) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 6) return '+371 *** **23';
      final prefix = '+${digits.substring(0, 3)}';
      final tail = digits.substring(digits.length - 2);
      return '$prefix *** **$tail';
    }

    String maskEmail(String value) {
      final trimmed = value.trim();
      if (!trimmed.contains('@')) return 'j***@gmail.com';
      final parts = trimmed.split('@');
      final local = parts.first.trim();
      final domain = parts.last.trim();
      if (local.isEmpty || domain.isEmpty) return 'j***@gmail.com';
      return '${local.substring(0, 1)}***@$domain';
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WorkaColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> unlock() async {
              if (loading || _contactAccess.isUnlockInProgress(candidateId)) {
                return;
              }
              setSheetState(() => loading = true);
              try {
                if (!context.mounted) return;
                final rootContext = Navigator.of(
                  context,
                  rootNavigator: true,
                ).context;
                final result = await _unlockCandidateContact(
                  rootContext,
                  candidateId: candidateId,
                  candidateName: candidateName,
                  entryPoint: 'unified_search_bottom_sheet',
                );
                if (!result.isSuccess) {
                  if (result.status == ContactUnlockStatus.purchasePending) {
                    final message = result.message.trim().isNotEmpty
                        ? result.message.trim()
                        : 'Платёж подтверждён, кредиты обновляются...';
                    _toast(message);
                  } else if (result.status == ContactUnlockStatus.cancelled) {
                    _toast('Оплата отменена');
                  } else {
                    final message = result.message.trim().isNotEmpty
                        ? result.message.trim()
                        : 'Не удалось открыть контакты';
                    _toast(message, error: true);
                  }
                  setSheetState(() => loading = false);
                  return;
                }
                contact =
                    result.contact ??
                    await _contactAccess.ensureLoadedContactForCandidate(
                      candidateId,
                    ) ??
                    contact;
                if (contact != null) {
                  _openedContacts[candidateId] = contact!;
                }
                creditsLeft = result.creditsLeft;
                hasAccess = true;
                if (mounted) setState(() {});
              } catch (_) {
                _toast('Не удалось открыть контакты', error: true);
              } finally {
                setSheetState(() => loading = false);
              }
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: SizedBox(
                        width: 44,
                        child: Divider(
                          thickness: 4,
                          color: WorkaColors.fieldBorder,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hasAccess ? 'Контакты открыты' : 'Контакты кандидата',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: WorkaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      candidateName.isEmpty ? 'Кандидат' : candidateName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: WorkaColors.textGreyDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Телефон: ${hasAccess ? (contact?.phone.trim().isNotEmpty == true ? contact!.phone : '—') : maskPhone(contact?.phone ?? '')}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Email: ${hasAccess ? (contact?.email.trim().isNotEmpty == true ? contact!.email : '—') : maskEmail(contact?.email ?? '')}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (hasAccess) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Контакты открыты',
                        style: TextStyle(
                          color: WorkaColors.textGreyDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Кредитов осталось: $creditsLeft',
                        style: const TextStyle(
                          color: WorkaColors.textGreyDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: loading
                                ? null
                                : () => Navigator.pop(sheetCtx),
                            child: const Text('Закрыть'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: hasAccess
                              ? ElevatedButton(
                                  onPressed: loading
                                      ? null
                                      : () {
                                          Navigator.pop(sheetCtx);
                                          openDetails();
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: WorkaColors.blue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Открыть профиль',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                )
                              : ElevatedButton(
                                  onPressed: loading ? null : unlock,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: WorkaColors.blue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Открыть контакты',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _uiStateKeyForSession() {
    final owner = _sessionUid.trim().isEmpty ? 'guest' : _sessionUid.trim();
    return '${_prefsUiStateKeyBase}_$owner';
  }

  Future<void> _restorePendingDetailsIfAny() async {
    final vacancyId = NavigationReturnSnapshot.pendingVacancyId;
    if (vacancyId != null && vacancyId.isNotEmpty) {
      NavigationReturnSnapshot.clearPendingDetails();
      await VacancyDetailsSheet.open(
        context,
        jobId: vacancyId,
        testMode: widget.testMode,
      );
      return;
    }

    final candidateId = NavigationReturnSnapshot.pendingCandidateId;
    final candidateUid = NavigationReturnSnapshot.pendingCandidateUid;
    if (candidateId != null &&
        candidateId.isNotEmpty &&
        candidateUid != null &&
        candidateUid.isNotEmpty) {
      NavigationReturnSnapshot.clearPendingDetails();
      await CandidateDetailsSheet.open(
        context,
        candidateId: candidateId,
        candidateUid: candidateUid,
        testMode: widget.testMode,
      );
    }
  }

  void _listenRemoteFav() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _remoteFavSub?.cancel();
    _remoteFavSub = _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .snapshots()
        .listen((snap) {
          final ids = <String>{};
          for (final d in snap.docs) {
            ids.add(d.id);
          }
          if (!mounted) return;
          setState(() => _remoteFav = ids);
        });
  }

  void _listenRemoteCandidateFav() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _remoteCandidateFavSub?.cancel();
    _remoteCandidateFavSub = _db
        .collection('users')
        .doc(uid)
        .collection('favoritesCandidates')
        .snapshots()
        .listen((snap) {
          final ids = <String>{};
          for (final d in snap.docs) {
            ids.add(d.id);
          }
          if (!mounted) return;
          setState(() => _remoteCandidateFav = ids);
        });
  }

  Future<void> _loadLocalFav() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() => _localFav = list.toSet());
  }

  Future<void> _loadLocalCandidateFav() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsCandidatesKey) ?? const <String>[];
    if (!mounted) return;
    setState(() => _localCandidateFav = list.toSet());
  }

  Future<void> _saveLocalFav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _localFav.toList());
  }

  Future<void> _saveLocalCandidateFav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsCandidatesKey, _localCandidateFav.toList());
  }

  bool _isFav(String id) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return _localFav.contains(id);
    // When logged in, remote is the source of truth; local is only for guests.
    return _remoteFav.contains(id);
  }

  bool _isCandidateFav(String id) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return _localCandidateFav.contains(id);
    // When logged in, remote is the source of truth.
    return _remoteCandidateFav.contains(id);
  }

  Future<void> _toggleFav(String id, Map<String, dynamic> jobData) async {
    final uid = _auth.currentUser?.uid;
    final nowFav = !_isFav(id);

    if (uid != null) {
      // Optimistic update on the remote set so the star flips instantly.
      setState(() {
        if (nowFav) {
          _remoteFav.add(id);
        } else {
          _remoteFav.remove(id);
        }
      });
    } else {
      setState(() {
        if (nowFav) {
          _localFav.add(id);
        } else {
          _localFav.remove(id);
        }
      });
      await _saveLocalFav();
    }

    if (uid != null) {
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('favorites')
          .doc(id);

      if (nowFav) {
        await ref.set({
          'jobId': id,
          'title': jobData['title'],
          'city': jobData['city'],
          'country': jobData['country'],
          'salary': jobData['salary'],
          'type': jobData['type'] ?? jobData['employmentType'],
          'category': jobData['category'],
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await ref.delete();
      }
    }

    FavoritesBus.notify();
  }

  Future<void> _toggleCandidateFav(
    String candidateId,
    Map<String, dynamic> candidateData,
  ) async {
    final uid = _auth.currentUser?.uid;
    final nowFav = !_isCandidateFav(candidateId);

    if (uid != null) {
      // Optimistic update on the remote set so the star flips instantly.
      setState(() {
        if (nowFav) {
          _remoteCandidateFav.add(candidateId);
        } else {
          _remoteCandidateFav.remove(candidateId);
        }
      });
    } else {
      setState(() {
        if (nowFav) {
          _localCandidateFav.add(candidateId);
        } else {
          _localCandidateFav.remove(candidateId);
        }
      });
      await _saveLocalCandidateFav();
    }

    if (uid != null) {
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('favoritesCandidates')
          .doc(candidateId);

      if (nowFav) {
        await ref.set({
          'candidateId': candidateId,
          'name': _candidateName(candidateData),
          'profession': _candidateProfession(candidateData),
          'city': _candidateCity(candidateData),
          'country': _candidateCountry(candidateData),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await ref.delete();
      }
    }

    FavoritesBus.notify();
  }

  DateTime _dt(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _sortJobsLocal(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    docs.sort((a, b) {
      final au = _dt(a.data()['updatedAt']);
      final bu = _dt(b.data()['updatedAt']);
      if (au != bu) return bu.compareTo(au);
      final ac = _dt(a.data()['createdAt']);
      final bc = _dt(b.data()['createdAt']);
      return bc.compareTo(ac);
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _createJobsStream() {
    final stream = JobsRepository(
      _db,
    ).watchSearchJobs(testMode: widget.testMode);

    return stream.map((s) {
      final docs = [...s];
      _sortJobsLocal(docs);
      return docs;
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _createCandidatesStream() {
    return _db
        .collection(FirestorePaths.cvs)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) {
          final docs = [...s.docs];
          docs.sort((a, b) {
            final au = _dt(a.data()['updatedAt']);
            final bu = _dt(b.data()['updatedAt']);
            if (au != bu) return bu.compareTo(au);
            final ac = _dt(a.data()['createdAt']);
            final bc = _dt(b.data()['createdAt']);
            return bc.compareTo(ac);
          });
          return docs
              .where((d) => WorkaEntityValidity.isValidPublicCv(d.data()))
              .toList();
        });
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  bool _toBoolValue(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final t = (v ?? '').toString().trim().toLowerCase();
    return t == 'true' || t == '1' || t == 'yes' || t == 'да';
  }

  bool _hasVerifiedEmployerFlag(Map<String, dynamic> m) {
    return m.containsKey('verifiedEmployer') ||
        m.containsKey('isVerified') ||
        m.containsKey('employerVerified') ||
        m.containsKey('verified');
  }

  bool _verifiedEmployerForCard(String jobId, Map<String, dynamic> m) {
    final fromData =
        _toBoolValue(m['verifiedEmployer']) ||
        _toBoolValue(m['isVerified']) ||
        _toBoolValue(m['employerVerified']) ||
        _toBoolValue(m['verified']);
    if (fromData) return true;
    if (_hasVerifiedEmployerFlag(m)) return false;
    // Для demo/mock показываем только на части карточек.
    return widget.testMode && jobId.hashCode.abs() % 4 == 0;
  }

  List<String> _tokenize(String raw) {
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) return const [];
    return s
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _shouldHideDebugContent(Map<String, dynamic> m) {
    if ((m['isDeleted'] ?? false) == true) return true;
    final status = _s(m['status']).toLowerCase();
    if (status == 'blocked' || status == 'banned' || status == 'suspended') {
      return true;
    }
    return false;
  }

  List<String> _suggestions(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final out = <String>[];
    for (final w in SearchFiltersConfig.keywordHints) {
      if (w.toLowerCase().contains(s)) out.add(w);
      if (out.length >= 10) break;
    }
    return out;
  }

  Future<void> _openFilters() async {
    if (_state.mode == SearchMode.vacancies) {
      final res = await Navigator.push<SearchFilters>(
        context,
        MaterialPageRoute(
          builder: (_) => FiltersScreen(initial: _state.vacancy),
        ),
      );
      if (res == null) return;
      setState(() => _state = _state.copyWith(vacancy: res));
      _schedulePersistUiState();
      return;
    }

    final res = await Navigator.push<CandidateFilters>(
      context,
      MaterialPageRoute(
        builder: (_) => CandidateFiltersScreen(initial: _state.candidate),
      ),
    );
    if (res == null) return;
    setState(() => _state = _state.copyWith(candidate: res));
    _schedulePersistUiState();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _applyVacancyFiltersAsync(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final filters = _state.vacancy;
    final qTokens = _tokenize(_qCtrl.text);
    final cityLabel = (filters.cityLabel ?? '').trim().toLowerCase();

    bool matchKeywords(Map<String, dynamic> m) {
      if (qTokens.isEmpty) return true;
      final hay = [
        _s(m['title']).toLowerCase(),
        _s(m['description']).toLowerCase(),
        _s(m['category']).toLowerCase(),
        _s(m['profession']).toLowerCase(),
        _s(m['city']).toLowerCase(),
        _s(m['country']).toLowerCase(),
        _s(m['employmentType']).toLowerCase(),
        _s(m['type']).toLowerCase(),
        _s(m['language']).toLowerCase(),
      ].join(' ');
      for (final t in qTokens) {
        if (!hay.contains(t)) return false;
      }
      return true;
    }

    bool matchLocation(Map<String, dynamic> m) {
      if (cityLabel.isNotEmpty) {
        final city = _s(m['city']).toLowerCase();
        final country = _s(m['country']).toLowerCase();
        final label = '$city • $country';
        return label.contains(cityLabel) ||
            city.contains(cityLabel) ||
            country.contains(cityLabel);
      }

      if (filters.countries.isEmpty) return true;
      final c = _s(m['country']);
      if (c.isEmpty) return true;
      return filters.countries.contains(c);
    }

    bool matchCategory(Map<String, dynamic> m) {
      if (filters.categories.isEmpty) return true;
      final v = _s(m['category']);
      if (v.isEmpty) return false;
      return filters.categories.contains(v);
    }

    bool matchEmployment(Map<String, dynamic> m) {
      if (filters.employment.isEmpty) return true;
      final v = _s(m['employmentType'], fallback: _s(m['type']));
      if (v.isEmpty) return true;
      return filters.employment.contains(v);
    }

    bool matchExperience(Map<String, dynamic> m) {
      if (filters.experience.isEmpty) return true;
      final raw = _s(m['experience']).toLowerCase();
      if (raw.isEmpty) {
        return filters.experience.contains('Без опыта');
      }

      String bucket;
      if (raw.contains('без')) {
        bucket = 'Без опыта';
      } else if (raw.contains('3+')) {
        bucket = '3+ года';
      } else if (raw.contains('1–3') ||
          raw.contains('1-3') ||
          (raw.contains('1') && raw.contains('3'))) {
        bucket = '1–3 года';
      } else if (raw.contains('до 1') ||
          raw.contains('0-1') ||
          raw.contains('0–1')) {
        bucket = 'До 1 года';
      } else if (raw.contains('3')) {
        bucket = '3+ года';
      } else {
        bucket = 'До 1 года';
      }

      return filters.experience.contains(bucket);
    }

    bool matchLanguages(Map<String, dynamic> m) {
      if (filters.languages.isEmpty) return true;
      final v = _s(m['language']);
      if (filters.languages.contains('Без языка') && v.isEmpty) return true;
      if (v.isEmpty) return false;
      return filters.languages.contains(v);
    }

    bool matchSwitches(Map<String, dynamic> m) {
      if (filters.housing && m['housingProvided'] != true) return false;
      if (filters.transport && m['transportProvided'] != true) return false;
      if (filters.teen && m['teenFriendly'] != true) return false;
      if (filters.disability && m['disabilityFriendly'] != true) return false;
      if (filters.helpsWithDocuments) {
        final helps =
            (m['helpsWithDocuments'] == true) ||
            (m['documentsSupport'] == true) ||
            (m['documentsHelp'] == true);
        if (!helps) return false;
      }
      if (filters.noLanguageRequired) {
        final noLanguage =
            (m['noLanguageRequired'] == true) ||
            (m['languageRequired'] == false) ||
            _s(m['language']).isEmpty ||
            _s(m['language']).toLowerCase() == 'без языка';
        if (!noLanguage) return false;
      }
      return true;
    }

    final out = docs.where((d) {
      final m = d.data();
      if (_shouldHideDebugContent(m)) return false;
      return matchKeywords(m) &&
          matchLocation(m) &&
          matchCategory(m) &&
          matchEmployment(m) &&
          matchExperience(m) &&
          matchLanguages(m) &&
          matchSwitches(m);
    }).toList();

    DateTime at(Map<String, dynamic> m) {
      final updatedAt = m['updatedAt'];
      if (updatedAt is Timestamp) return updatedAt.toDate();
      final createdAt = m['createdAt'];
      if (createdAt is Timestamp) return createdAt.toDate();
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    double salaryRank(Map<String, dynamic> m) {
      final eur = m['salaryEurPerMonth'];
      if (eur is num) return eur.toDouble();
      final from = m['salaryFrom'];
      if (from is num) return from.toDouble();
      return 0;
    }

    switch (_vacancySort) {
      case _VacancySort.newest:
        out.sort((a, b) => at(b.data()).compareTo(at(a.data())));
        break;
      case _VacancySort.salary:
        out.sort(
          (a, b) => salaryRank(b.data()).compareTo(salaryRank(a.data())),
        );
        break;
      case _VacancySort.best:
        out.sort((a, b) {
          final ia = _hasPaidUrgent(a.data()) ? 1 : 0;
          final ib = _hasPaidUrgent(b.data()) ? 1 : 0;
          return ib.compareTo(ia);
        });
        break;
    }

    return out;
  }

  Map<String, dynamic> _contacts(Map<String, dynamic> m) =>
      (m['contacts'] is Map)
      ? Map<String, dynamic>.from(m['contacts'])
      : <String, dynamic>{};
  Map<String, dynamic> _desired(Map<String, dynamic> m) => (m['desired'] is Map)
      ? Map<String, dynamic>.from(m['desired'])
      : <String, dynamic>{};

  bool _hasPaidUrgent(Map<String, dynamic> m) {
    if (m['isUrgent'] != true) return false;
    if (m['paidUrgent'] == true) return true;
    if (m['urgentActiveUntil'] != null) return true;
    return false;
  }

  String _candidateName(Map<String, dynamic> m) {
    final c = _contacts(m);
    final full = _s(c['name']);
    if (full.isNotEmpty) return full;
    final out = '${_s(c['firstName'])} ${_s(c['lastName'])}'.trim();
    return out.isEmpty ? 'Кандидат' : out;
  }

  String _candidateProfession(Map<String, dynamic> m) {
    final d = _desired(m);
    final p = _s(d['position']);
    if (p.isNotEmpty) return p;
    final g = _s(d['categoryGroup']);
    if (g.isNotEmpty) return g;
    return _s(m['title']);
  }

  String _candidateCity(Map<String, dynamic> m) {
    final d = _desired(m);
    final raw = _s(d['citiesText']);
    if (raw.isEmpty) return '';
    return raw.split(',').first.trim();
  }

  String _candidateCountry(Map<String, dynamic> m) {
    final d = _desired(m);
    final countries = (d['countries'] is List)
        ? (d['countries'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    return countries.isEmpty ? '' : countries.first;
  }

  String _candidateCategory(Map<String, dynamic> m) =>
      _s(_desired(m)['categoryGroup']);

  String _candidateLanguage(Map<String, dynamic> m) {
    final list = (m['languages'] is List) ? (m['languages'] as List) : const [];
    return list
        .map((e) => (e is Map ? _s(e['language']) : ''))
        .where((e) => e.isNotEmpty)
        .join(', ');
  }

  Set<String> _candidateLanguagesSet(Map<String, dynamic> m) {
    final out = <String>{};
    final langs = m['languages'];
    if (langs is List) {
      for (final e in langs) {
        if (e is Map) {
          final l = _s(e['language']);
          if (l.isNotEmpty) out.add(l);
        } else {
          final l = _s(e);
          if (l.isNotEmpty) out.add(l);
        }
      }
    }
    final single = _s(m['language']);
    if (single.isNotEmpty) out.add(single);
    return out;
  }

  String _candidateExperience(Map<String, dynamic> m) {
    final list = (m['experience'] is List)
        ? (m['experience'] as List)
        : const [];
    if (list.isEmpty) return 'Без опыта';
    return 'Опыт есть';
  }

  String _candidateExperienceBucket(Map<String, dynamic> m) {
    final raw = _s(m['experience']).toLowerCase();
    if (raw.isNotEmpty) {
      if (raw.contains('без')) return 'Без опыта';
      if (raw.contains('1') || raw.contains('2')) return '1–2';
      if (raw.contains('3') || raw.contains('4') || raw.contains('5+')) {
        return '3+';
      }
    }
    final list = (m['experience'] is List)
        ? (m['experience'] as List)
        : const [];
    if (list.isEmpty) return 'Без опыта';
    if (list.length <= 2) return '1–2';
    return '3+';
  }

  Set<String> _candidateEmploymentSet(Map<String, dynamic> m) {
    final d = _desired(m);
    final out = <String>{};
    final e = d['employmentType'] ?? m['employmentType'] ?? m['type'];
    final single = _s(e);
    if (single.isNotEmpty) out.add(single);
    final many = d['employmentTypes'] ?? m['employmentTypes'];
    if (many is List) {
      for (final v in many) {
        final s = _s(v);
        if (s.isNotEmpty) out.add(s);
      }
    }
    return out;
  }

  Set<String> _candidateDocuments(Map<String, dynamic> m) {
    final out = <String>{};
    final docs = m['documents'];
    if (docs is List) {
      for (final d in docs) {
        final s = _s(d);
        if (s.isNotEmpty) out.add(s);
      }
    }
    final docsMap = m['documents'] is Map
        ? Map<String, dynamic>.from(m['documents'] as Map)
        : <String, dynamic>{};
    if (m['euPassport'] == true || docsMap['euPassport'] == true) {
      out.add('Паспорт ЕС');
    }
    if (m['residencePermit'] == true ||
        m['vnj'] == true ||
        docsMap['residencePermit'] == true ||
        docsMap['vnj'] == true) {
      out.add('ВНЖ');
    }
    if (m['visa'] == true || docsMap['visa'] == true) {
      out.add('Виза');
    }
    return out;
  }

  bool? _candidateFlag(Map<String, dynamic> m, List<String> keys) {
    for (final key in keys) {
      if (!m.containsKey(key)) continue;
      final v = m[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final t = v.trim().toLowerCase();
        if (t == 'true' || t == 'yes' || t == '1') return true;
        if (t == 'false' || t == 'no' || t == '0') return false;
      }
    }
    return null;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyCandidateFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final filters = _state.candidate;
    final qTokens = _tokenize(_qCtrl.text);
    final cityLabel = (filters.cityLabel ?? '').trim().toLowerCase();

    bool matchKeywords(Map<String, dynamic> m) {
      if (qTokens.isEmpty) return true;
      final hay = [
        _candidateName(m).toLowerCase(),
        _s(m['about']).toLowerCase(),
        _candidateCategory(m).toLowerCase(),
        _candidateProfession(m).toLowerCase(),
        _candidateLanguage(m).toLowerCase(),
        _candidateExperience(m).toLowerCase(),
        _candidateCity(m).toLowerCase(),
        _candidateCountry(m).toLowerCase(),
      ].join(' ');
      for (final t in qTokens) {
        if (!hay.contains(t)) return false;
      }
      return true;
    }

    bool matchCategory(Map<String, dynamic> m) {
      if (filters.categories.isEmpty) return true;
      final v = _candidateCategory(m);
      if (v.isEmpty) return false;
      return filters.categories.contains(v);
    }

    bool matchLocation(Map<String, dynamic> m) {
      if (cityLabel.isNotEmpty) {
        final city = _candidateCity(m).toLowerCase();
        final country = _candidateCountry(m).toLowerCase();
        final label = '$city • $country';
        return label.contains(cityLabel) ||
            city.contains(cityLabel) ||
            country.contains(cityLabel);
      }
      if (filters.countries.isEmpty) return true;
      final c = _candidateCountry(m);
      if (c.isEmpty) return true;
      return filters.countries.contains(c);
    }

    bool matchLang(Map<String, dynamic> m) {
      if (filters.languages.isEmpty) return true;
      final set = _candidateLanguagesSet(m);
      if (filters.languages.contains('Без языка') && set.isEmpty) return true;
      if (set.isEmpty) return true;
      return set.any(filters.languages.contains);
    }

    bool matchExp(Map<String, dynamic> m) {
      if (filters.experience.isEmpty) return true;
      final bucket = _candidateExperienceBucket(m);
      if (bucket.isEmpty) return true;
      return filters.experience.contains(bucket);
    }

    bool matchEmployment(Map<String, dynamic> m) {
      if (filters.employment.isEmpty) return true;
      final set = _candidateEmploymentSet(m);
      if (set.isEmpty) return true;
      return set.any(filters.employment.contains);
    }

    bool matchDocuments(Map<String, dynamic> m) {
      if (filters.documents.isEmpty) return true;
      final set = _candidateDocuments(m);
      if (set.isEmpty) return true;
      return set.any(filters.documents.contains);
    }

    bool matchReadyToRelocate(Map<String, dynamic> m) {
      if (!filters.readyToRelocate) return true;
      final v = _candidateFlag(m, const [
        'readyToRelocate',
        'willingToRelocate',
        'relocate',
      ]);
      return v ?? true;
    }

    bool matchHasDriverLicense(Map<String, dynamic> m) {
      if (!filters.hasDriverLicense) return true;
      final v = _candidateFlag(m, const [
        'hasDriverLicense',
        'driverLicense',
        'license',
      ]);
      return v ?? true;
    }

    bool matchHasCar(Map<String, dynamic> m) {
      if (!filters.hasCar) return true;
      final v = _candidateFlag(m, const ['hasCar', 'ownCar', 'carAvailable']);
      return v ?? true;
    }

    return docs.where((d) {
      final m = d.data();
      if (_shouldHideDebugContent(m)) return false;
      return matchKeywords(m) &&
          matchLocation(m) &&
          matchCategory(m) &&
          matchLang(m) &&
          matchExp(m) &&
          matchEmployment(m) &&
          matchDocuments(m) &&
          matchReadyToRelocate(m) &&
          matchHasDriverLicense(m) &&
          matchHasCar(m);
    }).toList();
  }

  Widget _emptyVacancies() {
    final baseStyle = const TextStyle(
      fontWeight: FontWeight.w800,
      color: WorkaColors.textGreyDark,
      height: 1.25,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: baseStyle,
            children: [
              const TextSpan(
                text:
                    'К сожалению, по вашим параметрам ничего не найдено, попробуйте изменить параметры поиска или ',
              ),
              TextSpan(
                text: 'добавьте свое CV',
                style: baseStyle.copyWith(
                  color: WorkaColors.blue,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.underline,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => const AddCvScreen()),
                    );
                  },
              ),
              const TextSpan(
                text: ' чтобы работодатели могли связаться с вами',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: const Offset(0, 1),
                child: IconButton(
                  onPressed: () =>
                      BurgerDrawer.open(context, testMode: widget.testMode),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: const Icon(
                    Icons.menu_rounded,
                    size: 26,
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.all(6),
                  splashRadius: 22,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Worka',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 28,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: ProfileAvatarButton(testMode: widget.testMode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchControls() {
    final controlH = _collapsed ? 42.0 : 44.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                    boxShadow: WorkaUiShadows.card,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ui.SearchBar(
                          controller: _qCtrl,
                          focusNode: _qFocus,
                          hintText: 'Найти работу',
                          height: controlH,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: controlH,
                        width: controlH,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: WorkaColors.orange,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [WorkaUiShadows.single],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: _openFilters,
                              child: const Icon(
                                Icons.tune_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showSuggest) ...[
                  const SizedBox(height: 8),
                  _SuggestBox(
                    items: _suggestions(_qCtrl.text),
                    onPick: (v) {
                      _qCtrl.text = v;
                      _qCtrl.selection = TextSelection.collapsed(
                        offset: v.length,
                      );
                      setState(() => _showSuggest = false);
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFigmaFilterChipsRow() {
    final f = _state.vacancy;
    final salary2000Selected =
        (f.salaryAmount ?? 0) >= 2000 &&
        f.salaryCurrency == 'EUR' &&
        f.salaryPeriod == 'В месяц';
    final items = [
      FilterChipRowItem(
        label: 'Жильё',
        icon: Icons.home_outlined,
        iconColor: WorkaColors.blue,
        selected: f.housing,
        onSelected: (_) {
          setState(() {
            _state = _state.copyWith(vacancy: f.copyWith(housing: !f.housing));
          });
          _schedulePersistUiState();
        },
      ),
      FilterChipRowItem(
        label: '€2000+',
        icon: Icons.euro_rounded,
        iconColor: WorkaColors.salaryAccent,
        labelColor: WorkaColors.salaryAccent,
        selected: salary2000Selected,
        onSelected: (_) {
          setState(() {
            _state = _state.copyWith(
              vacancy: salary2000Selected
                  ? f.copyWith(
                      clearSalaryAmount: true,
                      clearSalaryFromEur: true,
                    )
                  : f.copyWith(
                      salaryAmount: 2000,
                      salaryCurrency: 'EUR',
                      salaryPeriod: 'В месяц',
                      clearSalaryFromEur: true,
                    ),
            );
          });
          _schedulePersistUiState();
        },
      ),
      FilterChipRowItem(
        label: 'Без языка',
        icon: Icons.close_rounded,
        iconColor: const Color(0xFFE53935),
        selected: f.noLanguageRequired || f.languages.isNotEmpty,
        onSelected: (_) => _openLanguageQuickSheet(),
      ),
      FilterChipRowItem(
        label: 'Страна',
        icon: Icons.public_rounded,
        iconWidget: const Text('🌍', style: TextStyle(fontSize: 16)),
        selected: f.countries.isNotEmpty,
        onSelected: (_) => _openCountryQuickSheet(),
      ),
      FilterChipRowItem(
        label: 'Без опыта',
        icon: Icons.close_rounded,
        iconColor: const Color(0xFFE53935),
        selected: f.experience.isNotEmpty,
        onSelected: (_) => _openExperienceQuickSheet(),
      ),
      FilterChipRowItem(
        label: 'График работы',
        icon: Icons.schedule_rounded,
        iconColor: WorkaColors.orange,
        selected: f.employment.isNotEmpty,
        onSelected: (_) => _openScheduleQuickSheet(),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _buildHeaderFilterChip(items[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderFilterChip(FilterChipRowItem item) {
    const chipRadius = 18.0;
    const textSize = 12.5;
    const iconSize = 16.0;
    const crossSize = 16.0;
    const crossStroke = 3.6;
    const boldCrossColor = Color(0xFFD32F2F);
    final hasLeadingIcon = item.label != '€2000+';

    Widget leading() {
      if (item.label == 'Без языка') {
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BoldRedCrossIcon(
              size: crossSize,
              stroke: crossStroke,
              color: boldCrossColor,
            ),
            SizedBox(width: 7),
            Icon(
              Icons.translate_rounded,
              size: iconSize,
              color: WorkaColors.blue,
            ),
          ],
        );
      }
      if (item.label == 'Без опыта') {
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BoldRedCrossIcon(
              size: crossSize,
              stroke: crossStroke,
              color: boldCrossColor,
            ),
            SizedBox(width: 7),
            Icon(
              Icons.work_outline_rounded,
              size: iconSize,
              color: WorkaColors.orange,
            ),
          ],
        );
      }
      return Icon(
        item.icon,
        size: iconSize,
        color: item.iconColor ?? WorkaColors.blueDark,
      );
    }

    Widget chipText() {
      if (item.label == '€2000+') {
        return RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: '€',
                style: TextStyle(
                  color: WorkaColors.salaryAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  height: 1.0,
                ),
              ),
              TextSpan(
                text: '2000+',
                style: TextStyle(
                  color: WorkaColors.salaryAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: textSize,
                  height: 1.1,
                ),
              ),
            ],
          ),
        );
      }
      return Text(
        item.label,
        style: TextStyle(
          color: item.labelColor ?? WorkaColors.blueDark,
          fontWeight: FontWeight.w700,
          fontSize: textSize,
          height: 1.1,
        ),
      );
    }

    return FilterChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasLeadingIcon) leading(),
          if (hasLeadingIcon) const SizedBox(width: 8),
          chipText(),
        ],
      ),
      selected: item.selected,
      onSelected: item.onSelected,
      selectedColor: WorkaColors.blue.withValues(alpha: 0.18),
      backgroundColor: Colors.white.withValues(alpha: 0.96),
      checkmarkColor: WorkaColors.blueDark,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.75)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chipRadius),
      ),
    );
  }

  Widget _buildModeAndQuickFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFDFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
        ),
        child: _ModeSegmented(
          mode: _state.mode,
          onChanged: (mode) {
            if (kDebugMode) {
              debugPrint('UnifiedSearch -> mode=${mode.name}');
            }
            NavigationReturnSnapshot.setHomeMode(mode);
            setState(() => _state = _state.copyWith(mode: mode));
            _schedulePersistUiState();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _updateCollapsedFromActiveScroll();
            });
          },
        ),
      ),
    );
  }

  Future<void> _openCountryQuickSheet() async {
    final f = _state.vacancy;
    final selected = Set<String>.from(f.countries);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkaColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Text('🌍', style: TextStyle(fontSize: 22)),
                      title: const Text(
                        'Страна',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      trailing: selected.isNotEmpty
                          ? TextButton(
                              onPressed: () =>
                                  setSheetState(() => selected.clear()),
                              child: const Text('Сбросить'),
                            )
                          : null,
                    ),
                    SizedBox(
                      height: 320,
                      child: ListView.builder(
                        itemCount: SearchFiltersConfig.countriesRu.length,
                        itemBuilder: (context, i) {
                          final country = SearchFiltersConfig.countriesRu[i];
                          final isSelected = selected.contains(country);
                          final flag = CountryDisplayFormatter.countryFlagOnly(
                            country,
                            euAsToken: false,
                          );
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            leading: Checkbox(
                              value: isSelected,
                              onChanged: (_) => setSheetState(() {
                                if (isSelected) {
                                  selected.remove(country);
                                } else {
                                  selected.add(country);
                                }
                              }),
                              activeColor: WorkaColors.blue,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            title: Row(
                              children: [
                                if (flag.isNotEmpty) ...[
                                  Text(
                                    flag,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Text(country),
                              ],
                            ),
                            onTap: () => setSheetState(() {
                              if (isSelected) {
                                selected.remove(country);
                              } else {
                                selected.add(country);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _state = _state.copyWith(
                                vacancy: f.copyWith(countries: selected),
                              );
                            });
                            _schedulePersistUiState();
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkaColors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Применить'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openLanguageQuickSheet() async {
    final f = _state.vacancy;
    final options = const [
      'Без знания языка',
      'Русский',
      'Английский',
      'Немецкий',
      'Эстонский',
      'Польский',
    ];
    final selected = <String>{
      if (f.noLanguageRequired || f.languages.contains('Без языка'))
        'Без знания языка',
      ...f.languages.where((e) => e != 'Без языка'),
    };

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkaColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        String? draftValue = options.firstWhere(
          (v) => !selected.contains(v),
          orElse: () => '',
        );
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final available = options
                .where((v) => !selected.contains(v))
                .toList(growable: false);
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                (draftValue != null &&
                                    draftValue!.isNotEmpty &&
                                    available.contains(draftValue))
                                ? draftValue
                                : (available.isNotEmpty
                                      ? available.first
                                      : null),
                            items: available
                                .map(
                                  (v) => DropdownMenuItem<String>(
                                    value: v,
                                    child: Text(
                                      v,
                                      style: const TextStyle(
                                        color: WorkaColors.textGreyDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: available.isEmpty
                                ? null
                                : (v) => setSheetState(() => draftValue = v),
                            decoration: InputDecoration(
                              hintText: available.isEmpty
                                  ? 'Все языки выбраны'
                                  : 'Выберите язык',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: WorkaColors.fieldBorder,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: WorkaColors.blue,
                                  width: 1.6,
                                ),
                              ),
                            ),
                            dropdownColor: Colors.white,
                            iconEnabledColor: WorkaColors.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: available.isEmpty
                                ? null
                                : () {
                                    final v = (draftValue ?? '').trim();
                                    if (v.isEmpty) return;
                                    setSheetState(() {
                                      selected.add(v);
                                      draftValue = options.firstWhere(
                                        (it) => !selected.contains(it),
                                        orElse: () => '',
                                      );
                                    });
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: WorkaColors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Добавить'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (selected.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Языки не выбраны',
                          style: TextStyle(
                            color: WorkaColors.textGrey,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ...(() {
                      final values = selected.toList()..sort();
                      return values
                          .map(
                            (label) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: WorkaColors.hoverBlueSoft,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: WorkaColors.blue),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        color: WorkaColors.textGreyDark,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => setSheetState(() {
                                      selected.remove(label);
                                      if ((draftValue ?? '').trim().isEmpty) {
                                        draftValue = label;
                                      }
                                    }),
                                    borderRadius: BorderRadius.circular(999),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: WorkaColors.blue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList();
                    })(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final languages = <String>{
                              ...selected.where((e) => e != 'Без знания языка'),
                              if (selected.contains('Без знания языка'))
                                'Без языка',
                            };
                            final noLanguage = selected.contains(
                              'Без знания языка',
                            );
                            setState(() {
                              _state = _state.copyWith(
                                vacancy: f.copyWith(
                                  languages: languages,
                                  noLanguageRequired: noLanguage,
                                ),
                              );
                            });
                            _schedulePersistUiState();
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkaColors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Применить'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openScheduleQuickSheet() async {
    final f = _state.vacancy;
    final options = const [
      'Полная занятость',
      'Частичная занятость',
      'Удалённая работа',
      'Гибрид',
      'Проектная',
      'Вахта',
      'Стажировка',
    ];
    final selected = {...f.employment};

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkaColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'График работы',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: WorkaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: options.map((label) {
                        final isSelected = selected.contains(label);
                        return FilterChip(
                          label: Text(label),
                          selected: isSelected,
                          onSelected: (v) {
                            setSheetState(() {
                              if (v) {
                                selected.add(label);
                              } else {
                                selected.remove(label);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _state = _state.copyWith(
                              vacancy: f.copyWith(employment: selected),
                            );
                          });
                          _schedulePersistUiState();
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Применить'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openExperienceQuickSheet() async {
    final f = _state.vacancy;
    final options = const ['Без опыта', 'До 1 года', '1–3 года', '3+ года'];
    final selected = <String>{...f.experience};

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkaColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Text(
                        'Без опыта',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ...options.map(
                      (label) => CheckboxListTile(
                        value: selected.contains(label),
                        title: Text(label),
                        onChanged: (v) {
                          setSheetState(() {
                            if (v == true) {
                              selected.add(label);
                            } else {
                              selected.remove(label);
                            }
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _state = _state.copyWith(
                                vacancy: f.copyWith(experience: selected),
                              );
                            });
                            _schedulePersistUiState();
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkaColors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Применить'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openVacancyPreviewSheet({
    required String jobId,
    required String title,
    required String city,
    required String country,
    required String salaryTextFallback,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkaColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        final location = [
          city,
          country,
        ].where((e) => e.trim().isNotEmpty).join(', ');
        final salary = salaryTextFallback.trim().isNotEmpty
            ? salaryTextFallback.trim()
            : 'Зарплата не указана';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: WorkaColors.textDark,
                ),
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  location,
                  style: const TextStyle(
                    color: WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                salary,
                style: const TextStyle(
                  color: WorkaColors.orange,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    NavigationReturnSnapshot.setPendingVacancyDetails(jobId);
                    VacancyDetailsSheet.open(
                      context,
                      jobId: jobId,
                      testMode: widget.testMode,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WorkaColors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Открыть',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _ownerIdFromJob(Map<String, dynamic> m) {
    return OwnershipResolver.vacancyOwnerIdFromMap(m);
  }

  Future<void> _quickApplyToJob({
    required String jobId,
    required Map<String, dynamic> jobData,
  }) async {
    try {
      await VacancyApplyEntrySheet.open(
        context,
        vacancy: jobData,
        onSendCvTap: () async {
          if (!AuthGuard.ensureSignedIn(context)) return false;
          final uid = (AuthGuard.effectiveUidOrNull() ?? '').trim();
          if (uid.isEmpty) return false;

          final cvSnap = await _db
              .collection(FirestorePaths.cvs)
              .where('ownerId', isEqualTo: uid)
              .get();
          final cvs = cvSnap.docs
              .where((d) => (d.data()['isDeleted'] ?? false) != true)
              .toList();

          if (cvs.isEmpty) {
            if (!mounted) return false;
            await Navigator.of(
              context,
              rootNavigator: true,
            ).push(MaterialPageRoute(builder: (_) => const AddCvScreen()));
            return false;
          }

          String selectedCvId;
          if (cvs.length == 1) {
            selectedCvId = cvs.first.id;
          } else {
            if (!mounted) return false;
            final picked = await CvPickerSheet.open(
              context,
              title: 'Выберите CV',
              allowCreate: true,
              forceTestCollection: widget.testMode,
            );
            if (picked == null) return false;
            selectedCvId = picked.cvId;
          }

          final ownerId = _ownerIdFromJob(jobData);
          if (ownerId.isEmpty) {
            if (!mounted) return false;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Не удалось определить владельца вакансии'),
              ),
            );
            return false;
          }

          await ResponseRepository(_db).createApply(
            jobId: jobId,
            jobOwnerId: ownerId,
            candidateCvId: selectedCvId,
            candidateOwnerId: uid,
            applicantProfileType: AppMode.currentMode == AccountMode.business
                ? 'business'
                : 'personal',
          );
          if (!mounted) return false;
          await showSentOverlay(context, 'Отклик отправлен');
          return true;
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка отправки: $e')));
    }
  }

  Widget _buildVacanciesResults() {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _jobsStreamRef,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Ошибка: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: _applyVacancyFiltersAsync(snap.data!),
          builder: (context, filteredSnap) {
            if (filteredSnap.hasError) {
              return Center(child: Text('Ошибка: ${filteredSnap.error}'));
            }
            // Show spinner only on first load (no previous data yet).
            // When Firestore fires a new snapshot while user is scrolling,
            // keep displaying the previous list instead of replacing it with a
            // spinner — this prevents scroll interruption.
            if (filteredSnap.data == null) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }

            final filtered = filteredSnap.data!;
            if (filtered.isEmpty) return _emptyVacancies();
            return ListView.separated(
              key: const PageStorageKey<String>('unified_vacancies_list'),
              controller: _vacanciesScroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 22, 10, 100),
              itemBuilder: (context, i) {
                final d = filtered[i];
                final m = d.data();
                final title = _s(m['title'], fallback: 'Без названия');
                final companyName = _s(
                  m['companyName'],
                  fallback: _s(m['company']),
                );
                final city = _s(m['city']);
                final country = _s(m['country']);
                final salaryFrom = (m['salaryFrom'] is num)
                    ? (m['salaryFrom'] as num).toDouble()
                    : null;
                final salaryTo = (m['salaryTo'] is num)
                    ? (m['salaryTo'] as num).toDouble()
                    : null;
                final salaryType = _s(
                  m['salaryType'],
                  fallback: _s(m['salaryPeriod'], fallback: 'В месяц'),
                );
                final salaryTextFallback = _s(m['salary']);
                final employmentLabel = _s(
                  m['workSchedule'],
                  fallback: _s(
                    m['workScheduleOption'],
                    fallback: _s(
                      m['employmentType'],
                      fallback: _s(m['type'], fallback: 'Полная занятость'),
                    ),
                  ),
                );
                final noLanguageRequired =
                    m['noLanguageRequired'] == true ||
                    _s(m['language']).toLowerCase() == 'без языка';
                final noExperienceRequired =
                    _s(m['experience']).toLowerCase().contains('без') &&
                        _s(m['experience']).toLowerCase().contains('опыт') ||
                    _s(m['experienceRequired']).toLowerCase() ==
                        'no_experience';
                final ownership = OwnershipResolver.byOwnerId(
                  OwnershipResolver.vacancyOwnerIdFromMap(m),
                );
                final isMine = ownership.known && ownership.isOwner;
                final verifiedEmployer = _verifiedEmployerForCard(d.id, m);

                return VacancyListCard(
                  mode: WorkaJobCardMode.marketplace,
                  title: title,
                  companyName: companyName,
                  city: city,
                  country: country,
                  salaryFrom: salaryFrom,
                  salaryTo: salaryTo,
                  salaryType: salaryType,
                  salaryTextFallback: salaryTextFallback,
                  employmentLabel: employmentLabel,
                  housingProvided: m['housingProvided'] == true,
                  transportProvided: m['transportProvided'] == true,
                  forTeenagers: m['teenFriendly'] == true,
                  forDisabled: m['disabilityFriendly'] == true,
                  isUrgent: _hasPaidUrgent(m),
                  jobId: d.id,
                  ownerUid: OwnershipResolver.vacancyOwnerIdFromMap(m),
                  ownerEmail: _s(
                    m['ownerEmail'],
                    fallback: _s(m['email'], fallback: _s(m['contactEmail'])),
                  ),
                  onTap: isMine
                      ? () {
                          _openVacancyPreviewSheet(
                            jobId: d.id,
                            title: title,
                            city: city,
                            country: country,
                            salaryTextFallback: salaryTextFallback,
                          );
                        }
                      : () {
                          _quickApplyToJob(jobId: d.id, jobData: m);
                        },
                  onApply: isMine
                      ? null
                      : () {
                          _quickApplyToJob(jobId: d.id, jobData: m);
                        },
                  showApply: !isMine,
                  salaryMainColor: WorkaColors.salaryAccent,
                  topRight: _FavButton(
                    active: _isFav(d.id),
                    onTap: () => _toggleFav(d.id, m),
                  ),
                  noLanguageRequired: noLanguageRequired,
                  noExperienceRequired: noExperienceRequired,
                  verifiedEmployer: verifiedEmployer,
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemCount: filtered.length,
            );
          },
        );
      },
    );
  }

  Widget _buildCandidatesResults() {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _candidatesStreamRef,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Ошибка: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final filtered = _applyCandidateFilters(snap.data!);
        if (filtered.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Text(
                'К сожалению, по вашим параметрам ничего не найдено, попробуйте изменить параметры поиска или добавьте своё CV, чтобы работодатели могли связаться с вами',
                style: TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Column(
          children: [
            if (_showViewedContactsNudge)
              _nudgeBanner(
                text: 'Свяжитесь с кандидатами напрямую',
                entryPoint: 'unified_viewed_nudge',
                onDismiss: _dismissViewedContactsNudge,
              ),
            if (_showIncomingInteractionNudge)
              _nudgeBanner(
                text: 'Кандидат уже взаимодействует с вами',
                entryPoint: 'unified_incoming_nudge',
                onDismiss: _dismissIncomingNudge,
              ),
            Expanded(
              child: ListView.separated(
                key: const PageStorageKey<String>('unified_candidates_list'),
                controller: _candidatesScroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, i) {
                  final d = filtered[i];
                  final m = PublicCvSanitizer.sanitizePublicCv(d.data());
                  final currentUid = OwnershipResolver.currentUid();
                  final candidateUid = OwnershipResolver.cvOwnerIdFromMap(m);

                  final contacts = (m['contacts'] is Map)
                      ? Map<String, dynamic>.from(m['contacts'] as Map)
                      : const <String, dynamic>{};
                  final cvName = [
                    (contacts['name'] ?? '').toString().trim(),
                    [
                      (contacts['firstName'] ?? '').toString().trim(),
                      (contacts['lastName'] ?? '').toString().trim(),
                    ].where((e) => e.isNotEmpty).join(' ').trim(),
                  ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
                  final ownershipKnown = candidateUid.isNotEmpty;
                  final isOwnCandidate =
                      ownershipKnown &&
                      currentUid.isNotEmpty &&
                      candidateUid.isNotEmpty &&
                      currentUid == candidateUid;
                  final contactsOpened = _contactAccess
                      .hasAccessToCandidateContact(d.id);
                  void openDetails() {
                    if (!contactsOpened) {
                      _onViewedWithoutUnlock(d.id);
                    }
                    NavigationReturnSnapshot.setPendingCandidateDetails(
                      candidateId: d.id,
                      candidateUid: candidateUid,
                    );
                    CandidateDetailsSheet.open(
                      context,
                      candidateId: d.id,
                      candidateUid: candidateUid,
                      testMode: widget.testMode,
                    );
                  }

                  CandidateListCard buildCard(bool hasOfferSent) {
                    return CandidateListCard(
                      onTap: openDetails,
                      onContactTap:
                          (!ownershipKnown || isOwnCandidate || hasOfferSent)
                          ? null
                          : () => _handleContactTap(
                              candidateId: d.id,
                              candidateName: cvName,
                              openDetails: openDetails,
                            ),
                      name: '',
                      ageText: '',
                      birthDate: null,
                      citizenshipCountry: '',
                      profession: '',
                      location: '',
                      category: '',
                      language: '',
                      languagesData: const <Map<String, dynamic>>[],
                      experience: '',
                      readyToWork: false,
                      hasWorkDocuments: false,
                      hasDriverLicense: false,
                      hasCar: false,
                      hasTools: false,
                      hasWorkwear: false,
                      hasComputerSkills: false,
                      drivingLicenseCategories: const <String>[],
                      readyToRelocate: false,
                      profileViews: 0,
                      isNewCandidate: false,
                      contactsOpened: contactsOpened,
                      hasOfferSent: hasOfferSent,
                      candidateId: d.id,
                      candidateUid: candidateUid,
                      candidateData: m,
                      testMode: widget.testMode,
                      topRight: FavoriteStarButton(
                        isFavorite: _isCandidateFav(d.id),
                        onTap: () => _toggleCandidateFav(d.id, m),
                        tooltip: 'В избранное',
                        size: 30,
                      ),
                      statusBadge: null,
                    );
                  }

                  // Use a real-time Firestore stream so the "Предложение отправлено"
                  // badge appears immediately after sending an offer, without needing
                  // a manual cache invalidation.
                  if (!ownershipKnown ||
                      isOwnCandidate ||
                      currentUid.isEmpty ||
                      candidateUid.isEmpty) {
                    return buildCard(false);
                  }
                  return CandidateOfferSentBuilder(
                    employerUid: currentUid,
                    candidateOwnerId: candidateUid,
                    builder: (context, hasOffer) => buildCard(hasOffer),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return KeyedSubtree(
      key: const Key('welcome_content'),
      child: AppBackgroundLayout(
        header: Column(children: [_buildTopBar(), _buildSearchControls()]),
        body: Column(
          children: [
            const SizedBox(height: 12),
            _buildFigmaFilterChipsRow(),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(WorkaUiRadius.container),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.52),
                    ),
                    boxShadow: WorkaUiShadows.card,
                  ),
                  child: Column(
                    children: [
                      _buildModeAndQuickFilters(),
                      Expanded(
                        child: IndexedStack(
                          index: _state.mode.index,
                          children: [
                            _buildVacanciesResults(),
                            _buildCandidatesResults(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoldRedCrossIcon extends StatelessWidget {
  const _BoldRedCrossIcon({
    required this.size,
    required this.stroke,
    required this.color,
  });

  final double size;
  final double stroke;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar(double angle) {
      return Transform.rotate(
        angle: angle,
        child: Container(
          width: size,
          height: stroke,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(stroke),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [bar(math.pi / 4), bar(-math.pi / 4)],
      ),
    );
  }
}

enum _VacancySort { best, newest, salary }

class _ModeSegmented extends StatelessWidget {
  final SearchMode mode;
  final ValueChanged<SearchMode> onChanged;

  const _ModeSegmented({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isVacancies = mode == SearchMode.vacancies;
    return Container(
      height: 48,
      decoration: WorkaSegmentedStyles.container(
        color: const Color(0xFFFCFDFF),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              selected: isVacancies,
              label: 'Вакансии',
              onTap: () => onChanged(SearchMode.vacancies),
            ),
          ),
          Expanded(
            child: _SegmentButton(
              selected: !isVacancies,
              label: 'Кандидаты',
              onTap: () => onChanged(SearchMode.candidates),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(WorkaUiRadius.segmented),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [WorkaColors.orange, WorkaColors.orange],
                )
              : null,
          borderRadius: BorderRadius.circular(WorkaUiRadius.segmented),
          border: selected
              ? Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.24),
                    width: 1,
                  ),
                )
              : null,
          boxShadow: selected ? WorkaUiShadows.button : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF3E4A60),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            fontSize: 16.5,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _SuggestBox extends StatelessWidget {
  final List<String> items;
  final ValueChanged<String> onPick;

  const _SuggestBox({required this.items, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.divider),
        boxShadow: WorkaUiShadows.card,
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: WorkaColors.divider),
        itemBuilder: (context, i) {
          final v = items[i];
          return InkWell(
            onTap: () => onPick(v),
            hoverColor: WorkaColors.hoverBlue,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Text(
                v,
                style: const TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FavButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _FavButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FavoriteStarButton(
      isFavorite: active,
      onTap: onTap,
      tooltip: active ? 'Убрать из избранного' : 'В избранное',
      size: 30,
    );
  }
}
