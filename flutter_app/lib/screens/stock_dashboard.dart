import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/stock_api.dart';
import '../utils/ticker_input_formatter.dart';
import '../utils/ticker_utils.dart';

class StockDashboard extends StatefulWidget {
  const StockDashboard({
    super.key,
    required this.api,
    this.initialSymbol,
    this.symbolListenable,
    this.loadTrigger,
    this.embedded = false,
    this.initialTab = 0,
  });

  final StockApi api;
  final String? initialSymbol;
  final ValueListenable<String>? symbolListenable;
  final ValueListenable<int>? loadTrigger;
  final bool embedded;
  final int initialTab;

  @override
  State<StockDashboard> createState() => _StockDashboardState();
}

class _StockDashboardState extends State<StockDashboard> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabs;
  late final FocusNode _symbolFocus;
  final _symbolCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _inferOnly = false;
  bool _saveAfterTrain = false;
  bool _hasLoadedOnce = false;

  @override
  bool get wantKeepAlive => widget.embedded;

  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _history;
  Map<String, dynamic>? _fundamental;
  Map<String, dynamic>? _technical;
  Map<String, dynamic>? _predict;
  Map<String, dynamic>? _artifacts;

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab.clamp(0, 4);
    _tabs = TabController(length: 5, vsync: this, initialIndex: tab);
    _symbolFocus = FocusNode();
    if (widget.initialSymbol != null && widget.initialSymbol!.isNotEmpty) {
      _symbolCtrl.text = normalizeTicker(widget.initialSymbol!);
    }
    _symbolCtrl.addListener(_onSymbolChanged);
    _symbolFocus.addListener(() {
      if (!_symbolFocus.hasFocus) {
        _normalizeSymbolField();
      }
    });
    _baseUrlCtrl.text = normalizeApiBaseUrl(widget.api.baseUrl);
    widget.symbolListenable?.addListener(_onExternalSymbol);
    widget.loadTrigger?.addListener(_onLoadTrigger);
  }

  void _onExternalSymbol() {
    final s = widget.symbolListenable?.value;
    if (s == null || s.isEmpty) return;
    final n = normalizeTicker(s);
    if (n != normalizeTicker(_symbolCtrl.text)) {
      _symbolCtrl.text = n;
    }
  }

  void _onLoadTrigger() {
    final s = widget.symbolListenable?.value ?? widget.initialSymbol;
    if (s != null && s.isNotEmpty) {
      _symbolCtrl.text = normalizeTicker(s);
      _loadAll();
    }
  }

  @override
  void didUpdateWidget(StockDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sym = widget.initialSymbol;
    if (sym != null &&
        sym.isNotEmpty &&
        sym != oldWidget.initialSymbol &&
        normalizeTicker(sym) != normalizeTicker(_symbolCtrl.text)) {
      _symbolCtrl.text = normalizeTicker(sym);
      _loadAll();
    }
  }

  @override
  void dispose() {
    widget.symbolListenable?.removeListener(_onExternalSymbol);
    widget.loadTrigger?.removeListener(_onLoadTrigger);
    _symbolCtrl.removeListener(_onSymbolChanged);
    _symbolFocus.dispose();
    _tabs.dispose();
    _symbolCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  StockApi _apiFromField() {
    final b = _baseUrlCtrl.text.trim();
    if (b.isEmpty) return StockApi();
    return StockApi(baseUrl: normalizeApiBaseUrl(b));
  }

  void _normalizeSymbolField() {
    final n = normalizeTicker(_symbolCtrl.text);
    if (n.isEmpty) return;
    if (n != _symbolCtrl.text) {
      _symbolCtrl.value = canonicalTickerValue(_symbolCtrl.text);
      setState(() {});
    }
  }

  bool _symbolSanitizing = false;

  void _onSymbolChanged() {
    if (_symbolSanitizing) return;
    final raw = _symbolCtrl.text;
    final n = normalizeTicker(raw);
    if (n == raw) return;
    _symbolSanitizing = true;
    try {
      _symbolCtrl.value = TextEditingValue(
        text: n,
        selection: TextSelection.collapsed(offset: n.length),
      );
    } finally {
      _symbolSanitizing = false;
    }
  }

  Future<void> _testConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = _apiFromField();
    try {
      final h = await api.health();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('API OK: ${h['status'] ?? h}')),
      );
      _baseUrlCtrl.text = api.baseUrl;
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_humanizeRequestError(e)),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = !_hasLoadedOnce;
      _error = null;
    });
    final sym = normalizeTicker(_symbolCtrl.text);
    if (sym.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Isi kode saham (contoh: BBCA, BUMI, IHSG).';
      });
      return;
    }
    _symbolCtrl.text = sym;
    _symbolCtrl.selection = TextSelection.collapsed(offset: sym.length);
    final bt = _baseUrlCtrl.text.trim();
    if (bt.isNotEmpty) {
      final nb = normalizeApiBaseUrl(bt);
      if (nb != bt) _baseUrlCtrl.text = nb;
    }
    final api = _apiFromField();
    try {
      final results = await Future.wait([
        api.getQuote(sym),
        api.getHistory(sym),
        api.getFundamental(sym),
        api.getTechnical(sym),
        api.getArtifacts(sym),
        api.predict(
          sym,
          train: !_inferOnly,
          save: _saveAfterTrain && !_inferOnly,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _quote = results[0] as Map<String, dynamic>;
        _history = results[1] as Map<String, dynamic>;
        _fundamental = results[2] as Map<String, dynamic>;
        _technical = results[3] as Map<String, dynamic>;
        _artifacts = results[4] as Map<String, dynamic>;
        _predict = results[5] as Map<String, dynamic>;
        _loading = false;
        _hasLoadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _humanizeRequestError(e);
      });
    }
  }

  String _humanizeRequestError(Object e) {
    final s = e.toString();
    if (s.contains('Failed to fetch') ||
        s.contains('SocketException') ||
        s.contains('Connection refused') ||
        s.contains('ClientException')) {
      return 'Tidak bisa menghubungi API ($s).\n\n'
          'Periksa:\n'
          '• Backend jalan di folder backend:\n'
          '  .\\.venv\\Scripts\\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000\n'
          '• URL benar (Web: http://127.0.0.1:8000 — tanpa slash di akhir)\n'
          '• Gunakan tombol "Tes koneksi API" di bawah\n'
          '• Firewall tidak memblokir port 8000';
    }
    if (s.contains('404') && _inferOnly) {
      return '$s\n\nModel tersimpan belum ada: matikan "Fast infer", '
          'centang "Save models after training", lalu Load sekali untuk melatih & menyimpan.';
    }
    if (s.contains('No data returned') || s.contains('No quote history')) {
      return '$s\n\n'
          'Data tidak ditemukan di Yahoo untuk simbol ini. '
          'Coba BBCA atau BMRI; pastikan backend sudah di-restart setelah update. '
          'Periksa koneksi internet (Yahoo kadang menolak request tanpa retry).';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      super.build(context);
    }
    final cs = Theme.of(context).colorScheme;
    final body = Column(
        children: [
          if (!widget.embedded)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _symbolCtrl,
                    focusNode: _symbolFocus,
                    autocorrect: false,
                    enableSuggestions: false,
                    onEditingComplete: _normalizeSymbolField,
                    onSubmitted: (_) => _normalizeSymbolField(),
                    decoration: const InputDecoration(
                      labelText: 'Kode saham',
                      hintText: 'BBCA',
                      helperText: 'Hanya huruf A–Z (contoh: BBCA, TLKM, IHSG)',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [TickerInputFormatter()],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API base URL',
                      border: OutlineInputBorder(),
                      helperText:
                          'Web/Chrome: http://127.0.0.1:8000 — Android emulator: http://10.0.2.2:8000 — HP: IP LAN PC Anda',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _testConnection,
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Tes koneksi API (/health)'),
                    ),
                  ),
                  const SizedBox(height: 4),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fast infer (saved models only, no training)'),
                  value: _inferOnly,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() {
                            _inferOnly = v ?? false;
                            if (_inferOnly) _saveAfterTrain = false;
                          }),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Save models after training (for fast infer later)'),
                  value: _saveAfterTrain,
                  onChanged: _loading || _inferOnly
                      ? null
                      : (v) => setState(() => _saveAfterTrain = v ?? false),
                ),
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: _loading ? null : _loadAll,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_download),
                  label: Text(_loading ? 'Loading…' : 'Load quote, studies & ML'),
                ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        _error!,
                        style: TextStyle(color: cs.error, fontSize: 13, height: 1.35),
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Analisis: ${_symbolCtrl.text.isEmpty ? "—" : _symbolCtrl.text}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : _loadAll,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download),
                    label: Text(_loading ? 'Loading…' : 'Load'),
                  ),
                ],
              ),
            ),
          if (widget.embedded && _error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SelectableText(_error!, style: TextStyle(color: cs.error)),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _QuoteTab(quote: _quote, history: _history, artifacts: _artifacts),
                _FundamentalTab(data: _fundamental),
                _TechnicalTab(data: _technical),
                _MlTab(data: _predict),
                _LiveTicksTab(symbolController: _symbolCtrl, baseUrlController: _baseUrlCtrl),
              ],
            ),
          ),
        ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Quote'),
                Tab(text: 'Fundamental'),
                Tab(text: 'Technical'),
                Tab(text: 'ML'),
                Tab(text: 'Live'),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('IDX Stock ML'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Quote'),
            Tab(text: 'Fundamental'),
            Tab(text: 'Technical'),
            Tab(text: 'ML'),
            Tab(text: 'Live'),
          ],
        ),
      ),
      body: body,
    );
  }
}

class _QuoteTab extends StatelessWidget {
  const _QuoteTab({this.quote, this.history, this.artifacts});

  final Map<String, dynamic>? quote;
  final Map<String, dynamic>? history;
  final Map<String, dynamic>? artifacts;

  @override
  Widget build(BuildContext context) {
    if (quote == null && history == null && artifacts == null) {
      return const Center(child: Text('Load data to see Open / High / Low / Close / Volume.'));
    }
    final rows = (history?['rows'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (artifacts != null) ...[
          Text(
            'Saved models: ${artifacts!['artifacts_exist'] == true ? 'yes' : 'no'}  (${artifacts!['path']})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (quote != null) ...[
          Text('${quote!['symbol']}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _kv('Last (close)', quote!['last_price']),
          _kv('Change %', quote!['change_percent']),
          _kv('Open', quote!['open']),
          _kv('High', quote!['high']),
          _kv('Low', quote!['low']),
          _kv('Volume', quote!['volume']),
          const Divider(height: 32),
        ],
        Text('Recent OHLCV', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (rows.length >= 2)
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (rows.length - 1).toDouble(),
                gridData: const FlGridData(show: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: (rows.length / 5).ceilToDouble().clamp(1, 999),
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                        final d = rows[i]['date']?.toString() ?? '';
                        return Text(d.length >= 10 ? d.substring(5, 10) : d, style: const TextStyle(fontSize: 9));
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, m) =>
                          Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 9)),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < rows.length; i++)
                        FlSpot(i.toDouble(), (rows[i]['close'] as num?)?.toDouble() ?? 0),
                    ],
                    isCurved: true,
                    color: Theme.of(context).colorScheme.primary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Open')),
              DataColumn(label: Text('High')),
              DataColumn(label: Text('Low')),
              DataColumn(label: Text('Close')),
              DataColumn(label: Text('Vol')),
            ],
            rows: [
              for (final r in rows.reversed.take(15))
                DataRow(
                  cells: [
                    DataCell(Text('${r['date']}')),
                    DataCell(Text('${r['open']}')),
                    DataCell(Text('${r['high']}')),
                    DataCell(Text('${r['low']}')),
                    DataCell(Text('${r['close']}')),
                    DataCell(Text('${r['volume']}')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, Object? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w500))),
            Expanded(child: Text('$v')),
          ],
        ),
      );
}

class _FundamentalTab extends StatelessWidget {
  const _FundamentalTab({this.data});
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) return const Center(child: Text('No fundamental data.'));
    final notes = (data!['interpretation_notes'] as List?)?.cast<String>() ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${data!['name'] ?? data!['symbol']}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _r('Sector', data!['sector']),
        _r('Industry', data!['industry']),
        _r('Market cap', data!['market_cap']),
        _r('Trailing P/E', data!['trailing_pe']),
        _r('Forward P/E', data!['forward_pe']),
        _r('P/B', data!['price_to_book']),
        _r('Div. yield %', data!['dividend_yield_percent']),
        _r('52w high', data!['fifty_two_week_high']),
        _r('52w low', data!['fifty_two_week_low']),
        if (notes.isNotEmpty) ...[
          const Divider(height: 24),
          Text('Notes', style: Theme.of(context).textTheme.titleMedium),
          for (final n in notes) ListTile(dense: true, leading: const Icon(Icons.info_outline), title: Text(n)),
        ],
      ],
    );
  }

  Widget _r(String k, Object? v) => ListTile(title: Text(k), subtitle: Text('$v'));
}

class _TechnicalTab extends StatelessWidget {
  const _TechnicalTab({this.data});
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) return const Center(child: Text('No technical data.'));
    final recent = (data!['recent_ohlcv_indicators'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${data!['symbol']}', style: Theme.of(context).textTheme.titleLarge),
        _r('Last close', data!['last_close']),
        _r('RSI(14)', data!['rsi14']),
        _r('RSI signal', data!['rsi_signal']),
        _r('MACD', data!['macd']),
        _r('MACD signal', data!['macd_signal']),
        _r('SMA20', data!['sma20']),
        _r('SMA50', data!['sma50']),
        _r('MA trend', data!['ma_cross_trend']),
        const Divider(height: 24),
        Text('Recent bars + indicators', style: Theme.of(context).textTheme.titleMedium),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Close')),
              DataColumn(label: Text('RSI')),
              DataColumn(label: Text('SMA20')),
              DataColumn(label: Text('SMA50')),
            ],
            rows: [
              for (final r in recent.reversed.take(12))
                DataRow(
                  cells: [
                    DataCell(Text('${r['date']}')),
                    DataCell(Text('${r['close']}')),
                    DataCell(Text('${r['rsi14']}')),
                    DataCell(Text('${r['sma20']}')),
                    DataCell(Text('${r['sma50']}')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _r(String k, Object? v) => ListTile(title: Text(k), subtitle: Text('$v'));
}

class _MlTab extends StatelessWidget {
  const _MlTab({this.data});
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) return const Center(child: Text('Run load to train models and predict next close.'));
    final models = (data!['models'] as Map?)?.cast<String, dynamic>() ?? {};
    final ens = data!['ensemble_next_close'];
    final last = (data!['last_row_features'] as Map?)?.cast<String, dynamic>();
    final disc = data!['disclaimer']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          "${data!['symbol']} — next close forecasts${data!['mode'] != null ? ' (${data!['mode']})' : ''}",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (last != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Last bar: O=${last['open']} H=${last['high']} L=${last['low']} '
              'C=${last['close']} V=${last['volume']}',
            ),
          ),
        if (ens != null) ListTile(title: const Text('Ensemble (mean)'), subtitle: Text('$ens')),
        const Divider(),
        for (final e in models.entries)
          Card(
            child: ListTile(
              title: Text(e.key.replaceAll('_', ' ')),
              subtitle: Text(_modelSubtitle(e.value)),
              isThreeLine: true,
            ),
          ),
        const SizedBox(height: 12),
        Text(disc, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  String _modelSubtitle(dynamic v) {
    if (v is! Map) return '$v';
    if (v['error'] != null) return '${v['error']}';
    final p = v['next_close_prediction'];
    final m = v['test_metrics'];
    if (m is Map) {
      return 'Predicted next close: $p\nTest MAE: ${m['mae']}  RMSE: ${m['rmse']}';
    }
    return 'Predicted next close: $p';
  }
}

class _LiveTicksTab extends StatefulWidget {
  const _LiveTicksTab({required this.symbolController, required this.baseUrlController});

  final TextEditingController symbolController;
  final TextEditingController baseUrlController;

  @override
  State<_LiveTicksTab> createState() => _LiveTicksTabState();
}

class _LiveTicksTabState extends State<_LiveTicksTab> {
  String _source = 'delayed_yfinance';
  WebSocketChannel? _channel;
  final _lines = <String>[];
  bool _busy = false;

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  void _disconnect() {
    _channel?.sink.close();
    _channel = null;
    setState(() => _busy = false);
  }

  Future<void> _connect() async {
    _disconnect();
    final sym = normalizeTicker(widget.symbolController.text);
    if (sym.isEmpty) {
      setState(() => _lines.insert(0, 'Isi kode saham di atas (contoh: BBCA).'));
      return;
    }
    widget.symbolController.text = sym;
    widget.symbolController.selection = TextSelection.collapsed(offset: sym.length);
    final baseTrim = widget.baseUrlController.text.trim();
    final String? apiBase = baseTrim.isEmpty ? null : normalizeApiBaseUrl(baseTrim);
    if (apiBase != null && apiBase != baseTrim) {
      widget.baseUrlController.text = apiBase;
    }
    final api = StockApi(baseUrl: apiBase);
    final uri = Uri.parse(api.wsTicksUrl(sym, source: _source));
    setState(() {
      _busy = true;
      _lines.insert(0, 'Connecting $uri …');
    });
    try {
      final ch = WebSocketChannel.connect(uri);
      _channel = ch;
      ch.stream.listen(
        (msg) {
          if (!mounted) return;
          setState(() {
            final s = msg is String ? msg : '$msg';
            _lines.insert(0, s.length > 500 ? '${s.substring(0, 500)}…' : s);
            if (_lines.length > 80) _lines.removeLast();
          });
        },
        onError: (e) {
          if (!mounted) return;
          final msg = '$e';
          final hint = msg.contains('Failed to connect') || msg.contains('SocketException')
              ? ' — pastikan backend jalan (python -m uvicorn) dan URL benar.'
              : '';
          setState(() => _lines.insert(0, 'Error: $e$hint'));
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _lines.insert(0, '— socket closed —');
          });
        },
      );
      setState(() => _busy = true);
    } catch (e) {
      setState(() {
        _busy = false;
        _lines.insert(0, 'Connect failed: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('WebSocket ticks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'delayed_yfinance: server mengambil kuotasi tunda setiap beberapa detik (demo). '
            'official_relay: hanya jika di server sudah diset IDX_OFFICIAL_WS_URL (feed vendor).',
            style: TextStyle(fontSize: 12),
          ),
          if (_source == 'official_relay') ...[
            const SizedBox(height: 8),
            Material(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'Mode official_relay: tanpa IDX_OFFICIAL_WS_URL di mesin API, stream tidak akan ke feed resmi. '
                  'Untuk uji lokal pilih delayed_yfinance dan pastikan uvicorn aktif.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _source,
            decoration: const InputDecoration(labelText: 'WS source', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'delayed_yfinance', child: Text('delayed_yfinance (demo)')),
              DropdownMenuItem(value: 'official_relay', child: Text('official_relay (vendor URL)')),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _source = v ?? 'delayed_yfinance'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(onPressed: _busy ? null : _connect, child: const Text('Connect')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _disconnect, child: const Text('Disconnect')),
            ],
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _lines.length,
              itemBuilder: (_, i) => SelectableText(_lines[i], style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
