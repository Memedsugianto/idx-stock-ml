import 'package:flutter/material.dart';

import 'screens/dashboard_shell.dart';
import 'services/stock_api.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IdxStockApp());
}

class IdxStockApp extends StatelessWidget {
  const IdxStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IDX Stock ML',
      theme: buildDashboardTheme(),
      home: DashboardShell(api: StockApi()),
      debugShowCheckedModeBanner: false,
    );
  }
}
