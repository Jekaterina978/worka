import 'package:flutter/material.dart';

import '../../theme/worka_colors.dart';

class WorkaLanguageDropdownMultiSelect extends StatefulWidget {
  const WorkaLanguageDropdownMultiSelect({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.emptyText = 'Языки не выбраны',
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String emptyText;

  @override
  State<WorkaLanguageDropdownMultiSelect> createState() =>
      _WorkaLanguageDropdownMultiSelectState();
}

class _WorkaLanguageDropdownMultiSelectState
    extends State<WorkaLanguageDropdownMultiSelect> {
  String? _draftLanguage;

  List<String> get _available {
    return widget.options
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !widget.selected.contains(e))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    final available = _available;
    _draftLanguage = available.isNotEmpty ? available.first : null;
  }

  @override
  void didUpdateWidget(covariant WorkaLanguageDropdownMultiSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    final available = _available;
    if (_draftLanguage == null || !available.contains(_draftLanguage)) {
      _draftLanguage = available.isNotEmpty ? available.first : null;
    }
  }

  void _addLanguage() {
    final value = (_draftLanguage ?? '').trim();
    if (value.isEmpty || widget.selected.contains(value)) return;
    final next = <String>{...widget.selected, value};
    widget.onChanged(next);
  }

  void _removeLanguage(String value) {
    final next = <String>{...widget.selected}..remove(value);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    final safeValue =
        _draftLanguage != null && available.contains(_draftLanguage)
        ? _draftLanguage
        : (available.isNotEmpty ? available.first : null);

    final selected = widget.selected.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: safeValue,
                  items: available
                      .map(
                        (v) => DropdownMenuItem<String>(
                          value: v,
                          child: Text(
                            v,
                            style: const TextStyle(
                              color: WorkaColors.textGreyDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: available.isEmpty
                      ? null
                      : (v) => setState(() => _draftLanguage = v),
                  decoration: InputDecoration(
                    hintText: available.isEmpty
                        ? 'Все языки добавлены'
                        : 'Выберите язык',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: WorkaColors.fieldBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: WorkaColors.blue,
                        width: 1.6,
                      ),
                    ),
                  ),
                  dropdownColor: Colors.white,
                  iconEnabledColor: WorkaColors.blue,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: available.isEmpty ? null : _addLanguage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WorkaColors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Добавить язык'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (selected.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WorkaColors.fieldBorder),
                  ),
                  child: Text(
                    widget.emptyText,
                    style: const TextStyle(
                      color: WorkaColors.textGrey,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ...selected.map(
                (lang) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: WorkaColors.hoverBlueSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WorkaColors.blue),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          lang,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: WorkaColors.textGreyDark,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _removeLanguage(lang),
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: WorkaColors.blue,
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
      ],
    );
  }
}
