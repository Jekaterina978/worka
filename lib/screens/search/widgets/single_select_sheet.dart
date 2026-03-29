import 'package:flutter/material.dart';
import '../../../theme/worka_colors.dart';
import 'filter_ui.dart';

class SingleSelectSheet extends StatelessWidget {
  final String title;
  final List<String> items;
  final String current;

  const SingleSelectSheet({
    super.key,
    required this.title,
    required this.items,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: FilterUi.whiteTheme(context),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: WorkaColors.textGreyDark)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final v = items[i];
                    final selected = v == current;
                    return InkWell(
                      onTap: () => Navigator.pop(context, v),
                      hoverColor: WorkaColors.hoverBlue,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: selected ? WorkaColors.blue : WorkaColors.fieldBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                v,
                                style: TextStyle(
                                  fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                                  color: WorkaColors.textGreyDark,
                                ),
                              ),
                            ),
                            if (selected) const Icon(Icons.check, color: WorkaColors.blue),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
