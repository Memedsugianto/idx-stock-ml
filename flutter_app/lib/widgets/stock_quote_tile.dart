import 'package:flutter/material.dart';

import '../services/stock_api.dart';
import '../theme/app_theme.dart';
import 'stock_logo_avatar.dart';

class StockQuoteTile extends StatelessWidget {
  const StockQuoteTile({
    super.key,
    required this.api,
    required this.code,
    this.name,
    required this.price,
    this.changePercent,
    this.onTap,
    this.trailing,
  });

  final StockApi api;
  final String code;
  final String? name;
  final double? price;
  final double? changePercent;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ch = changePercent;
    final up = ch != null && ch >= 0;
    final color = ch == null ? AppColors.textMuted : (up ? AppColors.success : AppColors.danger);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            StockLogoAvatar(api: api, code: code, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(code, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (name != null)
                    Text(name!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price != null ? price!.toStringAsFixed(0) : '—',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (ch != null)
                  Text(
                    '${up ? '+' : ''}${ch.toStringAsFixed(2)}%',
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}
