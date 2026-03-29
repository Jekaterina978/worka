import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../services/firestore_paths.dart';
import '../theme/worka_colors.dart';
import '../widgets/worka_header.dart';
import 'search/widgets/search_filters_config.dart';
import 'employer/search/models/candidate_filters_config.dart';

class AddCvScreen extends StatefulWidget {
  const AddCvScreen({super.key});

  @override
  State<AddCvScreen> createState() => _AddCvScreenState();
}

class _AddCvScreenState extends State<AddCvScreen> {
  final _nameCtrl = TextEditingController();
  final _professionCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();

  final _cityCtrl = TextEditingController();
  String _country = 'Эстония';

  String? _gender; // male/female
  String? _experience; // null = не выбрано
  String? _language; // null = без языка/не выбрано

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (SearchFiltersConfig.countriesRu.isNotEmpty) {
      _country = SearchFiltersConfig.countriesRu.firstWhere(
        (c) => c == 'Эстония',
        orElse: () => SearchFiltersConfig.countriesRu.first,
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _professionCtrl.dispose();
    _aboutCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _snack(String t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _professionCtrl.text.trim().isEmpty) {
      _snack('Заполните имя и профессию');
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        throw StateError('Требуется авторизация для создания CV.');
      }

      final payload = {
        'candidateId': uid,
        'ownerId': uid,
        'ownerUid': uid,
        'name': _nameCtrl.text.trim(),
        'profession': _professionCtrl.text.trim(),
        'about': _aboutCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'country': _country.trim(),
        'gender': _gender,
        'experience': _experience,
        'languages': _language,
      };

    final base = const String.fromEnvironment(
      'WORKA_API_BASE_URL',
      defaultValue: '',
    );
    assert(base.trim().isNotEmpty, 'WORKA_API_BASE_URL is required');
    final normalizedBase = base.endsWith('/api') ? base : '$base/api';
    final uri = Uri.parse('$normalizedBase/candidates/cv');
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final body = resp.body.trim();
        throw StateError(
          'Не удалось сохранить CV: '
          '${body.isNotEmpty ? body : 'status=${resp.statusCode}'}',
        );
      }

      if (!mounted) return;
      Navigator.of(context).maybePop();
      _snack('CV добавлено');
    } catch (e) {
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decor(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: WorkaColors.textGrey,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: WorkaColors.blue),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Добавить CV',
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          SizedBox(
            height: 56,
            child: TextField(
              controller: _nameCtrl,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: WorkaColors.textDark,
              ),
              decoration: _decor('Имя Фамилия', Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: TextField(
              controller: _professionCtrl,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: WorkaColors.textDark,
              ),
              decoration: _decor('Профессия', Icons.work),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: TextField(
              controller: _cityCtrl,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: WorkaColors.textDark,
              ),
              decoration: _decor('Город', Icons.location_city),
            ),
          ),
          const SizedBox(height: 12),

          // страна (одиночный выбор)
          InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Center(
                widthFactor: 0,
                child: Text('🌍', style: TextStyle(fontSize: 18)),
              ),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: WorkaColors.fieldBorder),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _country,
                isExpanded: true,
                items: SearchFiltersConfig.countriesRu
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _country = v ?? _country),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // пол
          Row(
            children: [
              Expanded(
                child: _chip(
                  'Мужчина',
                  _gender == 'male',
                  () => setState(
                    () => _gender = _gender == 'male' ? null : 'male',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _chip(
                  'Женщина',
                  _gender == 'female',
                  () => setState(
                    () => _gender = _gender == 'female' ? null : 'female',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ✅ опыт (КАНДИДАТЫ) — из CandidateFiltersConfig
          InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.school, color: WorkaColors.blue),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: WorkaColors.fieldBorder),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _experience ?? 'Не выбрано',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: 'Не выбрано',
                    child: Text('Не выбрано'),
                  ),
                  ...CandidateFiltersConfig.experiences.map(
                    (e) => DropdownMenuItem(value: e, child: Text(e)),
                  ),
                  // ✅ поддержка старых значений из БД
                  const DropdownMenuItem(
                    value: '1–2 года',
                    child: Text('1–2 года (старое)'),
                  ),
                  const DropdownMenuItem(
                    value: '3+ года',
                    child: Text('3+ года (старое)'),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    if (v == null || v == 'Не выбрано') {
                      _experience = null;
                    } else {
                      _experience = v;
                    }
                  });
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ✅ язык (КАНДИДАТЫ) — из CandidateFiltersConfig
          InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.language, color: WorkaColors.blue),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: WorkaColors.fieldBorder),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _language ?? 'Без языка',
                isExpanded: true,
                items: CandidateFiltersConfig.languages
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(
                  () => _language = (v == null || v == 'Без языка') ? null : v,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: WorkaColors.divider),
              borderRadius: BorderRadius.circular(18),
            ),
            child: TextField(
              controller: _aboutCtrl,
              maxLines: 6,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: WorkaColors.textDark,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'О себе',
                hintStyle: TextStyle(
                  color: WorkaColors.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.orange,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Сохранить',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
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

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? WorkaColors.hoverBlueSoft : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? WorkaColors.blue : WorkaColors.fieldBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: WorkaColors.textDark,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
