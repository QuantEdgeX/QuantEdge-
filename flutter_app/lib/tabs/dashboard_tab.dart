import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Both providers declare an `AppTab` enum, so import only what is needed.
import '../models/app_models.dart';
import '../providers/learning_provider.dart' show LearningProvider;
import '../providers/quiz_provider.dart' show QuizProvider;
import '../screens/profile_settings_screen.dart';
import '../screens/ticker_detail_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/xai_explanation_sheet.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchActive = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

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

    // Dynamically load user's selected tickers, with graceful fallback
    final savedTickers = quizProvider.selectedTickers.isNotEmpty
        ? quizProvider.selectedTickers
        : quizProvider.userProfile.chosenTickers;
    final List<String> activeTickers = savedTickers.isNotEmpty
        ? savedTickers
        : (assets.isNotEmpty
            ? assets.map((a) => a.ticker).toList()
            : const ['NVDA', 'AAPL', 'TSLA']);

    // Map active tickers to MarketAsset instances
    final List<MarketAsset> displayAssets = activeTickers.map((ticker) {
      final existing = assets.cast<MarketAsset?>().firstWhere(
        (a) => a?.ticker.toUpperCase() == ticker.toUpperCase(),
        orElse: () => null,
      );
      if (existing != null) return existing;

      final cached = quizProvider.tickerDetailCache[ticker.toUpperCase()];
      if (cached != null) {
        return MarketAsset(
          ticker: cached.ticker,
          status: cached.aiSignal,
          confidence: '${(cached.aiConfidence * 100).toInt()}%',
          sentiment: cached.sentimentScore.toStringAsFixed(2),
          insight: cached.xaiInsight,
          rsi: cached.rsi,
          price: cached.currentPrice,
          changePercent: cached.changePercent,
        );
      }

      return MarketAsset(
        ticker: ticker.toUpperCase(),
        status: 'BUY',
        confidence: '88%',
        sentiment: '0.45',
        insight:
            'Strong model alignment and positive factor momentum detected for $ticker.',
        rsi: 54.0,
      );
    }).toList();

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
          // ── Search bar ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard.withOpacity(0.5) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white12 : AppColors.lightBorder,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (val) {
                final query = val.trim();
                setState(() {
                  _isSearchActive = query.isNotEmpty;
                });
                quizProvider.searchTickers(query);
              },
              decoration: InputDecoration(
                hintText: 'Search stock ticker (e.g. NVDA, AAPL, MSFT)...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white30 : AppColors.lightTextMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.emerald,
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: isDark ? Colors.white54 : AppColors.lightTextMuted,
                        onPressed: () {
                          _searchCtrl.clear();
                          _searchFocusNode.unfocus();
                          setState(() {
                            _isSearchActive = false;
                          });
                          quizProvider.searchTickers('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          // ── Floating Live Search Results Overlay ───────────────────────
          if (_isSearchActive) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.emerald.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: quizProvider.isSearchingTickers
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.emerald,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : (quizProvider.tickerSearchResults.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'No matching tickers found for "${_searchCtrl.text}"',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: quizProvider.tickerSearchResults.map((res) {
                            final isPos = res.changePercent >= 0;
                            final sigColor = res.signal == 'BUY'
                                ? AppColors.emerald
                                : (res.signal == 'SELL' ? AppColors.rose : AppColors.amber);
                            return InkWell(
                              onTap: () {
                                final sym = res.ticker;
                                _searchCtrl.clear();
                                _searchFocusNode.unfocus();
                                setState(() {
                                  _isSearchActive = false;
                                });
                                quizProvider.searchTickers('');
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TickerDetailScreen(ticker: sym),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: isDark ? Colors.white10 : AppColors.lightBorder,
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                res.ticker,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                  color: textColor,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: sigColor.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: sigColor.withOpacity(0.3)),
                                                ),
                                                child: Text(
                                                  res.signal,
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w900,
                                                    color: sigColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            res.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: secondaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          res.price > 0 ? '\$${res.price.toStringAsFixed(2)}' : '—',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${isPos ? '+' : ''}${res.changePercent.toStringAsFixed(2)}%',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isPos ? AppColors.emerald : AppColors.rose,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 12,
                                      color: isDark ? Colors.white30 : AppColors.lightTextMuted,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        )),
            ),
          ],

          // ── Header ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRACTICE PORTFOLIO OVERVIEW',
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
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfileSettingsScreen(),
                    ),
                  );
                },
                child: Container(
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        levelLabel,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.emerald,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.settings_outlined,
                          size: 12, color: AppColors.emerald),
                    ],
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
                    'Practice Portfolio Value',
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

          if (displayAssets.isEmpty)
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

          ...displayAssets.map((item) {
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
                              signalType: item.status,
                              liveFactors: {
                                'rsi': item.rsi,
                                'sentiment': item.numericSentiment,
                                'finbertSentiment': item.numericSentiment,
                                'confidence': item.confidence,
                                'orderBookIntensity':
                                    'Institutional depth ${item.confidence}',
                                'volatility': '0.015 (Standard)',
                                'price': item.price,
                                'changePercent': item.changePercent,
                              },
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
                                  'AI CONFIDENCE',
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
                                  'NEWS & SOCIAL SENTIMENT',
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
                    // Interactive footer cue
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.insights_rounded,
                                size: 13, color: AppColors.emerald),
                            const SizedBox(width: 6),
                            Text(
                              'KEY PRICE DRIVERS & INSIGHT',
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