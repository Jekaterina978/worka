import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/screens/employer/search/models/candidate_filters.dart';
import 'package:worka/screens/employer/search/models/candidate_filters_config.dart';

class CandidateFiltersScreen extends StatefulWidget {
  final CandidateFilters initial;
  const CandidateFiltersScreen({super.key, required this.initial});

  @override
  State<CandidateFiltersScreen> createState() => _CandidateFiltersScreenState();
}

class _CandidateFiltersScreenState extends State<CandidateFiltersScreen> {
  late Set<String> _cats;
  late Set<String> _langs;
  late Set<String> _exp;

  @override
  void initState() {
    super.initState();
    _cats = {...widget.initial.categories};
    _langs = {...widget.initial.languages};
    _exp = {...widget.initial.experiences};
  }

  void _toggle(Set<String> set, String v) {
    setState(() {
      if (set.contains(v)) {
        set.remove(v);
      } else {
        set.add(v);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _cats.clear();
      _langs.clear();
      _exp.clear();
    });
  }

  void _done() {
    Navigator.pop(
      context,
      widget.initial.copyWith(
        categories: _cats,
        languages: _langs,
        experiences: _exp,
      ),
    );
  }

  String _valueLabel(Set<String> set) {
    if (set.isEmpty) return 'Не выбрано';
    if (set.length == 1) return set.first;
    return 'Выбрано: ${set.length}';
  }

  Future<void> _pickCategories() async {
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => _GroupedCategorySheet(
        selected: _cats,
        groups: CandidateFiltersConfig.categoryGroups,
      ),
    );
    if (res == null) return;
    setState(() {
      _cats
        ..clear()
        ..addAll(res);
    });
  }

  Future<void> _pickLanguages() async {
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => _MultiSelectSheet(
        title: 'Языки',
        options: CandidateFiltersConfig.languages,
        selected: _langs,
      ),
    );
    if (res == null) return;
    setState(() {
      _langs
        ..clear()
        ..addAll(res);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(Icons.arrow_back, color: WorkaColors.textGreyDark),
        ),
        title: Text(
          'Фильтры',
          style: TextStyle(fontWeight: FontWeight.w900, color: WorkaColors.textGreyDark),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              children: [
                _DropRow(label: 'Категория', value: _valueLabel(_cats), onTap: _pickCategories),
                const SizedBox(height: 12),
                _DropRow(label: 'Языки', value: _valueLabel(_langs), onTap: _pickLanguages),

                const SizedBox(height: 14),
                Divider(color: WorkaColors.divider),

                Text(
                  'Опыт работы',
                  style: TextStyle(fontWeight: FontWeight.w900, color: WorkaColors.textGreyDark),
                ),
                const SizedBox(height: 10),

                // ✅ ОПЫТ КНОПКАМИ (как у вакансий)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in CandidateFiltersConfig.experiences)
                      _ToggleChip(
                        text: e,
                        selected: _exp.contains(e),
                        onTap: () => _toggle(_exp, e),
                      ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _clearAll,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: BorderSide(color: WorkaColors.fieldBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        'Очистить',
                        style: TextStyle(
                          color: WorkaColors.orange,
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
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final valueColor = value == 'Не выбрано' ? WorkaColors.textGrey : WorkaColors.textGreyDark;

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
                    TextSpan(text: '$label: ', style: TextStyle(color: WorkaColors.textGreyDark)),
                    TextSpan(text: value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: WorkaColors.textGreyDark),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? WorkaColors.hoverBlueSoft : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? WorkaColors.blue : WorkaColors.fieldBorder),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: WorkaColors.textDark,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Универсальный bottom-sheet: чекбоксы + Очистить/Готово
class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final Set<String> selected;

  const _MultiSelectSheet({
    required this.title,
    required this.options,
    required this.selected,
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
      if (_sel.contains(v)) _sel.remove(v);
      else _sel.add(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final it in widget.options)
                    InkWell(
                      onTap: () => _toggle(it),
                      hoverColor: WorkaColors.hoverBlue,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _sel.contains(it),
                              onChanged: (_) => _toggle(it),
                              activeColor: WorkaColors.blue,
                            ),
                            Expanded(
                              child: Text(
                                it,
                                style: TextStyle(
                                  fontWeight: _sel.contains(it) ? FontWeight.w900 : FontWeight.w800,
                                  color: WorkaColors.textGreyDark,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => setState(_sel.clear),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: BorderSide(color: WorkaColors.fieldBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          'Очистить',
                          style: TextStyle(color: WorkaColors.orange, fontWeight: FontWeight.w900),
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
    );
  }
}

/// Категории с группами: чекбокс в заголовке группы.
class _GroupedCategorySheet extends StatefulWidget {
  final Set<String> selected;
  final Map<String, List<String>> groups;

  const _GroupedCategorySheet({required this.selected, required this.groups});

  @override
  State<_GroupedCategorySheet> createState() => _GroupedCategorySheetState();
}

class _GroupedCategorySheetState extends State<_GroupedCategorySheet> {
  late final Set<String> _sel;

  @override
  void initState() {
    super.initState();
    _sel = {...widget.selected};
  }

  bool _groupChecked(List<String> items) => items.isNotEmpty && items.every(_sel.contains);

  void _toggleGroup(List<String> items) {
    final all = _groupChecked(items);
    setState(() {
      if (all) {
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

  void _toggleItem(String v) {
    setState(() {
      if (_sel.contains(v)) _sel.remove(v);
      else _sel.add(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Text('Категория', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final entry in widget.groups.entries) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => _toggleGroup(entry.value),
                      hoverColor: WorkaColors.hoverBlue,
                      child: Row(
                        children: [
                          Checkbox(
                            value: _groupChecked(entry.value),
                            onChanged: (_) => _toggleGroup(entry.value),
                            activeColor: WorkaColors.blue,
                          ),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: WorkaColors.textGreyDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final it in entry.value)
                      InkWell(
                        onTap: () => _toggleItem(it),
                        hoverColor: WorkaColors.hoverBlue,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _sel.contains(it),
                                onChanged: (_) => _toggleItem(it),
                                activeColor: WorkaColors.blue,
                              ),
                              Expanded(
                                child: Text(
                                  it,
                                  style: TextStyle(
                                    fontWeight: _sel.contains(it) ? FontWeight.w900 : FontWeight.w800,
                                    color: WorkaColors.textGreyDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Divider(color: WorkaColors.divider),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => setState(_sel.clear),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: BorderSide(color: WorkaColors.fieldBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          'Очистить',
                          style: TextStyle(color: WorkaColors.orange, fontWeight: FontWeight.w900),
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
    );
  }
}
