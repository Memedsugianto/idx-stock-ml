import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;

/// Trims and removes a trailing `/` so paths join correctly (avoids `//quote/...`).
String normalizeApiBaseUrl(String raw) {
  var s = raw.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Default API base URL per platform.
///
/// **Web:** `dart:io` / [Platform] are unavailable — use localhost (set manually if API is elsewhere).
/// **Android emulator:** host loopback is `10.0.2.2`. **Physical Android:** use your PC's LAN IP in the app field.
/// **iOS simulator / desktop:** `127.0.0.1`.
String defaultBaseUrl() {
  if (kIsWeb) {
    return 'http://127.0.0.1:8000';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

class StockApiException implements Exception {
  StockApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => 'StockApiException($statusCode): $message';
}

class StockApi {
  StockApi({String? baseUrl})
      : baseUrl = normalizeApiBaseUrl(baseUrl ?? defaultBaseUrl());

  final String baseUrl;

  Uri _u(String path, [Map<String, String>? query]) {
    final u = Uri.parse(baseUrl);
    return u.replace(path: path, queryParameters: query);
  }

  /// WebSocket URL for `/ws/ticks/{symbol}` (delayed polling or official relay).
  String wsTicksUrl(String symbol, {String source = 'delayed_yfinance'}) {
    final b = baseUrl;
    final path = '/ws/ticks/${Uri.encodeComponent(symbol)}';
    final q = 'source=${Uri.encodeQueryComponent(source)}';
    if (b.startsWith('https://')) {
      return 'wss://${b.substring(8)}$path?$q';
    }
    if (b.startsWith('http://')) {
      return 'ws://${b.substring(7)}$path?$q';
    }
    return 'ws://$b$path?$q';
  }

  Future<Map<String, dynamic>> health() async {
    final res = await http.get(_u('/health'));
    return _decode(res);
  }

  Future<Map<String, dynamic>> getMarketMovers({int limit = 5}) async {
    final res = await http.get(_u('/market/movers', {'limit': '$limit'}));
    return _decode(res);
  }

  /// Same-origin logo image (proxied by backend; works on Flutter Web without CORS).
  String logoProxyUrl(String code) {
    final c = code.replaceAll('.JK', '').toUpperCase();
    return '${baseUrl}/logo/${Uri.encodeComponent(c)}';
  }

  Future<Map<String, dynamic>> getQuote(String symbol) async {    final res = await http.get(_u('/quote/${Uri.encodeComponent(symbol)}'));
    return _decode(res);
  }

  Future<Map<String, dynamic>> getHistory(String symbol, {String period = '2y'}) async {
    final res = await http.get(_u('/history/${Uri.encodeComponent(symbol)}', {'period': period}));
    return _decode(res);
  }

  Future<Map<String, dynamic>> getFundamental(String symbol) async {
    final res = await http.get(_u('/analysis/fundamental/${Uri.encodeComponent(symbol)}'));
    return _decode(res);
  }

  Future<Map<String, dynamic>> getTechnical(String symbol, {String period = '2y'}) async {
    final res = await http.get(_u('/analysis/technical/${Uri.encodeComponent(symbol)}', {'period': period}));
    return _decode(res);
  }

  Future<Map<String, dynamic>> getArtifacts(String symbol) async {
    final res = await http.get(_u('/predict/artifacts/${Uri.encodeComponent(symbol)}'));
    return _decode(res);
  }

  /// [train]=false uses saved models only (fast). [save]=true persists after training.
  Future<Map<String, dynamic>> predict(
    String symbol, {
    String period = '2y',
    double testSize = 0.2,
    bool train = true,
    bool save = false,
    int lstmLookback = 20,
    int lstmEpochs = 60,
    int tfEpochs = 80,
  }) async {
    final res = await http.post(
      _u('/predict'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'symbol': symbol,
        'period': period,
        'test_size': testSize,
        'train': train,
        'save': save,
        'lstm_lookback': lstmLookback,
        'lstm_epochs': lstmEpochs,
        'tf_epochs': tfEpochs,
      }),
    );
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var msg = res.body;
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['detail'] != null) msg = m['detail'].toString();
      } catch (_) {}
      throw StockApiException(msg, res.statusCode);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw StockApiException('Invalid JSON object');
    }
    return data;
  }
}
