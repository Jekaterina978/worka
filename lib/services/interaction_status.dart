class InteractionStatus {
  static const pending = 'pending';
  static const viewed = 'viewed';
  static const accepted = 'accepted';
  static const rejected = 'rejected';
  // Legacy alias kept for backward compatibility with old code/fixtures.
  static const declined = rejected;
  static const postponed = 'postponed';
  static const sent = 'sent';
  static const freshLegacy = 'new';

  static String normalize(dynamic value, {String fallback = pending}) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty) return fallback;
    if (raw == freshLegacy) return pending;
    if (raw == 'declined') return rejected;
    return raw;
  }

  static bool isFresh(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    return raw == pending || raw == freshLegacy || raw == sent || raw == 'sent';
  }

  static bool isViewedLike(dynamic value) {
    final s = normalize(value);
    return s == viewed || s == postponed;
  }

  static String visibleLabel(dynamic value) {
    switch (normalize(value)) {
      case pending:    return 'Отправлено';
      case 'sent':     return 'Отправлено';
      case viewed:     return 'Просмотрено';
      case postponed:  return 'Отложено';
      case accepted:   return 'Принято';
      case rejected:   return 'Отклонено';
      default:         return 'Отправлено';
    }
  }

  static bool canReceiverChangeStatus(String status) {
    final s = normalize(status);
    return s != accepted && s != rejected;
  }
}
