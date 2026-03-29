import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExchangeRateService {
  static const _prefsKey = 'worka_fx_rates_to_eur_v1';

  /// курс 1 [currency] → EUR (сколько EUR за 1 единицу валюты)
  static Future<double?> rateToEur(String currency) async {
    final c = currency.toUpperCase().trim();
    if (c == 'EUR') return 1.0;

    final online = await _fetchOnline(c);
    if (online != null) {
      await _saveCached(c, online);
      return online;
    }

    return _loadCached(c);
  }

  static Future<double?> _fetchOnline(String currency) async {
    try {
      // base=EUR => rates[currency] = сколько currency за 1 EUR
      // нам нужно наоборот: EUR за 1 currency => 1 / rate
      final uri = Uri.parse('https://api.exchangerate.host/latest?base=EUR&symbols=$currency');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final rates = (json['rates'] as Map?)?.cast<String, dynamic>();
      final r = rates?[currency];
      if (r == null) return null;

      final eurToCur = (r as num).toDouble();
      if (eurToCur <= 0) return null;

      return 1.0 / eurToCur;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCached(String currency, double rateToEur) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey) ?? '{}';
    final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
    data[currency] = rateToEur;
    await prefs.setString(_prefsKey, jsonEncode(data));
  }

  static Future<double?> _loadCached(String currency) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;

      final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final v = data[currency];
      if (v == null) return null;

      return (v as num).toDouble();
    } catch (_) {
      return null;
    }
  }
}
