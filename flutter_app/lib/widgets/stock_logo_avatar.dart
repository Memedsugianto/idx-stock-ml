import 'package:flutter/material.dart';

import '../services/stock_api.dart';
import '../theme/app_theme.dart';

/// Logo emiten via API proxy `/logo/{code}` (TradingView IDX + Yahoo fallback).
class StockLogoAvatar extends StatelessWidget {
  const StockLogoAvatar({
    super.key,
    required this.api,
    required this.code,
    this.radius = 18,
  });

  final StockApi api;
  final String code;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final clean = code.replaceAll('.JK', '').toUpperCase();
    final url = api.logoProxyUrl(clean);
    final initials = clean.length >= 2 ? clean.substring(0, 2) : clean;

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryLight,
      child: ClipOval(
        child: Image.network(
          url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(
            child: Text(
              initials,
              style: TextStyle(
                fontSize: radius * 0.65,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Center(
              child: SizedBox(
                width: radius,
                height: radius,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        ),
      ),
    );
  }
}
