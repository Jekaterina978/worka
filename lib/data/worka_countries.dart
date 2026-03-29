class WorkaCountries {
  // RU -> EN (чтобы можно было сопоставлять с тем, что хранится в Firestore)
  static const Map<String, String> ruToEn = {
    // EU
    'Австрия': 'Austria',
    'Бельгия': 'Belgium',
    'Болгария': 'Bulgaria',
    'Хорватия': 'Croatia',
    'Кипр': 'Cyprus',
    'Чехия': 'Czechia',
    'Дания': 'Denmark',
    'Эстония': 'Estonia',
    'Финляндия': 'Finland',
    'Франция': 'France',
    'Германия': 'Germany',
    'Греция': 'Greece',
    'Венгрия': 'Hungary',
    'Ирландия': 'Ireland',
    'Италия': 'Italy',
    'Латвия': 'Latvia',
    'Литва': 'Lithuania',
    'Люксембург': 'Luxembourg',
    'Мальта': 'Malta',
    'Нидерланды': 'Netherlands',
    'Польша': 'Poland',
    'Португалия': 'Portugal',
    'Румыния': 'Romania',
    'Словакия': 'Slovakia',
    'Словения': 'Slovenia',
    'Испания': 'Spain',
    'Швеция': 'Sweden',

    // extra Scandinavia
    'Норвегия': 'Norway',
    'Исландия': 'Iceland',

    // Ukraine
    'Украина': 'Ukraine',

    // CIS
    'Армения': 'Armenia',
    'Азербайджан': 'Azerbaijan',
    'Беларусь': 'Belarus',
    'Грузия': 'Georgia',
    'Казахстан': 'Kazakhstan',
    'Киргизстан': 'Kyrgyzstan',
    'Молдова': 'Moldova',
    'Таджикистан': 'Tajikistan',
    'Туркменистан': 'Turkmenistan',
    'Узбекистан': 'Uzbekistan',
  };

  static final Map<String, String> enToRu = {
    for (final e in ruToEn.entries) e.value: e.key,
  };

  static List<String> ruList() {
    final list = ruToEn.keys.toList()..sort();
    return list;
  }

  static String? toEn(String ru) => ruToEn[ru];
  static String? toRu(String en) => enToRu[en];
}
