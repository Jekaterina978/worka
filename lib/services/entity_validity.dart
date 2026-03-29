class WorkaEntityValidity {
  WorkaEntityValidity._();

  static bool _isTrue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final t = (value ?? '').toString().trim().toLowerCase();
    return t == 'true' || t == '1' || t == 'yes' || t == 'да';
  }

  static String _s(dynamic value) => (value ?? '').toString().trim();

  static bool _isPlaceholderText(String value) {
    final t = value.trim().toLowerCase();
    if (t.isEmpty) return true;
    return t == '-' ||
        t == 'n/a' ||
        t == 'null' ||
        t == 'undefined' ||
        t == 'не указано' ||
        t == 'не указан' ||
        t == 'не указана';
  }

  static bool _containsLetter(String value) {
    return RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(value);
  }

  static bool _looksGarbageText(String value) {
    final t = value.trim();
    if (t.length < 2) return true;
    if (!_containsLetter(t)) return true;
    final chars = t.replaceAll(RegExp(r'\s+'), '');
    if (chars.isEmpty) return true;
    final letters = RegExp(r'[A-Za-zА-Яа-яЁё]').allMatches(chars).length;
    final digits = RegExp(r'\d').allMatches(chars).length;
    final symbols = RegExp(r'[^A-Za-zА-Яа-яЁё0-9]').allMatches(chars).length;
    if (letters == 0) return true;
    if (digits > letters * 2) return true;
    if (symbols > letters) return true;
    final uniqueChars = chars.toLowerCase().split('').toSet().length;
    if (chars.length >= 6 && uniqueChars <= 2) return true;
    return false;
  }

  static bool _isValidHumanLabel(String value) {
    if (_isPlaceholderText(value)) return false;
    if (_looksGarbageText(value)) return false;
    return true;
  }

  static bool _isValidCountryLabel(String value) {
    final t = value.trim();
    if (_isPlaceholderText(t)) return false;
    if (t.length < 2) return false;
    if (!_containsLetter(t)) return false;
    return true;
  }

  static bool _isStaleDuplicateLike(Map<String, dynamic> doc) {
    if (_isTrue(doc['isStaleDuplicate']) ||
        _isTrue(doc['isDuplicate']) ||
        _isTrue(doc['duplicate']) ||
        _isTrue(doc['isSuperseded']) ||
        _isTrue(doc['superseded'])) {
      return true;
    }
    if (_s(doc['duplicateOfId']).isNotEmpty ||
        _s(doc['supersededById']).isNotEmpty ||
        _s(doc['replacedById']).isNotEmpty) {
      return true;
    }
    final status = _s(doc['status']).toLowerCase();
    return status == 'duplicate' || status == 'stale' || status == 'superseded';
  }

  static bool hasCopyToken(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return false;
    return t.contains('копия') || t.contains('copy');
  }

  static String resolveOwnerId(
    Map<String, dynamic> doc, {
    List<String> keys = const <String>[
      'ownerId',
      'ownerUid',
      'ownerKey',
      'authorId',
      'userId',
    ],
  }) {
    for (final key in keys) {
      final value = _s(doc[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _isDeletedLike(Map<String, dynamic> doc) {
    if (_isTrue(doc['isDeleted'])) return true;
    if (doc['deletedAt'] != null) return true;
    final status = _s(doc['status']).toLowerCase();
    return status == 'deleted' ||
        status == 'archived' ||
        status == 'removed' ||
        status == 'blocked' ||
        status == 'banned' ||
        status == 'suspended';
  }

  static bool _hasOwner(Map<String, dynamic> doc) {
    return resolveOwnerId(doc).isNotEmpty;
  }

  static bool _hasValidSalary(Map<String, dynamic> doc) {
    final amount = doc['salaryAmount'] ?? doc['salaryFrom'];
    if (amount is num && amount > 0 && amount <= 200000) return true;
    final salaryText = _s(doc['salaryText']).isNotEmpty
        ? _s(doc['salaryText'])
        : _s(doc['salary']);
    if (_isPlaceholderText(salaryText)) return false;
    final match = RegExp(
      r'(\d{2,7})',
    ).firstMatch(salaryText.replaceAll(' ', ''));
    if (match == null) return false;
    final parsed = num.tryParse(match.group(1) ?? '');
    if (parsed == null) return false;
    return parsed > 0 && parsed <= 200000;
  }

  static bool _hasValidCvSalary(Map<String, dynamic> doc) {
    final desired = doc['desired'] is Map<String, dynamic>
        ? (doc['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final amount =
        desired['salaryAmount'] ??
        desired['salaryFrom'] ??
        desired['salaryExpected'] ??
        doc['salaryAmount'] ??
        doc['salaryFrom'] ??
        doc['salaryExpected'];
    if (amount is num && amount > 0 && amount <= 200000) return true;
    final salaryText = _s(desired['salaryText']).isNotEmpty
        ? _s(desired['salaryText'])
        : (_s(doc['salaryText']).isNotEmpty
              ? _s(doc['salaryText'])
              : _s(doc['salary']));
    if (_isPlaceholderText(salaryText)) return false;
    final match = RegExp(
      r'(\d{2,7})',
    ).firstMatch(salaryText.replaceAll(' ', ''));
    if (match == null) return false;
    final parsed = num.tryParse(match.group(1) ?? '');
    if (parsed == null) return false;
    return parsed > 0 && parsed <= 200000;
  }

  static bool isValidPublicVacancy(Map<String, dynamic> doc) {
    if (_isDeletedLike(doc)) return false;
    if (_isStaleDuplicateLike(doc)) return false;
    if (_isTrue(doc['isDraft']) ||
        _isTrue(doc['draft']) ||
        _isTrue(doc['isIncomplete']) ||
        _isTrue(doc['incomplete'])) {
      return false;
    }
    final status = _s(doc['status']).toLowerCase();
    if (status == 'draft' || status == 'unfinished' || status == 'incomplete') {
      return false;
    }
    if (doc.containsKey('isComplete') && _isTrue(doc['isComplete']) == false) {
      return false;
    }
    if (doc.containsKey('publishable') &&
        _isTrue(doc['publishable']) == false) {
      return false;
    }
    if (doc.containsKey('published') && _isTrue(doc['published']) == false) {
      return false;
    }
    if (doc.containsKey('isPublished') &&
        _isTrue(doc['isPublished']) == false) {
      return false;
    }
    final title = _s(doc['title']);
    if (!_isValidHumanLabel(title) || hasCopyToken(title)) return false;
    final category = _s(doc['category']);
    if (!_isValidHumanLabel(category)) return false;
    final city = _s(doc['city']);
    final country = _s(doc['country']);
    if (!_isValidHumanLabel(city) || !_isValidCountryLabel(country)) {
      return false;
    }
    if (!_hasValidSalary(doc)) return false;
    if (!_hasOwner(doc)) return false;
    return true;
  }

  static bool isValidOwnerVacancy(
    Map<String, dynamic> doc, {
    required String ownerUid,
  }) {
    if (_isDeletedLike(doc)) return false;
    final owner = _s(doc['ownerId']).isNotEmpty
        ? _s(doc['ownerId'])
        : resolveOwnerId(doc);
    if (ownerUid.trim().isEmpty || owner != ownerUid.trim()) return false;
    return true;
  }

  static bool isValidPublicCv(Map<String, dynamic> doc) {
    if (_isDeletedLike(doc)) return false;
    if (_isStaleDuplicateLike(doc)) return false;
    if (_isTrue(doc['isDraft']) ||
        _isTrue(doc['draft']) ||
        _isTrue(doc['isIncomplete']) ||
        _isTrue(doc['incomplete'])) {
      return false;
    }
    final status = _s(doc['status']).toLowerCase();
    if (status == 'draft' || status == 'unfinished' || status == 'incomplete') {
      return false;
    }
    if (doc.containsKey('isComplete') && _isTrue(doc['isComplete']) == false) {
      return false;
    }
    if (doc.containsKey('publishable') &&
        _isTrue(doc['publishable']) == false) {
      return false;
    }
    if (doc.containsKey('published') && _isTrue(doc['published']) == false) {
      return false;
    }
    if (doc.containsKey('isPublished') &&
        _isTrue(doc['isPublished']) == false) {
      return false;
    }
    final title = _s(doc['title']).isNotEmpty
        ? _s(doc['title'])
        : _s(doc['profession']);
    if (!_isValidHumanLabel(title) || hasCopyToken(title)) return false;
    final owner = resolveOwnerId(
      doc,
      keys: const <String>[
        'ownerId',
        'ownerUid',
        'candidateOwnerId',
        'candidateUid',
        'userId',
      ],
    );
    if (owner.isEmpty) return false;
    final desired = doc['desired'] is Map<String, dynamic>
        ? (doc['desired'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final city = _s(doc['city']).isNotEmpty
        ? _s(doc['city'])
        : _s(desired['citiesText']);
    final countries = desired['countries'];
    final country = (countries is List && countries.isNotEmpty)
        ? countries.first.toString().trim()
        : _s(doc['country']);
    if (!_isValidHumanLabel(city) || !_isValidCountryLabel(country)) {
      return false;
    }
    if (!_hasValidCvSalary(doc)) return false;
    return true;
  }

  static bool isValidOwnerCv(
    Map<String, dynamic> doc, {
    required String ownerUid,
  }) {
    if (_isDeletedLike(doc)) return false;
    final owner = _s(doc['ownerId']).isNotEmpty
        ? _s(doc['ownerId'])
        : resolveOwnerId(
            doc,
            keys: const <String>[
              'ownerId',
              'ownerUid',
              'candidateOwnerId',
              'candidateUid',
              'userId',
            ],
          );
    if (ownerUid.trim().isEmpty || owner != ownerUid.trim()) return false;
    return true;
  }

  static bool isValidResponse(Map<String, dynamic> response) {
    if (_isDeletedLike(response)) return false;
    final type = _s(response['type']).toLowerCase();
    if (type != 'apply' && type != 'application' && type != 'response') {
      return false;
    }
    final vacancyId = _s(response['vacancyId']).isNotEmpty
        ? _s(response['vacancyId'])
        : _s(response['jobId']);
    final cvId = _s(response['candidateCvId']).isNotEmpty
        ? _s(response['candidateCvId'])
        : _s(response['cvId']);
    final candidateOwner = _s(response['candidateOwnerId']).isNotEmpty
        ? _s(response['candidateOwnerId'])
        : _s(response['candidateUid']);
    final employerOwner = _s(response['employerOwnerId']).isNotEmpty
        ? _s(response['employerOwnerId'])
        : _s(response['vacancyOwnerId']);
    if (vacancyId.isEmpty || cvId.isEmpty) return false;
    if (candidateOwner.isEmpty || employerOwner.isEmpty) return false;
    return true;
  }

  static bool isValidOffer(Map<String, dynamic> offer) {
    if (_isDeletedLike(offer)) return false;
    final type = _s(offer['type']).toLowerCase();
    if (type != 'offer') return false;
    final vacancyId = _s(offer['vacancyId']).isNotEmpty
        ? _s(offer['vacancyId'])
        : _s(offer['jobId']);
    final cvId = _s(offer['candidateCvId']).isNotEmpty
        ? _s(offer['candidateCvId'])
        : _s(offer['cvId']);
    final candidateOwner = _s(offer['candidateOwnerId']).isNotEmpty
        ? _s(offer['candidateOwnerId'])
        : _s(offer['candidateUid']);
    final employerOwner = _s(offer['employerOwnerId']).isNotEmpty
        ? _s(offer['employerOwnerId'])
        : _s(offer['vacancyOwnerId']);
    if (vacancyId.isEmpty || cvId.isEmpty) return false;
    if (candidateOwner.isEmpty || employerOwner.isEmpty) return false;
    return true;
  }
}
