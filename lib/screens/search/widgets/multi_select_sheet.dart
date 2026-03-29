import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';
import '../../../widgets/forms/language_dropdown_multi_select.dart';

const _categoryIconColor = Color(0xFFFF8A00);

class MultiSelectSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final Set<String> selected;
  final Map<String, List<String>>? grouped;
  final IconData? Function(String label)? itemIconBuilder;

  const MultiSelectSheet({
    super.key,
    required this.title,
    required this.items,
    required this.selected,
    this.grouped,
    this.itemIconBuilder,
  });

  @override
  State<MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<MultiSelectSheet> {
  late final Set<String> _sel;
  static const Color _clearInactiveBg = Color(0xFFFFD9AE);
  bool get _isLanguageSheet =>
      widget.title.trim().toLowerCase() == 'язык' ||
      widget.title.trim().toLowerCase() == 'языки';

  @override
  void initState() {
    super.initState();
    _sel = {...widget.selected};
  }

  void _toggleItem(String v) {
    setState(() {
      if (_sel.contains(v)) {
        _sel.remove(v);
      } else {
        _sel.add(v);
      }
    });
  }

  void _toggleGroup(String groupTitle, List<String> groupItems) {
    final allSelected =
        groupItems.isNotEmpty && groupItems.every(_sel.contains);
    setState(() {
      if (allSelected) {
        for (final it in groupItems) {
          _sel.remove(it);
        }
      } else {
        for (final it in groupItems) {
          _sel.add(it);
        }
      }
    });
  }

  Widget _languagePickerBody() {
    return WorkaLanguageDropdownMultiSelect(
      options: widget.items,
      selected: _sel,
      onChanged: (next) => setState(() {
        _sel
          ..clear()
          ..addAll(next);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _sel.isNotEmpty;
    final grouped = widget.grouped;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.title == 'Категория') ...[
                    const Icon(
                      Icons.work_outline,
                      color: _categoryIconColor,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: WorkaColors.textGreyDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _isLanguageSheet
                  ? _languagePickerBody()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        if (grouped != null) ...[
                          for (final entry in grouped.entries) ...[
                            const SizedBox(height: 10),
                            _GroupHeaderRow(
                              title: entry.key,
                              checked:
                                  entry.value.isNotEmpty &&
                                  entry.value.every(_sel.contains),
                              onToggle: () =>
                                  _toggleGroup(entry.key, entry.value),
                              leadingIcon: widget.itemIconBuilder?.call(
                                entry.key,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final it in entry.value)
                              _CheckRow(
                                label: it,
                                checked: _sel.contains(it),
                                onToggle: () => _toggleItem(it),
                              ),
                            const Divider(color: WorkaColors.divider),
                          ],
                        ] else ...[
                          for (final it in widget.items)
                            _CheckRow(
                              label: it,
                              checked: _sel.contains(it),
                              onToggle: () => _toggleItem(it),
                              leadingIcon: widget.itemIconBuilder?.call(it),
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
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => setState(_sel.clear),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasSelection
                              ? WorkaColors.orange
                              : _clearInactiveBg,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Очистить',
                          style: TextStyle(
                            color: hasSelection
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.85),
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
                          backgroundColor: WorkaColors.blue,
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

class _GroupHeaderRow extends StatelessWidget {
  final String title;
  final bool checked;
  final VoidCallback onToggle;
  final IconData? leadingIcon;

  const _GroupHeaderRow({
    required this.title,
    required this.checked,
    required this.onToggle,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              activeColor: WorkaColors.blue,
              onChanged: (_) => onToggle(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        color: WorkaColors.textGreyDark,
                      ),
                    ),
                  ),
                  if (leadingIcon != null) ...[
                    const SizedBox(width: 10),
                    Icon(leadingIcon, color: _categoryIconColor, size: 26),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onToggle;
  final IconData? leadingIcon;

  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onToggle,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              activeColor: WorkaColors.blue,
              onChanged: (_) => onToggle(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: WorkaColors.textGreyDark,
                ),
              ),
            ),
            if (leadingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(leadingIcon, color: _categoryIconColor, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}
