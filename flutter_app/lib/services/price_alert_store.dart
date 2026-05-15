import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PriceAlert {
  PriceAlert({
    required this.symbol,
    required this.targetPrice,
    required this.alertAbove,
    this.triggered = false,
  });

  final String symbol;
  final double targetPrice;
  final bool alertAbove;
  bool triggered;

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'target': targetPrice,
        'above': alertAbove,
        'triggered': triggered,
      };

  static PriceAlert fromJson(Map<String, dynamic> j) => PriceAlert(
        symbol: '${j['symbol']}',
        targetPrice: (j['target'] as num).toDouble(),
        alertAbove: j['above'] == true,
        triggered: j['triggered'] == true,
      );
}

class PriceAlertStore {
  static const _key = 'idx_price_alerts';

  Future<List<PriceAlert>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => PriceAlert.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<PriceAlert> alerts) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(alerts.map((a) => a.toJson()).toList()));
  }

  Future<void> add(PriceAlert alert) async {
    final list = await load();
    list.add(alert);
    await save(list);
  }
}
