class CandidateAge {
  CandidateAge._();

  static String fromMap(Map<String, dynamic> data, {DateTime? now}) {
    final current = now ?? DateTime.now();

    String s(dynamic v) => (v ?? '').toString().trim();

    int? parseAge(dynamic v) {
      final txt = s(v);
      if (txt.isEmpty) return null;
      final direct = int.tryParse(txt);
      if (direct != null && direct >= 14 && direct <= 90) return direct;
      final digits = RegExp(r'\d{2}').firstMatch(txt)?.group(0);
      final guessed = digits == null ? null : int.tryParse(digits);
      if (guessed != null && guessed >= 14 && guessed <= 90) return guessed;
      return null;
    }

    int? parseYear(dynamic v) {
      final txt = s(v);
      if (txt.isEmpty) return null;
      final year = int.tryParse(txt);
      if (year != null && year >= 1900 && year <= current.year) return year;
      return null;
    }

    DateTime? parseDate(dynamic v) {
      if (v is DateTime) return v;
      if (v != null) {
        try {
          final dynamic maybeDate = (v as dynamic).toDate();
          if (maybeDate is DateTime) return maybeDate;
        } catch (_) {}
      }
      final txt = s(v);
      if (txt.isEmpty) return null;
      final date = DateTime.tryParse(txt);
      if (date != null) return date;
      final normalized = txt.replaceAll('/', '-').replaceAll('.', '-');
      final parts = normalized.split('-').where((e) => e.isNotEmpty).toList();
      if (parts.length == 3) {
        final a = int.tryParse(parts[0]);
        final b = int.tryParse(parts[1]);
        final c = int.tryParse(parts[2]);
        if (a != null && b != null && c != null) {
          // dd-mm-yyyy
          if (c >= 1900 &&
              c <= current.year &&
              a >= 1 &&
              a <= 31 &&
              b >= 1 &&
              b <= 12) {
            return DateTime(c, b, a);
          }
          // yyyy-mm-dd
          if (a >= 1900 &&
              a <= current.year &&
              b >= 1 &&
              b <= 12 &&
              c >= 1 &&
              c <= 31) {
            return DateTime(a, b, c);
          }
        }
      }
      return null;
    }

    int computeAge(DateTime birthDate) {
      var age = current.year - birthDate.year;
      final hadBirthday =
          (current.month > birthDate.month) ||
          (current.month == birthDate.month && current.day >= birthDate.day);
      if (!hadBirthday) age -= 1;
      return age;
    }

    final personal = (data['personal'] is Map)
        ? Map<String, dynamic>.from(data['personal'] as Map)
        : const <String, dynamic>{};

    final directAge = [
      data['age'],
      data['candidateAge'],
      personal['age'],
    ].map(parseAge).firstWhere((v) => v != null, orElse: () => null);
    if (directAge != null) {
      return '$directAge';
    }

    final birthYear = [
      data['birthYear'],
      data['yearOfBirth'],
      personal['birthYear'],
      personal['yearOfBirth'],
    ].map(parseYear).firstWhere((v) => v != null, orElse: () => null);
    if (birthYear != null) {
      final age = current.year - birthYear;
      if (age >= 14 && age <= 90) return '$age';
    }

    final birthDate = [
      data['birthDate'],
      data['dateOfBirth'],
      data['birthday'],
      personal['birthDate'],
      personal['dateOfBirth'],
      personal['birthday'],
    ].map(parseDate).firstWhere((v) => v != null, orElse: () => null);
    if (birthDate != null) {
      final age = computeAge(birthDate);
      if (age >= 14 && age <= 90) return '$age';
    }

    return '';
  }
}
