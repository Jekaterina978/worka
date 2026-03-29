enum ProfileTab { personal, business }

enum AccountMode { personal, business }

const String kLastProfileTabKey = 'worka_last_profile_tab';
const String kAccountModeKey = 'account_mode';

String accountModeToValue(AccountMode mode) =>
    mode == AccountMode.business ? 'business' : 'personal';

AccountMode accountModeFromValue(String value) =>
    value == 'business' ? AccountMode.business : AccountMode.personal;

String profileTabToValue(ProfileTab tab) =>
    tab == ProfileTab.business ? 'business' : 'personal';

ProfileTab profileTabFromValue(String value) =>
    value == 'business' ? ProfileTab.business : ProfileTab.personal;

String _s(dynamic v) => (v ?? '').toString().trim();

Map<String, dynamic> _map(Map<String, dynamic> source, String key) {
  final v = source[key];
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry('$k', val));
  return const <String, dynamic>{};
}

String _read(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final v = _s(source[key]);
    if (v.isNotEmpty) return v;
  }
  return '';
}

bool _hasBasicContacts(Map<String, dynamic> source) {
  final personal = _map(source, 'personal');
  final firstName = _read(source, ['firstName', 'name']);
  final lastName = _read(source, ['lastName']);
  final email = _read(source, ['email']);
  final phone = _read(source, ['phone']);
  if (firstName.isNotEmpty &&
      lastName.isNotEmpty &&
      email.isNotEmpty &&
      phone.isNotEmpty) {
    return true;
  }

  final pFirstName = _read(personal, ['firstName', 'name']);
  final pLastName = _read(personal, ['lastName']);
  final pEmail = _read(personal, ['email']);
  final pPhone = _read(personal, ['phone']);
  return pFirstName.isNotEmpty &&
      pLastName.isNotEmpty &&
      pEmail.isNotEmpty &&
      pPhone.isNotEmpty;
}

bool isPersonalComplete(Map<String, dynamic> source) {
  final personal = _map(source, 'personal');

  final firstName =
      _read(personal, ['firstName', 'name']).isNotEmpty ||
      _read(source, ['firstName', 'name']).isNotEmpty;
  final lastName =
      _read(personal, ['lastName']).isNotEmpty ||
      _read(source, ['lastName']).isNotEmpty;
  final email =
      _read(personal, ['email']).isNotEmpty ||
      _read(source, ['email']).isNotEmpty;
  final phone =
      _read(personal, ['phone']).isNotEmpty ||
      _read(source, ['phone']).isNotEmpty;

  final citizenship =
      _read(personal, [
        'citizenshipName',
        'countryName',
        'country',
      ]).isNotEmpty ||
      _read(source, ['citizenshipName', 'countryName', 'country']).isNotEmpty;

  final rawRoles = source['roles'];
  final roles = <String>{};
  if (rawRoles is Iterable) {
    for (final item in rawRoles) {
      final v = _s(item).toLowerCase();
      if (v.isNotEmpty) roles.add(v);
    }
  }
  final role = _read(source, [
    'role',
    'profileType',
    'userType',
    'accountType',
  ]).toLowerCase();
  if (roles.isEmpty) {
    if (role == 'worker') roles.add('worker');
    if (role == 'employer') roles.add('employer_private');
    if (role == 'employer_private' || role == 'employer_company') {
      roles.add(role);
    }
  }
  final needsWorkerSpecific = roles.isEmpty || roles.contains('worker');

  if (!firstName || !lastName || !email || !phone || !citizenship) return false;
  if (!needsWorkerSpecific) return true;

  final gender =
      _read(personal, ['gender']).isNotEmpty ||
      _read(source, ['gender']).isNotEmpty;
  final birthDate = personal['birthDate'] ?? source['birthDate'];
  final hasBirthDate = birthDate != null;
  return gender && hasBirthDate;
}

bool isBusinessComplete(Map<String, dynamic> source) {
  final business = _map(source, 'business');
  final employerType = _read(business, ['employerType']).isNotEmpty
      ? _read(business, ['employerType'])
      : _read(source, ['employerType']);
  if (employerType.isEmpty) return false;
  if (!_hasBasicContacts(source)) return false;

  if (employerType == 'private') return true;

  final companyName = _read(business, ['companyName']).isNotEmpty
      ? _read(business, ['companyName'])
      : _read(source, ['companyName']);
  return companyName.isNotEmpty;
}
