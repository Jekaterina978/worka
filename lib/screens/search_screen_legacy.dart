import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worka/core/events/app_events.dart';

import '../theme/worka_colors.dart';
import 'vacancy_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // ===== firestore/auth =====
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== controllers =====
  final _jobCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  final _jobFocus = FocusNode();
  late StreamSubscription<String> _paymentSub;

  // ===== ui sizes =====
  static const double fieldH = 56;
  static const double btnH = 56;
  static const double radius = 18;

  // ===== favorites =====
  static const _prefsKey = 'worka_favorites_job_ids';
  Set<String> _localFav = {};
  Set<String> _remoteFav = {};

  // ===== suggestions =====
  bool _showJobSuggest = false;

  // ===== filters state =====
  // location (multi) – countries
  final Set<String> _selectedCountries = {}; // по умолчанию пусто
  // category (multi) – professions
  final Set<String> _selectedCategories = {};
  // employment (multi)
  final Set<String> _selectedEmployment = {};
  // experience (single)
  String _experience = 'Все';
  // languages (multi)
  final Set<String> _selectedLanguages = {};
  // salary from
  int? _salaryFrom;

  // switches
  bool _housing = false;
  bool _transport = false;
  bool _teen = false;

  // ===== data lists (RU) =====

  // страны (Европа + Скандинавия + Украина + СНГ)
  static const List<String> countriesRu = [
    'Австрия','Бельгия','Болгария','Хорватия','Кипр','Чехия','Дания','Эстония','Финляндия','Франция',
    'Германия','Греция','Венгрия','Ирландия','Италия','Латвия','Литва','Люксембург','Мальта','Нидерланды',
    'Польша','Португалия','Румыния','Словакия','Словения','Испания','Швеция',
    'Норвегия','Исландия',
    'Украина',
    'Армения','Азербайджан','Беларусь','Грузия','Казахстан','Кыргызстан','Молдова','Россия','Таджикистан',
    'Туркменистан','Узбекистан',
  ];

  // города для подсказок (город, страна) – по-русски
  static const List<Map<String, String>> cityHints = [
    {'city': 'Таллинн', 'country': 'Эстония'},
    {'city': 'Тарту', 'country': 'Эстония'},
    {'city': 'Пярну', 'country': 'Эстония'},
    {'city': 'Рига', 'country': 'Латвия'},
    {'city': 'Вильнюс', 'country': 'Литва'},
    {'city': 'Хельсинки', 'country': 'Финляндия'},
    {'city': 'Стокгольм', 'country': 'Швеция'},
    {'city': 'Осло', 'country': 'Норвегия'},
    {'city': 'Копенгаген', 'country': 'Дания'},
    {'city': 'Берлин', 'country': 'Германия'},
    {'city': 'Мюнхен', 'country': 'Германия'},
    {'city': 'Варшава', 'country': 'Польша'},
    {'city': 'Прага', 'country': 'Чехия'},
    {'city': 'Париж', 'country': 'Франция'},
    {'city': 'Мадрид', 'country': 'Испания'},
    {'city': 'Барселона', 'country': 'Испания'},
    {'city': 'Киев', 'country': 'Украина'},
    {'city': 'Львов', 'country': 'Украина'},
    {'city': 'Минск', 'country': 'Беларусь'},
    {'city': 'Алматы', 'country': 'Казахстан'},
    {'city': 'Астана', 'country': 'Казахстан'},
    {'city': 'Тбилиси', 'country': 'Грузия'},
  ];

  static const List<String> professionHints = [
    'Менеджер','Офис-менеджер','Администратор','Руководитель проекта','Ассистент','Секретарь',
    'Продавец','Кассир','Менеджер по продажам','Консультант','Оператор call-центра','Аккаунт-менеджер',
    'Программист / Разработчик','Тестировщик (QA)','Системный администратор','Аналитик данных','Веб-дизайнер','DevOps инженер',
    'Бухгалтер','Экономист','Финансовый аналитик','HR-специалист','Рекрутер',
    'Водитель','Курьер','Кладовщик','Логист','Оператор производства','Сборщик',
    'Электрик','Сантехник','Сварщик','Маляр','Строитель','Техник',
    'Официант','Бармен','Повар','Горничная','Уборщик','Парикмахер',
    'Врач','Медсестра','Фармацевт','Сиделка',
    'Учитель','Воспитатель','Переводчик','Социальный работник',
  ];

  static const List<String> employmentTypes = ['Полная','Частичная','Вахта','Проектная'];
  static const List<String> experiences = ['Все','Без опыта','1–2 года','3+ года'];
  static const List<String> languages = [
    'Не требуется',
    'Русский','English','Deutsch','Français','Español','Italiano','Polski','Suomi','Svenska','Norsk',
  ];

  static const Map<String, List<String>> categoryGroups = {
    'Офис и управление': ['Менеджер','Офис-менеджер','Администратор','Руководитель проекта','Ассистент','Секретарь'],
    'Продажи и работа с клиентами': ['Продавец','Кассир','Менеджер по продажам','Консультант','Оператор call-центра','Аккаунт-менеджер'],
    'IT и технологии': ['Программист / Разработчик','Тестировщик (QA)','Системный администратор','Аналитик данных','Веб-дизайнер','DevOps инженер'],
    'Финансы и офисные специалисты': ['Бухгалтер','Экономист','Финансовый аналитик','HR-специалист','Рекрутер'],
    'Логистика и производство': ['Водитель','Курьер','Кладовщик','Логист','Оператор производства','Сборщик'],
    'Строительство и рабочие специальности': ['Электрик','Сантехник','Сварщик','Маляр','Строитель','Техник'],
    'Сфера обслуживания': ['Официант','Бармен','Повар','Горничная','Уборщик','Парикмахер'],
    'Медицина и уход': ['Врач','Медсестра','Фармацевт','Сиделка'],
    'Образование и социальная сфера': ['Учитель','Воспитатель','Переводчик','Социальный работник'],
  };

  bool get _supportsHover {
    final p = defaultTargetPlatform;
    return kIsWeb || p == TargetPlatform.macOS || p == TargetPlatform.windows || p == TargetPlatform.linux;
    // на мобиле hover не нужен
  }

  @override
  void initState() {
    super.initState();
    _loadLocalFav();

    _jobFocus.addListener(() {
      if (!_jobFocus.hasFocus) setState(() => _showJobSuggest = false);
    });
    _jobCtrl.addListener(() {
      final t = _jobCtrl.text.trim();
      setState(() => _showJobSuggest = t.isNotEmpty && _jobFocus.hasFocus);
    });

    _paymentSub = AppEvents.onPaymentCompleted.listen((jobCode) {
      print('REFRESH TRIGGERED FOR: $jobCode');
      // TODO: replace with actual reload method if different
      _reloadJobs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вакансия успешно продвинута 🚀'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _paymentSub.cancel();
    _jobCtrl.dispose();
    _locationCtrl.dispose();
    _jobFocus.dispose();
    super.dispose();
  }

  Future<void> _loadLocalFav() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() => _localFav = list.toSet());
  }

  Future<void> _saveLocalFav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _localFav.toList());
  }

  void _reloadJobs() {
    // Trigger rebuild so entitlements and data are fetched fresh.
    setState(() {});
  }

  bool _isFav(String id) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return _localFav.contains(id);
    return _localFav.contains(id) || _remoteFav.contains(id);
  }

  Future<void> _toggleFav(String id, Map<String, dynamic> jobData) async {
    final uid = _auth.currentUser?.uid;

    setState(() {
      if (_localFav.contains(id)) {
        _localFav.remove(id);
      } else {
        _localFav.add(id);
      }
    });
    await _saveLocalFav();

    if (uid != null) {
      final ref = _db.collection('users').doc(uid).collection('favorites').doc(id);
      final nowFav = _localFav.contains(id) || _remoteFav.contains(id);

      if (nowFav) {
        await ref.set({
          'jobId': id,
          'title': jobData['title'],
          'company': jobData['company'],
          'city': jobData['city'],
          'country': jobData['country'],
          'salaryText': jobData['salaryText'] ?? jobData['salary'],
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await ref.delete();
      }
    }
  }

  // ===== streams =====
  Stream<QuerySnapshot<Map<String, dynamic>>> _jobsStream() {
    return _db.collection('jobs').orderBy('createdAt', descending: true).limit(200).snapshots();
  }

  // ===== helpers =====
  List<String> _filterJobHints(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final out = <String>[];
    for (final p in professionHints) {
      // подсказки с первой буквы
      if (p.toLowerCase().startsWith(s)) out.add(p);
      if (out.length >= 8) break;
    }
    return out;
  }

  List<String> _filterCityHints(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final out = <String>[];
    for (final m in cityHints) {
      final label = '${m['city']}, ${m['country']}';
      if (label.toLowerCase().startsWith(s)) out.add(label);
      if (out.length >= 10) break;
    }
    return out;
  }

  String _countriesLabel(Set<String> countries) {
    if (countries.isEmpty) return 'Локация';
    if (countries.length <= 2) return countries.join(', ');
    return 'Выбрано: ${countries.length}';
  }

  // ===== UI: dialogs =====
  Future<T?> _showTopSheet<T>({required Widget child}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: child,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, w) {
        final offset = Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero).animate(anim);
        return SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: w));
      },
    );
  }

  Future<void> _openLocationPicker() async {
    final res = await _showTopSheet<_LocationPickResult>(
      child: _LocationSheet(
        initialCountries: _selectedCountries,
        supportsHover: _supportsHover,
      ),
    );
    if (res == null) return;

    setState(() {
      _selectedCountries
        ..clear()
        ..addAll(res.countries);

      if (res.pickedCityLabel != null) {
        _locationCtrl.text = res.pickedCityLabel!;
      } else {
        // если выбраны страны — показываем их в поле (как label),
        // а не держим пусто
        _locationCtrl.text = '';
      }
    });
  }

  Future<void> _openFilters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final res = await showModalBottomSheet<_FiltersResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => _FiltersSheet(
        salaryFrom: _salaryFrom,
        selectedEmployment: _selectedEmployment,
        experience: _experience,
        selectedLanguages: _selectedLanguages,
        selectedCategories: _selectedCategories,
        housing: _housing,
        transport: _transport,
        teen: _teen,
        supportsHover: _supportsHover,
      ),
    );

    if (res == null) return;

    setState(() {
      _salaryFrom = res.salaryFrom;
      _experience = res.experience;

      _selectedEmployment
        ..clear()
        ..addAll(res.employment);

      _selectedLanguages
        ..clear()
        ..addAll(res.languages);

      _selectedCategories
        ..clear()
        ..addAll(res.categories);

      _housing = res.housing;
      _transport = res.transport;
      _teen = res.teen;
    });
  }

  // ===== filtering jobs client-side =====
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    String s(dynamic v) => (v ?? '').toString().trim();
    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    final jobQuery = _jobCtrl.text.trim().toLowerCase();
    final locText = _locationCtrl.text.trim().toLowerCase();

    bool matchJob(Map<String, dynamic> m) {
      if (jobQuery.isEmpty) return true;
      final title = s(m['title']).toLowerCase();
      final category = s(m['category']).toLowerCase();
      final profession = s(m['profession']).toLowerCase();
      final desc = s(m['description']).toLowerCase();
      return title.contains(jobQuery) ||
          category.contains(jobQuery) ||
          profession.contains(jobQuery) ||
          desc.contains(jobQuery);
    }

    bool matchLocation(Map<String, dynamic> m) {
      // если в поле введён город/страна
      if (locText.isNotEmpty) {
        final city = s(m['city']).toLowerCase();
        final country = s(m['country']).toLowerCase();
        final label = '$city, $country';
        return city.contains(locText) || country.contains(locText) || label.contains(locText);
      }

      // иначе — по выбранным странам
      if (_selectedCountries.isEmpty) return true;
      final c = s(m['country']);
      if (c.isEmpty) return true;
      return _selectedCountries.contains(c);
    }

    bool matchSalary(Map<String, dynamic> m) {
      if (_salaryFrom == null) return true;
      final from = toInt(m['salaryFromNum']);
      final to = toInt(m['salaryToNum']);
      final maxSalary = to ?? from;
      if (maxSalary == null) return true;
      return maxSalary >= _salaryFrom!;
    }

    bool matchEmployment(Map<String, dynamic> m) {
      if (_selectedEmployment.isEmpty) return true;
      final v = s(m['employmentType']);
      if (v.isEmpty) return true;
      return _selectedEmployment.contains(v);
    }

    bool matchExperience(Map<String, dynamic> m) {
      if (_experience == 'Все') return true;
      final v = s(m['experience']);
      if (v.isEmpty) return true;
      return v == _experience;
    }

    bool matchLanguages(Map<String, dynamic> m) {
      if (_selectedLanguages.isEmpty) return true;
      final v = s(m['language']);
      if (_selectedLanguages.contains('Не требуется')) {
        if (v.isEmpty) return true;
      }
      if (v.isEmpty) return false;
      return _selectedLanguages.contains(v);
    }

    bool matchCategory(Map<String, dynamic> m) {
      if (_selectedCategories.isEmpty) return true;
      final v = s(m['category']);
      if (v.isEmpty) return false;
      return _selectedCategories.contains(v);
    }

    bool matchSwitches(Map<String, dynamic> m) {
      if (_housing && m['housingProvided'] != true) return false;
      if (_transport && m['transportProvided'] != true) return false;
      if (_teen && m['teenFriendly'] != true) return false;
      return true;
    }

    final list = docs.where((d) {
      final m = d.data();
      return matchJob(m) &&
          matchLocation(m) &&
          matchCategory(m) &&
          matchSalary(m) &&
          matchEmployment(m) &&
          matchExperience(m) &&
          matchLanguages(m) &&
          matchSwitches(m);
    }).toList();

    list.sort((a, b) {
      final aEnt = a.data()['entitlements'];
      final bEnt = b.data()['entitlements'];

      final aBump = (aEnt is Map && aEnt['bump'] == true) ? 1 : 0;
      final bBump = (bEnt is Map && bEnt['bump'] == true) ? 1 : 0;
      if (aBump != bBump) return bBump.compareTo(aBump); // bump выше

      final au = (a.data()['isUrgent'] == true) ? 1 : 0;
      final bu = (b.data()['isUrgent'] == true) ? 1 : 0;
      return bu.compareTo(au);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;

    final locationPlaceholder = _countriesLabel(_selectedCountries);

    return Scaffold(
      backgroundColor: WorkaColors.bg,
      appBar: AppBar(
        leading: const SizedBox.shrink(),
        centerTitle: true,
        title: SizedBox(height: 28, child: Image.asset('assets/logo.png', fit: BoxFit.contain)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              children: [
                // 1) Поиск по профессии
                _Field(
                  height: fieldH,
                  controller: _jobCtrl,
                  focusNode: _jobFocus,
                  hint: 'Поиск по профессии',
                  prefix: const Icon(Icons.search),
                  onTap: () {
                    final t = _jobCtrl.text.trim();
                    setState(() => _showJobSuggest = t.isNotEmpty);
                  },
                ),

                if (_showJobSuggest) ...[
                  const SizedBox(height: 8),
                  _SuggestBox(
                    items: _filterJobHints(_jobCtrl.text),
                    supportsHover: _supportsHover,
                    onPick: (v) {
                      _jobCtrl.text = v;
                      _jobCtrl.selection = TextSelection.collapsed(offset: v.length);
                      setState(() => _showJobSuggest = false);
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ],

                const SizedBox(height: 12),

                // 2) Локация (ввод) + кнопка Найти
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: fieldH,
                        child: TextField(
                          controller: _locationCtrl,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: WorkaColors.textDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: locationPlaceholder,
                            hintStyle: const TextStyle(color: WorkaColors.textGrey, fontWeight: FontWeight.w800),
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            suffixIcon: IconButton(
                              tooltip: 'Выбрать страны',
                              onPressed: _openLocationPicker,
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(radius),
                              borderSide: const BorderSide(color: WorkaColors.fieldBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(radius),
                              borderSide: const BorderSide(color: WorkaColors.blue, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: btnH,
                      width: 120,
                      child: ElevatedButton(
                        onPressed: () => setState(() {}),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.blue,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        child: const Text(
                          'Найти',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),

                // подсказки городов
                if (_locationCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SuggestBox(
                    items: _filterCityHints(_locationCtrl.text),
                    supportsHover: _supportsHover,
                    onPick: (v) {
                      _locationCtrl.text = v;
                      _locationCtrl.selection = TextSelection.collapsed(offset: v.length);
                      setState(() {});
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ],

                const SizedBox(height: 12),

                // 3) Фильтры (оранжевая)
                SizedBox(
                  height: btnH,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _openFilters,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WorkaColors.orange,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    ),
                    child: const Text(
                      'Фильтры',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
const SizedBox(height: 10),


const SizedBox(height: 6),

          // список вакансий
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _jobsStream(),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Ошибка: ${snap.error}'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snap.data!.docs;
                final filtered = _applyFilters(docs);

                if (uid == null) {
                  return _JobsList(
                    docs: filtered,
                    isFav: _isFav,
                    onToggleFav: _toggleFav,
                  );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _db.collection('users').doc(uid).collection('favorites').snapshots(),
                  builder: (context, fs) {
                    _remoteFav = {};
                    if (fs.hasData) {
                      for (final d in fs.data!.docs) {
                        _remoteFav.add(d.id);
                      }
                    }
                    return _JobsList(
                      docs: filtered,
                      isFav: _isFav,
                      onToggleFav: _toggleFav,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ================= UI parts =================

class _Field extends StatelessWidget {
  final double height;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final Widget? prefix;
  final VoidCallback? onTap;

  const _Field({
    required this.height,
    required this.controller,
    required this.hint,
    this.focusNode,
    this.prefix,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onTap: onTap,
        style: const TextStyle(color: WorkaColors.textDark, fontWeight: FontWeight.w800, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: WorkaColors.textGrey, fontWeight: FontWeight.w800),
          prefixIcon: prefix,
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_SearchScreenState.radius),
            borderSide: const BorderSide(color: WorkaColors.fieldBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_SearchScreenState.radius),
            borderSide: const BorderSide(color: WorkaColors.blue, width: 2),
          ),
        ),
      ),
    );
  }
}

class _SuggestBox extends StatelessWidget {
  final List<String> items;
  final ValueChanged<String> onPick;
  final bool supportsHover;

  const _SuggestBox({
    required this.items,
    required this.onPick,
    required this.supportsHover,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.divider),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 6),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: WorkaColors.divider),
        itemBuilder: (context, i) {
          final v = items[i];
          return _HoverRow(
            label: v,
            supportsHover: supportsHover,
            onTap: () => onPick(v),
          );
        },
      ),
    );
  }
}

class _HoverRow extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool supportsHover;

  const _HoverRow({
    required this.label,
    required this.onTap,
    required this.supportsHover,
  });

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover ? WorkaColors.hoverBlue : Colors.white;

    final child = InkWell(
      onTap: widget.onTap,
      hoverColor: WorkaColors.hoverBlue,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Text(
          widget.label,
          style: TextStyle(
            color: WorkaColors.textGreyDark, // серый
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );

    if (!widget.supportsHover) return child;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: child,
    );
  }
}

// ================= JOB LIST =================

class _JobsList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool Function(String id) isFav;
  final Future<void> Function(String id, Map<String, dynamic> data) onToggleFav;

  const _JobsList({
    required this.docs,
    required this.isFav,
    required this.onToggleFav,
  });

  @override
  Widget build(BuildContext context) {
    String s(dynamic v, {String fallback = ''}) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty ? fallback : t;
    }

    if (docs.isEmpty) {
      return const Center(child: Text('Ничего не найдено'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final d = docs[i];
        final m = d.data();

        final title = s(m['title'], fallback: 'Вакансия');
        final city = s(m['city'], fallback: 'Локация не указана');
        final country = s(m['country'], fallback: '');
        final location = country.isEmpty ? city : '$city, $country';

        final salary = s(m['salaryText'] ?? m['salary'], fallback: 'Зарплата не указана');
        final fav = isFav(d.id);

        return _JobCard(
          title: title,
          location: location,
          salary: salary,
          isFav: fav,
          onFavTap: () => onToggleFav(d.id, m),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => VacancyDetailsScreen(jobId: d.id)),
            );
          },
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  final String title;
  final String location;
  final String salary;
  final bool isFav;
  final VoidCallback onFavTap;
  final VoidCallback onTap;

  const _JobCard({
    required this.title,
    required this.location,
    required this.salary,
    required this.isFav,
    required this.onFavTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
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
        child: Stack(
          children: [
            Positioned(
              right: 6,
              top: 4,
              child: IconButton(
                onPressed: onFavTap,
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFav ? WorkaColors.starYellow : Colors.grey.shade600,
                ),
                tooltip: 'В избранное',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: WorkaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: WorkaColors.textGrey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.payments_outlined, size: 16, color: WorkaColors.textGrey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          salary,
                          style: const TextStyle(color: WorkaColors.textGreyDark, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= LOCATION SHEET =================

class _LocationPickResult {
  final Set<String> countries;
  final String? pickedCityLabel;

  const _LocationPickResult({required this.countries, this.pickedCityLabel});
}

class _LocationSheet extends StatefulWidget {
  final Set<String> initialCountries;
  final bool supportsHover;

  const _LocationSheet({
    required this.initialCountries,
    required this.supportsHover,
  });

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  final _q = TextEditingController();
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialCountries);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<String> _cityResults(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final out = <String>[];
    for (final m in _SearchScreenState.cityHints) {
      final label = '${m['city']}, ${m['country']}';
      if (label.toLowerCase().contains(s)) out.add(label);
      if (out.length >= 12) break;
    }
    return out;
  }

  List<String> _countryResults(String q) {
    final s = q.trim().toLowerCase();
    final list = _SearchScreenState.countriesRu;
    if (s.isEmpty) return list;
    return list.where((e) => e.toLowerCase().contains(s)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text;
    final cities = _cityResults(q);
    final countries = _countryResults(q);

    final maxH = MediaQuery.of(context).size.height * 0.75;

    return Material(
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: SizedBox(
        height: maxH,
        child: Column(
          children: [
            // HEADER
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Локация',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: WorkaColors.textDark,
                  ),
                ),
              ),
            ),

            // SEARCH
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                height: 50,
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: WorkaColors.textDark,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Введите город или страну',
                    hintStyle: const TextStyle(
                      color: WorkaColors.textGrey,
                      fontWeight: FontWeight.w800,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: WorkaColors.fieldBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: WorkaColors.blue, width: 2),
                    ),
                  ),
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (cities.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Text(
                        'Города',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: WorkaColors.textGreyDark,
                        ),
                      ),
                    ),
                    for (final c in cities)
                      _HoverRow(
                        label: c,
                        supportsHover: widget.supportsHover,
                        onTap: () {
                          Navigator.pop(
                            context,
                            _LocationPickResult(
                              countries: _selected,
                              pickedCityLabel: c,
                            ),
                          );
                        },
                      ),
                    const Divider(color: WorkaColors.divider),
                  ],

                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text(
                      'Страны',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: WorkaColors.textGreyDark,
                      ),
                    ),
                  ),

                  for (final c in countries)
                    _LocationCheckRow(
                      label: c,
                      checked: _selected.contains(c),
                      supportsHover: widget.supportsHover,
                      onToggle: () {
                        setState(() {
                          if (_selected.contains(c)) {
                            _selected.remove(c);
                          } else {
                            _selected.add(c);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),

            // BUTTONS (как ты просила)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _selected.clear();
                            _q.clear();
                          });
                        },
                        child: const Text(
                          'Очистить',
                          style: TextStyle(
                            color: WorkaColors.textGreyDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            _LocationPickResult(countries: _selected),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.orange,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationCheckRow extends StatefulWidget {
  final String label;
  final bool checked;
  final VoidCallback onToggle;
  final bool supportsHover;

  const _LocationCheckRow({
    required this.label,
    required this.checked,
    required this.onToggle,
    required this.supportsHover,
  });

  @override
  State<_LocationCheckRow> createState() => _LocationCheckRowState();
}

class _LocationCheckRowState extends State<_LocationCheckRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover ? WorkaColors.hoverBlue : Colors.white;

    final child = InkWell(
      onTap: widget.onToggle,
      hoverColor: WorkaColors.hoverBlue,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Checkbox(
              value: widget.checked,
              activeColor: WorkaColors.blue,
              onChanged: (_) => widget.onToggle(),
            ),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontWeight: widget.checked ? FontWeight.w900 : FontWeight.w800,
                  color: widget.checked ? WorkaColors.textDark : WorkaColors.textGreyDark, // выбранное черным
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.supportsHover) return child;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: child,
    );
  }
}

// ================= FILTERS SHEET =================

class _FiltersResult {
  final int? salaryFrom;
  final Set<String> categories;
  final Set<String> employment;
  final String experience;
  final Set<String> languages;
  final bool housing;
  final bool transport;
  final bool teen;

  const _FiltersResult({
    required this.salaryFrom,
    required this.categories,
    required this.employment,
    required this.experience,
    required this.languages,
    required this.housing,
    required this.transport,
    required this.teen,
  });
}

class _FiltersSheet extends StatefulWidget {
  final int? salaryFrom;
  final Set<String> selectedCategories;
  final Set<String> selectedEmployment;
  final String experience;
  final Set<String> selectedLanguages;
  final bool housing;
  final bool transport;
  final bool teen;
  final bool supportsHover;

  const _FiltersSheet({
    required this.salaryFrom,
    required this.selectedCategories,
    required this.selectedEmployment,
    required this.experience,
    required this.selectedLanguages,
    required this.housing,
    required this.transport,
    required this.teen,
    required this.supportsHover,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late final TextEditingController _salary;

  final Set<String> _cats = {};
  final Set<String> _empl = {};
  String _exp = 'Все';
  final Set<String> _langs = {};

  bool _housing = false;
  bool _transport = false;
  bool _teen = false;

  @override
  void initState() {
    super.initState();
    _salary = TextEditingController(text: widget.salaryFrom?.toString() ?? '');
    _cats.addAll(widget.selectedCategories);
    _empl.addAll(widget.selectedEmployment);
    _exp = widget.experience;
    _langs.addAll(widget.selectedLanguages);
    _housing = widget.housing;
    _transport = widget.transport;
    _teen = widget.teen;
  }

  @override
  void dispose() {
    _salary.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _salary.clear();
      _cats.clear();
      _empl.clear();
      _exp = 'Все';
      _langs.clear();
      _housing = false;
      _transport = false;
      _teen = false;
    });
  }

  void _done() {
    Navigator.pop(
      context,
      _FiltersResult(
        salaryFrom: int.tryParse(_salary.text.trim()),
        categories: _cats,
        employment: _empl,
        experience: _exp,
        languages: _langs,
        housing: _housing,
        transport: _transport,
        teen: _teen,
      ),
    );
  }

  Future<void> _openMultiList({
    required String title,
    required List<String> items,
    required Set<String> selected,
    Map<String, List<String>>? grouped,
  }) async {
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => _MultiSelectSheet(
        title: title,
        items: items,
        selected: selected,
        grouped: grouped,
        supportsHover: widget.supportsHover,
      ),
    );

    if (res == null) return;
    setState(() {
      selected
        ..clear()
        ..addAll(res);
    });
  }

  Future<void> _openSingleList({
    required String title,
    required List<String> items,
    required String current,
    required ValueChanged<String> onPick,
  }) async {
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => _SingleSelectSheet(
        title: title,
        items: items,
        current: current,
        supportsHover: widget.supportsHover,
      ),
    );
    if (res == null) return;
    onPick(res);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.78,
          child: Column(
            children: [
              const SizedBox(height: 6),
              const Text('Фильтры', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _DropRow(
                      label: 'Категория',
                      value: _cats.isEmpty ? 'Все' : 'Выбрано: ${_cats.length}',
                      onTap: () => _openMultiList(
                        title: 'Категория',
                        items: const [],
                        selected: _cats,
                        grouped: _SearchScreenState.categoryGroups,
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text('Зарплата от', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 56,
                      child: TextField(
                        controller: _salary,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textDark),
                        decoration: InputDecoration(
                          hintText: 'Например 70',
                          hintStyle: const TextStyle(color: WorkaColors.textGrey, fontWeight: FontWeight.w800),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: WorkaColors.fieldBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: WorkaColors.blue, width: 2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    _DropRow(
                      label: 'Тип занятости',
                      value: _empl.isEmpty ? 'Все' : 'Выбрано: ${_empl.length}',
                      onTap: () => _openMultiList(
                        title: 'Тип занятости',
                        items: _SearchScreenState.employmentTypes,
                        selected: _empl,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _DropRow(
                      label: 'Опыт',
                      value: _exp,
                      onTap: () => _openSingleList(
                        title: 'Опыт',
                        items: _SearchScreenState.experiences,
                        current: _exp,
                        onPick: (v) => setState(() => _exp = v),
                      ),
                    ),
                    const SizedBox(height: 12),

                    _DropRow(
                      label: 'Язык',
                      value: _langs.isEmpty ? 'Все' : 'Выбрано: ${_langs.length}',
                      onTap: () => _openMultiList(
                        title: 'Язык',
                        items: _SearchScreenState.languages,
                        selected: _langs,
                      ),
                    ),

                    const SizedBox(height: 14),
                    const Divider(color: WorkaColors.divider),

                    SwitchListTile(
                      value: _housing,
                      onChanged: (v) => setState(() => _housing = v),
                      title: const Text(
                        'Жильё',
                        style: TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
                      ),
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: WorkaColors.orange,
                      inactiveTrackColor: Color(0xFFE0E0E0),
                    ),
                    SwitchListTile(
                      value: _transport,
                      onChanged: (v) => setState(() => _transport = v),
                      title: const Text(
                        'Развозка',
                        style: TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
                      ),
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: WorkaColors.orange,
                      inactiveTrackColor: Color(0xFFE0E0E0),
                    ),
                    SwitchListTile(
                      value: _teen,
                      onChanged: (v) => setState(() => _teen = v),
                      title: const Text(
                        'Подходит подросткам',
                        style: TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
                      ),
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: WorkaColors.orange,
                      inactiveTrackColor: Color(0xFFE0E0E0),
                    ),
                  ],
                ),
              ),

              // bottom actions (как в локации)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextButton(
                          onPressed: _clear,
                          child: const Text(
                            'Очистить',
                            style: TextStyle(
                              color: WorkaColors.textGreyDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _done,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkaColors.orange,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text(
                            'Готово',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DropRow({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAll = value == 'Все';
    final valueColor = isAll ? WorkaColors.textGrey : WorkaColors.textDark;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WorkaColors.fieldBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: const TextStyle(color: WorkaColors.textGreyDark),
                    ),
                    TextSpan(
                      text: value,
                      style: TextStyle(color: valueColor, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: WorkaColors.textGreyDark),
          ],
        ),
      ),
    );
  }
}

class _SingleSelectSheet extends StatelessWidget {
  final String title;
  final List<String> items;
  final String current;
  final bool supportsHover;

  const _SingleSelectSheet({
    required this.title,
    required this.items,
    required this.current,
    required this.supportsHover,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: WorkaColors.divider),
                itemBuilder: (context, i) {
                  final v = items[i];
                  final selected = v == current;
                  return _HoverPickRow(
                    label: v,
                    selected: selected,
                    supportsHover: supportsHover,
                    onTap: () => Navigator.pop(context, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final Set<String> selected;
  final Map<String, List<String>>? grouped;
  final bool supportsHover;

  const _MultiSelectSheet({
    required this.title,
    required this.items,
    required this.selected,
    this.grouped,
    required this.supportsHover,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<String> _sel;

  @override
  void initState() {
    super.initState();
    _sel = {...widget.selected};
  }

  void _toggle(String v) {
    setState(() {
      if (_sel.contains(v)) {
        _sel.remove(v);
      } else {
        _sel.add(v);
      }
    });
  }

  void _toggleGroup(List<String> items) {
    final allSelected = items.isNotEmpty && items.every(_sel.contains);
    setState(() {
      if (allSelected) {
        for (final it in items) {
          _sel.remove(it);
        }
      } else {
        for (final it in items) {
          _sel.add(it);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final grouped = widget.grouped;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (grouped != null) ...[
                    for (final entry in grouped.entries) ...[
                      const SizedBox(height: 10),
                      Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 6),

                      _GroupCheckRow(
                        label: 'Выбрать всё в группе',
                        checked: entry.value.isNotEmpty && entry.value.every(_sel.contains),
                        supportsHover: widget.supportsHover,
                        onToggle: () => _toggleGroup(entry.value),
                      ),

                      const SizedBox(height: 6),
                      for (final it in entry.value)
                        _CheckRow(
                          label: it,
                          checked: _sel.contains(it),
                          supportsHover: widget.supportsHover,
                          onToggle: () => _toggle(it),
                        ),
                      const Divider(color: WorkaColors.divider),
                    ],
                  ] else ...[
                    for (final it in widget.items)
                      _CheckRow(
                        label: it,
                        checked: _sel.contains(it),
                        supportsHover: widget.supportsHover,
                        onToggle: () => _toggle(it),
                      ),
                  ],
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextButton(
                        onPressed: () => setState(_sel.clear),
                        child: const Text(
                          'Очистить',
                          style: TextStyle(
                            color: WorkaColors.textGreyDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, _sel),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.orange,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Готово', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCheckRow extends StatefulWidget {
  final String label;
  final bool checked;
  final VoidCallback onToggle;
  final bool supportsHover;

  const _GroupCheckRow({
    required this.label,
    required this.checked,
    required this.onToggle,
    required this.supportsHover,
  });

  @override
  State<_GroupCheckRow> createState() => _GroupCheckRowState();
}

class _GroupCheckRowState extends State<_GroupCheckRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover ? WorkaColors.hoverBlue : Colors.white;

    final content = InkWell(
      onTap: widget.onToggle,
      hoverColor: WorkaColors.hoverBlue,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Checkbox(value: widget.checked, activeColor: WorkaColors.blue, onChanged: (_) => widget.onToggle()),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: widget.checked ? WorkaColors.textDark : WorkaColors.textGreyDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.supportsHover) return content;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: content,
    );
  }
}

class _CheckRow extends StatefulWidget {
  final String label;
  final bool checked;
  final VoidCallback onToggle;
  final bool supportsHover;

  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onToggle,
    required this.supportsHover,
  });

  @override
  State<_CheckRow> createState() => _CheckRowState();
}

class _CheckRowState extends State<_CheckRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover ? WorkaColors.hoverBlue : Colors.white;

    final child = InkWell(
      onTap: widget.onToggle,
      hoverColor: WorkaColors.hoverBlue,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Checkbox(
              value: widget.checked,
              activeColor: WorkaColors.blue,
              onChanged: (_) => widget.onToggle(),
            ),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontWeight: widget.checked ? FontWeight.w900 : FontWeight.w800,
                  color: widget.checked ? WorkaColors.textDark : WorkaColors.textGreyDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.supportsHover) return child;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: child,
    );
  }
}

class _HoverPickRow extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool supportsHover;

  const _HoverPickRow({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.supportsHover,
  });

  @override
  State<_HoverPickRow> createState() => _HoverPickRowState();
}

class _HoverPickRowState extends State<_HoverPickRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover ? WorkaColors.hoverBlue : Colors.white;

    final content = InkWell(
      onTap: widget.onTap,
      hoverColor: WorkaColors.hoverBlue,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontWeight: widget.selected ? FontWeight.w900 : FontWeight.w800,
                  color: widget.selected ? WorkaColors.textDark : WorkaColors.textGreyDark,
                ),
              ),
            ),
            if (widget.selected) const Icon(Icons.check, color: WorkaColors.blue),
          ],
        ),
      ),
    );

    if (!widget.supportsHover) return content;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: content,
    );
  }
}
