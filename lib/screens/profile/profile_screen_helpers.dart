part of 'package:worka/screens/profile_screen.dart';

mixin _ProfileScreenHelpers on State<ProfileScreen> {
  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  DateTime? _dateFromAny(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  int? _ageFromBirthDate(dynamic raw) {
    final birth = _dateFromAny(raw);
    if (birth == null) return null;
    final now = DateTime.now();
    var age = now.year - birth.year;
    final hadBirthday =
        now.month > birth.month ||
        (now.month == birth.month && now.day >= birth.day);
    if (!hadBirthday) age -= 1;
    return age > 0 ? age : null;
  }

  String _creditsStateTitle(int credits) {
    if (credits <= 0) return 'Кредитов нет';
    if (credits <= 3) return 'Мало кредитов';
    return 'Кредитов достаточно';
  }

  String _creditsStateHint(int credits) {
    if (credits <= 0) {
      return 'Чтобы открыть контакт кандидата, пополните баланс.';
    }
    if (credits <= 3) {
      return 'Осталось мало кредитов. Лучше пополнить заранее.';
    }
    return 'Можно открывать контакты без ограничений прямо сейчас.';
  }

  Color _creditsStateColor(int credits) {
    if (credits <= 0) return const Color(0xFFD14343);
    if (credits <= 3) return const Color(0xFFB86A00);
    return const Color(0xFF1F7A3D);
  }
}
