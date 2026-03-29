class PublicCvSanitizer {
  const PublicCvSanitizer._();

  static const Set<String> _sensitiveTopLevelKeys = <String>{
    'email',
    'phone',
    'phoneNumber',
    'phoneCountryCode',
    'contactEmail',
    'contactPhone',
    'whatsapp',
    'telegram',
    'viber',
    'messenger',
    'tg',
    'wa',
    'facebookMessenger',
  };

  static const Set<String> _sensitiveContactKeys = <String>{
    'email',
    'phone',
    'phoneNumber',
    'phoneCountryCode',
    'whatsapp',
    'telegram',
    'viber',
    'messenger',
    'tg',
    'wa',
    'facebookMessenger',
    'contactEmail',
    'contactPhone',
  };

  static Map<String, dynamic> sanitizePublicCv(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    for (final key in _sensitiveTopLevelKeys) {
      out.remove(key);
    }
    final contacts = out['contacts'];
    if (contacts is Map) {
      final sanitizedContacts = Map<String, dynamic>.from(contacts);
      for (final key in _sensitiveContactKeys) {
        sanitizedContacts.remove(key);
      }
      out['contacts'] = sanitizedContacts;
    }
    return out;
  }
}
