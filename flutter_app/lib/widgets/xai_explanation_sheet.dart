import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../providers/quiz_provider.dart';
import '../screens/ticker_detail_screen.dart';
import '../theme/app_theme.dart';

/// Shows an XAI Explanation Bottom Sheet Modal for a given ticker.
/// Displays SHAP feature attributions, sentiment metrics, RSI, and level-tailored explanation.
void showXaiExplanationSheet(
  BuildContext context, {
  required String ticker,
  required bool isDarkMode,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDarkMode ? AppColors.darkCard : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _XaiExplanationSheetBody(
      ticker: ticker,
      isDarkMode: isDarkMode,
    ),
  );
}

class _XaiExplanationSheetBody extends StatefulWidget {
  final String ticker;
  final bool isDarkMode;

  const _XaiExplanationSheetBody({
    required this.ticker,
    required this.isDarkMode,
  });

  @override
  State<_XaiExplanationSheetBody> createState() =>
      _XaiExplanationSheetBodyState();
}

class _XaiExplanationSheetBodyState extends State<_XaiExplanationSheetBody> {
  TickerDetail? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final quizProvider = context.read<QuizProvider>();
    final detail = await quizProvider.fetchTickerDetail(widget.ticker);
    if (mounted) {
      setState(() {
        _detail = detail;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.isDarkMode ? Colors.white : AppColors.lightTextPrimary;
    final secondaryColor =
        widget.isDarkMode ? Colors.white60 : AppColors.lightTextSecondary;
    final mutedColor =
        widget.isDarkMode ? Colors.white38 : AppColors.lightTextMuted;
    final surfaceColor =
        widget.isDarkMode ? Colors.black26 : const Color(0xFFF8FAFC);

    final userLevel = context.watch<QuizProvider>().userLevel;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        if (_loading) {
          return Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: AppColors.emerald),
                const SizedBox(height: 18),
                Text(
                  'Computing XAI attributions for ${widget.ticker}...',
                  style: TextStyle(fontSize: 13, color: secondaryColor),
                ),
              ],
            ),
          );
        }

        final detail = _detail;
        if (detail == null) {
          return Container(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                'Could not load XAI explanation for ${widget.ticker}',
                style: TextStyle(color: textColor),
              ),
            ),
          );
        }

        final isUp = detail.isPositive;
        final changeColor = isUp ? AppColors.emerald : AppColors.rose;
        final signalColor = detail.signalColor;

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: mutedColor.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header row
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
                        color: widget.isDarkMode
                            ? Colors.black38
                            : AppColors.lightTextPrimary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        detail.ticker,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.companyName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '\$${detail.currentPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${isUp ? '+' : ''}${detail.changePercent.toStringAsFixed(2)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: changeColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: signalColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: signalColor.withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    detail.aiSignal,
                    style: TextStyle(
                      color: signalColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Level & Badge banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.emerald.withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined,
                      size: 16, color: AppColors.emerald),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'XAI Model Attribution (Level $userLevel)',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),
                  Text(
                    '${(detail.aiConfidence * 100).toInt()}% Conf.',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.emerald,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Key Technical & Sentiment Metrics Row
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FINBERT SENTIMENT',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${detail.sentimentScore >= 0 ? '+' : ''}${detail.sentimentScore.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: detail.sentimentScore >= 0
                                    ? AppColors.emerald
                                    : AppColors.rose,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              detail.sentimentScore > 0.1
                                  ? '(Bullish)'
                                  : (detail.sentimentScore < -0.1
                                      ? '(Bearish)'
                                      : '(Neutral)'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: secondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: widget.isDarkMode ? Colors.white12 : AppColors.lightBorder,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RSI (14)',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              detail.rsi.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              detail.rsi > 70
                                  ? '(Overbought)'
                                  : (detail.rsi < 30 ? '(Oversold)' : '(Neutral)'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: secondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Narrative XAI Insight
            Text(
              'EXPLANATION BREAKDOWN',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail.xaiInsight,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            const SizedBox(height: 18),

            // SHAP Feature Attribution Factors
            Text(
              'SHAP FEATURE ATTRIBUTIONS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 10),
            ...detail.factors.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: f.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          f.code,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: f.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  f.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  f.weight,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: f.color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: f.percentage,
                                minHeight: 6,
                                backgroundColor: f.color.withOpacity(0.12),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(f.color),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),

            if (detail.boldPrediction.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.amber.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 14, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        detail.boldPrediction,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: widget.isDarkMode
                              ? Colors.white70
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Open Detail Screen button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.candlestick_chart_rounded, size: 16),
                label: const Text(
                  'Open Live Chart & Full Breakdown',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TickerDetailScreen(ticker: detail.ticker),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shows a Factor Attribution Bottom Sheet for a market factor in MarketTab
void showFactorExplanationSheet(
  BuildContext context, {
  required FactorImpact factor,
  required int userLevel,
  required bool isDarkMode,
}) {
  final textColor = isDarkMode ? Colors.white : AppColors.lightTextPrimary;
  final secondaryColor =
      isDarkMode ? Colors.white70 : AppColors.lightTextSecondary;

  final Map<String, String> factorDescriptions = {
    'VOL':
        'Volume analysis examines trading activity velocity and order-book depth. Institutional orders manifest as abrupt volume spikes, signaling reliable trend continuation or impending reversal.',
    'PR':
        'Price trend and momentum model the slope of exponential moving averages against historical volatility channels, pinpointing high-probability breakout velocities.',
    'SN':
        'FinBERT Natural Language Processing analyzes real-time sentiment streams across social feeds, financial news, and analyst revisions to compute collective market sentiment.',
    'VLT':
        'Volatility index quantifies real-time variance and implied standard deviation across option strikes, flagging high-risk turbulence before price moves occur.',
    'RT':
        'Retail order flow detects retail consensus clustering versus institutional block distribution, identifying contrarian reversal points.',
  };

  final desc = factorDescriptions[factor.code.toUpperCase()] ??
      '${factor.name} contributes ${(factor.percentage * 100).toInt()}% towards the AI recommendation engine, weighted via SHAP multi-factor attribution.';

  showModalBottomSheet(
    context: context,
    backgroundColor: isDarkMode ? AppColors.darkCard : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white24 : AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: factor.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      factor.code,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: factor.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        factor.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      Text(
                        'SHAP Factor Vector',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode ? Colors.white54 : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: factor.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  factor.weight,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: factor.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: factor.percentage,
              minHeight: 8,
              backgroundColor: factor.color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(factor.color),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'FACTOR ATTRIBUTION MECHANICS',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: isDarkMode ? Colors.white38 : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.black26 : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    size: 14, color: AppColors.emerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Calibrated for Level $userLevel experience weighting',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? Colors.white60 : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Understood',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    ),
  );
}

