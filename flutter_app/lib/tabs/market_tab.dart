import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../providers/quiz_provider.dart';
import '../screens/ticker_detail_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/xai_explanation_sheet.dart';

/// Factor progress bar widget with interactive tap action for SHAP attribution inspection
class FactorProgressBar extends StatelessWidget {
  final FactorImpact factor;
  final bool isDarkMode;
  final VoidCallback onTap;

  const FactorProgressBar({
    super.key,
    required this.factor,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: factor.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        factor.code,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: factor.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          factor.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDarkMode
                                ? Colors.white
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        Text(
                          'SHAP Vector',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: isDarkMode
                                ? Colors.white38
                                : AppColors.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      factor.weight,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: factor.color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      AppIcons.info,
                      size: 15,
                      color: isDarkMode
                          ? Colors.white38
                          : AppColors.lightTextMuted,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: factor.percentage,
                minHeight: 8,
                backgroundColor:
                    isDarkMode ? Colors.white12 : AppColors.lightBorder,
                valueColor: AlwaysStoppedAnimation<Color>(factor.color),
              ),
            ),
          ],
        ),
      ),
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
    final mutedColor = isDark ? Colors.white54 : AppColors.lightTextMuted;

    final List<FactorImpact> factors = quizProvider.factorImpacts;
    final List<MarketAsset> assets = quizProvider.marketAssets;

    return RefreshIndicator(
      onRefresh: () => quizProvider.refreshMarketData(),
      color: AppColors.emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
        children: [
          // ── Section 1: Influence Vectors ──────────────────────────────────
          Text(
            'INFLUENCE VECTORS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: mutedColor,
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
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withOpacity(0.5)
                  : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark ? Colors.white12 : AppColors.lightBorder,
                width: 2,
              ),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...factors.map(
                  (f) => FactorProgressBar(
                    factor: f,
                    isDarkMode: isDark,
                    onTap: () {
                      showFactorExplanationSheet(
                        context,
                        factor: f,
                        userLevel: quizProvider.userLevel,
                        isDarkMode: isDark,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Divider(
                  color: isDark ? Colors.white12 : AppColors.lightBorder,
                  height: 1,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.touch_app_rounded,
                        size: 13, color: AppColors.emerald),
                    const SizedBox(width: 6),
                    Text(
                      'Tap any factor bar to inspect XAI attribution mechanics',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Section 2: Market Stock Rows ──────────────────────────────────
          Text(
            'MARKET SIGNALS & ASSETS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: mutedColor,
            ),
          ),
          Text(
            'Tracked Stock Assets',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: textColor,
            ),
          ),
          const SizedBox(height: 16),

          if (assets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: quizProvider.isLoadingAssets
                    ? const CircularProgressIndicator(color: AppColors.emerald)
                    : Text(
                        'No market assets available. Pull down to refresh.',
                        style: TextStyle(fontSize: 12, color: mutedColor),
                      ),
              ),
            ),

          ...assets.map((item) {
            final Color badgeColor = item.statusColor;
            final sentimentColor = item.numericSentiment > 0
                ? AppColors.emerald
                : item.numericSentiment < 0
                    ? AppColors.rose
                    : mutedColor;

            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TickerDetailScreen(ticker: item.ticker),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface.withOpacity(0.5)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark ? Colors.white12 : AppColors.lightBorder,
                    width: 2,
                  ),
                  boxShadow: isDark
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.black38
                                    : AppColors.lightTextPrimary,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                item.ticker,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: badgeColor.withOpacity(0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                item.status,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(AppIcons.info, size: 20),
                          color: mutedColor,
                          onPressed: () {
                            showXaiExplanationSheet(
                              context,
                              ticker: item.ticker,
                              isDarkMode: isDark,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CONFIDENCE',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: isDark
                                        ? Colors.white38
                                        : AppColors.lightTextMuted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.confidence,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SENTIMENT',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: isDark
                                        ? Colors.white38
                                        : AppColors.lightTextMuted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.sentiment,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: sentimentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.insights_rounded,
                                size: 13, color: AppColors.emerald),
                            const SizedBox(width: 6),
                            Text(
                              'FACTOR VECTORS & PREDICTION',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                color: mutedColor,
                              ),
                            ),
                          ],
                        ),
                        const Row(
                          children: [
                            Text(
                              'VIEW DETAIL',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                color: AppColors.emerald,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios_rounded,
                                size: 9, color: AppColors.emerald),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
