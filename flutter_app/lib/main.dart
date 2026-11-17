import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/quiz_provider.dart';
import 'providers/learning_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Existing screens — unchanged
import 'screens/onboarding_quiz_screen.dart';
import 'screens/onboarding_glossary_screen.dart';
import 'screens/level_celebration_screen.dart';
import 'screens/main_workspace_screen.dart';

// New screens
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/enrichment_quiz_screen.dart';
import 'screens/ticker_selection_screen.dart';
import 'screens/profile_settings_screen.dart';
import 'widgets/app_tour_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully.');
  } catch (e) {
    debugPrint('Firebase initialization skipped (missing config): $e');
  }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => QuizProvider()),
        ChangeNotifierProvider(create: (_) => LearningProvider()),
      ],
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

/// A navigator key scoped to the phone-frame so that all Navigator.push
/// calls and showDialog calls render inside the clipped container.
final GlobalKey<NavigatorState> phoneNavigatorKey = GlobalKey<NavigatorState>();

class MobileAppContainer extends StatelessWidget {
  const MobileAppContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final phase = quizProvider.phase;

    // No more early return for splash screen; it is now inside the phone frame.

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
          // All navigation & dialogs must be clipped inside the phone frame.
          // We achieve this by placing a nested Navigator here.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
            child: Navigator(
              key: phoneNavigatorKey,
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => _PhoneShell(phase: phase),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The persistent phone chrome (header + phase body).
/// Lives as the base route inside the nested Navigator.
class _PhoneShell extends StatelessWidget {
  final AppPhase phase;
  const _PhoneShell({required this.phase});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    return SafeArea(
      child: Column(
        children: [
          // ── Top header bar ─────────────────────────────────
          if (quizProvider.phase != AppPhase.splash)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Only show QUANTEDGE / ALPHA ENGINE on main app
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
                          color: textColor,
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
                  const Text(
                    'QuantEdge',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: AppColors.emerald,
                    ),
                  ),

                Row(
                  children: [
                    // XAI level badge + avatar — only on main app
                    if (quizProvider.phase == AppPhase.mainApp) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ProfileSettingsScreen(),
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
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
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'User Profile & Settings',
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ProfileSettingsScreen(),
                          ));
                        },
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
                        icon: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [AppColors.emerald, AppColors.blue],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              quizProvider.userProfile.name.isNotEmpty
                                  ? quizProvider.userProfile.name[0]
                                      .toUpperCase()
                                  : 'Q',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Theme toggle — always visible
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
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Phase body ──────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: KeyedSubtree(
                key: ValueKey(quizProvider.phase),
                child: _buildPhase(quizProvider.phase),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhase(AppPhase phase) {
    switch (phase) {
      case AppPhase.splash:
        return const SplashScreen();
      case AppPhase.login:
        return const LoginScreen();
      case AppPhase.enrichment:
        return const EnrichmentQuizScreen();
      case AppPhase.onboarding1:
        return const OnboardingQuizScreen();
      case AppPhase.onboarding2:
        return const OnboardingGlossaryScreen();
      case AppPhase.assessmentComplete:
        return const LevelCelebrationScreen();
      case AppPhase.tour:
        return const AppTourOverlay(child: MainWorkspaceScreen());
      case AppPhase.tickerSelection:
        return const TickerSelectionScreen();
      case AppPhase.mainApp:
        return const MainWorkspaceScreen();
    }
  }
}