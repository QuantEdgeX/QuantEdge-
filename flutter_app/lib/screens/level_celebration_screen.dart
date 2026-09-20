import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class LevelCelebrationScreen extends StatelessWidget {
  const LevelCelebrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? AppColors.emerald.withOpacity(0.4)
                    : AppColors.emerald,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.emerald.withOpacity(0.3),
                  blurRadius: 50,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              AppIcons.award,
              color: AppColors.emerald,
              size: 60,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'SUCCESS BADGE EARNED',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.0,
              color: isDark ? AppColors.emeraldLight : AppColors.emeraldDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Assessment Complete!',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: textColor,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkCard.withOpacity(0.5)
                  : Colors.white,
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: isDark ? Colors.white10 : AppColors.lightBorder,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Based on your market scenario logic, your assigned language profile is:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: isDark
                        ? Colors.white60
                        : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Level ${quizProvider.userLevel} (Intermediate XAI Tracking) Assigned',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: isDark
                        ? AppColors.emeraldLight
                        : AppColors.emeraldDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          ElevatedButton(
            onPressed: () => quizProvider.setPhase(AppPhase.mainApp),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white
                  : AppColors.lightTextPrimary,
              foregroundColor: isDark ? Colors.black : Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 10,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AppIcons.zap, color: AppColors.emerald, size: 18),
                SizedBox(width: 10),
                Text(
                  'PROCEED TO WORKSPACE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
