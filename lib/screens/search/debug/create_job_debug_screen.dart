import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/exchange_rate_service.dart';
import '../../../theme/worka_colors.dart';

class CreateJobDebugScreen extends StatefulWidget {
  const CreateJobDebugScreen({super.key});

  @override
  State<CreateJobDebugScreen> createState() => _CreateJobDebugScreenState();
}

class _CreateJobDebugScreenState extends State<CreateJobDebugScreen> {
  final _db = FirebaseFirestore.instance;

  final _title = TextEditingController(text: 'Уборка квартиры');
  final _category = TextEditingController(text: 'Сфера обслуживания');
  final _city = TextEditingController(text: 'Таллинн');
  final _country = TextEditingController(text: 'Эстония');
  final _type = TextEditingController(text: 'Частичная занятость');
  final _desc = TextEditingController(text: 'Тестовая вакансия для отладки');

  final _salaryAmount = TextEditingController(text: '70');

  String _salaryCurrency = 'EUR';
  String _salaryPeriod = 'day'; // hour/day/month

  bool _urgent = true;
  bool _housing = false;
  bool _transport = false;
  bool _teen = false;
  bool _disability = false;

  bool _saving = false;
  String? _result;

  double _toEurPerMonth(double eurAmount, String period) {
    switch (period) {
      case 'hour':
        return eurAmount * 160.0;
      case 'day':
        return eurAmount * 22.0;
      case 'month':
      default:
        return eurAmount;
    }
  }

  String _salaryText(double amount, String cur, String period) {
    final p = switch (period) {
      'hour' => 'час',
      'day' => 'день',
      _ => 'месяц',
    };
    final sym = cur == 'EUR'
        ? '€'
        : cur == 'USD'
            ? '\$'
            : cur == 'GBP'
                ? '£'
                : cur;
    return '${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)}$sym / $p';
  }

  Future<void> _createJob() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _result = null;
    });

    try {
      final amount = double.tryParse(_salaryAmount.text.trim().replaceAll(',', '.'));
      if (amount == null || amount <= 0) {
        throw Exception('Неверная зарплата');
      }

      // currency -> EUR
      double eur = amount;
      if (_salaryCurrency != 'EUR') {
        final rate = await ExchangeRateService.rateToEur(_salaryCurrency);
        if (rate == null) {
          throw Exception('Не удалось получить курс для $_salaryCurrency');
        }
        eur = amount * rate;
      }

      final eurPerMonth = _toEurPerMonth(eur, _salaryPeriod);

      final doc = <String, dynamic>{
        'title': _title.text.trim(),
        'category': _category.text.trim(),
        'city': _city.text.trim(),
        'country': _country.text.trim(),
        'type': _type.text.trim(),
        'description': _desc.text.trim(),

        'createdAt': FieldValue.serverTimestamp(),
        'isUrgent': _urgent,

        // switches
        'housingProvided': _housing,
        'transportProvided': _transport,
        'teenFriendly': _teen,
        'disabilityFriendly': _disability,

        // salary structured
        'salaryAmount': amount,
        'salaryCurrency': _salaryCurrency,
        'salaryPeriod': _salaryPeriod,
        'salaryEurPerMonth': eurPerMonth,

        // salary for UI
        'salary': _salaryText(amount, _salaryCurrency, _salaryPeriod),
      };

      final ref = await _db.collection('jobs').add(doc);

      final snap = await ref.get();
      setState(() {
        _result = '✅ Создано: ${ref.id}\n\nSaved:\n${snap.data()}';
      });
    } catch (e) {
      setState(() => _result = '❌ Ошибка: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _city.dispose();
    _country.dispose();
    _type.dispose();
    _desc.dispose();
    _salaryAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WorkaColors.bg,
      appBar: AppBar(
        title: const Text('DEBUG: Создать вакансию'),
        backgroundColor: Colors.white,
        foregroundColor: WorkaColors.textDark,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _field('Название', _title),
          _field('Категория', _category),
          Row(
            children: [
              Expanded(child: _field('Город', _city)),
              const SizedBox(width: 12),
              Expanded(child: _field('Страна', _country)),
            ],
          ),
          _field('График', _type),
          _field('Описание', _desc, lines: 3),

          const SizedBox(height: 16),
          const Text('Зарплата', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(child: _field('Сумма', _salaryAmount, number: true)),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _salaryCurrency,
                items: const ['EUR', 'USD', 'GBP', 'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'UAH']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _salaryCurrency = v ?? 'EUR'),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _salaryPeriod,
                items: const [
                  DropdownMenuItem(value: 'hour', child: Text('в час')),
                  DropdownMenuItem(value: 'day', child: Text('в день')),
                  DropdownMenuItem(value: 'month', child: Text('в месяц')),
                ],
                onChanged: (v) => setState(() => _salaryPeriod = v ?? 'day'),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),

          SwitchListTile(
            value: _urgent,
            onChanged: (v) => setState(() => _urgent = v),
            title: const Text('Приоритет', style: TextStyle(fontWeight: FontWeight.w800)),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _housing,
            onChanged: (v) => setState(() => _housing = v),
            title: const Text('Жильё', style: TextStyle(fontWeight: FontWeight.w800)),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _transport,
            onChanged: (v) => setState(() => _transport = v),
            title: const Text('Развозка', style: TextStyle(fontWeight: FontWeight.w800)),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _teen,
            onChanged: (v) => setState(() => _teen = v),
            title: const Text('Подходит подросткам', style: TextStyle(fontWeight: FontWeight.w800)),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _disability,
            onChanged: (v) => setState(() => _disability = v),
            title: const Text('Подходит для инвалидов', style: TextStyle(fontWeight: FontWeight.w800)),
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _createJob,
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.orange,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Создать в Firestore', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: WorkaColors.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_result!, style: const TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {int lines = 1, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: lines,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WorkaColors.fieldBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WorkaColors.blue, width: 2),
          ),
        ),
      ),
    );
  }
}
