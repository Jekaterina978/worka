import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:worka/screens/cv/widgets/cv_profile_view.dart';
import 'package:worka/services/firestore_paths.dart';
import 'package:worka/services/ownership_resolver.dart';
import 'package:worka/services/public_cv_sanitizer.dart';
import 'package:worka/theme/worka_colors.dart';
import 'package:worka/theme/worka_ui_tokens.dart';
import 'package:worka/features/payments/models/employer_payment_models.dart';
import 'package:worka/features/payments/contact_access_controller.dart';
import 'package:worka/screens/employer/search/widgets/offer_job_picker_sheet.dart';
import 'package:worka/widgets/sent_overlay.dart';

class CandidateDetailsSheet extends StatefulWidget {
  final String candidateId;
  final String candidateUid;
  final bool testMode;

  const CandidateDetailsSheet({
    super.key,
    required this.candidateId,
    required this.candidateUid,
    this.testMode = true,
  });

  static Future<void> open(
    BuildContext context, {
    required String candidateId,
    required String candidateUid,
    bool testMode = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: CandidateDetailsSheet(
          candidateId: candidateId,
          candidateUid: candidateUid,
          testMode: testMode,
        ),
      ),
    );
  }

  @override
  State<CandidateDetailsSheet> createState() => _CandidateDetailsSheetState();
}

class _CandidateDetailsSheetState extends State<CandidateDetailsSheet> {
  final _db = FirebaseFirestore.instance;
  final _contactAccess = ContactAccessController.instance;
  final Map<String, CandidateContact> _openedContacts =
      <String, CandidateContact>{};
  bool _contactsExpanded = false;
  bool _loadingUnlockedContact = false;

  @override
  void initState() {
    super.initState();
    _contactAccess.addListener(_onContactAccessChanged);
    _primeUnlockedContact();
  }

  @override
  void dispose() {
    _contactAccess.removeListener(_onContactAccessChanged);
    super.dispose();
  }

  void _onContactAccessChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _primeUnlockedContact() async {
    await _contactAccess.bootstrap(uid: OwnershipResolver.currentUid());
    if (!mounted) return;
    if (!_contactAccess.hasAccessToCandidateContact(widget.candidateId)) return;
    await _ensureUnlockedContactLoaded();
  }

  Future<void> _ensureUnlockedContactLoaded() async {
    final candidateId = widget.candidateId.trim();
    if (candidateId.isEmpty || _loadingUnlockedContact) return;
    if (!_contactAccess.hasAccessToCandidateContact(candidateId)) return;
    if (_openedContacts[candidateId] != null ||
        _contactAccess.contactForCandidate(candidateId) != null) {
      return;
    }
    _loadingUnlockedContact = true;
    try {
      final loaded = await _contactAccess.ensureLoadedContactForCandidate(
        candidateId,
      );
      if (!mounted || loaded == null) return;
      setState(() {
        _openedContacts[candidateId] = loaded;
      });
    } finally {
      _loadingUnlockedContact = false;
    }
  }

  String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String? _sanitizeAvatarUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final normalized = value.toLowerCase();
    const invalid = <String>{
      '',
      '-',
      'null',
      'undefined',
      'n/a',
      'placeholder',
    };
    if (invalid.contains(normalized)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    if (!isHttp || uri.host.trim().isEmpty) return null;
    return value;
  }

  Widget _candidateAvatar({
    required String initialsFallbackText,
    required String? avatarUrl,
    required String gender,
    double size = 52,
  }) {
    final sanitizedUrl = _sanitizeAvatarUrl(avatarUrl);
    final normalizedGender = gender.trim().toLowerCase();
    final bool isMale =
        normalizedGender == 'male' ||
        normalizedGender == 'm' ||
        normalizedGender == 'м' ||
        normalizedGender == 'мужской' ||
        normalizedGender == 'мужчина' ||
        normalizedGender == 'man';
    final bool isFemale =
        normalizedGender == 'female' ||
        normalizedGender == 'f' ||
        normalizedGender == 'ж' ||
        normalizedGender == 'женский' ||
        normalizedGender == 'женщина' ||
        normalizedGender == 'woman';
    final String? genderAsset = isMale
        ? 'assets/avatars/male.png'
        : (isFemale ? 'assets/avatars/female.png' : null);

    Widget initialsFallback() {
      return Center(
        child: Text(
          initialsFallbackText.isEmpty ? 'U' : initialsFallbackText,
          style: const TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      );
    }

    Widget genderAssetFallback() {
      if (genderAsset == null) return initialsFallback();
      return Image.asset(
        genderAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initialsFallback(),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: WorkaColors.blue.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: sanitizedUrl != null
            ? Image.network(
                sanitizedUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => genderAssetFallback(),
              )
            : genderAssetFallback(),
      ),
    );
  }

  Map<String, dynamic> _fallbackCandidateCv(Map<String, dynamic> candidate) {
    final profession = _s(candidate['profession']);
    final countriesWanted = (candidate['countriesWanted'] is List)
        ? (candidate['countriesWanted'] as List)
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
        : <String>[];
    return <String, dynamic>{
      'title': profession.isEmpty ? 'Не указано' : profession,
      'summary': _s(candidate['summary']),
      'contacts': {'name': _s(candidate['name'])},
      'desired': {'position': profession, 'countries': countriesWanted},
    };
  }

  Map<String, dynamic> _candidateFromCvDoc(
    Map<String, dynamic> cv, {
    required String cvId,
  }) {
    final contacts = (cv['contacts'] is Map)
        ? Map<String, dynamic>.from(cv['contacts'])
        : <String, dynamic>{};
    final desired = (cv['desired'] is Map)
        ? Map<String, dynamic>.from(cv['desired'])
        : <String, dynamic>{};
    final firstName = _s(contacts['firstName']);
    final lastName = _s(contacts['lastName']);
    final fullName = ('$firstName $lastName').trim();
    final countries = (desired['countries'] is List)
        ? (desired['countries'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final city = _s(desired['citiesText']).split(',').first.trim();
    return <String, dynamic>{
      'cvId': cvId,
      'ownerId': _s(cv['ownerId']),
      'ownerUid': _s(cv['ownerUid']),
      'name': _s(
        contacts['name'],
        fallback: fullName.isEmpty ? 'Кандидат' : fullName,
      ),
      'firstName': firstName,
      'lastName': lastName,
      'profession': _s(
        desired['position'],
        fallback: _s(desired['categoryGroup']),
      ),
      'category': _s(desired['categoryGroup']),
      'city': city,
      'country': countries.isEmpty ? '' : countries.first,
      'avatarUrl': _s(
        contacts['avatarUrl'],
        fallback: _s(contacts['photoUrl'], fallback: _s(cv['avatarUrl'])),
      ),
      'gender': _s(contacts['gender'], fallback: _s(cv['gender'])),
      'summary': _s(cv['summary']),
      'countriesWanted': countries,
    };
  }

  Map<String, dynamic> _employerViewCv(
    Map<String, dynamic> fullCv, {
    required bool hasUnlockedAccess,
  }) {
    final out = PublicCvSanitizer.sanitizePublicCv(
      Map<String, dynamic>.from(fullCv),
    );
    if (!hasUnlockedAccess && out['contacts'] is Map<String, dynamic>) {
      final contacts = Map<String, dynamic>.from(
        out['contacts'] as Map<String, dynamic>,
      );
      contacts.remove('email');
      contacts.remove('phone');
      contacts.remove('whatsapp');
      contacts.remove('telegram');
      contacts.remove('viber');
      contacts.remove('messenger');
      contacts.remove('tg');
      contacts.remove('wa');
      contacts.remove('facebookMessenger');
      out['contacts'] = contacts;
    }
    return out;
  }

  Future<void> _showSentOverlayAndClose() async {
    if (!mounted) return;
    await showSentOverlay(context, 'Предложение отправлено');
    if (mounted) Navigator.pop(context);
  }

  CandidateContact _contactFromCandidate(Map<String, dynamic> candidate) {
    final cached =
        _openedContacts[widget.candidateId] ??
        _contactAccess.contactForCandidate(widget.candidateId);
    if (cached != null) return cached;
    return CandidateContact(
      candidateId: _s(candidate['cvId'], fallback: widget.candidateId),
      name: _s(candidate['name'], fallback: 'Кандидат'),
      email: '',
      phone: '',
    );
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = _s(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  bool _isNewCandidate(Map<String, dynamic> candidate) {
    final raw =
        candidate['createdAt'] ??
        candidate['updatedAt'] ??
        candidate['publishedAt'];
    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is DateTime) {
      dt = raw;
    }
    if (dt == null) return false;
    return DateTime.now().difference(dt).inDays <= 3;
  }

  bool _hasUnlockedAccess() {
    if (_contactsExpanded) return true;
    return _contactAccess.hasAccessToCandidateContact(widget.candidateId);
  }

  DateTime? _dateFromAny(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw == null) return null;
    try {
      final dynamic value = raw;
      final dynamic converted = value.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  int? _ageFromCandidate(Map<String, dynamic> candidate) {
    final contacts = (candidate['contacts'] is Map)
        ? Map<String, dynamic>.from(candidate['contacts'])
        : const <String, dynamic>{};
    final birthRaw =
        candidate['birthDate'] ??
        candidate['dateOfBirth'] ??
        contacts['birthDate'] ??
        contacts['dateOfBirth'];
    final date = _dateFromAny(birthRaw);
    if (date == null) return null;
    final now = DateTime.now();
    var age = now.year - date.year;
    final hadBirthday =
        now.month > date.month ||
        (now.month == date.month && now.day >= date.day);
    if (!hadBirthday) age -= 1;
    if (age < 14 || age > 100) return null;
    return age;
  }

  Widget _signalChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WorkaColors.hoverBlue.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: WorkaColors.blue.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: WorkaColors.subtitle,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> candidate) {
    final contacts = (candidate['contacts'] is Map)
        ? Map<String, dynamic>.from(candidate['contacts'])
        : const <String, dynamic>{};
    final desired = (candidate['desired'] is Map)
        ? Map<String, dynamic>.from(candidate['desired'])
        : const <String, dynamic>{};
    final firstName = _s(
      candidate['firstName'],
      fallback: _s(contacts['firstName']),
    );
    final lastName = _s(
      candidate['lastName'],
      fallback: _s(contacts['lastName']),
    );
    final fullName = ('$firstName $lastName').trim();
    final name = _s(
      candidate['name'],
      fallback: fullName.isEmpty ? 'Кандидат' : fullName,
    );
    final age = _ageFromCandidate(candidate);
    final nameWithAge = age == null ? name : '$name, $age';
    final cvTitle = _s(
      candidate['title'],
      fallback: _s(
        candidate['profession'],
        fallback: _s(desired['position'], fallback: 'CV'),
      ),
    );
    final city = _s(candidate['city']);
    final country = _s(
      candidate['country'],
      fallback: _s(candidate['countryName']),
    );
    final location = city.isNotEmpty && country.isNotEmpty
        ? '$country · $city'
        : (country.isNotEmpty ? country : city);
    final avatarUrl = _s(candidate['avatarUrl']);
    final gender = _s(candidate['gender']);
    final initials = name
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .take(2)
        .map((e) => e.substring(0, 1).toUpperCase())
        .join();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF5B8CFF), Color(0xFF3F6FE5)],
        ),
        boxShadow: WorkaUiShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _candidateAvatar(
            initialsFallbackText: initials,
            avatarUrl: avatarUrl,
            gender: gender,
            size: 52,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameWithAge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cvTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFEAF2FF),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenContactsButton({
    required Map<String, dynamic> candidate,
    required bool contactsOpened,
  }) {
    debugPrint(
      '[CANDIDATE_DETAIL_RENDER] candidateId=${widget.candidateId} ctrlHash=${identityHashCode(_contactAccess)} hasAccess=${_contactAccess.hasAccessToCandidateContact(widget.candidateId)} hasContact=${_contactAccess.contactForCandidate(widget.candidateId) != null} showingPaywall=${!contactsOpened}',
    );
    if (contactsOpened) return const SizedBox.shrink();
    String maskPhone(String raw) {
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 6) return '+371 *** **23';
      final prefix = raw.trim().startsWith('+')
          ? '+${digits.substring(0, 3)}'
          : '+${digits.substring(0, 3)}';
      final tail = digits.substring(digits.length - 2);
      return '$prefix *** **$tail';
    }

    String maskEmail(String raw) {
      final trimmed = raw.trim();
      if (!trimmed.contains('@')) return 'j***@gmail.com';
      final parts = trimmed.split('@');
      final local = parts.first.trim();
      final domain = parts.last.trim();
      if (local.isEmpty || domain.isEmpty) return 'j***@gmail.com';
      final first = local.substring(0, 1);
      return '$first***@$domain';
    }

    String pickMaskedPhone() {
      final contacts = candidate['contacts'];
      final fromContacts = contacts is Map
          ? _s(
              contacts['phone'],
              fallback: _s(
                contacts['phoneNumber'],
                fallback: _s(contacts['contactPhone']),
              ),
            )
          : '';
      final top = _s(
        candidate['phone'],
        fallback: _s(
          candidate['phoneNumber'],
          fallback: _s(candidate['candidatePhone']),
        ),
      );
      final source = fromContacts.isNotEmpty ? fromContacts : top;
      return maskPhone(source);
    }

    String pickMaskedEmail() {
      final contacts = candidate['contacts'];
      final fromContacts = contacts is Map
          ? _s(contacts['email'], fallback: _s(contacts['contactEmail']))
          : '';
      final top = _s(
        candidate['email'],
        fallback: _s(candidate['candidateEmail']),
      );
      final source = fromContacts.isNotEmpty ? fromContacts : top;
      return maskEmail(source);
    }

    final maskedPhone = pickMaskedPhone();
    final maskedEmail = pickMaskedEmail();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: WorkaUiShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Контакты скрыты до открытия',
            style: TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.phone_outlined,
                size: 18,
                color: WorkaColors.textGreyDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Телефон: $maskedPhone',
                  style: const TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.email_outlined,
                size: 18,
                color: WorkaColors.textGreyDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Email: $maskedEmail',
                  style: const TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () async {
                try {
                  final result = await _contactAccess.ensureContactUnlocked(
                    context,
                    candidateId: widget.candidateId,
                    candidateName: _s(candidate['name']),
                    entryPoint: 'candidate_details_sheet',
                  );
                  if (!mounted || !result.isSuccess) return;

                  final loaded =
                      result.contact ??
                      await _contactAccess.ensureLoadedContactForCandidate(
                        widget.candidateId,
                      );
                  if (loaded != null) {
                    _openedContacts[widget.candidateId] = loaded;
                    setState(() => _contactsExpanded = true);
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Не удалось открыть контакты'),
                      ),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Не удалось открыть контакты: $e'),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.orange,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Открыть контакты',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalsBlock(Map<String, dynamic> candidate) {
    final signals = <String>[];
    final experience = _s(
      candidate['experience'],
      fallback: _s(candidate['workExperience']),
    );
    if (experience.isNotEmpty) {
      final low = experience.toLowerCase();
      signals.add(
        low.contains('без') && low.contains('опыт') ? 'Без опыта' : 'Есть опыт',
      );
    }

    final docsList = (candidate['documents'] is List)
        ? (candidate['documents'] as List)
        : const [];
    if (_asBool(candidate['hasDocuments']) ||
        _asBool(candidate['hasWorkDocuments']) ||
        docsList.isNotEmpty) {
      signals.add('Есть документы');
    }
    if (_asBool(candidate['hasDriverLicense']) ||
        _asBool(candidate['driverLicense'])) {
      signals.add('Есть права');
    }
    if (_asBool(candidate['readyToRelocate'])) {
      signals.add('Готов к переезду');
    }
    if (_asBool(candidate['readyToWork']) ||
        _asBool(candidate['availableNow'])) {
      signals.add('Готов начать работу');
    }
    if (_isNewCandidate(candidate)) {
      signals.add('Новый кандидат');
    }
    if (signals.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: signals.take(6).map(_signalChip).toList(),
      ),
    );
  }

  static String _digitsOnly(String raw) {
    return raw.replaceAll(RegExp(r'[^\d+]'), '');
  }

  static String _extractUsernameLike(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    final cleaned = value
        .replaceAll(RegExp(r'^https?://', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'^(t\.me/|telegram\.me/)', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'^(m\.me/|facebook\.com/)', caseSensitive: false),
          '',
        )
        .replaceAll('@', '')
        .split('?')
        .first;
    final parts = cleaned
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    return parts.last;
  }

  static Future<bool> _launchAny(List<Uri> uris) async {
    for (final uri in uris) {
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    }
    return false;
  }

  static Future<bool> _openWhatsapp(String rawContact, String message) {
    final digits = _digitsOnly(rawContact);
    if (digits.isEmpty) return Future<bool>.value(false);
    final encoded = Uri.encodeComponent(message);
    return _launchAny([
      Uri.parse('whatsapp://send?phone=$digits&text=$encoded'),
      Uri.parse('https://wa.me/${digits.replaceAll('+', '')}?text=$encoded'),
    ]);
  }

  static Future<bool> _openTelegram(String rawContact, String message) {
    final username = _extractUsernameLike(rawContact);
    if (username.isEmpty) return Future<bool>.value(false);
    final encoded = Uri.encodeComponent(message);
    return _launchAny([
      Uri.parse('tg://resolve?domain=$username&text=$encoded'),
      Uri.parse('https://t.me/$username?text=$encoded'),
    ]);
  }

  static Future<bool> _openViber(String rawContact, String message) {
    final phone = _digitsOnly(rawContact);
    if (phone.isEmpty) return Future<bool>.value(false);
    final encoded = Uri.encodeComponent(message);
    return _launchAny([
      Uri.parse('viber://chat?number=$phone&text=$encoded'),
      Uri.parse(
        'https://invite.viber.com/?number=${phone.replaceAll('+', '')}',
      ),
    ]);
  }

  static Future<bool> _openMessenger(String rawContact, String message) {
    final handle = _extractUsernameLike(rawContact);
    if (handle.isEmpty) return Future<bool>.value(false);
    final encoded = Uri.encodeComponent(message);
    return _launchAny([
      Uri.parse('fb-messenger://user-thread/$handle'),
      Uri.parse('https://m.me/$handle?ref=$encoded'),
    ]);
  }

  Future<void> _openEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email.trim());
    final ok = await _launchAny([uri]);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Не удалось открыть email')));
    }
  }

  Future<void> _openPhone(String phone) async {
    final clean = _digitsOnly(phone);
    if (clean.isEmpty) return;
    final ok = await _launchAny([Uri.parse('tel:$clean')]);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть телефон')),
      );
    }
  }

  Future<void> _openMessengerChannel({
    required Future<bool> Function(String contact, String message) opener,
    required String contact,
    required String message,
  }) async {
    final ok = await opener(contact, message);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть канал связи')),
      );
    }
  }

  Widget _solidContactButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _outlinedContactButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: WorkaColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsBlock(
    CandidateContact contact,
    Map<String, dynamic> candidate,
  ) {
    debugPrint(
      '[CANDIDATE_DETAIL_RENDER] candidateId=${widget.candidateId} ctrlHash=${identityHashCode(_contactAccess)} hasAccess=${_contactAccess.hasAccessToCandidateContact(widget.candidateId)} hasContact=${_contactAccess.contactForCandidate(widget.candidateId) != null} showingPaywall=false showingRealContacts=true',
    );
    final whatsapp = contact.whatsapp.trim();
    final telegram = contact.telegram.trim();
    final viber = contact.viber.trim();
    final messenger = contact.messenger.trim();
    final email = contact.email.trim();
    final phone = contact.phone.trim();
    final autoMessage = 'Здравствуйте! Меня интересует ваш профиль.';
    final hasAny =
        whatsapp.isNotEmpty ||
        telegram.isNotEmpty ||
        viber.isNotEmpty ||
        messenger.isNotEmpty ||
        email.isNotEmpty ||
        phone.isNotEmpty;
    if (!hasAny) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.divider.withValues(alpha: 0.75)),
        boxShadow: WorkaUiShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (whatsapp.isNotEmpty) ...[
            _solidContactButton(
              icon: FontAwesomeIcons.whatsapp,
              label: 'Написать в WhatsApp',
              backgroundColor: const Color(0xFF25D366),
              onTap: () => _openMessengerChannel(
                opener: _openWhatsapp,
                contact: whatsapp,
                message: autoMessage,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (telegram.isNotEmpty) ...[
            _solidContactButton(
              icon: FontAwesomeIcons.telegram,
              label: 'Написать в Telegram',
              backgroundColor: const Color(0xFF229ED9),
              onTap: () => _openMessengerChannel(
                opener: _openTelegram,
                contact: telegram,
                message: autoMessage,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (viber.isNotEmpty) ...[
            _solidContactButton(
              icon: FontAwesomeIcons.viber,
              label: 'Написать в Viber',
              backgroundColor: const Color(0xFF7360F2),
              onTap: () => _openMessengerChannel(
                opener: _openViber,
                contact: viber,
                message: autoMessage,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (messenger.isNotEmpty) ...[
            _solidContactButton(
              icon: FontAwesomeIcons.facebookMessenger,
              label: 'Написать в Messenger',
              backgroundColor: const Color(0xFF2B62F3),
              onTap: () => _openMessengerChannel(
                opener: _openMessenger,
                contact: messenger,
                message: autoMessage,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (email.isNotEmpty) ...[
            _outlinedContactButton(
              icon: Icons.email_outlined,
              text: 'Email: $email',
              onTap: () => _openEmail(email),
            ),
            const SizedBox(height: 8),
          ],
          if (phone.isNotEmpty) ...[
            _outlinedContactButton(
              icon: Icons.phone_outlined,
              text: 'Телефон: $phone',
              onTap: () => _openPhone(phone),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openOfferPicker(Map<String, dynamic> candidate) async {
    final candidateUid = _s(
      widget.candidateUid,
      fallback: _s(
        candidate['ownerId'],
        fallback: _s(
          candidate['ownerUid'],
          fallback: _s(
            candidate['candidateUid'],
            fallback: _s(candidate['uid'], fallback: _s(candidate['userId'])),
          ),
        ),
      ),
    );
    if (candidateUid.isEmpty) {
      debugPrint(
        'CandidateDetailsSheet: candidateUid missing. candidate keys: ${candidate.keys.toList()}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось определить кандидата'),
          backgroundColor: WorkaColors.textDark,
        ),
      );
      return;
    }

    final sent = await OfferJobPickerSheet.open(
      context,
      candidateUid: candidateUid,
      candidateCvId: _s(candidate['cvId'], fallback: widget.candidateId),
      candidateData: candidate,
      testMode: widget.testMode,
    );

    if (sent == true) {
      await _showSentOverlayAndClose();
    }
  }

  Widget _centerState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: WorkaColors.textGreyDark,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidateRef = _db
        .collection(FirestorePaths.cvs)
        .doc(widget.candidateId);
    final cvRef = _db.collection(FirestorePaths.cvs).doc(widget.candidateId);
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: candidateRef.snapshots(),
          builder: (context, candidateSnap) {
            if (!candidateSnap.hasData) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (!candidateSnap.data!.exists) {
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: cvRef.snapshots(),
                builder: (context, cvSnap) {
                  if (!cvSnap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (!cvSnap.data!.exists) {
                    return _centerState('Кандидат не найден');
                  }
                  final cvData = cvSnap.data!.data() ?? <String, dynamic>{};
                  final candidate = _candidateFromCvDoc(
                    cvData,
                    cvId: widget.candidateId,
                  );
                  return _candidateBody(candidate, forceCvData: cvData);
                },
              );
            }

            final candidate = candidateSnap.data!.data() ?? <String, dynamic>{};
            return _candidateBody(candidate);
          },
        ),
      ),
    );
  }

  Widget _candidateBody(
    Map<String, dynamic> candidate, {
    Map<String, dynamic>? forceCvData,
  }) {
    final candidateOwnerId = widget.candidateUid.trim().isNotEmpty
        ? widget.candidateUid.trim()
        : OwnershipResolver.cvOwnerIdFromMap(candidate);
    final ownership = OwnershipResolver.byOwnerId(candidateOwnerId);
    final currentUid = OwnershipResolver.currentUid();
    final ownershipKnown = ownership.known;
    final isOwnCv = ownership.isOwner;
    final cvId = _s(candidate['cvId'], fallback: widget.candidateId);
    final offerSentStream = (!ownershipKnown || currentUid.isEmpty)
        ? Stream<bool>.value(false)
        : _db
              .collection(FirestorePaths.jobOffers)
              .where('type', isEqualTo: 'offer')
              .where('employerOwnerId', isEqualTo: currentUid)
              .where('candidateOwnerId', isEqualTo: candidateOwnerId)
              .where(
                'status',
                whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
              )
              .limit(1)
              .snapshots()
              .map((s) {
                if (kDebugMode) {
                  debugPrint(
                    'CandidateDetailsSheet offer badge employerUid=$currentUid candidateOwnerId=$candidateOwnerId count=${s.docs.length}',
                  );
                }
                return s.docs.isNotEmpty;
              });

    return StreamBuilder<bool>(
      stream: offerSentStream,
      builder: (context, snap) {
        final offerSent = snap.data ?? false;
        final hasUnlockedAccess = _hasUnlockedAccess();
        final candidateId = widget.candidateId.trim();
        if (hasUnlockedAccess &&
            candidateId.isNotEmpty &&
            _openedContacts[candidateId] == null &&
            _contactAccess.contactForCandidate(candidateId) == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureUnlockedContactLoaded();
          });
        }
        final contactForCard =
            _openedContacts[widget.candidateId] ??
            _contactFromCandidate(candidate);
        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                  child: Row(
                    children: [
                      const Text(
                        'Кандидат',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: WorkaColors.textDark,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close,
                          color: WorkaColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (cvId.isEmpty) {
                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildHeroCard(candidate),
                              _buildOpenContactsButton(
                                candidate: candidate,
                                contactsOpened: hasUnlockedAccess,
                              ),
                              _buildSignalsBlock(candidate),
                              if (hasUnlockedAccess)
                                _buildContactsBlock(contactForCard, candidate),
                              CvProfileView(
                                cvId: widget.candidateId,
                                cv: _fallbackCandidateCv(candidate),
                                mode: CvViewerMode.employer,
                                showHeaderSection: false,
                                showTitleSection: false,
                                hideEmptySections: true,
                                showSensitiveContacts: hasUnlockedAccess,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  130,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (forceCvData != null) {
                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildHeroCard(candidate),
                              _buildOpenContactsButton(
                                candidate: candidate,
                                contactsOpened: hasUnlockedAccess,
                              ),
                              _buildSignalsBlock({
                                ...forceCvData,
                                ...candidate,
                              }),
                              if (hasUnlockedAccess)
                                _buildContactsBlock(contactForCard, candidate),
                              CvProfileView(
                                cvId: cvId,
                                cv: _employerViewCv(
                                  forceCvData,
                                  hasUnlockedAccess: hasUnlockedAccess,
                                ),
                                mode: CvViewerMode.employer,
                                showHeaderSection: false,
                                showTitleSection: false,
                                hideEmptySections: true,
                                showSensitiveContacts: hasUnlockedAccess,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  130,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final cvStream = _db
                          .collection(FirestorePaths.cvs)
                          .doc(cvId)
                          .snapshots()
                          .map((d) {
                            return d.exists
                                ? [d]
                                : <DocumentSnapshot<Map<String, dynamic>>>[];
                          });
                      return StreamBuilder<
                        List<DocumentSnapshot<Map<String, dynamic>>>
                      >(
                        stream: cvStream,
                        builder: (context, cvSnap) {
                          if (!cvSnap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          }
                          final doc = cvSnap.data!.isNotEmpty
                              ? cvSnap.data!.first
                              : null;
                          if (doc == null) {
                            return SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildHeroCard(candidate),
                                  _buildOpenContactsButton(
                                    candidate: candidate,
                                    contactsOpened: hasUnlockedAccess,
                                  ),
                                  _buildSignalsBlock(candidate),
                                  if (hasUnlockedAccess)
                                    _buildContactsBlock(
                                      contactForCard,
                                      candidate,
                                    ),
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      10,
                                    ),
                                    child: Text(
                                      'Полное CV кандидата не найдено',
                                      style: TextStyle(
                                        color: WorkaColors.textGreyDark,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  CvProfileView(
                                    cvId: widget.candidateId,
                                    cv: _fallbackCandidateCv(candidate),
                                    mode: CvViewerMode.employer,
                                    showHeaderSection: false,
                                    showTitleSection: false,
                                    hideEmptySections: true,
                                    showSensitiveContacts: hasUnlockedAccess,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      6,
                                      16,
                                      130,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final cvData = PublicCvSanitizer.sanitizePublicCv(
                            doc.data() ?? <String, dynamic>{},
                          );
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                _buildHeroCard(candidate),
                                _buildOpenContactsButton(
                                  candidate: candidate,
                                  contactsOpened: hasUnlockedAccess,
                                ),
                                _buildSignalsBlock({...cvData, ...candidate}),
                                if (hasUnlockedAccess)
                                  _buildContactsBlock(
                                    contactForCard,
                                    candidate,
                                  ),
                                CvProfileView(
                                  cvId: cvId,
                                  cv: _employerViewCv(
                                    cvData,
                                    hasUnlockedAccess: hasUnlockedAccess,
                                  ),
                                  mode: CvViewerMode.employer,
                                  showHeaderSection: false,
                                  showTitleSection: false,
                                  hideEmptySections: true,
                                  showSensitiveContacts: hasUnlockedAccess,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    6,
                                    16,
                                    130,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Builder(
                  builder: (context) {
                    if (!ownershipKnown) {
                      return SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkaColors.blue,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Готово',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    }
                    if (isOwnCv) {
                      return Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: WorkaColors.blue),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                minimumSize: const Size.fromHeight(56),
                              ),
                              child: const Text(
                                'Редактировать CV',
                                style: TextStyle(
                                  color: WorkaColors.blue,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WorkaColors.orange,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                minimumSize: const Size.fromHeight(56),
                              ),
                              child: const Text(
                                'Готово',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: offerSent
                          ? Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: WorkaColors.orange,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Text(
                                'Предложение отправлено',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : ElevatedButton(
                              onPressed: () => _openOfferPicker(candidate),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WorkaColors.orange,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                'Предложить работу',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
