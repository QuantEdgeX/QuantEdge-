import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/quiz_provider.dart';
import 'screens/onboarding_quiz_screen.dart';
import 'screens/onboarding_glossary_screen.dart';
import 'screens/level_celebration_screen.dart';
import 'screens/main_workspace_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => QuizProvider(),
      child: const QuantEdgeApp(),
    ),
  );
}

class QuantEdgeApp extends StatelessWidget {
  const QuantEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuizProvider>();

    return MaterialApp(
      title: 'QuantEdge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: provider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const MobileAppContainer(),
    );
  }
}

class MobileAppContainer extends StatelessWidget {
  const MobileAppContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF080B14)
          : const Color(0xFFEAE8E0),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 890),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBg : AppColors.lightBg,
            borderRadius: BorderRadius.circular(44),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (quizProvider.phase == AppPhase.mainApp)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          children: [
                            if (quizProvider.phase == AppPhase.mainApp) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white10
                                        : AppColors.lightBorder,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'XAI LEVEL: ${quizProvider.userLevel}',
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
                            ],
                            IconButton(
                              onPressed: () => quizProvider.toggleTheme(),
                              style: IconButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
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
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildPhase(quizProvider.phase),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhase(AppPhase phase) {
    switch (phase) {
      case AppPhase.onboarding1:
        return const OnboardingQuizScreen();
      case AppPhase.onboarding2:
        return const OnboardingGlossaryScreen();
      case AppPhase.assessmentComplete:
        return const LevelCelebrationScreen();
      case AppPhase.mainApp:
        return const MainWorkspaceScreen();
    }
  }
}
