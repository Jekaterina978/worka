import 'package:flutter/material.dart';
import '../data/worka_theme.dart';
import '../widgets/worka_header.dart';

class CodePick {
  final String countryNameRu;
  final String dialCode;
  const CodePick({required this.countryNameRu, required this.dialCode});
}

class CountryCodePickerScreen extends StatefulWidget {
  const CountryCodePickerScreen({super.key});

  @override
  State<CountryCodePickerScreen> createState() => _CountryCodePickerScreenState();
}

class _CountryCodePickerScreenState extends State<CountryCodePickerScreen> {
  final _q = TextEditingController();

  static const _items = <CodePick>[
    // Europe (примерно)
    CodePick(countryNameRu: 'Германия', dialCode: '+49'),
    CodePick(countryNameRu: 'Франция', dialCode: '+33'),
    CodePick(countryNameRu: 'Италия', dialCode: '+39'),
    CodePick(countryNameRu: 'Испания', dialCode: '+34'),
    CodePick(countryNameRu: 'Польша', dialCode: '+48'),
    CodePick(countryNameRu: 'Швеция', dialCode: '+46'),
    CodePick(countryNameRu: 'Норвегия', dialCode: '+47'),
    CodePick(countryNameRu: 'Финляндия', dialCode: '+358'),
    CodePick(countryNameRu: 'Эстония', dialCode: '+372'),
    CodePick(countryNameRu: 'Латвия', dialCode: '+371'),
    CodePick(countryNameRu: 'Литва', dialCode: '+370'),
    // CIS
    CodePick(countryNameRu: 'Украина', dialCode: '+380'),
    CodePick(countryNameRu: 'Казахстан', dialCode: '+7'),
    CodePick(countryNameRu: 'Армения', dialCode: '+374'),
    CodePick(countryNameRu: 'Азербайджан', dialCode: '+994'),
    CodePick(countryNameRu: 'Беларусь', dialCode: '+375'),
    CodePick(countryNameRu: 'Грузия', dialCode: '+995'),
    CodePick(countryNameRu: 'Киргизстан', dialCode: '+996'),
    CodePick(countryNameRu: 'Молдова', dialCode: '+373'),
    CodePick(countryNameRu: 'Таджикистан', dialCode: '+992'),
    CodePick(countryNameRu: 'Узбекистан', dialCode: '+998'),
  ];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _items
        : _items.where((e) => e.countryNameRu.toLowerCase().contains(q) || e.dialCode.contains(q)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Код страны',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
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
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: TextField(
                      controller: _q,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Найти страну или код…',
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: WorkaTheme.blue, width: 1.6),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final it = list[i];
                        return Material(
                          color: Colors.white,
                          child: InkWell(
                            hoverColor: WorkaTheme.blueSoft,
                            onTap: () => Navigator.pop(context, it),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(it.countryNameRu, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                  Text(it.dialCode, style: const TextStyle(fontWeight: FontWeight.w900)),
                                ],
                              ),
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
        ],
      ),
    );
  }
}
