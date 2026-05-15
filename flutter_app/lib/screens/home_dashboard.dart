import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/price_alert_store.dart';
import '../services/stock_api.dart';
import '../services/watchlist_store.dart';
import '../theme/app_theme.dart';
import '../utils/ticker_utils.dart';
import '../widgets/stock_logo_avatar.dart';
import '../widgets/stock_quote_tile.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({
    super.key,
    required this.api,
    required this.onSymbolChanged,
    required this.onOpenAnalysis,
    required this.onNotifications,
  });

  final StockApi api;
  final void Function(String symbol) onSymbolChanged;
  final void Function(String symbol) onOpenAnalysis;
  final void Function(List<String> messages) onNotifications;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> with AutomaticKeepAliveClientMixin {
  final _watchlist = WatchlistStore();
  final _alerts = PriceAlertStore();
  bool _loading = false;
  bool _chartLoading = false;
  String? _error;
  String _selected = 'BBCA';

  @override
  bool get wantKeepAlive => true;
  List<String> _symbols = [];
  final Map<String, Map<String, dynamic>> _quotes = {};
  Map<String, dynamic>? _movers;
  Map<String, dynamic>? _history;
  String _chartPeriod = '6mo';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _selectSymbolForChart(String code) async {
    final c = normalizeTicker(code);
    if (c.isEmpty) return;
    setState(() {
      _selected = c;
      _chartLoading = true;
      _error = null;
    });
    widget.onSymbolChanged(c);
    try {
      final hist = await widget.api.getHistory(c, period: _chartPeriod);
      if (!mounted) return;
      setState(() {
        _history = hist;
        _chartLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chartLoading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = _quotes.isEmpty;
      _error = null;
    });
    try {
      final symbols = await _watchlist.load();
      final movers = await widget.api.getMarketMovers(limit: 5);
      final quotes = <String, Map<String, dynamic>>{};
      for (final s in symbols) {
        try {
          quotes[s] = await widget.api.getQuote(s);
        } catch (_) {}
      }
      if (!symbols.contains(_selected) && symbols.isNotEmpty) {
        _selected = symbols.first;
      }
      final hist = await widget.api.getHistory(_selected, period: _chartPeriod);
      final notif = await _evaluateAlerts(quotes);
      if (!mounted) return;
      setState(() {
        _symbols = symbols;
        _quotes
          ..clear()
          ..addAll(quotes);
        _movers = movers;
        _history = hist;
        _loading = false;
      });
      widget.onNotifications(notif);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<List<String>> _evaluateAlerts(Map<String, Map<String, dynamic>> quotes) async {
    final list = await _alerts.load();
    final messages = <String>[];
    for (final a in list) {
      if (a.triggered) continue;
      final q = quotes[a.symbol];
      final p = (q?['last_price'] as num?)?.toDouble();
      if (p == null) continue;
      final hit = a.alertAbove ? p >= a.targetPrice : p <= a.targetPrice;
      if (hit) {
        a.triggered = true;
        messages.add(
          '${a.symbol}: harga ${p.toStringAsFixed(0)} '
          '${a.alertAbove ? '≥' : '≤'} target ${a.targetPrice.toStringAsFixed(0)}',
        );
      }
    }
    await _alerts.save(list);
    return messages;
  }

  Future<void> _addWatchlist() async {
    final ctrl = TextEditingController();
    final s = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah watchlist'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Kode saham', hintText: 'BBCA'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, normalizeTicker(ctrl.text)),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (s != null && s.isNotEmpty) {
      await _watchlist.add(s);
      await _refresh();
    }
  }

  Future<void> _addPriceAlert() async {
    final priceCtrl = TextEditingController();
    var above = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Alert harga $_selected'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target harga (IDR)'),
              ),
              SwitchListTile(
                title: const Text('Alert saat harga di atas target'),
                value: above,
                onChanged: (v) => setD(() => above = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                final t = double.tryParse(priceCtrl.text.replaceAll(',', ''));
                if (t != null) {
                  await _alerts.add(
                    PriceAlert(symbol: _selected, targetPrice: t, alertAbove: above),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _quotes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final gainers = (_movers?['gainers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final losers = (_movers?['losers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rows = (_history?['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Dashboard IDX', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                if (_loading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
                FilledButton.icon(
                  onPressed: _addPriceAlert,
                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                  label: const Text('Alert harga'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 900;
                return Flex(
                  direction: wide ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: wide ? 2 : 0,
                      child: Column(
                        children: [
                          _buildHighlightCards(),
                          const SizedBox(height: 16),
                          _buildChartCard(rows, chartLoading: _chartLoading),
                        ],
                      ),
                    ),
                    SizedBox(width: wide ? 16 : 0, height: wide ? 0 : 16),
                    Expanded(
                      flex: wide ? 1 : 0,
                      child: Column(
                        children: [
                          _moversCard('Top Gainer', gainers, AppColors.success),
                          const SizedBox(height: 12),
                          _moversCard('Top Loser', losers, AppColors.danger),
                          const SizedBox(height: 12),
                          _watchlistCard(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightCards() {
    final show = _symbols.take(4).toList();
    if (show.isEmpty) show.addAll(['BBCA', 'TLKM']);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: show.map((code) {
        final q = _quotes[code];
        final selected = code == _selected;
        return SizedBox(
          width: 200,
          child: Card(
            color: selected ? AppColors.primaryLight : AppColors.cardBg,
            child: InkWell(
              onTap: () => _selectSymbolForChart(code),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StockLogoAvatar(api: widget.api, code: code, radius: 16),
                        const SizedBox(width: 8),
                        Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (q?['last_price'] as num?)?.toStringAsFixed(0) ?? '—',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${(q?['change_percent'] as num?) != null ? '${q!['change_percent']}%': '—'}',
                      style: TextStyle(
                        color: ((q?['change_percent'] as num?) ?? 0) >= 0
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChartCard(List<Map<String, dynamic>> rows, {bool chartLoading = false}) {
    final spots = <FlSpot>[];
    for (var i = 0; i < rows.length; i++) {
      final c = (rows[i]['close'] as num?)?.toDouble();
      if (c != null) spots.add(FlSpot(i.toDouble(), c));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Performa $_selected', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(width: 8),
                if (_chartLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => widget.onOpenAnalysis(_selected),
                  child: const Text('Analisis & ML'),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '3mo', label: Text('3B')),
                    ButtonSegment(value: '6mo', label: Text('6B')),
                    ButtonSegment(value: '1y', label: Text('1Y')),
                    ButtonSegment(value: '2y', label: Text('2Y')),
                  ],
                  selected: {_chartPeriod},
                  onSelectionChanged: (s) async {
                    final p = s.first;
                    setState(() => _chartPeriod = p);
                    await _selectSymbolForChart(_selected);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: spots.length < 2 && !chartLoading
                  ? const Center(child: Text('Klik kode saham untuk menampilkan grafik'))
                  : Stack(
                      children: [
                        if (spots.length >= 2)
                          LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: true),
                              borderData: FlBorderData(show: false),
                              titlesData: const FlTitlesData(
                                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  color: AppColors.primary,
                                  barWidth: 2.5,
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                  ),
                                  dotData: const FlDotData(show: false),
                                ),
                              ],
                            ),
                          ),
                        if (chartLoading)
                          const ColoredBox(
                            color: Color(0x88F8FAFC),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'O:${rows.last['open']}  H:${rows.last['high']}  L:${rows.last['low']}  '
                'C:${rows.last['close']}  Vol:${rows.last['volume']}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _moversCard(String title, List<Map<String, dynamic>> items, Color accent) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: accent),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(),
            if (items.isEmpty)
              const Text('Belum ada data', style: TextStyle(color: AppColors.textMuted))
            else
              ...items.map((e) {
                final code = '${e['code'] ?? e['symbol']}';
                return StockQuoteTile(
                  api: widget.api,
                  code: code.replaceAll('.JK', ''),
                  price: (e['last_price'] as num?)?.toDouble(),
                  changePercent: (e['change_percent'] as num?)?.toDouble(),
                  onTap: () => _selectSymbolForChart(code.replaceAll('.JK', '')),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _watchlistCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Watchlist', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addWatchlist,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            const Divider(),
            ..._symbols.map((code) {
              final q = _quotes[code];
              return StockQuoteTile(
                api: widget.api,
                code: code,
                price: (q?['last_price'] as num?)?.toDouble(),
                changePercent: (q?['change_percent'] as num?)?.toDouble(),
                onTap: () => _selectSymbolForChart(code),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    await _watchlist.remove(code);
                    await _refresh();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
