import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class AppTourOverlay extends StatefulWidget {
  final Widget child;
  const AppTourOverlay({super.key, required this.child});

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  static const _steps = [
    _TourStep(
      title: 'Your Dashboard',
      body: 'This is your personalised hub — see your chosen tickers, AI signals, and portfolio overview at a glance.',
      icon: Icons.dashboard_rounded,
      alignment: Alignment.topCenter,
      targetOffset: Offset(0, 0.2),
    ),
    _TourStep(
      title: 'Tap any ticker card',
      body: 'Tap a ticker to open a live price chart, AI prediction statement, and factor impact breakdown.',
      icon: Icons.touch_app_rounded,
      alignment: Alignment.center,
      targetOffset: Offset(0, 0),
    ),
    _TourStep(
      title: 'ⓘ XAI Insight',
      body: 'The ⓘ icon on each card shows a personalised AI explanation adapted to your XAI level.',
      icon: Icons.info_outline_rounded,
      alignment: Alignment.center,
      targetOffset: Offset(0, 0),
    ),
    _TourStep(
      title: 'Skill Quiz',
      body: 'The Quiz tab lets you practice trading scenarios and earn XP to level up your XAI insight depth.',
      icon: Icons.quiz_rounded,
      alignment: Alignment.bottomCenter,
      targetOffset: Offset(0, -0.15),
    ),
    _TourStep(
      title: 'AI Assistant',
      body: 'Ask your QuantEdge assistant anything — from portfolio risk to market anomaly analysis.',
      icon: Icons.smart_toy_rounded,
      alignment: Alignment.bottomCenter,
      targetOffset: Offset(0, -0.15),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 300), vsync: this)..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  void _next() {
    if (_step < _steps.length - 1) {
      _animCtrl.forward(from: 0);
      setState(() => _step++);
    } else {
      context.read<QuizProvider>().completeTour();
    }
  }

  void _skip() => context.read<QuizProvider>().completeTour();

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<QuizProvider>().isDarkMode;
    final step = _steps[_step];

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Dark scrim
        FadeTransition(
          opacity: _fadeAnim,
          child: Container(color: Colors.black.withOpacity(0.65)),
        ),
        // Tour card
        FadeTransition(
          opacity: _fadeAnim,
          child: Align(
            alignment: step.alignment,
            child: Padding(
              padding: EdgeInsets.only(
                top: step.alignment == Alignment.topCenter ? 120 : 0,
                bottom: step.alignment == Alignment.bottomCenter ? 120 : 0,
                left: 24, right: 24,
              ),
              child: _TourCard(
                step: step,
                stepIndex: _step,
                totalSteps: _steps.length,
                isDark: isDark,
                onNext: _next,
                onSkip: _skip,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tour card ─────────────────────────────────────────────────────────────────

class _TourCard extends StatelessWidget {
  final _TourStep step;
  final int stepIndex;
  final int totalSteps;
  final bool isDark;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TourCard({
    required this.step, required this.stepIndex, required this.totalSteps,
    required this.isDark, required this.onNext, required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final isLast = stepIndex == totalSteps - 1;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? AppColors.emerald.withOpacity(0.3) : AppColors.emerald.withOpacity(0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.emerald.withOpacity(0.15),
            blurRadius: 30, spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(step.icon, color: AppColors.emerald, size: 26),
          ),
          const SizedBox(height: 16),

          // Title
          Text(step.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic, color: textColor,
            ),
          ),
          const SizedBox(height: 8),

          // Body
          Text(step.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12, height: 1.6,
              color: isDark ? Colors.white60 : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // Step dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalSteps, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == stepIndex ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == stepIndex ? AppColors.emerald : AppColors.emerald.withOpacity(0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
          ),
          const SizedBox(height: 20),

          // Buttons
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 8,
              shadowColor: AppColors.emerald.withOpacity(0.4),
            ),
            child: Text(
              isLast ? 'PICK MY TICKERS →' : 'NEXT →',
              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12),
            ),
          ),
          if (!isLast) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onSkip,
              child: Text('Skip tour',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white30 : AppColors.lightTextMuted,
                )),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _TourStep {
  final String title;
  final String body;
  final IconData icon;
  final Alignment alignment;
  final Offset targetOffset;

  const _TourStep({
    required this.title, required this.body, required this.icon,
    required this.alignment, required this.targetOffset,
  });
}
