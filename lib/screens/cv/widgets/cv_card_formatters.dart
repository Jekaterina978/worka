import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _parseBirthDate(dynamic birthDateRaw) {
  if (birthDateRaw is Timestamp) return birthDateRaw.toDate();
  if (birthDateRaw is DateTime) return birthDateRaw;
  if (birthDateRaw is String && birthDateRaw.trim().isNotEmpty) {
    return DateTime.tryParse(birthDateRaw.trim());
  }
  return null;
}

int? calculateAgeFromBirthDate(dynamic birthDateRaw) {
  final birthDate = _parseBirthDate(birthDateRaw);
  if (birthDate == null) return null;

  final now = DateTime.now();
  int age = now.year - birthDate.year;
  final hadBirthday =
      now.month > birthDate.month ||
      (now.month == birthDate.month && now.day >= birthDate.day);
  if (!hadBirthday) age -= 1;
  return age > 0 ? age : null;
}

String? mapLanguageToShortCode(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value.trim().toLowerCase();
  final firstToken = normalized.split(RegExp(r'[\s,/;()]+')).first.trim();
  final key = firstToken.isEmpty ? normalized : firstToken;

  switch (key) {
    case 'русский':
    case 'russian':
    case 'rus':
    case 'ru':
      return 'RUS';
    case 'английский':
    case 'english':
    case 'eng':
    case 'en':
      return 'ENG';
    case 'эстонский':
    case 'estonian':
    case 'eesti':
    case 'est':
    case 'et':
      return 'EST';
    case 'немецкий':
    case 'german':
    case 'deu':
      return 'DEU';
    case 'польский':
    case 'polish':
    case 'pol':
      return 'POL';
    case 'украинский':
    case 'ukrainian':
    case 'ukr':
      return 'UKR';
    case 'французский':
    case 'french':
    case 'fra':
      return 'FRA';
    case 'испанский':
    case 'spanish':
    case 'esp':
      return 'ESP';
    default:
      return firstToken.isNotEmpty ? firstToken.toUpperCase() : null;
  }
}

String? _normalizeLanguageLevel(String? levelRaw) {
  if (levelRaw == null || levelRaw.trim().isEmpty) return null;
  final normalized = levelRaw.trim().toLowerCase();
  switch (normalized) {
    case 'a1':
    case 'a2':
    case 'b1':
    case 'b2':
    case 'c1':
    case 'c2':
      return normalized.toUpperCase();
    case 'начальный':
    case 'базовый':
    case 'elementary':
    case 'basic':
      return 'A2';
    case 'средний':
    case 'intermediate':
      return 'B1';
    case 'выше среднего':
    case 'upper intermediate':
      return 'B2';
    case 'продвинутый':
    case 'advanced':
    case 'свободный':
    case 'свободно':
      return 'C1';
    case 'родной':
    case 'носитель':
    case 'native':
      return 'C2';
    default:
      return normalized.toUpperCase();
  }
}

String? formatLanguageBadge(String? language, String? level) {
  String? lang = language;
  String? lvl = level;
  if ((lvl == null || lvl.trim().isEmpty) &&
      lang != null &&
      lang.trim().contains(RegExp(r'\s+'))) {
    final parts = lang.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      lang = parts.first;
      lvl = parts.skip(1).join(' ');
    }
  }

  final code = mapLanguageToShortCode(lang);
  if (code == null) return null;
  final normalizedLevel = _normalizeLanguageLevel(lvl);
  if (normalizedLevel == null || normalizedLevel.isEmpty) return code;
  return '$code $normalizedLevel';
}

String? mapCitizenshipToDisplayValue(String? citizenshipCountry) {
  if (citizenshipCountry == null || citizenshipCountry.trim().isEmpty) {
    return null;
  }

  const euCountries = {
    'austria',
    'belgium',
    'bulgaria',
    'croatia',
    'cyprus',
    'czech republic',
    'czechia',
    'denmark',
    'estonia',
    'finland',
    'france',
    'germany',
    'greece',
    'hungary',
    'ireland',
    'italy',
    'latvia',
    'lithuania',
    'luxembourg',
    'malta',
    'netherlands',
    'poland',
    'portugal',
    'romania',
    'slovakia',
    'slovenia',
    'spain',
    'sweden',
    'австрия',
    'бельгия',
    'болгария',
    'хорватия',
    'кипр',
    'чехия',
    'дания',
    'эстония',
    'финляндия',
    'франция',
    'германия',
    'греция',
    'венгрия',
    'ирландия',
    'италия',
    'латвия',
    'литва',
    'люксембург',
    'мальта',
    'нидерланды',
    'польша',
    'португалия',
    'румыния',
    'словакия',
    'словения',
    'испания',
    'швеция',
  };

  const cisCountries = {
    'armenia': 'Армения',
    'azerbaijan': 'Азербайджан',
    'belarus': 'Беларусь',
    'kazakhstan': 'Казахстан',
    'kyrgyzstan': 'Кыргызстан',
    'moldova': 'Молдова',
    'russia': 'Россия',
    'tajikistan': 'Таджикистан',
    'ukraine': 'Украина',
    'uzbekistan': 'Узбекистан',
    'армения': 'Армения',
    'азербайджан': 'Азербайджан',
    'беларусь': 'Беларусь',
    'казахстан': 'Казахстан',
    'кыргызстан': 'Кыргызстан',
    'молдова': 'Молдова',
    'россия': 'Россия',
    'таджикистан': 'Таджикистан',
    'украина': 'Украина',
    'узбекистан': 'Узбекистан',
  };

  final normalized = citizenshipCountry.trim().toLowerCase();

  if (euCountries.contains(normalized)) return 'EU';
  if (cisCountries.containsKey(normalized)) return cisCountries[normalized];

  return citizenshipCountry.trim();
}

List<String> buildCandidateBadges({
  List<Map<String, dynamic>> languages = const <Map<String, dynamic>>[],
  List<String> drivingLicenseCategories = const <String>[],
  required bool hasCar,
  required bool hasTools,
  required bool hasWorkwear,
  required bool hasComputerSkills,
}) {
  final out = <String>[];

  for (final l in languages.take(3)) {
    final language = (l['language'] ?? l['name'] ?? '').toString().trim();
    final level = (l['level'] ?? '').toString().trim();
    final badge = formatLanguageBadge(language, level);
    if (badge != null && badge.isNotEmpty) {
      out.add(badge);
    }
  }

  if (hasComputerSkills) out.add('icon:computer');

  for (final c in drivingLicenseCategories.take(2)) {
    final clean = c.trim().toUpperCase();
    if (clean.isNotEmpty) out.add(clean);
  }

  if (hasCar) out.add('icon:car');
  if (hasTools) out.add('icon:tools');
  if (hasWorkwear) out.add('icon:workwear');

  return out;
}
