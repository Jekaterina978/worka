// lib/screens/search/widgets/location_picker_sheet.dart
import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';
import '../../../utils/country_display_formatter.dart';

class LocationPickResult {
  final Set<String> countries;
  final String? pickedCityLabel;

  const LocationPickResult({
    required this.countries,
    this.pickedCityLabel,
  });

  List<String> get countriesList => countries.toList();
}

class LocationPickerSheet extends StatefulWidget {
  final List<String> allCountries;
  final Set<String> initialCountries;
  final List<String> initialSelected;
  final String? initialCityLabel;
  final bool singleSelect;
  final Map<String, String> cityToCountry;

  const LocationPickerSheet({
    super.key,
    this.allCountries = const <String>[],
    this.initialCountries = const <String>{},
    this.initialSelected = const <String>[],
    this.initialCityLabel,
    this.singleSelect = false,
    this.cityToCountry = const <String, String>{},
  });

  static Future<LocationPickResult?> open(
    BuildContext context, {
    required List<String> allCountries,
    Set<String> initialCountries = const <String>{},
    List<String> initialSelected = const <String>[],
    String? initialCityLabel,
    bool singleSelect = false,
    Map<String, String> cityToCountry = const <String, String>{},
  }) {
    return showModalBottomSheet<LocationPickResult>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => LocationPickerSheet(
        allCountries: allCountries,
        initialCountries: initialCountries,
        initialSelected: initialSelected,
        initialCityLabel: initialCityLabel,
        singleSelect: singleSelect,
        cityToCountry: cityToCountry,
      ),
    );
  }

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final _q = TextEditingController();
  late Set<String> _selected;

  int? _hoverCityIdx;
  static const Color _clearInactiveBg = Color(0xFFFFD9AE);

  static String _norm(String s) => s.trim().toLowerCase();

  static const List<String> _fallbackCountries = <String>[
    'Австрия',
    'Албания',
    'Андорра',
    'Армения',
    'Беларусь',
    'Бельгия',
    'Болгария',
    'Босния и Герцеговина',
    'Великобритания',
    'Венгрия',
    'Германия',
    'Греция',
    'Грузия',
    'Дания',
    'Ирландия',
    'Исландия',
    'Испания',
    'Италия',
    'Кипр',
    'Латвия',
    'Литва',
    'Лихтенштейн',
    'Люксембург',
    'Мальта',
    'Молдова',
    'Монако',
    'Нидерланды',
    'Норвегия',
    'Польша',
    'Португалия',
    'Румыния',
    'Северная Македония',
    'Сербия',
    'Словакия',
    'Словения',
    'Турция',
    'Украина',
    'Финляндия',
    'Франция',
    'Хорватия',
    'Черногория',
    'Чехия',
    'Швейцария',
    'Швеция',
    'Эстония',
  ];

  List<String> get _countries {
    final src = widget.allCountries.isNotEmpty ? widget.allCountries : _fallbackCountries;

    final set = <String>{};
    for (final c in src) {
      final t = c.trim();
      if (t.isNotEmpty) set.add(t);
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String _flagForCountry(String country) {
    final flag = CountryDisplayFormatter.countryFlagOnly(
      country.trim(),
      euAsToken: false,
    );
    return flag.trim().isEmpty ? '🌍' : flag;
  }

  @override
  void initState() {
    super.initState();
    _selected = {
      ...widget.initialCountries,
      ...widget.initialSelected,
    };
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _toggleCountry(String c) {
    setState(() {
      if (widget.singleSelect) {
        if (_selected.contains(c)) {
          _selected.remove(c);
        } else {
          _selected
            ..clear()
            ..add(c);
        }
        return;
      }

      if (_selected.contains(c)) {
        _selected.remove(c);
      } else {
        _selected.add(c);
      }
    });
  }

  void _clear() => setState(() => _selected.clear());

  List<MapEntry<String, String>> _citySuggestions(String query) {
    final q = _norm(query);
    if (q.isEmpty || q.length < 2) return const [];
    if (widget.cityToCountry.isEmpty) return const [];

    final entries = widget.cityToCountry.entries.toList();
    final starts = <MapEntry<String, String>>[];
    final contains = <MapEntry<String, String>>[];

    for (final e in entries) {
      final city = _norm(e.key);
      if (city.startsWith(q)) {
        starts.add(e);
      } else if (city.contains(q)) {
        contains.add(e);
      }
    }

    final combined = [...starts, ...contains];

    final allSet = _countries.map(_norm).toSet();
    final filtered = combined.where((e) => allSet.contains(_norm(e.value))).toList();

    if (filtered.length > 6) return filtered.sublist(0, 6);
    return filtered;
  }

  void _selectCountryFromCitySuggestion(String country) {
    setState(() {
      if (widget.singleSelect) {
        _selected
          ..clear()
          ..add(country);
      } else {
        _selected.add(country);
      }
      _q.clear();
      _hoverCityIdx = null;
    });
  }

  // ✅ Синие чекбоксы (без фиолетового Material)
  Widget _workaCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Checkbox(
      value: value,
      onChanged: onChanged,
      activeColor: WorkaColors.blue, // заливка
      checkColor: Colors.white, // галочка
      side: const BorderSide(color: WorkaColors.fieldBorder, width: 1.4), // рамка когда unchecked
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return WorkaColors.blue;
        return Colors.transparent;
      }),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.focused)) {
          return WorkaColors.hoverBlueSoft;
        }
        return null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.78;

    final query = _q.text;
    final qn = _norm(query);

    final all = _countries;
    final filteredCountries = qn.isEmpty ? all : all.where((e) => _norm(e).contains(qn)).toList();

    final citySugs = _citySuggestions(query);
    final hasSelection = _selected.isNotEmpty;
    final doneStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        return WorkaColors.blue;
      }),
      foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.focused)) {
          return WorkaColors.hoverBlueSoft;
        }
        return null;
      }),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      elevation: WidgetStateProperty.all(0),
    );

    return SafeArea(
      child: Container(
        color: Colors.white,
        child: SizedBox(
          height: h,
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text('Где работать?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  children: [
                    TextField(
                      controller: _q,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, color: WorkaColors.textGreyDark),
                        hintText: 'Где работать?',
                        filled: true,
                        fillColor: Colors.white,
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

                    if (citySugs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: WorkaColors.fieldBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: citySugs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: WorkaColors.divider),
                          itemBuilder: (context, i) {
                            final e = citySugs[i];
                            final cityLabel = e.key.trim();
                            final country = e.value.trim();
                            final hovered = _hoverCityIdx == i;
                            final countryFlag = _flagForCountry(country);

                            return MouseRegion(
                              onEnter: (_) => setState(() => _hoverCityIdx = i),
                              onExit: (_) => setState(() => _hoverCityIdx = null),
                              child: InkWell(
                                hoverColor: WorkaColors.hoverBlueSoft,
                                onTap: () => _selectCountryFromCitySuggestion(country),
                                child: Container(
                                  color: hovered ? WorkaColors.hoverBlueSoft : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.location_city, size: 18, color: WorkaColors.textGrey),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '$cityLabel, $countryFlag $country',
                                          style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textDark),
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios, size: 14, color: WorkaColors.textGrey),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                  itemCount: filteredCountries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: WorkaColors.divider),
                  itemBuilder: (context, i) {
                    final c = filteredCountries[i];
                    final checked = _selected.contains(c);

                    return InkWell(
                      hoverColor: WorkaColors.hoverBlueSoft,
                      onTap: () => _toggleCountry(c),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            _workaCheckbox(value: checked, onChanged: (_) => _toggleCountry(c)),
                            const SizedBox(width: 8),
                            Text(_flagForCountry(c), style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c,
                                style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: WorkaColors.divider.withValues(alpha: 0.9))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _clear,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: hasSelection ? WorkaColors.orange : _clearInactiveBg,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: Text(
                              'Очистить',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: hasSelection ? Colors.white : Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(
                              context,
                              LocationPickResult(countries: {..._selected}, pickedCityLabel: null),
                            ),
                            style: doneStyle,
                            child: const Text(
                              'Готово',
                              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
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
        ),
      ),
    );
  }
}
