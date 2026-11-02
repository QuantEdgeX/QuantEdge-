import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class XaiAssessmentQuestion {
  final String id;
  final String domain;
  final String prompt;
  final String contextBlurb;
  final List<({String id, String text})> options;
  final String correctOptionId;
  final String explanation;

  const XaiAssessmentQuestion({
    required this.id,
    required this.domain,
    required this.prompt,
    required this.contextBlurb,
    required this.options,
    required this.correctOptionId,
    required this.explanation,
  });
}

class OnboardingQuizScreen extends StatefulWidget {
  const OnboardingQuizScreen({super.key});

  @override
  State<OnboardingQuizScreen> createState() => _OnboardingQuizScreenState();
}

class _OnboardingQuizScreenState extends State<OnboardingQuizScreen> {
  // ── 5 Original Core XAI Assessment Questions ─────────────────────────────
  static const List<XaiAssessmentQuestion> _questions = [
    // 1. Technical Analysis
    XaiAssessmentQuestion(
      id: 'q_tech_001',
      domain: 'TECHNICAL ANALYSIS',
      prompt: 'RSI Reading & Momentum Interpretation',
      contextBlurb:
          "AAPL's 14-day RSI just crossed above 72 while its 5-day Moving Average (MA5) continues to slope upward. How should a trader interpret this momentum signal?",
      options: [
        (id: 'A', text: 'Strong buy signal — rising MA guarantees further rapid upside.'),
        (id: 'B', text: 'Overbought territory — signal is extended; consider profit-taking or trailing stops.'),
        (id: 'C', text: 'RSI above 70 is an automatic short/sell regardless of trend strength.'),
        (id: 'D', text: 'RSI is completely irrelevant whenever a moving average is rising.'),
      ],
      correctOptionId: 'B',
      explanation:
          'RSI > 70 indicates an overbought condition where momentum is extended. While trend strength may persist, risk of a pullback increases, making risk containment or profit-taking prudent.',
    ),

    // 2. Market Microstructure
    XaiAssessmentQuestion(
      id: 'q_micro_001',
      domain: 'MARKET MICROSTRUCTURE',
      prompt: 'Order Book Intensity & Price Pressure',
      contextBlurb:
          'What does a high concentration of bid volume relative to ask volume near the active price (high Order Book Intensity) indicate for short-term price pressure?',
      options: [
        (id: 'A', text: 'Total global stock supply has permanently increased.'),
        (id: 'B', text: 'Aggressive buyer demand is absorbing liquidity, signaling upward short-term price pressure.'),
        (id: 'C', text: 'The stock dividend yield has been cut by the board of directors.'),
        (id: 'D', text: 'Historical volatility is guaranteed to decrease over the next 10 years.'),
      ],
      correctOptionId: 'B',
      explanation:
          'Order Book Intensity measures buy versus sell depth near the inside market. Heavy bid clustering relative to asks signals immediate liquidity absorption that tends to push price upward.',
    ),

    // 3. Sentiment Analysis (NLP / FinBERT)
    XaiAssessmentQuestion(
      id: 'q_sent_001',
      domain: 'SENTIMENT ANALYSIS (FinBERT)',
      prompt: 'Price-Sentiment Divergence',
      contextBlurb:
          "QuantEdge's FinBERT model scores recent NVDA headlines at -0.45 (bearish), while the stock's spot price is currently up +4.2% on intraday retail volume. What should you conclude?",
      options: [
        (id: 'A', text: 'Price momentum always invalidates news; sentiment scores should be ignored.'),
        (id: 'B', text: 'Price-sentiment divergence detected. Negative narrative friction may delay momentum; reduce confidence weighting.'),
        (id: 'C', text: 'Negative news sentiment guarantees an immediate crash within 60 seconds.'),
        (id: 'D', text: 'FinBERT scores measure exchange trading fees rather than text tone.'),
      ],
      correctOptionId: 'B',
      explanation:
          'Price-sentiment divergence occurs when price action and narrative tone conflict. Institutional alpha models lower confidence weighting on rallies that lack positive fundamental sentiment backing.',
    ),

    // 4. Quantitative Risk Management
    XaiAssessmentQuestion(
      id: 'q_risk_001',
      domain: 'RISK MANAGEMENT',
      prompt: 'Volatility Spike & Exposure Sizing',
      contextBlurb:
          "TSLA's 5-day rolling volatility doubled overnight ahead of a major macro event, while model confidence dropped from 90% to 65%. What is the appropriate risk management action?",
      options: [
        (id: 'A', text: 'Double position size to maximize potential profit from the high volatility.'),
        (id: 'B', text: 'Reduce position sizing to constrain Value-at-Risk (VaR) and limit downside exposure.'),
        (id: 'C', text: 'Ignore volatility; quantitative models should never adjust position sizes.'),
        (id: 'D', text: 'Liquidate all other portfolio assets and put 100% into TSLA.'),
      ],
      correctOptionId: 'B',
      explanation:
          'Volatility sizing (vol-targeting) requires reducing position sizes as realized volatility climbs. This keeps portfolio dollar-risk constant and prevents outsized drawdowns.',
    ),

    // 5. Explainable AI (XAI) & Multi-Factor Modeling
    XaiAssessmentQuestion(
      id: 'q_xai_001',
      domain: 'EXPLAINABLE AI (XAI)',
      prompt: 'SHAP Feature Contribution & Factor Alignment',
      contextBlurb:
          'QuantEdge outputs a BUY signal for MSFT (88% confidence). SHAP feature contributions show: RSI = +0.38, FinBERT Sentiment = +0.32, Order Book = +0.18, Volatility = -0.06. How should you interpret this?',
      options: [
        (id: 'A', text: 'Only RSI matters; multi-factor attribution adds no value.'),
        (id: 'B', text: 'Multi-factor convergence: technical momentum and news sentiment reinforce each other (>70% total weight), supporting strong conviction.'),
        (id: 'C', text: 'SHAP values represent the exact dollar dividend the stock will pay.'),
        (id: 'D', text: 'Negative volatility weight indicates the model has failed and is broken.'),
      ],
      correctOptionId: 'B',
      explanation:
          'SHAP values decompose the model prediction into individual factor contributions. When both technical and NLP sentiment factors align positively, the resulting signal has higher structural reliability.',
    ),
  ];

  int _currentIndex = 0;
  String? _selectedOption;
  final Map<int, String> _userAnswers = {};
  bool _isAssessmentCompleted = false;
  String _calculatedLevel = 'Beginner';
  int _calculatedNumericLevel = 2;
  int _correctCount = 0;

  void _handleOptionSelect(String optId) {
    setState(() {
      _selectedOption = optId;
    });
  }

  void _handleContinue() {
    if (_selectedOption == null) return;

    _userAnswers[_currentIndex] = _selectedOption!;

    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption = _userAnswers[_currentIndex];
      });
    } else {
      // Completed all 5 questions — calculate experience level
      int correct = 0;
      for (int i = 0; i < _questions.length; i++) {
        if (_userAnswers[i] == _questions[i].correctOptionId) {
          correct++;
        }
      }

      String level;
      int numericLevel;
      if (correct <= 2) {
        level = 'Beginner';
        numericLevel = 2;
      } else if (correct <= 4) {
        level = 'Intermediate';
        numericLevel = 3;
      } else {
        level = 'Advanced';
        numericLevel = 4;
      }

      setState(() {
        _correctCount = correct;
        _calculatedLevel = level;
        _calculatedNumericLevel = numericLevel;
        _isAssessmentCompleted = true;
      });

      // Update provider with calculated user level & profile
      final quizProvider = context.read<QuizProvider>();
      quizProvider.setUserLevel(numericLevel);
      quizProvider.updateUserProfile(
        quizProvider.userProfile.copyWith(experienceLevel: level),
      );
    }
  }

  void _proceedToTickerSelection() {
    // Linear routing: Onboarding Quiz ➔ Ticker Selection Screen
    context.read<QuizProvider>().setPhase(AppPhase.tickerSelection);
  }

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    if (_isAssessmentCompleted) {
      return _buildCelebrationView(context, isDark, textColor);
    }

    final question = _questions[_currentIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Step indicator ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'QUESTION ${_currentIndex + 1} OF ${_questions.length}: XAI ASSESSMENT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                ),
              ),
              Text(
                '${((_currentIndex + 1) / _questions.length * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.emerald,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Progress bar ──────────────────────────────────────────────
          Row(
            children: List.generate(_questions.length, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < _questions.length - 1 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: i <= _currentIndex
                        ? AppColors.emerald
                        : (isDark ? Colors.white10 : Colors.black12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // ── Question Card ─────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkCard.withOpacity(0.5)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark ? Colors.white10 : AppColors.lightBorder,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Domain tag + icon
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.emerald.withOpacity(0.18)
                                : AppColors.emerald.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            AppIcons.target,
                            color: AppColors.emerald,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                question.domain,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: AppColors.emerald,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                question.prompt,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Context blurb / Scenario
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black26
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white10 : AppColors.lightBorder,
                        ),
                      ),
                      child: Text(
                        question.contextBlurb,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Options list
                    ...question.options.map((option) {
                      final isSelected = _selectedOption == option.id;
                      Color borderColor = isDark ? Colors.white10 : AppColors.lightBorder;
                      Color bgColor = isDark ? Colors.white.withOpacity(0.04) : Colors.white;
                      Color badgeBg = isDark ? Colors.white10 : const Color(0xFFF1F5F9);
                      Color badgeText = isDark ? Colors.white54 : AppColors.lightTextMuted;

                      if (isSelected) {
                        borderColor = AppColors.emerald;
                        bgColor = AppColors.emerald.withOpacity(0.12);
                        badgeBg = AppColors.emerald;
                        badgeText = Colors.white;
                      }

                      return GestureDetector(
                        onTap: () => _handleOptionSelect(option.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.emerald
                                        : (isDark ? Colors.white10 : AppColors.lightBorder),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    option.id,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: badgeText,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  option.text,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    height: 1.35,
                                    color: isSelected ? AppColors.emerald : textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Continue Button ───────────────────────────────────────────
          ElevatedButton(
            onPressed: _selectedOption != null ? _handleContinue : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              disabledBackgroundColor: isDark ? Colors.white10 : Colors.black12,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: _selectedOption != null ? 8 : 0,
              shadowColor: AppColors.emerald.withOpacity(0.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _currentIndex < _questions.length - 1
                      ? 'CONTINUE'
                      : 'CALCULATE MY XAI LEVEL',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    fontSize: 12,
                    color: _selectedOption != null
                        ? Colors.white
                        : (isDark ? Colors.white30 : Colors.black38),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: _selectedOption != null
                      ? Colors.white
                      : (isDark ? Colors.white30 : Colors.black38),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCelebrationView(BuildContext context, bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.emerald,
                width: 3.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.emerald.withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              AppIcons.award,
              color: AppColors.emerald,
              size: 54,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'XAI ASSESSMENT COMPLETE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
              color: AppColors.emerald,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Level Profile Assigned!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: textColor,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkCard.withOpacity(0.55)
                  : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark ? Colors.white10 : AppColors.lightBorder,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Based on your $_correctCount/5 score on quantitative scenario analysis, your assigned XAI profile is:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: isDark ? Colors.white60 : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.emerald, width: 1.5),
                  ),
                  child: Text(
                    '$_calculatedLevel (Level $_calculatedNumericLevel)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: AppColors.emerald,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _calculatedNumericLevel <= 2
                      ? 'QuantEdge will provide intuitive, jargon-free explanations with simple sentiment & direction cues.'
                      : (_calculatedNumericLevel == 3
                          ? 'QuantEdge will provide balanced technical & FinBERT sentiment metrics with RSI and moving average context.'
                          : 'QuantEdge will display deep multi-factor attributions, SHAP scores, and volatility regime statistics.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: isDark ? Colors.white54 : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _proceedToTickerSelection,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 10,
              shadowColor: AppColors.emerald.withOpacity(0.4),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'CHOOSE YOUR TICKERS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    fontSize: 12,
                  ),
                ),
                SizedBox(width: 8),
                Icon(AppIcons.chevronRight, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
