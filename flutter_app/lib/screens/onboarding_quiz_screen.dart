import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class OnboardingQuizScreen extends StatelessWidget {
  const OnboardingQuizScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    if (quizProvider.isLoadingQuiz && quizProvider.currentQuestion == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.emerald),
      );
    }

    final question = quizProvider.currentQuestion;
    if (question == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Unable to load dynamic question.',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => quizProvider.initQuizSession(),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
              child: const Text('RETRY', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    final String domainText =
        (question['domain'] ?? 'TECHNICAL ANALYSIS').toString().toUpperCase();
    final String promptText = question['prompt'] ?? '';
    final List choicesList = (question['choices'] as List?) ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STEP 1 OF 2: LEARNING ENGINE',
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
                  color: isDark ? Colors.white10 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppColors.emerald,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.emerald.withOpacity(0.2)
                            : AppColors.lightTextPrimary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        AppIcons.target,
                        color: isDark ? AppColors.emerald : Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'DOMAIN: $domainText',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '"$promptText"',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                        color: isDark
                            ? Colors.white70
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...choicesList.map((choiceObj) {
                      final choice = choiceObj as Map<String, dynamic>;
                      final optId = (choice['id'] ?? '').toString();
                      final optText = (choice['text'] ?? '').toString();
                      final isSelected =
                          quizProvider.selectedQuizOption == optId;

                      Color borderColor =
                          isDark ? Colors.white10 : AppColors.lightBorder;
                      Color bgColor = isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.white;
                      Color badgeBg = isDark
                          ? const Color(0xFF18181B)
                          : const Color(0xFFF8FAFC);
                      Color badgeText =
                          isDark ? Colors.white38 : AppColors.lightTextMuted;

                      if (isSelected) {
                        borderColor = AppColors.emerald;
                        bgColor = AppColors.emerald.withOpacity(0.15);
                        badgeBg = AppColors.emerald;
                        badgeText = Colors.white;
                      }

                      return GestureDetector(
                        onTap: () => quizProvider.selectQuizOption(optId),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? borderColor
                                        : (isDark
                                            ? Colors.white10
                                            : AppColors.lightBorder),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    optId.toUpperCase(),
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
                                  optText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? AppColors.emerald
                                        : textColor,
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
          // Show SUBMIT/CONTINUE button whenever an option has been selected
          if (quizProvider.selectedQuizOption != null)
            ElevatedButton(
              onPressed: quizProvider.isLoadingQuiz
                  ? null
                  : () => quizProvider
                      .submitQuizAnswer(quizProvider.selectedQuizOption!),
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
              child: quizProvider.isLoadingQuiz
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'CONTINUE',
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
