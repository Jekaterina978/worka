import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/worka_colors.dart';
import '../../widgets/contact_fields.dart';
import '../../widgets/worka_header.dart';
import '../../services/firestore_paths.dart';
import '../search/widgets/search_filters_config.dart';

enum CvEditSection { contacts, main, desired, experience, languages, education }

class CvEditSectionScreen extends StatefulWidget {
  final String cvId;
  final CvEditSection section;

  /// ✅ если true — редактируем в cvs_test (без логина)
  final bool testMode;

  const CvEditSectionScreen({
    super.key,
    required this.cvId,
    required this.section,
    this.testMode = false,
  });

  @override
  State<CvEditSectionScreen> createState() => _CvEditSectionScreenState();
}

class _CvEditSectionScreenState extends State<CvEditSectionScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _saving = false;

  // contacts
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phoneNumber = TextEditingController();
  String _phoneCountryCode = '+372';

  // main
  final _title = TextEditingController();
  final _summary = TextEditingController();

  // desired (NEW)
  String _categoryGroup = '';
  final _position = TextEditingController(); // не обязательно
  String _locationLabel = '';
  final _citiesText = TextEditingController(); // не обязательно
  Set<String> _countries = {};
  String _employmentType = '';

  // lists
  final List<Map<String, dynamic>> _experience = [];
  final List<Map<String, dynamic>> _languages = [];
  final List<Map<String, dynamic>> _education = [];

  DocumentReference<Map<String, dynamic>> get _cvRef {
    return _db.collection(FirestorePaths.cvs).doc(widget.cvId);
  }

  Future<DocumentReference<Map<String, dynamic>>> _resolveCvRef() async {
    final primary = _cvRef;
    final primarySnap = await primary.get();
    if (primarySnap.exists) return primary;
    return _db.collection(FirestorePaths.cvs).doc(widget.cvId);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phoneNumber.dispose();
    _title.dispose();
    _summary.dispose();
    _position.dispose();
    _citiesText.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<Map<String, dynamic>> _loadPrivateContacts(String cvId) async {
    final id = cvId.trim();
    if (id.isEmpty) return <String, dynamic>{};
    try {
      final snap = await _db
          .collection('candidate_contacts_private')
          .doc(id)
          .get();
      final data = snap.data();
      if (data == null || data.isEmpty) return <String, dynamic>{};
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _load() async {
    final u = _auth.currentUser;

    final ref = await _resolveCvRef();
    final cvSnap = await ref.get();
    final cv = cvSnap.data() ?? {};
    final privateContacts = await _loadPrivateContacts(widget.cvId);

    final contacts = Map<String, dynamic>.from(cv['contacts'] ?? {});
    if (privateContacts.isNotEmpty) {
      final privateEmail = _s(privateContacts['email']);
      final privateCode = _s(privateContacts['phoneCountryCode']);
      final privateNumber = _s(privateContacts['phoneNumber']);
      final privatePhone = _s(privateContacts['phone']);
      if (privateEmail.isNotEmpty) contacts['email'] = privateEmail;
      if (privateCode.isNotEmpty) contacts['phoneCountryCode'] = privateCode;
      if (privateNumber.isNotEmpty) contacts['phoneNumber'] = privateNumber;
      if (privatePhone.isNotEmpty) contacts['phone'] = privatePhone;
    }
    final fullName = _s(contacts['name']);
    _firstName.text = _s(contacts['firstName']);
    _lastName.text = _s(contacts['lastName']);
    if ((_firstName.text + _lastName.text).trim().isEmpty &&
        fullName.isNotEmpty) {
      final parts = fullName
          .split(' ')
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        _firstName.text = parts.first;
        if (parts.length > 1) _lastName.text = parts.sublist(1).join(' ');
      }
    }
    _email.text = _s(contacts['email']);
    final storedCode = _s(contacts['phoneCountryCode']);
    final storedNum = ContactFieldsValidators.normalizeDigits(
      _s(contacts['phoneNumber']),
    );
    if (storedCode.isNotEmpty && storedNum.isNotEmpty) {
      _phoneCountryCode = storedCode;
      _phoneNumber.text = storedNum;
    } else {
      final parsed = ContactFieldsValidators.parseStoredPhone(
        _s(contacts['phone']).isNotEmpty
            ? _s(contacts['phone'])
            : _s(u?.phoneNumber),
      );
      _phoneCountryCode = parsed.countryCode;
      _phoneNumber.text = parsed.number;
    }

    // main
    _title.text = _s(cv['title']);
    _summary.text = _s(cv['summary']);

    // desired normalize (old/new)
    final desired = Map<String, dynamic>.from(cv['desired'] ?? {});
    final d = _normalizeDesired(desired);

    _categoryGroup = _s(d['categoryGroup'] ?? d['category']);
    _position.text = _s(d['position']);
    _locationLabel = _s(d['locationLabel']);
    _citiesText.text = _s(d['citiesText']);
    _employmentType = _s(d['employmentType']);

    final cs = d['countries'];
    if (cs is List) {
      _countries = cs
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toSet();
    } else {
      _countries = {};
    }

    _experience
      ..clear()
      ..addAll(
        (cv['experience'] as List<dynamic>? ?? []).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final startDate = _s(m['startDate']);
          final endDate = _s(m['endDate']);
          if (startDate.isEmpty &&
              m['startYear'] != null &&
              m['startMonth'] != null) {
            final y = int.tryParse('${m['startYear']}');
            final mo = int.tryParse('${m['startMonth']}');
            if (y != null && mo != null) {
              m['startDate'] =
                  '${y.toString().padLeft(4, '0')}-${mo.toString().padLeft(2, '0')}-01';
            }
          }
          if (endDate.isEmpty &&
              m['endYear'] != null &&
              m['endMonth'] != null) {
            final y = int.tryParse('${m['endYear']}');
            final mo = int.tryParse('${m['endMonth']}');
            if (y != null && mo != null) {
              m['endDate'] =
                  '${y.toString().padLeft(4, '0')}-${mo.toString().padLeft(2, '0')}-01';
            }
          }
          return m;
        }),
      );

    _languages
      ..clear()
      ..addAll(
        (cv['languages'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

    _education
      ..clear()
      ..addAll(
        (cv['education'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

    if (mounted) setState(() {});
  }

  Map<String, dynamic> _normalizeDesired(Map<String, dynamic> desiredRaw) {
    final d = Map<String, dynamic>.from(desiredRaw);

    List<String> asStringList(dynamic v) {
      if (v == null) return [];
      if (v is List) {
        return v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      final s = v.toString().trim();
      if (s.isEmpty) return [];
      return [s];
    }

    // new keys
    final cg = _s(d['categoryGroup']);
    final pos = _s(d['position']);
    final loc = _s(d['locationLabel']);
    final citiesText = _s(d['citiesText']);
    final cities = asStringList(d['cities']);
    final emp = _s(d['employmentType']);
    final countries = asStringList(d['countries']);

    // old keys
    final oldCategory = _s(d['category']);
    final oldPos = asStringList(d['positions'] ?? d['position']);
    final oldLoc = asStringList(d['locations'] ?? d['locationLabel']);
    final oldEmp = asStringList(d['employmentTypes'] ?? d['employmentType']);

    d['categoryGroup'] = cg.isNotEmpty ? cg : oldCategory;
    d['position'] = pos.isNotEmpty
        ? pos
        : (oldPos.isNotEmpty ? oldPos.first : '');
    d['locationLabel'] = loc.isNotEmpty
        ? loc
        : (oldLoc.isNotEmpty ? oldLoc.first : '');
    d['citiesText'] = citiesText.isNotEmpty ? citiesText : cities.join(', ');
    d['employmentType'] = emp.isNotEmpty
        ? emp
        : (oldEmp.isNotEmpty ? oldEmp.first : '');
    d['countries'] = countries;

    return d;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final ref = await _resolveCvRef();
      final now = FieldValue.serverTimestamp();
      final patch = <String, dynamic>{'updatedAt': now};

      switch (widget.section) {
        case CvEditSection.contacts:
          final phoneDigits = ContactFieldsValidators.normalizeDigits(
            _phoneNumber.text,
          );
          patch['contacts'] = {
            'name': '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim(),
            'firstName': _firstName.text.trim(),
            'lastName': _lastName.text.trim(),
            'email': _email.text.trim(),
            'phoneCountryCode': _phoneCountryCode,
            'phoneNumber': phoneDigits,
            'phone': '$_phoneCountryCode$phoneDigits',
          };
          break;

        case CvEditSection.main:
          patch['title'] = _title.text.trim();
          patch['summary'] = _summary.text.trim();
          break;

        case CvEditSection.desired:
          patch['desired'] = {
            'categoryGroup': _categoryGroup.trim(),
            'position': _position.text.trim(),
            'locationLabel': _locationLabel.trim(),
            'citiesText': _citiesText.text.trim(),
            'cities': _citiesText.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
            'countries': _countries.toList(),
            'employmentType': _employmentType.trim(),
          };
          break;

        case CvEditSection.experience:
          patch['experience'] = _experience
              .map(_normalizeExperienceRow)
              .where(_mapNotEmpty)
              .toList();
          break;

        case CvEditSection.languages:
          patch['languages'] = _languages.where(_mapNotEmpty).toList();
          break;

        case CvEditSection.education:
          patch['education'] = _education.where(_mapNotEmpty).toList();
          break;
      }

      await ref.set(patch, SetOptions(merge: true));
      _toast('Сохранено ✅');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _mapNotEmpty(Map<String, dynamic> m) {
    return m.entries.any(
      (e) => e.value != null && e.value.toString().trim().isNotEmpty,
    );
  }

  Map<String, dynamic> _normalizeExperienceRow(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    final start = DateTime.tryParse(_s(out['startDate']));
    final end = DateTime.tryParse(_s(out['endDate']));
    out['startMonth'] = start?.month;
    out['startYear'] = start?.year;
    out['endMonth'] = end?.month;
    out['endYear'] = end?.year;
    if ((out['isCurrent'] ?? false) == true) {
      out['endDate'] = '';
      out['endMonth'] = null;
      out['endYear'] = null;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) {
      CvEditSection.contacts => 'Контакты',
      CvEditSection.main => 'Заголовок и описание',
      CvEditSection.desired => 'Желаемая работа',
      CvEditSection.experience => 'Опыт работы',
      CvEditSection.languages => 'Языки',
      CvEditSection.education => 'Образование',
    };

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: title,
            leading: IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                children: [
                  ..._body(),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WorkaColors.orange,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body() {
    switch (widget.section) {
      case CvEditSection.contacts:
        return [
          Form(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ContactFields(
              firstNameController: _firstName,
              lastNameController: _lastName,
              emailController: _email,
              phoneNumberController: _phoneNumber,
              phoneCountryCode: _phoneCountryCode,
              onPhoneCountryCodeChanged: (v) =>
                  setState(() => _phoneCountryCode = v),
              onChanged: () => setState(() {}),
              enabled: !_saving,
            ),
          ),
        ];

      case CvEditSection.main:
        return [
          _field('Заголовок', _title),
          const SizedBox(height: 12),
          _multiline('Краткое описание', _summary),
        ];

      case CvEditSection.desired:
        return [
          _dropdownSingle(
            label: 'Категория',
            value: _categoryGroup.isEmpty ? null : _categoryGroup,
            items: SearchFiltersConfig.categoryNames, // ✅ группы
            onChanged: (v) => setState(() => _categoryGroup = v ?? ''),
          ),
          const SizedBox(height: 12),
          _field('Должность (не обязательно)', _position),
          const SizedBox(height: 12),
          _fieldSimple(
            label: 'Дополнительно',
            value: _citiesText.text,
            onChanged: (v) => setState(() {
              _citiesText.text = v;
              _locationLabel = v;
            }),
            hint: 'Город, место',
          ),
          const SizedBox(height: 12),
          _countriesEditor(),
          const SizedBox(height: 12),
          _dropdownSingle(
            label: 'Тип работы',
            value: _employmentType.isEmpty ? null : _employmentType,
            items: SearchFiltersConfig.employment,
            onChanged: (v) => setState(() => _employmentType = v ?? ''),
          ),
        ];

      case CvEditSection.experience:
        return _experienceEditor();

      case CvEditSection.languages:
        return _languagesEditor();

      case CvEditSection.education:
        return _listEditor(
          title: 'Учебное заведение',
          items: _education,
          emptyTemplate: {'school': '', 'speciality': '', 'country': ''},
          fields: const [
            _KvField('Учебное заведение', 'school'),
            _KvField('Специальность', 'speciality'),
            _KvField('Страна', 'country'),
          ],
        );
    }
  }

  Widget _countriesEditor() {
    final all = SearchFiltersConfig.countriesRu;
    return _block(
      title: 'Страны',
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WorkaColors.fieldBorder),
        ),
        child: Column(
          children: [
            for (int i = 0; i < all.length; i++) ...[
              _selectRow(
                label: all[i],
                selected: _countries.contains(all[i]),
                onTap: () {
                  final c = all[i];
                  setState(() {
                    if (_countries.contains(c)) {
                      _countries.remove(c);
                    } else {
                      _countries.add(c);
                    }
                  });
                },
              ),
              if (i != all.length - 1)
                const Divider(height: 1, color: WorkaColors.divider),
            ],
          ],
        ),
      ),
    );
  }

  // ===== List editor =====

  List<Widget> _experienceEditor() {
    if (_experience.isEmpty) {
      _experience.add({
        'position': '',
        'company': '',
        'country': '',
        'description': '',
        'startDate': '',
        'endDate': '',
        'isCurrent': false,
      });
    }
    return [
      for (int i = 0; i < _experience.length; i++) ...[
        _block(
          title: 'Место работы ${i + 1}',
          trailing: i == 0
              ? null
              : IconButton(
                  onPressed: () => setState(() => _experience.removeAt(i)),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: WorkaColors.textGreyDark,
                  ),
                ),
          child: Column(
            children: [
              _kvText(
                label: 'Должность',
                initial: (_experience[i]['position'] ?? '').toString(),
                onChanged: (v) => _experience[i]['position'] = v,
              ),
              const SizedBox(height: 10),
              _kvText(
                label: 'Название фирмы',
                initial: (_experience[i]['company'] ?? '').toString(),
                onChanged: (v) => _experience[i]['company'] = v,
              ),
              const SizedBox(height: 10),
              _dropdownSingle(
                label: 'Локация (страна)',
                value:
                    (_experience[i]['country'] ?? '').toString().trim().isEmpty
                    ? null
                    : (_experience[i]['country'] ?? '').toString().trim(),
                items: SearchFiltersConfig.countriesRu,
                onChanged: (v) =>
                    setState(() => _experience[i]['country'] = v ?? ''),
              ),
              const SizedBox(height: 10),
              _datePickerField(
                label: 'Дата начала',
                rawDate: (_experience[i]['startDate'] ?? '').toString(),
                onPicked: (v) =>
                    setState(() => _experience[i]['startDate'] = v),
              ),
              const SizedBox(height: 10),
              _toggleTile(
                title: 'По настоящее время',
                value: (_experience[i]['isCurrent'] ?? false) == true,
                onChanged: (v) => setState(() {
                  _experience[i]['isCurrent'] = v;
                  if (v) _experience[i]['endDate'] = '';
                }),
              ),
              if ((_experience[i]['isCurrent'] ?? false) != true) ...[
                const SizedBox(height: 10),
                _datePickerField(
                  label: 'Дата окончания',
                  rawDate: (_experience[i]['endDate'] ?? '').toString(),
                  onPicked: (v) =>
                      setState(() => _experience[i]['endDate'] = v),
                ),
              ],
              const SizedBox(height: 10),
              _kvText(
                label: 'Описание',
                initial: (_experience[i]['description'] ?? '').toString(),
                maxLines: 4,
                onChanged: (v) => _experience[i]['description'] = v,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => setState(() {
            _experience.add({
              'position': '',
              'company': '',
              'country': '',
              'description': '',
              'startDate': '',
              'endDate': '',
              'isCurrent': false,
            });
          }),
          icon: const Icon(Icons.add, color: WorkaColors.blue),
          label: const Text(
            'Добавить',
            style: TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: WorkaColors.fieldBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _listEditor({
    required String title,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> emptyTemplate,
    required List<_KvField> fields,
  }) {
    if (items.isEmpty) items.add(Map<String, dynamic>.from(emptyTemplate));

    return [
      for (int i = 0; i < items.length; i++) ...[
        _block(
          title: '$title ${i + 1}',
          trailing: i == 0
              ? null
              : IconButton(
                  onPressed: () => setState(() => items.removeAt(i)),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: WorkaColors.textGreyDark,
                  ),
                ),
          child: Column(
            children: [
              for (final f in fields) ...[
                _kvText(
                  label: f.label,
                  initial: (items[i][f.key] ?? '').toString(),
                  onChanged: (v) => items[i][f.key] = v,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => setState(
            () => items.add(Map<String, dynamic>.from(emptyTemplate)),
          ),
          icon: const Icon(Icons.add, color: WorkaColors.blue),
          label: const Text(
            'Добавить',
            style: TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: WorkaColors.fieldBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _languagesEditor() {
    if (_languages.isEmpty) {
      _languages.add(<String, dynamic>{'language': '', 'level': ''});
    }

    final languageOptions = <String>{
      ...SearchFiltersConfig.languages.map((e) => e.trim()),
      ..._languages
          .map((e) => (e['language'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty),
    }.toList()..sort();

    final levelOptions = <String>{
      'A1',
      'A2',
      'B1',
      'B2',
      'C1',
      'C2',
      'Родной',
      ..._languages
          .map((e) => (e['level'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty),
    }.toList();

    return [
      for (int i = 0; i < _languages.length; i++) ...[
        _block(
          title: 'Язык ${i + 1}',
          trailing: i == 0
              ? null
              : IconButton(
                  onPressed: () => setState(() => _languages.removeAt(i)),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: WorkaColors.textGreyDark,
                  ),
                ),
          child: Column(
            children: [
              _dropdownSingle(
                label: 'Язык',
                value:
                    (_languages[i]['language'] ?? '').toString().trim().isEmpty
                    ? null
                    : (_languages[i]['language'] ?? '').toString().trim(),
                items: languageOptions,
                onChanged: (v) =>
                    setState(() => _languages[i]['language'] = v ?? ''),
              ),
              const SizedBox(height: 10),
              _dropdownSingle(
                label: 'Уровень',
                value: (_languages[i]['level'] ?? '').toString().trim().isEmpty
                    ? null
                    : (_languages[i]['level'] ?? '').toString().trim(),
                items: levelOptions,
                onChanged: (v) =>
                    setState(() => _languages[i]['level'] = v ?? ''),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => setState(() {
            _languages.add(<String, dynamic>{'language': '', 'level': ''});
          }),
          icon: const Icon(Icons.add, color: WorkaColors.blue),
          label: const Text(
            'Добавить язык',
            style: TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: WorkaColors.fieldBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    ];
  }

  // ===== UI blocks =====

  Widget _block({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WorkaColors.divider),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 6),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: c,
          keyboardType: keyboard,
          decoration: _inputDeco(''),
        ),
      ],
    );
  }

  Widget _fieldSimple({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? hint,
  }) {
    final ctrl = TextEditingController(text: value);
    ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: ctrl.text.length),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          decoration: _inputDeco(hint ?? ''),
        ),
      ],
    );
  }

  Widget _multiline(String label, TextEditingController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(controller: c, maxLines: 6, decoration: _inputDeco('')),
      ],
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
      ),
    );
  }

  Widget _dropdownSingle({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final normalized = <String>{
      for (final e in items.map((e) => e.trim()).where((e) => e.isNotEmpty)) e,
    }.toList();
    final safeValue = (value != null && normalized.contains(value.trim()))
        ? value.trim()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: _inputDeco(''),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: safeValue,
              hint: const Text(
                'Выберите',
                style: TextStyle(color: WorkaColors.textGrey),
              ),
              items: normalized
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _selectRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? WorkaColors.hoverBlueSoft : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: WorkaColors.textGreyDark,
                ),
              ),
            ),
            if (selected) const Icon(Icons.check, color: WorkaColors.blue),
          ],
        ),
      ),
    );
  }

  Widget _kvText({
    required String label,
    required String initial,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: initial,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: _inputDeco(''),
        ),
      ],
    );
  }

  Widget _toggleTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: WorkaColors.textGreyDark,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _datePickerField({
    required String label,
    required String rawDate,
    required ValueChanged<String> onPicked,
  }) {
    final parsed = DateTime.tryParse(rawDate);
    String two(int v) => v.toString().padLeft(2, '0');
    final text = parsed == null
        ? 'Выберите дату'
        : '${two(parsed.day)}.${two(parsed.month)}.${parsed.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: WorkaColors.textGreyDark,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: parsed ?? now,
              firstDate: DateTime(1980, 1, 1),
              lastDate: DateTime(now.year + 1, 12, 31),
              builder: (ctx, child) {
                final base = Theme.of(ctx);
                return Theme(
                  data: base.copyWith(
                    colorScheme: base.colorScheme.copyWith(
                      primary: WorkaColors.blue,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: WorkaColors.textDark,
                    ),
                    dialogTheme: const DialogThemeData(
                      backgroundColor: Colors.white,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked == null) return;
            onPicked(
              '${picked.year.toString().padLeft(4, '0')}-${two(picked.month)}-${two(picked.day)}',
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: WorkaColors.fieldBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  color: WorkaColors.blue,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: parsed == null
                        ? WorkaColors.textGrey
                        : WorkaColors.textDark,
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

class _KvField {
  final String label;
  final String key;
  const _KvField(this.label, this.key);
}
