import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
// Both provider files declare an `AppTab` enum, so import only the
// provider classes from here to avoid an "ambiguous import" error.
import 'providers/learning_provider.dart' show LearningProvider;
import 'providers/quiz_provider.dart' show QuizProvider;
import 'screens/main_workspace_screen.dart';
import 'screens/onboarding_quiz_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        // Single LearningProvider. It checks onboarding status as soon as
        // the app starts.
        ChangeNotifierProvider(
          create: (_) => LearningProvider()..checkOnboardingStatus(),
        ),
        // Needed by DashboardTab, PortfolioTab and AssistantTab. Without
        // it they throw "Could not find the correct Provider<QuizProvider>".
        ChangeNotifierProvider(
          create: (_) => QuizProvider(),
        ),
      ],
      child: const QuantEdgeApp(),
    ),
  );
}

class QuantEdgeApp extends StatelessWidget {
  const QuantEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // QuizProvider owns the dark-mode flag (toggled from the header button).
    final isDarkMode = context.select<QuizProvider, bool>(
      (provider) => provider.isDarkMode,
    );

    return MaterialApp(
      title: 'QuantEdge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const MobileAppContainer(),
    );
  }
}

class MobileAppContainer extends StatelessWidget {
  const MobileAppContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Fallback level from QuizProvider (used until the learning score loads).
    final userLevel = context.select<QuizProvider, int>(
      (provider) => provider.userLevel,
    );

    // Onboarding state + the learner's real score.
    final onboardingChecked = context.select<LearningProvider, bool>(
      (p) => p.onboardingChecked,
    );
    final needsOnboarding = context.select<LearningProvider, bool>(
      (p) => p.needsOnboarding,
    );
    final learnScore = context.select<LearningProvider, int?>(
      (p) => p.progress?.score,
    );

    // Live level shown in the header chip (backend score 1-10 -> level 1-5).
    final xaiLevel = (learnScore != null && learnScore > 0)
        ? ((learnScore + 1) ~/ 2).clamp(1, 5).toInt()
        : userLevel;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF080B14)
          : const Color(0xFFEAE8E0),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 430,
            maxHeight: 890,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBg : AppColors.lightBg,
            borderRadius: BorderRadius.circular(44),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              width: 8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.6 : 0.1),
                blurRadius: 50,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'QUANTEDGE',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                                letterSpacing: 2.0,
                                fontSize: 16,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                            const Text(
                              'ALPHA ENGINE',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3.0,
                                color: AppColors.emerald,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : Colors.white,
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white10
                                      : AppColors.lightBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'XAI LEVEL: $xaiLevel',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: isDark
                                          ? Colors.white70
                                          : AppColors.lightTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.emerald,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () =>
                                  context.read<QuizProvider>().toggleTheme(),
                              style: IconButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.white10
                                        : AppColors.lightBorder,
                                  ),
                                ),
                              ),
                              icon: Icon(
                                isDark ? AppIcons.sun : AppIcons.moon,
                                size: 18,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !onboardingChecked
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.emerald,
                            ),
                          )
                        : needsOnboarding
                            ? const OnboardingQuizScreen()
                            : const MainWorkspaceScreen(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}