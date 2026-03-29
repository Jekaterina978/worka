class WorkaLists {
  static const String defaultCountry = 'Estonia';

  static List<String> allCountries() {
    const eu = [
      'Austria','Belgium','Bulgaria','Croatia','Cyprus','Czechia','Denmark','Estonia','Finland','France',
      'Germany','Greece','Hungary','Ireland','Italy','Latvia','Lithuania','Luxembourg','Malta','Netherlands',
      'Poland','Portugal','Romania','Slovakia','Slovenia','Spain','Sweden',
    ];

    const scandinavia = ['Norway', 'Iceland'];

    const ukraine = ['Ukraine'];

    const cis = [
      'Armenia','Azerbaijan','Belarus','Georgia','Kazakhstan','Kyrgyzstan','Moldova','Tajikistan','Turkmenistan','Uzbekistan',
    ];

    final all = <String>[...eu, ...scandinavia, ...ukraine, ...cis];
    all.sort();
    return all;
  }
}
