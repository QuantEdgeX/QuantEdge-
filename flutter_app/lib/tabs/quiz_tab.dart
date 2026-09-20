import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class QuizTab extends StatefulWidget {
  const QuizTab({super.key});

  @override
  State<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<QuizTab> {
  int _currentIndex = 0;
  int? _selectedIndex;
  bool _isFinished = false;

  // Local static quiz data for instant, reliable loading
  final List<Map<String, dynamic>> _questions = [
    {
      'question': 'What indicates a bullish Golden Cross in technical analysis?',
      'options': [
        'Short-term MA crosses above long-term MA',
        'Price drops below 200-day moving average',
        'RSI oversold indicator drops below 20',
        'Trading volume completely dries up'
      ],
      'answer': 0,
      'term': 'Golden Cross',
      'definition': 'A chart pattern where a short-term moving average crosses above a long-term moving average, signaling upward price momentum.',
    },
    {
      'question': 'What does Order Book Intensity measure in market microstructure?',
      'options': [
        'Total stock supply available globally',
        'Concentration of buy vs. sell orders near active price',
        'Annual dividend yield payout ratios',
        'Historical volatility calculated over 10 years'
      ],
      'answer': 1,
      'term': 'Order Book Intensity',
      'definition': 'A quantitative metric evaluating buying and selling pressure relative to the bid-ask spread.',
    },
    {
      'question': 'How is FinBERT sentiment analysis primarily utilized in trading?',
      'options': [
        'Calculating company physical inventory levels',
        'Classifying financial text & news as positive, negative, or neutral',
        'Automating high-frequency order placement options',
        'Predicting central bank interest rates 5 years ahead'
      ],
      'answer': 1,
      'term': 'NLP Sentiment Analysis',
      'definition': 'Natural language processing tuned for financial domains to convert unstructured news into actionable sentiment scores.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    // ─── Quiz Finished Screen (Summary & Definitions) ────────────────────────
    if (_isFinished) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.15),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.emerald, width: 2),
            ),
            child: Column(
              children: [
                const Icon(Icons.stars_rounded, color: AppColors.emerald, size: 48),
                const SizedBox(height: 12),
                Text(
                  'QUIZ COMPLETED!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '+250 XP Earned • Skill Level Progressed',
                  style: TextStyle(color: AppColors.emerald, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'LESSON SUMMARY & KEY DEFINITIONS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: isDark ? Colors.white54 : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 12),
          ..._questions.map((q) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white12 : AppColors.lightBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q['term'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.emerald,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      q['definition'],
                      style: TextStyle(fontSize: 12, color: textColor, height: 1.4),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              setState(() {
                _currentIndex = 0;
                _selectedIndex = null;
                _isFinished = false;
              });
            },
            child: const Text('RETAKE QUIZ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      );
    }

    // ─── Active Quiz Question View ───────────────────────────────────────────
    final q = _questions[_currentIndex];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SKILL ASSESSMENT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: isDark ? Colors.white54 : AppColors.lightTextMuted,
              ),
            ),
            Text(
              'Question ${_currentIndex + 1}/${_questions.length}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.emerald),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? Colors.white12 : AppColors.lightBorder, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                q['question'],
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textColor, height: 1.3),
              ),
              const SizedBox(height: 20),
              ...List.generate(
                (q['options'] as List).length,
                (idx) => InkWell(
                  onTap: () => setState(() => _selectedIndex = idx),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _selectedIndex == idx
                          ? AppColors.emerald.withOpacity(0.15)
                          : isDark
                              ? Colors.black26
                              : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _selectedIndex == idx ? AppColors.emerald : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedIndex == idx ? AppColors.emerald : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedIndex == idx ? AppColors.emerald : Colors.grey.shade400,
                            ),
                          ),
                          child: Text(
                            String.fromCharCode(65 + idx),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: _selectedIndex == idx ? Colors.white : (isDark ? Colors.white70 : Colors.black.withOpacity(0.8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            q['options'][idx],
                            style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _selectedIndex == null
                      ? null
                      : () {
                          if (_currentIndex + 1 < _questions.length) {
                            setState(() {
                              _currentIndex += 1;
                              _selectedIndex = null;
                            });
                          } else {
                            // Wire directly into QuizProvider state
                            quizProvider.completePracticeQuiz(250);
                            setState(() => _isFinished = true);
                          }
                        },
                  child: const Text('SUBMIT ANSWER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}