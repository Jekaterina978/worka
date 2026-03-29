import 'package:flutter/material.dart';
import '../theme/worka_colors.dart';

class LocationPickerSheet extends StatefulWidget {
  final String title; // "Локация"
  final List<String> allItems;
  final List<String> initialSelected;

  const LocationPickerSheet({
    super.key,
    required this.title,
    required this.allItems,
    this.initialSelected = const [],
  });

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final _q = TextEditingController();
  late final Set<String> _selected = widget.initialSelected.toSet();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.78;

    final q = _q.text.trim().toLowerCase();
    final items = q.isEmpty
        ? widget.allItems
        : widget.allItems.where((e) => e.toLowerCase().contains(q)).toList();

    final allCount = widget.allItems.length;
    final selCount = _selected.length;
    final allSelected = allCount > 0 && selCount == allCount;

    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: WorkaColors.textGreyDark),
                  hintText: 'Поиск страны',
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
            ),

            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1, color: WorkaColors.divider),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return InkWell(
                      hoverColor: WorkaColors.hoverBlue,
                      onTap: () {
                        setState(() {
                          if (allSelected) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(widget.allItems);
                          }
                        });
                      },
                      child: _RowCheck(text: 'Выбрать всё', checked: allSelected),
                    );
                  }

                  final v = items[i - 1];
                  final checked = _selected.contains(v);

                  return InkWell(
                    hoverColor: WorkaColors.hoverBlue,
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(v);
                      } else {
                        _selected.add(v);
                      }
                    }),
                    child: _RowCheck(text: v, checked: checked),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => setState(() => _selected.clear()),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: WorkaColors.fieldBorder),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        child: const Text(
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
                        onPressed: () => Navigator.pop(context, _selected.toList()..sort()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.orange,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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

class _RowCheck extends StatelessWidget {
  final String text;
  final bool checked;

  const _RowCheck({required this.text, required this.checked});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Checkbox(value: checked, onChanged: null),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
            ),
          ),
        ],
      ),
    );
  }
}