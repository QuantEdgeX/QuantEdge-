import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../models/app_models.dart';
import '../theme/app_theme.dart';

// Factor progress bar widget for displaying factor impact distribution
class FactorProgressBar extends StatelessWidget {
  final String code;
  final String name;
  final String weight;
  final double pct;
  final Color color;
  final bool isDarkMode;

  const FactorProgressBar({
    super.key,
    required this.code,
    required this.name,
    required this.weight,
    required this.pct,
    required this.color,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        isDarkMode ? Colors.white : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  code,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color:
                        isDarkMode ? Colors.white38 : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
            Text(
              weight,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor:
                isDarkMode ? Colors.white12 : AppColors.lightBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class MarketTab extends StatelessWidget {
  const MarketTab({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    // Dynamic getter subscription
    final List<FactorImpact> factors = quizProvider.factorImpacts;

    return RefreshIndicator(
      onRefresh: () => quizProvider.refreshMarketData(),
      color: AppColors.emerald,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
        children: [
          Text(
            'INFLUENCE VECTORS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: isDark ? Colors.white54 : AppColors.lightTextMuted,
            ),
          ),
          Text(
            'Factor Impact Distribution',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: textColor,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withOpacity(0.5)
                  : Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDark ? Colors.white12 : AppColors.lightBorder,
                width: 2,
              ),
            ),
            child: Column(
              children: factors
                  .map((f) => FactorProgressBar(
                        code: f.code,
                        name: f.name,
                        weight: f.weight,
                        pct: f.percentage,
                        color: f.color,
                        isDarkMode: isDark,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
