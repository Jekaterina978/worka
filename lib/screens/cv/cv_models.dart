class CvDoc {
  final String id;
  final Map<String, dynamic> data;

  CvDoc({required this.id, required this.data});

  String get ownerUid => (data['ownerUid'] ?? '').toString();
  String get title => (data['title'] ?? '').toString();
  String get summary => (data['summary'] ?? '').toString();

  Map<String, dynamic> get contacts => (data['contacts'] is Map)
      ? Map<String, dynamic>.from(data['contacts'])
      : <String, dynamic>{};

  List<Map<String, dynamic>> get experience => _listMap(data['experience']);
  List<Map<String, dynamic>> get education => _listMap(data['education']);
  List<Map<String, dynamic>> get languages => _listMap(data['languages']);

  Map<String, dynamic> get desired => (data['desired'] is Map)
      ? Map<String, dynamic>.from(data['desired'])
      : <String, dynamic>{};

  List<String> get desiredCountries {
    final d = desired;
    final v = d['countries'];
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  String get desiredLocationLabel {
    final d = desired;
    final t = (d['locationLabel'] ?? '').toString().trim();
    if (t.isNotEmpty) return t;
    final c = desiredCountries;
    return c.isEmpty ? '' : c.join(', ');
  }

  static List<Map<String, dynamic>> _listMap(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // Для “карточки” — коротко
  String get cardTitle =>
      title.trim().isEmpty ? 'CV без названия' : title.trim();
  String get cardSubtitle =>
      summary.trim().isEmpty ? 'Без описания' : summary.trim();

  String get fullName {
    final c = contacts;
    final name = (c['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final first = (c['firstName'] ?? data['firstName'] ?? '').toString().trim();
    final last = (c['lastName'] ?? data['lastName'] ?? '').toString().trim();
    final out = '$first $last'.trim();
    return out.isEmpty ? 'Кандидат' : out;
  }

  String get firstName =>
      (contacts['firstName'] ?? data['firstName'] ?? '').toString().trim();
  String get lastName =>
      (contacts['lastName'] ?? data['lastName'] ?? '').toString().trim();
  dynamic get birthDate => data['birthDate'] ?? contacts['birthDate'];
  String get profession =>
      (desired['position'] ?? data['profession'] ?? data['title'] ?? '')
          .toString()
          .trim();
  String get city {
    final cities = desired['cities'];
    if (cities is List && cities.isNotEmpty) {
      final first = cities.first.toString().trim();
      if (first.isNotEmpty) return first;
    }
    return (desired['citiesText'] ?? data['city'] ?? '').toString().trim();
  }

  String get country {
    final countries = desired['countries'];
    if (countries is List && countries.isNotEmpty) {
      final first = countries.first.toString().trim();
      if (first.isNotEmpty) return first;
    }
    return (data['country'] ?? data['countryName'] ?? '').toString().trim();
  }

  String get citizenshipCountry =>
      (data['citizenshipCountry'] ?? data['citizenshipName'] ?? country)
          .toString()
          .trim();
  String get citizenshipGroup =>
      (data['citizenshipGroup'] ?? '').toString().trim();
  String get avatarUrl =>
      (data['avatarUrl'] ?? data['photoUrl'] ?? '').toString().trim();
  String get initials => (data['initials'] ?? '').toString().trim();
  String get salaryAmount =>
      (data['salaryAmount'] ?? desired['salaryAmount'] ?? '').toString().trim();
  String get salaryCurrency =>
      (data['salaryCurrency'] ?? desired['salaryCurrency'] ?? 'EUR')
          .toString()
          .trim();
  String get salaryPeriod =>
      (data['salaryPeriod'] ?? desired['salaryPeriod'] ?? '').toString().trim();
  String get availabilityText =>
      (data['availabilityText'] ??
              desired['availability'] ??
              desired['employmentType'] ??
              '')
          .toString()
          .trim();
  List<String> get drivingLicenseCategories {
    final driving = (data['drivingLicense'] is Map)
        ? Map<String, dynamic>.from(data['drivingLicense'] as Map)
        : const <String, dynamic>{};
    final categories = driving['categories'];
    if (categories is List) {
      return categories
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final license =
        (driving['license'] ?? data['drivingLicenseCategories'] ?? '')
            .toString()
            .trim();
    if (license.isEmpty) return const <String>[];
    return license
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool get hasCar =>
      data['hasCar'] == true ||
      (data['drivingLicense'] is Map &&
          (data['drivingLicense'] as Map)['hasCar'] == true);
  bool get hasTools => data['hasTools'] == true;
  bool get hasWorkwear => data['hasWorkwear'] == true;
  bool get hasComputerSkills => data['hasComputerSkills'] == true;
  String get computerSkillsDetails =>
      (data['computerSkillsDetails'] ?? '').toString().trim();
  bool get isHighlighted => data['isHighlighted'] == true;

  static Map<String, dynamic> normalizeDesired(Map<String, dynamic> d) {
    final out = <String, dynamic>{};
    out['categoryGroup'] = (d['categoryGroup'] ?? '').toString();

    final position = (d['position'] ?? '').toString().trim();
    out['position'] = position;

    final countries = (d['countries'] is List)
        ? (d['countries'] as List).map((e) => e.toString()).toList()
        : <String>[];
    out['countries'] = countries;

    final locLabel = (d['locationLabel'] ?? '').toString().trim();
    out['locationLabel'] = locLabel.isNotEmpty
        ? locLabel
        : (countries.isEmpty ? '' : countries.join(', '));

    final citiesText = (d['citiesText'] ?? '').toString().trim();
    out['citiesText'] = citiesText;
    out['cities'] = (d['cities'] is List)
        ? (d['cities'] as List).map((e) => e.toString()).toList()
        : <String>[];

    out['employmentType'] = (d['employmentType'] ?? '').toString();
    return out;
  }
}
