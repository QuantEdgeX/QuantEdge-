import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Both providers declare an `AppTab` enum, so import only what is needed.
import '../providers/learning_provider.dart' show LearningProvider;
import '../providers/quiz_provider.dart' show QuizProvider;
import '../theme/app_theme.dart';
import '../widgets/info_modal_sheet.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  // Same ladder as the backend's SCORE_NAMES (score 1-10).
  static const Map<int, String> _scoreNames = {
    1: 'Newbie',
    2: 'Beginner',
    3: 'Beginner+',
    4: 'Intermediate',
    5: 'Intermediate+',
    6: 'Advanced',
    7: 'Advanced+',
    8: 'Expert',
    9: 'Expert+',
    10: 'Master',
  };

  /// "+$12.30" / "-$7.65"
  static String _signedMoney(double value) {
    final sign = value >= 0 ? '+' : '-';
    return '$sign\$${value.abs().toStringAsFixed(2)}';
  }

  static Color _changeColor(double value) =>
      value >= 0 ? AppColors.emerald : AppColors.rose;

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final learningProvider = context.watch<LearningProvider>();

    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final mutedColor = isDark ? Colors.white54 : AppColors.lightTextMuted;
    final secondaryColor =
        isDark ? Colors.white60 : AppColors.lightTextSecondary;

    final metrics = quizProvider.dashboardMetrics;
    final assets = quizProvider.marketAssets;

    // Real learning stats from the backend; fall back to the dashboard
    // endpoint's numbers until the learning progress has loaded.
    final progress = learningProvider.progress;
    final xpPoints = progress?.xp ?? metrics?.xpPoints ?? 0;
    final learnScore = progress?.score ?? 0;
    final levelLabel = learnScore > 0
        ? (_scoreNames[learnScore] ?? 'Newbie').toUpperCase()
        : 'LEVEL ${quizProvider.userLevel}';

    return RefreshIndicator(
      onRefresh: () => Future.wait([
        quizProvider.refreshAllData(),
        learningProvider.loadLearningData(),
      ]),
      color: AppColors.emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PORTFOLIO OVERVIEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: mutedColor,
                    ),
                  ),
                  Text(
                    'Performance Dashboard',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white12 : AppColors.lightBorder,
                    width: 2,
                  ),
                ),
                child: Text(
                  levelLabel,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppColors.emerald,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Portfolio + learning stats ──────────────────────────────────
          if (quizProvider.isLoadingDashboard && metrics == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: AppColors.emerald),
              ),
            )
          else if (metrics != null) ...[
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
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Portfolio Value',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\$${metrics.portfolioValue.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Change',
                            style: TextStyle(
                              fontSize: 10,
                              color: secondaryColor,
                            ),
                          ),
                          Text(
                            _signedMoney(metrics.dailyChange),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _changeColor(metrics.dailyChange),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Weekly Change',
                            style: TextStyle(
                              fontSize: 10,
                              color: secondaryColor,
                            ),
                          ),
                          Text(
                            _signedMoney(metrics.weeklyChange),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _changeColor(metrics.weeklyChange),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        'XP Points',
                        style: TextStyle(
                          fontSize: 10,
                          color: secondaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$xpPoints',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.emerald,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        'Win Rate',
                        style: TextStyle(
                          fontSize: 10,
                          color: secondaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(metrics.winRate * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.emerald,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        'Next Level',
                        style: TextStyle(
                          fontSize: 10,
                          color: secondaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        metrics.nextLevelMilestone,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.amber,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Market insights ─────────────────────────────────────────────
          Text(
            'MARKET INSIGHTS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: mutedColor,
            ),
          ),
          const SizedBox(height: 12),

          if (assets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: quizProvider.isLoadingAssets
                    ? const CircularProgressIndicator(
                        color: AppColors.emerald,
                      )
                    : Text(
                        'No market data yet. Pull down to refresh.',
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

            return Container(
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
                        onPressed: () async {
                          final navigator =
                              Navigator.of(context, rootNavigator: true);

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.emerald,
                              ),
                            ),
                          );

                          String dynamicInsight;

                          try {
                            dynamicInsight =
                                await quizProvider.fetchXaiInsightForAsset(
                              item,
                            );
                          } finally {
                            // Always close the loading dialog.
                            navigator.pop();
                          }

                          if (context.mounted) {
                            showInfoModal(
                              context,
                              title:
                                  'XAI Insight (Level ${quizProvider.userLevel})',
                              content: dynamicInsight,
                              isDarkMode: isDark,
                            );
                          }
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
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}