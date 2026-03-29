import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/worka_colors.dart';

class VacancyApplyEntrySheet extends StatefulWidget {
  const VacancyApplyEntrySheet({
    super.key,
    required this.vacancy,
    required this.onSendCvTap,
  });

  final Map<String, dynamic> vacancy;
  final Future<bool> Function() onSendCvTap;

  static Future<bool> open(
    BuildContext context, {
    required Map<String, dynamic> vacancy,
    required Future<bool> Function() onSendCvTap,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          VacancyApplyEntrySheet(vacancy: vacancy, onSendCvTap: onSendCvTap),
    ).then((value) => value == true);
  }

  @override
  State<VacancyApplyEntrySheet> createState() => _VacancyApplyEntrySheetState();
}

class _VacancyApplyEntrySheetState extends State<VacancyApplyEntrySheet> {
  Map<String, dynamic> _employerProfile = const <String, dynamic>{};

  static String _s(dynamic v, {String fallback = ''}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _ownerIdFromVacancy(Map<String, dynamic> job) {
    final values = <String>[
      _s(job['ownerId']),
      _s(job['ownerUid']),
      _s(job['employerId']),
      _s(job['ownerKey']),
      _s(job['userId']),
      _s(_asMap(job['business'])['ownerId']),
    ];
    for (final value in values) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _loadEmployerProfile();
  }

  Future<void> _loadEmployerProfile() async {
    final ownerId = _ownerIdFromVacancy(widget.vacancy);
    if (ownerId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .get();
      if (!mounted) return;
      setState(
        () => _employerProfile = snap.data() ?? const <String, dynamic>{},
      );
    } catch (_) {
      // silent: contacts from vacancy itself still work
    }
  }

  static String _digitsOnly(String input) {
    final out = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (out.startsWith('00')) return '+${out.substring(2)}';
    return out;
  }

  static String _extractUsernameLike(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('@')) value = value.substring(1);
    if (value.contains('://')) {
      final uri = Uri.tryParse(value);
      if (uri != null) {
        final seg = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
        if (seg.isNotEmpty) value = seg.last;
      }
    }
    return value.replaceAll('/', '').trim();
  }

  static String _salaryText(Map<String, dynamic> data) {
    final salaryText = _s(data['salaryText'], fallback: _s(data['salary']));
    if (salaryText.isNotEmpty) {
      final hasCurrency =
          salaryText.contains('€') ||
          salaryText.contains(r'$') ||
          salaryText.contains('₽') ||
          salaryText.contains('£') ||
          salaryText.toLowerCase().contains('eur');
      return hasCurrency ? salaryText : '€ $salaryText';
    }
    final amount = data['salaryAmount'] ?? data['salaryFrom'];
    if (amount is num && amount > 0) return '€ ${amount.round()}';
    return '€—';
  }

  static String _pick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _s(map[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String _scheduleText(Map<String, dynamic> data) {
    return _pick(data, const [
      'workSchedule',
      'workScheduleOption',
      'employmentType',
      'schedule',
      'shift',
      'workFormat',
      'type',
    ]);
  }

  static String _startText(Map<String, dynamic> data) {
    final immediate =
        data['startImmediately'] == true ||
        data['immediateStart'] == true ||
        data['asap'] == true ||
        _s(data['startWhen']).toLowerCase() == 'asap';
    if (immediate) return 'Приступать сразу';

    final explicit = _pick(data, const [
      'startWhen',
      'availableFrom',
      'startFrom',
      'startDateText',
    ]);
    if (explicit.isNotEmpty) return explicit;

    final date = _asDate(data['startDate'] ?? data['availableFromDate']);
    if (date != null) {
      final dd = date.day.toString().padLeft(2, '0');
      final mm = date.month.toString().padLeft(2, '0');
      final yyyy = date.year.toString();
      return '$dd.$mm.$yyyy';
    }
    return '';
  }

  static String _locationText(Map<String, dynamic> data) {
    final city = _s(data['city'], fallback: _s(data['locationCity']));
    final country = _s(data['country'], fallback: _s(data['countryName']));
    if (city.isEmpty && country.isEmpty) return 'Локация не указана';
    if (city.isEmpty) return country;
    if (country.isEmpty) return city;
    return '$country · $city';
  }

  static bool _hasNoLanguage(Map<String, dynamic> data) {
    if (data['noLanguageRequired'] == true) return true;
    final language = _s(data['language']).toLowerCase();
    if (language == 'без языка' || language == 'без знания языка') return true;
    final langs = data['languages'];
    if (langs is List) {
      for (final item in langs) {
        final text = _s(item).toLowerCase();
        if (text.contains('без языка') || text.contains('без знания языка')) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _hasNoExperience(Map<String, dynamic> data) {
    final exp = _s(data['experience']).toLowerCase();
    final required = _s(data['experienceRequired']).toLowerCase();
    return exp.contains('без') && exp.contains('опыт') ||
        required == 'no_experience';
  }

  static bool _isUrgent(Map<String, dynamic> data) {
    if (data['urgent'] == true || data['isUrgent'] == true) return true;
    final until = data['urgentActiveUntil'];
    if (until is Timestamp) return until.toDate().isAfter(DateTime.now());
    if (until is DateTime) return until.isAfter(DateTime.now());
    return false;
  }

  static bool _isReliable(Map<String, dynamic> data) {
    return data['verifiedEmployer'] == true ||
        data['isVerified'] == true ||
        data['employerVerified'] == true ||
        data['verified'] == true;
  }

  Widget _iconBadge({
    required IconData icon,
    required Color color,
    Color background = const Color(0xFFF2F6FF),
    Color border = const Color(0xFFDCE5FA),
  }) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Widget _compoundNoBadge({required IconData icon, required Color iconColor}) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF8D3D3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.close_rounded, size: 17, color: Color(0xFFD32F2F)),
          const SizedBox(width: 5),
          Icon(icon, size: 17, color: iconColor),
        ],
      ),
    );
  }

  List<Widget> _buildBadges(Map<String, dynamic> data) {
    final out = <Widget>[];

    if (data['housingProvided'] == true || data['housing'] == true) {
      out.add(_iconBadge(icon: Icons.home_outlined, color: WorkaColors.blue));
    }
    if (data['transportProvided'] == true || data['transport'] == true) {
      out.add(
        _iconBadge(
          icon: Icons.airport_shuttle_outlined,
          color: WorkaColors.orange,
        ),
      );
    }
    if (_hasNoLanguage(data)) {
      out.add(
        _compoundNoBadge(
          icon: Icons.translate_rounded,
          iconColor: WorkaColors.blueDark,
        ),
      );
    }
    if (_hasNoExperience(data)) {
      out.add(
        _compoundNoBadge(
          icon: Icons.work_outline_rounded,
          iconColor: WorkaColors.orange,
        ),
      );
    }
    if (_isUrgent(data)) {
      out.add(
        _iconBadge(
          icon: Icons.flash_on_rounded,
          color: Colors.white,
          background: const Color(0xFFFF6A4E),
          border: const Color(0xFFFF6A4E),
        ),
      );
    }
    if (_isReliable(data)) {
      out.add(
        _iconBadge(
          icon: Icons.verified_rounded,
          color: const Color(0xFFFFA000),
          background: const Color(0xFFFFF8E1),
          border: const Color(0xFFFFE7A6),
        ),
      );
    }
    return out;
  }

  _ContactChannels _extractChannels() {
    final job = widget.vacancy;
    final profile = _employerProfile;
    final contacts = _asMap(job['contacts']);
    final socialLinks = _asMap(job['socialLinks']);
    final employerContacts = _asMap(job['employerContacts']);
    final business = _asMap(job['business']);
    final personal = _asMap(job['personal']);

    final profileContacts = _asMap(profile['contacts']);
    final profileSocial = _asMap(profile['socialLinks']);
    final profileBusiness = _asMap(profile['business']);
    final profilePersonal = _asMap(profile['personal']);

    String pick(List<String> keys) {
      for (final key in keys) {
        final values = <String>[
          _s(job[key]),
          _s(contacts[key]),
          _s(socialLinks[key]),
          _s(employerContacts[key]),
          _s(business[key]),
          _s(personal[key]),
          _s(profile[key]),
          _s(profileContacts[key]),
          _s(profileSocial[key]),
          _s(profileBusiness[key]),
          _s(profilePersonal[key]),
        ];
        for (final value in values) {
          if (value.isNotEmpty) return value;
        }
      }
      return '';
    }

    return _ContactChannels(
      whatsapp: pick(const ['whatsapp', 'wa']),
      telegram: pick(const ['telegram', 'tg']),
      viber: pick(const ['viber']),
      messenger: pick(const ['messenger', 'facebookMessenger']),
    );
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

  @override
  Widget build(BuildContext context) {
    final title = _s(widget.vacancy['title'], fallback: 'Вакансия');
    final location = _locationText(widget.vacancy);
    final salary = _salaryText(widget.vacancy);
    final schedule = _scheduleText(widget.vacancy);
    final start = _startText(widget.vacancy);
    final badges = _buildBadges(widget.vacancy);
    final channels = _extractChannels();
    final hasChannels = channels.hasAny;
    final autoMessage = 'Здравствуйте! Меня интересует вакансия $title.';

    Future<void> openChannel(
      Future<bool> Function(String contact, String message) opener,
      String contact,
    ) async {
      final ok = await opener(contact, autoMessage);
      if (!context.mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть канал связи')),
        );
      }
    }

    Widget messengerButton({
      required IconData icon,
      required String label,
      required Color backgroundColor,
      required Color foregroundColor,
      Color? borderColor,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: foregroundColor),
          label: Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            side: borderColor == null ? null : BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    final messengerButtons = <Widget>[
      if (channels.whatsapp.isNotEmpty)
        messengerButton(
          icon: FontAwesomeIcons.whatsapp,
          label: 'Написать в WhatsApp',
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          onTap: () => openChannel(_openWhatsapp, channels.whatsapp),
        ),
      if (channels.telegram.isNotEmpty)
        messengerButton(
          icon: FontAwesomeIcons.telegram,
          label: 'Написать в Telegram',
          backgroundColor: const Color(0xFFE9F5FE),
          foregroundColor: const Color(0xFF1D8DD8),
          borderColor: const Color(0xFFBFE5FB),
          onTap: () => openChannel(_openTelegram, channels.telegram),
        ),
      if (channels.viber.isNotEmpty)
        messengerButton(
          icon: FontAwesomeIcons.viber,
          label: 'Написать в Viber',
          backgroundColor: const Color(0xFFF1ECFF),
          foregroundColor: const Color(0xFF6D4AD9),
          borderColor: const Color(0xFFDCCEFF),
          onTap: () => openChannel(_openViber, channels.viber),
        ),
      if (channels.messenger.isNotEmpty)
        messengerButton(
          icon: FontAwesomeIcons.facebookMessenger,
          label: 'Написать в Messenger',
          backgroundColor: const Color(0xFFEAF0FF),
          foregroundColor: const Color(0xFF2B62F3),
          borderColor: const Color(0xFFC9D8FF),
          onTap: () => openChannel(_openMessenger, channels.messenger),
        ),
    ];

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * 0.94,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                14 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: WorkaColors.divider,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: WorkaColors.textDark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: WorkaColors.textGreyDark,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(
                            color: WorkaColors.textGreyDark,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          salary,
                          style: const TextStyle(
                            color: WorkaColors.salaryAccent,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: badges),
                  ],
                  if (schedule.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _MetaRow(
                      icon: Icons.schedule_rounded,
                      label: 'График работы',
                      value: schedule,
                    ),
                  ],
                  if (start.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _MetaRow(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Когда приступать',
                      value: start,
                    ),
                  ],
                  if (hasChannels) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Средства связи',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: WorkaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: [
                        for (int i = 0; i < messengerButtons.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          messengerButtons[i],
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        final sent = await widget.onSendCvTap();
                        if (!context.mounted) return;
                        if (sent) Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WorkaColors.orange,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Отправить CV',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: WorkaColors.textGreyDark),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    color: WorkaColors.textGreyDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactChannels {
  const _ContactChannels({
    required this.whatsapp,
    required this.telegram,
    required this.viber,
    required this.messenger,
  });

  final String whatsapp;
  final String telegram;
  final String viber;
  final String messenger;

  bool get hasAny =>
      whatsapp.isNotEmpty ||
      telegram.isNotEmpty ||
      viber.isNotEmpty ||
      messenger.isNotEmpty;
}
