import 'package:flutter/material.dart';

import '../services/stock_api.dart';
import '../theme/app_theme.dart';
import '../utils/ticker_utils.dart';
import 'home_dashboard.dart';
import 'stock_dashboard.dart';

enum NavItem { dashboard, analysis, live }

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, required this.api});

  final StockApi api;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  NavItem _nav = NavItem.dashboard;
  final _symbolNotifier = ValueNotifier<String>('BBCA');
  final _analysisLoadTrigger = ValueNotifier<int>(0);
  final _baseUrlCtrl = TextEditingController();
  final List<String> _notifications = [];

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl.text = widget.api.baseUrl;
    _pages = [
      HomeDashboard(
        key: const PageStorageKey('idx_home'),
        api: widget.api,
        onSymbolChanged: (s) => _symbolNotifier.value = s,
        onOpenAnalysis: (s) {
          _symbolNotifier.value = s;
          _analysisLoadTrigger.value++;
          setState(() => _nav = NavItem.analysis);
        },
        onNotifications: (msgs) {
          if (msgs.isEmpty) return;
          setState(() => _notifications.insertAll(0, msgs));
        },
      ),
      StockDashboard(
        key: const PageStorageKey('idx_analysis'),
        api: widget.api,
        symbolListenable: _symbolNotifier,
        loadTrigger: _analysisLoadTrigger,
        embedded: true,
      ),
      StockDashboard(
        key: const PageStorageKey('idx_live'),
        api: widget.api,
        symbolListenable: _symbolNotifier,
        embedded: true,
        initialTab: 4,
      ),
    ];
  }

  @override
  void dispose() {
    _symbolNotifier.dispose();
    _analysisLoadTrigger.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  void _goAnalysis(String s) {
    _symbolNotifier.value = s;
    _analysisLoadTrigger.value++;
    setState(() => _nav = NavItem.analysis);
  }

  StockApi _api() {
    final b = _baseUrlCtrl.text.trim();
    return b.isEmpty ? widget.api : StockApi(baseUrl: normalizeApiBaseUrl(b));
  }

  void _showNotifications() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notifikasi harga'),
        content: SizedBox(
          width: 400,
          child: _notifications.isEmpty
              ? const Text('Belum ada alert terpicu. Buat alert dari Dashboard.')
              : ListView(
                  shrinkWrap: true,
                  children: _notifications
                      .map((m) => ListTile(
                            leading: const Icon(Icons.notifications, color: AppColors.primary),
                            title: Text(m),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            selected: _nav,
            onSelect: (n) => setState(() => _nav = n),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  symbol: _symbolNotifier.value,
                  baseUrlCtrl: _baseUrlCtrl,
                  notificationCount: _notifications.length,
                  onSearch: _goAnalysis,
                  onBell: _showNotifications,
                  onSettings: () async {
                    final ok = await _api().health();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('API: ${ok['status']}')),
                    );
                  },
                ),
                Expanded(
                  child: IndexedStack(
                    index: _nav.index,
                    children: _pages,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});

  final NavItem selected;
  final ValueChanged<NavItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.candlestick_chart, color: AppColors.primary, size: 28),
                SizedBox(width: 10),
                Text(
                  'IDX Stock ML',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('MENU', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
          _NavTile(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            active: selected == NavItem.dashboard,
            onTap: () => onSelect(NavItem.dashboard),
          ),
          _NavTile(
            icon: Icons.analytics_outlined,
            label: 'Analisis & ML',
            active: selected == NavItem.analysis,
            onTap: () => onSelect(NavItem.analysis),
          ),
          _NavTile(
            icon: Icons.bolt_outlined,
            label: 'Live ticks',
            active: selected == NavItem.live,
            onTap: () => onSelect(NavItem.live),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Data: Yahoo (tunda). Bukan saran investasi.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(icon, color: active ? AppColors.primary : AppColors.textMuted),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? AppColors.primary : const Color(0xFF334155),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: active ? AppColors.primaryLight : null,
        onTap: onTap,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.symbol,
    required this.baseUrlCtrl,
    required this.notificationCount,
    required this.onSearch,
    required this.onBell,
    required this.onSettings,
  });

  final String symbol;
  final TextEditingController baseUrlCtrl;
  final int notificationCount;
  final ValueChanged<String> onSearch;
  final VoidCallback onBell;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('search_$symbol'),
              controller: TextEditingController(text: symbol),
              decoration: InputDecoration(
                hintText: 'Cari kode saham (BBCA, TLKM)...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.pageBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onSubmitted: (v) {
                final s = normalizeTicker(v);
                if (s.isNotEmpty) onSearch(s);
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: TextField(
              controller: baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'API URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(onPressed: onSettings, icon: const Icon(Icons.link)),
          Badge(
            isLabelVisible: notificationCount > 0,
            label: Text('$notificationCount'),
            child: IconButton(onPressed: onBell, icon: const Icon(Icons.notifications_outlined)),
          ),
        ],
      ),
    );
  }
}
