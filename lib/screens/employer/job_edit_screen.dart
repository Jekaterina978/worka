import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../theme/worka_colors.dart';
import '../../widgets/worka_header.dart';

class JobEditScreen extends StatefulWidget {
  const JobEditScreen({
    super.key,
    required this.jobCode,
  });

  final String jobCode;

  @override
  State<JobEditScreen> createState() => _JobEditScreenState();
}

class _JobEditScreenState extends State<JobEditScreen> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _salary = TextEditingController();
  final _desc = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _country.dispose();
    _salary.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  Future<void> _load() async {
    // Backend GET endpoint not specified; keep existing values.
    // If needed, initial data should be passed from previous screen.
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _patchJob({
    required String jobCode,
    required Map<String, dynamic> payload,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Требуется авторизация для обновления вакансии.');
    }

    final base = const String.fromEnvironment('WORKA_API_BASE_URL', defaultValue: '')
        .replaceAll(RegExp(r'/+$'), '');
    assert(base.isNotEmpty, 'WORKA_API_BASE_URL is required');
    final normalizedBase = base.endsWith('/api') ? base : '$base/api';
    final uri = Uri.parse('$normalizedBase/jobs/$jobCode');
    final resp = await http.patch(
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
        'Не удалось сохранить вакансию: '
        '${body.isNotEmpty ? body : 'status=${resp.statusCode}'}',
      );
    }
    final json = jsonDecode(resp.body);
    if (json is Map && json['job'] is Map) {
      return Map<String, dynamic>.from(json['job'] as Map);
    }
    return const {};
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final city = _city.text.trim();
      final country = _country.text.trim();
      final locationParts = <String>[
        if (city.isNotEmpty) city,
        if (country.isNotEmpty) country,
      ];
      final location = locationParts.join(', ');

      final job = await _patchJob(
        jobCode: widget.jobCode,
        payload: {
          'title': _title.text.trim(),
          'description': _desc.text.trim(),
          'location': location,
        },
      );

      // Update UI from response if available
      if (job.isNotEmpty) {
        _title.text = (job['title'] ?? _title.text).toString();
        _desc.text = (job['description'] ?? _desc.text).toString();
        final loc = (job['location'] ?? location).toString();
        if (loc.contains(',')) {
          final parts = loc.split(',');
          _city.text = parts.first.trim();
          _country.text = parts.skip(1).join(',').trim();
        } else {
          _city.text = loc;
        }
        setState(() {});
      }

      _toast('Сохранено ✅');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _deco(String label, IconData icon, {Widget? iconWidget}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, color: WorkaColors.textGreyDark),
      prefixIcon: iconWidget ?? Icon(icon, color: WorkaColors.blue),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Изменить вакансию',
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
              child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          TextField(controller: _title, decoration: _deco('Название', Icons.work_outline)),
          const SizedBox(height: 12),
          TextField(controller: _city, decoration: _deco('Город', Icons.location_city_outlined)),
          const SizedBox(height: 12),
          TextField(controller: _country, decoration: _deco('Страна', Icons.public, iconWidget: const Center(widthFactor: 0, child: Text('🌍', style: TextStyle(fontSize: 18))))),
          const SizedBox(height: 12),
          TextField(controller: _salary, decoration: _deco('Зарплата', Icons.payments_outlined)),
          const SizedBox(height: 12),
          TextField(controller: _desc, maxLines: 6, decoration: _deco('Описание', Icons.description_outlined)),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.orange,
                disabledBackgroundColor: WorkaColors.orange.withValues(alpha: 0.35),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Сохранить',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white),
                    ),
            ),
          ),
        ],
      )),
          ),
        ],
      ),
    );
  }
}
