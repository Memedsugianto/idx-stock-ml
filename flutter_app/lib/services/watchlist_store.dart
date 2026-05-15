import 'package:shared_preferences/shared_preferences.dart';

class WatchlistStore {
  static const _key = 'idx_watchlist';

  Future<List<String>> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_key) ?? ['BBCA', 'TLKM', 'BBRI', 'BMRI'];
  }

  Future<void> save(List<String> symbols) async {
    final p = await SharedPreferences.getInstance();
    final clean = symbols.map((s) => s.toUpperCase()).toSet().toList();
    await p.setStringList(_key, clean);
  }

  Future<void> add(String symbol) async {
    final list = await load();
    final s = symbol.toUpperCase();
    if (!list.contains(s)) {
      list.add(s);
      await save(list);
    }
  }

  Future<void> remove(String symbol) async {
    final list = await load();
    list.remove(symbol.toUpperCase());
    await save(list);
  }
}
