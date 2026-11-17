import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../providers/quiz_provider.dart';
import '../screens/ticker_detail_screen.dart';
import '../theme/app_theme.dart';

/// Shows an AI Explanation Bottom Sheet Modal for a given ticker.
/// Features a Qwen-powered QuantEdge AI Insight natural-language narrative,
/// dynamically calibrated to the user's Insight Depth (Level 1-2: Simple, Level 3-4: Advanced).
void showXaiExplanationSheet(
  BuildContext context, {
  required String ticker,
  required bool isDarkMode,
  String? signalType,
  Map<String, dynamic>? liveFactors,
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
      signalType: signalType,
      liveFactors: liveFactors,
    ),
  );
}

class _XaiExplanationSheetBody extends StatefulWidget {
  final String ticker;
  final bool isDarkMode;
  final String? signalType;
  final Map<String, dynamic>? liveFactors;

  const _XaiExplanationSheetBody({
    required this.ticker,
    required this.isDarkMode,
    this.signalType,
    this.liveFactors,
  });

  @override
  State<_XaiExplanationSheetBody> createState() =>
      _XaiExplanationSheetBodyState();
}

class _XaiExplanationSheetBodyState extends State<_XaiExplanationSheetBody>
    with SingleTickerProviderStateMixin {
  TickerDetail? _detail;
  bool _loading = true;

  String? _qwenExplanation;
  bool _loadingQwen = true;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    ));

    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final quizProvider = context.read<QuizProvider>();
    final int userLevel = quizProvider.userLevel;

    // 1. Fetch detailed stats & price drivers
    final detail = await quizProvider.fetchTickerDetail(widget.ticker);

    if (mounted) {
      setState(() {
        _detail = detail;
        _loading = false;
      });
    }

    // 2. Synthesize factor map for QuantEdge AI Insight
    final effectiveSignal = widget.signalType ?? detail?.aiSignal ?? 'BUY';
    final effectiveFactors = <String, dynamic>{
      'rsi': widget.liveFactors?['rsi'] ?? detail?.rsi ?? 52.0,
      'sentiment': widget.liveFactors?['sentiment'] ??
          detail?.sentimentScore ??
          0.0,
      'finbertSentiment': widget.liveFactors?['finbertSentiment'] ??
          detail?.sentimentScore ??
          0.0,
      'volatility': widget.liveFactors?['volatility'] ?? '0.015 (Standard)',
      'orderBookIntensity': widget.liveFactors?['orderBookIntensity'] ??
          (detail != null && detail.factors.isNotEmpty
              ? '${detail.factors.first.name} (${detail.factors.first.weight})'
              : 'Institutional order clustering'),
      'confidence': widget.liveFactors?['confidence'] ??
          '${((detail?.aiConfidence ?? 0.85) * 100).toInt()}%',
      'price': widget.liveFactors?['price'] ?? detail?.currentPrice ?? 0.0,
      'changePercent': widget.liveFactors?['changePercent'] ??
          detail?.changePercent ??
          0.0,
    };

    // 3. Fetch QuantEdge AI Insight explanation with level controls
    try {
      final explanation = await quizProvider.fetchQwenExplanation(
        ticker: widget.ticker,
        signalType: effectiveSignal,
        factors: effectiveFactors,
        userLevel: userLevel,
      );

      if (mounted) {
        setState(() {
          _qwenExplanation = explanation;
          _loadingQwen = false;
        });
        _animCtrl.forward();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingQwen = false;
        });
      }
    }
  }

  Future<void> _regenerateCopilot() async {
    if (_loadingQwen) return;
    setState(() {
      _loadingQwen = true;
      _animCtrl.reset();
    });

    final quizProvider = context.read<QuizProvider>();
    final int userLevel = quizProvider.userLevel;
    final effectiveSignal = widget.signalType ?? _detail?.aiSignal ?? 'BUY';
    final effectiveFactors = <String, dynamic>{
      'rsi': widget.liveFactors?['rsi'] ?? _detail?.rsi ?? 52.0,
      'finbertSentiment': widget.liveFactors?['finbertSentiment'] ??
          _detail?.sentimentScore ??
          0.0,
      'volatility': widget.liveFactors?['volatility'] ?? '0.018',
      'orderBookIntensity': widget.liveFactors?['orderBookIntensity'] ??
          'Strong buyer demand',
    };

    final explanation = await quizProvider.fetchQwenExplanation(
      ticker: widget.ticker,
      signalType: effectiveSignal,
      factors: effectiveFactors,
      userLevel: userLevel,
      forceRefresh: true,
      simplify: true,
    );

    if (mounted) {
      setState(() {
        _qwenExplanation = explanation;
        _loadingQwen = false;
      });
      _animCtrl.forward();
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
    final bool isSimple = userLevel <= 2;
    final String depthLabel =
        isSimple ? 'Insight Depth: Simple' : 'Insight Depth: Advanced';

    return DraggableScrollableSheet(
      initialChildSize: isSimple ? 0.70 : 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
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
                  'Loading insight for ${widget.ticker}...',
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
                'Could not load data for ${widget.ticker}',
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'AI Overall Signal',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: mutedColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: signalColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
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
              ],
            ),
            const SizedBox(height: 18),

            // Insight Depth Banner
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
                  const Icon(Icons.auto_awesome,
                      size: 16, color: AppColors.emerald),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'QuantEdge AI Insight • $depthLabel',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),
                  Text(
                    '${(detail.aiConfidence * 100).toInt()}% Confidence',
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

            // Key Technical & Sentiment Metrics Row (Layman labeled)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // News & Social Sentiment Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEWS & SOCIAL SENTIMENT',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (isSimple) ...[
                          Text(
                            detail.sentimentScore > 0.1
                                ? 'Positive & Optimistic'
                                : (detail.sentimentScore < -0.1
                                    ? 'Cautious & Cautious'
                                    : 'Balanced & Neutral'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: detail.sentimentScore >= 0
                                  ? AppColors.emerald
                                  : AppColors.rose,
                            ),
                          ),
                        ] else ...[
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
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: widget.isDarkMode
                        ? Colors.white12
                        : AppColors.lightBorder,
                  ),
                  const SizedBox(width: 12),
                  // Price Momentum Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSimple ? 'PRICE MOMENTUM' : 'PRICE MOMENTUM (RSI)',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (isSimple) ...[
                          Text(
                            detail.rsi > 70
                                ? 'Strong Buying Wave'
                                : (detail.rsi < 30
                                    ? 'Oversold / Heavy Selling'
                                    : 'Steady / Normal'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: detail.rsi > 70
                                  ? AppColors.amber
                                  : (detail.rsi < 30
                                      ? AppColors.rose
                                      : textColor),
                            ),
                          ),
                        ] else ...[
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
                                    : (detail.rsi < 30
                                        ? '(Oversold)'
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── QUANTEDGE AI INSIGHT NARRATIVE SECTION ─────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: AppColors.emerald,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'QUANTEDGE AI INSIGHT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _regenerateCopilot,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.isDarkMode
                          ? Colors.white10
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 12,
                          color: mutedColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Re-explain',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Copilot Content Box (Loading or Animated Markdown)
            if (_loadingQwen)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: widget.isDarkMode
                        ? Colors.white10
                        : AppColors.lightBorder,
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: AppColors.emerald,
                          strokeWidth: 2.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'QuantEdge AI Insight is analyzing market conditions...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: secondaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Evaluating news sentiment, buyer/seller demand, and price momentum.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: mutedColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              )
            else if (_qwenExplanation != null)
              FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: widget.isDarkMode
                          ? AppColors.darkCard.withOpacity(0.6)
                          : const Color(0xFFF9FBFA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.emerald.withOpacity(0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.emerald.withOpacity(0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildFormattedNarrative(
                      _qwenExplanation!,
                      widget.isDarkMode,
                      textColor,
                      secondaryColor,
                    ),
                  ),
                ),
              )
            else
              Text(
                detail.xaiInsight,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),

            // ── DE-DUPLICATED FACTOR BARS: HIDE ON SIMPLE LEVEL ─────────────
            // When userLevel <= 2, factor bars are hidden here to keep the sheet
            // focused solely on the narrative. Static factor bars remain on TickerDetailScreen.
            if (!isSimple) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'KEY PRICE DRIVERS',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: mutedColor,
                    ),
                  ),
                  Text(
                    'RELATIVE IMPACT',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: mutedColor,
                    ),
                  ),
                ],
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
            ],

            if (detail.boldPrediction.isNotEmpty) ...[
              const SizedBox(height: 14),
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
                    const Icon(Icons.bolt_rounded,
                        size: 16, color: AppColors.amber),
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
                  'Open Live Chart & Key Price Drivers',
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

  /// Parses narrative into a formatted 2-sentence summary block and styled bullet list
  Widget _buildFormattedNarrative(
    String rawText,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    final lines = rawText.split('\n').map((l) => l.trim()).toList();
    final summaryLines = <String>[];
    final bulletLines = <String>[];

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith('•') ||
          line.startsWith('-') ||
          line.startsWith('*')) {
        bulletLines.add(line.replaceFirst(RegExp(r'^[•\-\*]\s*'), ''));
      } else {
        if (bulletLines.isEmpty) {
          summaryLines.add(line);
        } else {
          bulletLines.add(line);
        }
      }
    }

    final summaryText = summaryLines.join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summaryText.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: AppColors.emerald.withOpacity(0.7),
                  width: 3.0,
                ),
              ),
            ),
            child: Text(
              summaryText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        ...bulletLines.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5, right: 8),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.emerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child:
                        _buildRichMarkdownSpan(b, textColor, secondaryColor),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  /// Helper to render markdown **bold** terms smoothly with Text.rich
  Widget _buildRichMarkdownSpan(
    String text,
    Color textColor,
    Color secondaryColor,
  ) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: secondaryColor,
            fontWeight: FontWeight.w400,
          ),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: textColor,
          fontWeight: FontWeight.w800,
        ),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: secondaryColor,
          fontWeight: FontWeight.w400,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
    );
  }
}

/// Shows a Key Price Driver Bottom Sheet for an influence vector in MarketTab
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
        'Buyer/Seller trading volume shows the strength of buying and selling pressure. When large institutional funds enter the market, sudden volume jumps confirm the reliability of the price direction.',
    'PR':
        'Price momentum tracks how quickly and strongly a stock has been moving over recent days, spotting breakout moves before they become obvious.',
    'SN':
        'News & social sentiment analyzes financial news headlines, analyst reports, and social feeds to gauge investor optimism and market mood.',
    'VLT':
        'Market volatility measures how calm or turbulent price swings currently are, helping the AI adjust risk before sharp moves occur.',
    'RT':
        'Individual investor demand measures everyday retail activity versus large institutional funds to find key reversal turning points.',
  };

  final desc = factorDescriptions[factor.code.toUpperCase()] ??
      '${factor.name} contributes ${(factor.percentage * 100).toInt()}% towards the AI recommendation engine as a key price driver.';

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
                        'Key Price Driver',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode
                              ? Colors.white54
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            'PRICE DRIVER MECHANICS',
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
                    'Insight Depth: Level $userLevel (${userLevel <= 2 ? "Simple" : "Advanced"})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode
                          ? Colors.white60
                          : AppColors.lightTextSecondary,
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
