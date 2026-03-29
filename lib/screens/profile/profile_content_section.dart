part of 'package:worka/screens/profile_screen.dart';

Widget buildProfileContentUI(
  _ProfileScreenState s, {
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
  const double avatarRadius = 52;

  final displayName = isBusiness
      ? (companyName.isNotEmpty
            ? companyName
            : (name.isNotEmpty ? name : 'Профиль'))
      : (name.isNotEmpty ? name : 'Профиль');
  final profileTypeText = isBusiness
      ? (employerType.isNotEmpty ? employerType : 'Бизнес-аккаунт')
      : 'Личный аккаунт';
  final age = isBusiness ? null : s._ageFromBirthDate(profile['birthDate']);
  final displayNameWithAge = age == null ? displayName : '$displayName, $age';

  bool isEuToken(String v) {
    final n = v.trim().toLowerCase();
    return n == 'eu' ||
        n == 'europa' ||
        n == 'european union' ||
        n == 'евросоюз';
  }

  final personalMap = (profile['personal'] is Map)
      ? Map<String, dynamic>.from(profile['personal'] as Map)
      : const <String, dynamic>{};
  final privateCity = [
    s._s(personalMap['city']),
    s._s(profile['city']),
  ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
  final privateCountryRaw = [
    s._s(personalMap['countryName']),
    s._s(profile['countryName']),
    s._s(personalMap['country']),
    s._s(profile['country']),
  ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
  final locationCountryFromLabel = () {
    final parts = location
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 2) return '';
    final candidate = parts.last;
    return isEuToken(candidate) ? '' : candidate;
  }();
  final privateCountry =
      (!isEuToken(privateCountryRaw) && privateCountryRaw.isNotEmpty)
      ? privateCountryRaw
      : locationCountryFromLabel;
  final privateAddress = [
    if (privateCity.isNotEmpty) privateCity,
    if (privateCountry.isNotEmpty) privateCountry,
  ].join(', ');

  final businessMap = (profile['business'] is Map)
      ? Map<String, dynamic>.from(profile['business'] as Map)
      : const <String, dynamic>{};
  final businessAvatarUrl = [
    s._s(businessMap['logoUrl']),
    s._s(businessMap['companyLogoUrl']),
    s._s(profile['logoUrl']),
    s._s(profile['companyLogoUrl']),
    s._s(profile['avatarUrl']),
  ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
  final privateAvatarUrl = [
    s._s(personalMap['avatarUrl']),
    s._s(personalMap['photoUrl']),
    s._s(profile['avatarUrl']),
    s._s(profile['photoUrl']),
    s._s(profile['imageUrl']),
  ].firstWhere((e) => e.isNotEmpty, orElse: () => '');

  final contactsMap = (profile['contacts'] is Map)
      ? Map<String, dynamic>.from(profile['contacts'] as Map)
      : const <String, dynamic>{};
  final genderRaw = s
      ._s(profile['gender'], fallback: s._s(contactsMap['gender']))
      .toLowerCase();
  final avatarGender = switch (genderRaw) {
    'female' || 'ж' || 'жен' || 'женский' => _AvatarGender.female,
    'male' || 'м' || 'муж' || 'мужской' => _AvatarGender.male,
    _ => _AvatarGender.unknown,
  };

  final ownerUid = isBusiness ? businessUid : uid;

  final enabledProfiles = (profile['enabledProfiles'] as List? ?? [])
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  final hasBusinessProfile =
      enabledProfiles.contains('business') || businessMap.isNotEmpty;

  // ---- Sub-widgets ----

  Widget profileMenuCard() {
    if (isBusiness) {
      return buildMenuCardBusiness(
        s,
        businessUid: businessUid,
        isTestMode: s.widget.testMode,
      );
    }
    return buildMenuCardPersonal(s, uid: uid, isTestMode: s.widget.testMode);
  }

  Widget creditsStateBlock() {
    if (!isBusiness) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: s._creditsState(businessUid),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final credits = snap.data!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ProfilePaymentSection(
            credits: credits,
            stateTitle: s._creditsStateTitle(credits),
            stateHint: s._creditsStateHint(credits),
            stateColor: s._creditsStateColor(credits),
            onBuyCredits: s._openContactPackageSheet,
            showBuyButton: true,
          ),
        );
      },
    );
  }

  Widget contactRows() {
    final rows = <Widget>[];
    if (privateAddress.isNotEmpty) {
      rows.add(buildProfileContactRow(
        iconBg: const Color(0xFFE8F5E9),
        iconColor: const Color(0xFF388E3C),
        icon: Icons.location_on_outlined,
        label: 'Адрес',
        value: privateAddress,
      ));
    }
    if (email.isNotEmpty) {
      rows.add(buildProfileContactRow(
        iconBg: const Color(0xFFE3F2FD),
        iconColor: const Color(0xFF1976D2),
        icon: Icons.email_outlined,
        label: 'Email',
        value: email,
      ));
    }
    if (phone.isNotEmpty) {
      rows.add(buildProfileContactRow(
        iconBg: const Color(0xFFFFF3E0),
        iconColor: const Color(0xFFE65100),
        icon: Icons.phone_outlined,
        label: 'Телефон',
        value: phone,
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(children: rows);
  }

  Widget profileSwitcher() {
    if (!hasBusinessProfile) {
      return buildAddProfileButton(
        label: 'Добавить бизнес-профиль',
        icon: Icons.business_outlined,
        onTap: s._openBusinessFillFlow,
      );
    }
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1F8),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          buildSegmentTab(
            tab: ProfileTab.personal,
            selected: s._selectedTab,
            onTap: () => s._setTab(ProfileTab.personal),
            label: 'Личный',
          ),
          buildSegmentTab(
            tab: ProfileTab.business,
            selected: s._selectedTab,
            onTap: () => s._setTab(ProfileTab.business),
            label: 'Бизнес',
          ),
        ],
      ),
    );
  }

  Widget statCards() {
    return Row(
      children: [
        Expanded(
          child: StreamBuilder<ResponseStats>(
            stream: s._offersStats(
              ownerUid,
              profileType: isBusiness ? 'business' : 'personal',
            ),
            builder: (ctx, snap) => buildStatCard(
              fresh: snap.data?.fresh ?? 0,
              total: snap.data?.total ?? 0,
              label: 'Предложения',
              onTap: () => Navigator.push(
                s.context,
                MaterialPageRoute(
                  builder: (_) => OffersListScreen(
                    testMode: s.widget.testMode,
                    workerUid: isBusiness ? '' : uid,
                    employerUid: isBusiness ? businessUid : '',
                    profileType: isBusiness ? 'business' : 'personal',
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StreamBuilder<ResponseStats>(
            stream: s._employerApplicationsStats(
              ownerUid,
              ownerType: isBusiness ? 'business' : 'personal',
            ),
            builder: (ctx, snap) => buildStatCard(
              fresh: snap.data?.fresh ?? 0,
              total: snap.data?.total ?? 0,
              label: 'Мои кандидаты',
              onTap: () => Navigator.push(
                s.context,
                MaterialPageRoute(
                  builder: (_) => ApplicationsListScreen(
                    testMode: s.widget.testMode,
                    jobId: '',
                    employerUid: ownerUid,
                    candidateUid: '',
                    profileType: isBusiness ? 'business' : 'personal',
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StreamBuilder<ResponseStats>(
            stream: s._candidateApplicationsStats(
              uid,
              profileType: isBusiness ? 'business' : 'personal',
            ),
            builder: (ctx, snap) => buildStatCard(
              fresh: snap.data?.fresh ?? 0,
              total: snap.data?.total ?? 0,
              label: 'Кандидаты мне',
              onTap: () => Navigator.push(
                s.context,
                MaterialPageRoute(
                  builder: (_) => ApplicationsListScreen(
                    testMode: s.widget.testMode,
                    jobId: '',
                    employerUid: '',
                    candidateUid: uid,
                    profileType: isBusiness ? 'business' : 'personal',
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  return Column(
    children: [
      // Fixed gradient header row
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4A6FDB), Color(0xFF5A80FF)],
          ),
        ),
        child: WorkaHeader(
          title: 'Профиль',
          leading: s._profileMenuButton(iconColor: Colors.white),
          testMode: s.widget.testMode,
        ),
      ),
      // Scrollable body (gradient bg behind avatar, then white card)
      Expanded(
        child: ColoredBox(
          color: const Color(0xFF5A80FF),
          child: SingleChildScrollView(
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                // White card — top margin creates space for the avatar overlap
                Container(
                  margin: const EdgeInsets.only(top: avatarRadius),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6FB),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Space for the avatar's bottom half inside the card
                      const SizedBox(height: avatarRadius + 14),
                      // Name + account type
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              displayNameWithAge,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF0C1C3F),
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              profileTypeText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF5D6A85),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Contact info rows (address, email, phone)
                      contactRows(),
                      const SizedBox(height: 16),
                      // Segment switcher (Personal / Business) or Add Business button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: profileSwitcher(),
                      ),
                      // Fill profile button (personal only, when profile is incomplete)
                      if (!isBusiness &&
                          !s._isPersonalProfileComplete(profile)) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: buildAddProfileButton(
                            label: 'Дополнить профиль',
                            icon: Icons.edit_outlined,
                            onTap: s._openPersonalFillFlow,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Stat cards row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: statCards(),
                      ),
                      const SizedBox(height: 16),
                      // Navigation menu card
                      profileMenuCard(),
                      const SizedBox(height: 12),
                      // Business credits block (business only)
                      creditsStateBlock(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
                // Avatar centred at the header / card boundary
                _ProfileAvatar(
                  radius: avatarRadius,
                  initials: isBusiness
                      ? s._initialsFrom(displayName, fallback: 'C').substring(0, 1)
                      : s._initialsFrom(displayName),
                  isBusiness: isBusiness,
                  avatarUrl: isBusiness ? businessAvatarUrl : privateAvatarUrl,
                  gender: avatarGender,
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
