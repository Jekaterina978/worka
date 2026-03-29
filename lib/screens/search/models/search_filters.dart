class SearchFilters {
  final Set<String> countries;
  final String? cityLabel;

  final Set<String> categories;
  final Set<String> employment;

  /// ✅ опыт теперь множественный (кнопки)
  final Set<String> experience;

  final Set<String> languages;

  // Salary input (user)
  final double? salaryAmount; // e.g. 70
  final String salaryPeriod; // 'В час' | 'В день' | 'В месяц'
  final String salaryCurrency; // 'EUR' | 'USD' ...
  final double? salaryFromEur; // amount converted to EUR (same period)

  final bool housing;
  final bool transport;
  final bool teen;
  final bool disability;
  final bool helpsWithDocuments;
  final bool noLanguageRequired;

  const SearchFilters({
    required this.countries,
    required this.cityLabel,
    required this.categories,
    required this.employment,
    required this.experience,
    required this.languages,
    required this.salaryAmount,
    required this.salaryPeriod,
    required this.salaryCurrency,
    required this.salaryFromEur,
    required this.housing,
    required this.transport,
    required this.teen,
    required this.disability,
    required this.helpsWithDocuments,
    required this.noLanguageRequired,
  });

  factory SearchFilters.initial() => const SearchFilters(
        countries: {},
        cityLabel: null,
        categories: {},
        employment: {},
        experience: {}, // ✅ было 'Все'
        languages: {},
        salaryAmount: null,
        salaryPeriod: 'В месяц',
        salaryCurrency: 'EUR',
        salaryFromEur: null,
        housing: false,
        transport: false,
        teen: false,
        disability: false,
        helpsWithDocuments: false,
        noLanguageRequired: false,
      );

  SearchFilters copyWith({
    Set<String>? countries,
    String? cityLabel,
    bool clearCityLabel = false,

    Set<String>? categories,
    Set<String>? employment,
    Set<String>? experience,
    Set<String>? languages,

    double? salaryAmount,
    bool clearSalaryAmount = false,
    String? salaryPeriod,
    String? salaryCurrency,
    double? salaryFromEur,
    bool clearSalaryFromEur = false,

    bool? housing,
    bool? transport,
    bool? teen,
    bool? disability,
    bool? helpsWithDocuments,
    bool? noLanguageRequired,
  }) {
    return SearchFilters(
      countries: countries ?? this.countries,
      cityLabel: clearCityLabel ? null : (cityLabel ?? this.cityLabel),

      categories: categories ?? this.categories,
      employment: employment ?? this.employment,
      experience: experience ?? this.experience,
      languages: languages ?? this.languages,

      salaryAmount: clearSalaryAmount ? null : (salaryAmount ?? this.salaryAmount),
      salaryPeriod: salaryPeriod ?? this.salaryPeriod,
      salaryCurrency: salaryCurrency ?? this.salaryCurrency,
      salaryFromEur: clearSalaryFromEur ? null : (salaryFromEur ?? this.salaryFromEur),

      housing: housing ?? this.housing,
      transport: transport ?? this.transport,
      teen: teen ?? this.teen,
      disability: disability ?? this.disability,
      helpsWithDocuments: helpsWithDocuments ?? this.helpsWithDocuments,
      noLanguageRequired: noLanguageRequired ?? this.noLanguageRequired,
    );
  }
}
