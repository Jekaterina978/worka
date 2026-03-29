class CountryDisplayFormatter {
  static const Map<String, String> _countryFlags = <String, String>{
    'estonia': '🇪🇪',
    'эстония': '🇪🇪',
    'sweden': '🇸🇪',
    'швеция': '🇸🇪',
    'finland': '🇫🇮',
    'финляндия': '🇫🇮',
    'latvia': '🇱🇻',
    'латвия': '🇱🇻',
    'lithuania': '🇱🇹',
    'литва': '🇱🇹',
    'poland': '🇵🇱',
    'польша': '🇵🇱',
    'germany': '🇩🇪',
    'германия': '🇩🇪',
    'russia': '🇷🇺',
    'россия': '🇷🇺',
    'ukraine': '🇺🇦',
    'украина': '🇺🇦',
    'kazakhstan': '🇰🇿',
    'казахстан': '🇰🇿',
    'uzbekistan': '🇺🇿',
    'узбекистан': '🇺🇿',
    'kyrgyzstan': '🇰🇬',
    'кыргызстан': '🇰🇬',
    'tajikistan': '🇹🇯',
    'таджикистан': '🇹🇯',
    'armenia': '🇦🇲',
    'армения': '🇦🇲',
    'azerbaijan': '🇦🇿',
    'азербайджан': '🇦🇿',
    'moldova': '🇲🇩',
    'молдова': '🇲🇩',
    'belarus': '🇧🇾',
    'беларусь': '🇧🇾',
    'france': '🇫🇷',
    'франция': '🇫🇷',
    'spain': '🇪🇸',
    'испания': '🇪🇸',
    'italy': '🇮🇹',
    'италия': '🇮🇹',
    'norway': '🇳🇴',
    'норвегия': '🇳🇴',
    'denmark': '🇩🇰',
    'дания': '🇩🇰',
    'netherlands': '🇳🇱',
    'нидерланды': '🇳🇱',
    // Extended Russian-name coverage for SearchFiltersConfig.countriesRu
    'австрия': '🇦🇹',
    'albania': '🇦🇱',
    'албания': '🇦🇱',
    'andorra': '🇦🇩',
    'андорра': '🇦🇩',
    'belgium': '🇧🇪',
    'бельгия': '🇧🇪',
    'bulgaria': '🇧🇬',
    'болгария': '🇧🇬',
    'бoсния и герцеговина': '🇧🇦',
    'босния и герцеговина': '🇧🇦',
    'united kingdom': '🇬🇧',
    'великобритания': '🇬🇧',
    'hungary': '🇭🇺',
    'венгрия': '🇭🇺',
    'greece': '🇬🇷',
    'греция': '🇬🇷',
    'georgia': '🇬🇪',
    'грузия': '🇬🇪',
    'ireland': '🇮🇪',
    'ирландия': '🇮🇪',
    'iceland': '🇮🇸',
    'исландия': '🇮🇸',
    'cyprus': '🇨🇾',
    'кипр': '🇨🇾',
    'liechtenstein': '🇱🇮',
    'лихтенштейн': '🇱🇮',
    'luxembourg': '🇱🇺',
    'люксембург': '🇱🇺',
    'malta': '🇲🇹',
    'мальта': '🇲🇹',
    'monaco': '🇲🇨',
    'монако': '🇲🇨',
    'north macedonia': '🇲🇰',
    'северная македония': '🇲🇰',
    'serbia': '🇷🇸',
    'сербия': '🇷🇸',
    'slovakia': '🇸🇰',
    'словакия': '🇸🇰',
    'slovenia': '🇸🇮',
    'словения': '🇸🇮',
    'turkey': '🇹🇷',
    'турция': '🇹🇷',
    'portugal': '🇵🇹',
    'португалия': '🇵🇹',
    'romania': '🇷🇴',
    'румыния': '🇷🇴',
    'switzerland': '🇨🇭',
    'швейцария': '🇨🇭',
    'croatia': '🇭🇷',
    'хорватия': '🇭🇷',
    'montenegro': '🇲🇪',
    'черногория': '🇲🇪',
    'czechia': '🇨🇿',
    'czech republic': '🇨🇿',
    'чехия': '🇨🇿',
    'austria': '🇦🇹',
  };

  static const Set<String> _euCountries = <String>{
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
    'eu',
  };

  static String normalize(String value) => value.trim().toLowerCase();

  static bool isEu(String value) => _euCountries.contains(normalize(value));

  static String countryFlagToken(String value) {
    final normalized = normalize(value);
    if (normalized.isEmpty) return '';
    if (isEu(normalized)) return 'EU';
    return _countryFlags[normalized] ?? '🌍';
  }

  static String countryFlagOnly(String value, {bool euAsToken = true}) {
    final normalized = normalize(value);
    if (normalized.isEmpty) return '';
    if (euAsToken && isEu(normalized)) return 'EU';
    if (isEu(normalized)) return _countryFlags[normalized] ?? '🇪🇺';
    return _countryFlags[normalized] ?? '🌍';
  }

  static String formatCountryWithFlag(String country) {
    final clean = country.trim();
    if (clean.isEmpty) return '';
    final token = countryFlagToken(clean);
    if (token.isEmpty) return clean;
    return '$token $clean';
  }

  static List<String> formatCountriesWithFlags(Iterable<String> countries) {
    return countries
        .map((e) => formatCountryWithFlag(e))
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }
}
