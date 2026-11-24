import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class OnboardingGlossaryScreen extends StatelessWidget {
  const OnboardingGlossaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    final words = [
      {'id': 'vol', 'text': 'Volume Analysis'},
      {'id': 'sent', 'text': 'Social Sentiment'},
    ];

    final meanings = [
      {
        'id': 'm-vol',
        'wordId': 'vol',
        'text': 'Measures share trading intensity to find heavy money flows.',
      },
      {
        'id': 'm-sent',
        'wordId': 'sent',
        'text': 'Tracks public crowd mood from news and media streams.',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STEP 2 OF 2: METRIC ALIGNMENT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                ),
              ),
              Container(
                width: 80,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.emerald,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkCard.withOpacity(0.4)
                    : Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDark ? Colors.white10 : AppColors.lightBorder,
                  width: 2,
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Text(
                      'PAIR CORE PARAMETERS TO THEIR PLAIN-ENGLISH EXPLANATIONS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        color: isDark
                            ? Colors.white38
                            : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ...words.map((w) {
                      final matched = quizProvider.matchedPairs.contains(
                        w['id'],
                      );
                      final active = quizProvider.selectedWordId == w['id'];

                      return GestureDetector(
                        onTap: matched
                            ? null
                            : () => quizProvider.selectWord(w['id']!),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: matched
                                ? AppColors.emerald.withOpacity(0.1)
                                : (active
                                      ? AppColors.emerald.withOpacity(0.05)
                                      : (isDark
                                            ? Colors.white.withOpacity(0.05)
                                            : const Color(0xFFF8FAFC))),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: matched || active
                                  ? AppColors.emerald
                                  : (isDark
                                        ? Colors.white10
                                        : AppColors.lightBorder),
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                w['text']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: matched || active
                                      ? AppColors.emerald
                                      : textColor,
                                ),
                              ),
                              if (matched)
                                const Icon(
                                  AppIcons.checkCircle2,
                                  color: AppColors.emerald,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    ...meanings.map((m) {
                      final matched = quizProvider.matchedPairs.contains(
                        m['wordId'],
                      );
                      final active = quizProvider.selectedMeaningId == m['id'];

                      return GestureDetector(
                        onTap: matched
                            ? null
                            : () => quizProvider.selectMeaning(
                                m['id']!,
                                m['wordId']!,
                              ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: matched
                                ? AppColors.emerald.withOpacity(0.05)
                                : (active
                                      ? AppColors.emerald.withOpacity(0.05)
                                      : (isDark
                                            ? const Color(0xFF121827)
                                            : const Color(0xFFF8FAFC))),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: matched || active
                                  ? AppColors.emerald
                                  : (isDark
                                        ? Colors.white10
                                        : AppColors.lightBorder),
                              width: 2,
                            ),
                          ),
                          child: Text(
                            m['text']!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                              color: matched
                                  ? AppColors.emerald.withOpacity(0.5)
                                  : (active ? AppColors.emerald : textColor),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (quizProvider.isGlossaryFinished)
            ElevatedButton(
              onPressed: () =>
                  quizProvider.setPhase(AppPhase.assessmentComplete),
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
                  Icon(AppIcons.sparkles, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'EVALUATE MY LEVEL',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
