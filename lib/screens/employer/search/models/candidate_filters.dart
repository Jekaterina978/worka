class CandidateFilters {
  final Set<String> countries;
  final String? cityLabel;
  final Set<String> categories;
  final Set<String> experience; // primary set used by new search
  final Set<String> languages;
  final Set<String> employment;
  final Set<String> documents;
  final bool readyToRelocate;
  final bool hasDriverLicense;
  final bool hasCar;

  const CandidateFilters({
    required this.countries,
    required this.cityLabel,
    required this.categories,
    required this.experience,
    required this.languages,
    required this.employment,
    required this.documents,
    required this.readyToRelocate,
    required this.hasDriverLicense,
    required this.hasCar,
  });

  /// Compatibility alias for older callers.
  Set<String> get experiences => experience;

  factory CandidateFilters.initial() => const CandidateFilters(
        countries: {},
        cityLabel: null,
        categories: {},
        experience: {},
        languages: {},
        employment: {},
        documents: {},
        readyToRelocate: false,
        hasDriverLicense: false,
        hasCar: false,
      );

  CandidateFilters copyWith({
    Set<String>? countries,
    String? cityLabel,
    bool clearCityLabel = false,
    Set<String>? categories,
    Set<String>? experience,
    Set<String>? experiences, // legacy name
    Set<String>? languages,
    Set<String>? employment,
    Set<String>? documents,
    bool? readyToRelocate,
    bool? hasDriverLicense,
    bool? hasCar,
  }) {
    final nextExperience = experience ?? experiences ?? this.experience;
    return CandidateFilters(
      countries: countries ?? this.countries,
      cityLabel: clearCityLabel ? null : (cityLabel ?? this.cityLabel),
      categories: categories ?? this.categories,
      experience: nextExperience,
      languages: languages ?? this.languages,
      employment: employment ?? this.employment,
      documents: documents ?? this.documents,
      readyToRelocate: readyToRelocate ?? this.readyToRelocate,
      hasDriverLicense: hasDriverLicense ?? this.hasDriverLicense,
      hasCar: hasCar ?? this.hasCar,
    );
  }
}
