import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/learning_provider.dart' show LearningProvider;
import '../providers/quiz_provider.dart' show QuizProvider;
import '../theme/app_theme.dart';

/// Duolingo-style onboarding: a few questions about the learner's current
/// stock-market knowledge, then a choice of where to start. The answers
/// decide how many Learn topics are unlocked.
class OnboardingQuizScreen extends StatefulWidget {
  const OnboardingQuizScreen({super.key});

  @override
  State<OnboardingQuizScreen> createState() => _OnboardingQuizScreenState();
}

class _Opt {
  final String title;
  final String? subtitle;
  final String? emoji;

  const _Opt(this.title, {this.subtitle, this.emoji});
}

class _OnboardingQuizScreenState extends State<OnboardingQuizScreen> {
  static const int _lastStep = 3;

  // Mirrors the backend curriculum order (used for the "start at my level" card).
  static const List<String> _topicTitles = [
    'Stock Market Basics',
    'Stock Ownership & Exchanges',
    'Stock Prices & Market Capitalization',
    'Reading Stock Charts',
    'Fundamental Analysis',
    'Valuation Ratios',
    'Dividends & Growth Investing',
    'Technical Analysis',
    'Risk Management',
    'Portfolio Diversification',
    'Market News & Sentiment',
    'Earnings & Company Events',
    'Trading & Market Mechanics',
    'Advanced Investing Concepts',
    'Quantitative & AI Investing',
  ];

  static const List<_Opt> _knowledgeOptions = [
    _Opt("I'm new to stocks"),
    _Opt('I know some basic terms'),
    _Opt('I can read charts and ratios'),
    _Opt("I'm an experienced investor"),
  ];

  static const List<_Opt> _experienceOptions = [
    _Opt('Never', emoji: '🌱'),
    _Opt('Once or twice', emoji: '🛒'),
    _Opt('I invest regularly', emoji: '📈'),
    _Opt('I actively trade', emoji: '⚡'),
  ];

  static const List<String> _concepts = [
    'Market capitalization',
    'P/E ratio',
    'Candlestick charts',
    'RSI & moving averages',
    'Diversification',
    'Backtesting & overfitting',
  ];

  // ── Answers ───────────────────────────────────────────────────────────────
  int _step = 0;
  int? _knowledge;
  int? _experience;
  final Set<int> _known = {};
  int? _path; // 0 = start from scratch, 1 = start at my level
  bool _isSaving = false;

  // ── Scoring ───────────────────────────────────────────────────────────────

  int get _points => (_knowledge ?? 0) * 2 + (_experience ?? 0) + _known.length;

  /// 0-based index of the topic the learner would start on.
  int get _startIndex {
    final p = _points;

    if (p <= 1) return 0;
    if (p <= 4) return 2;
    if (p <= 8) return 5;
    if (p <= 12) return 8;
    return 11;
  }

  String get _levelName {
    switch (_startIndex) {
      case 0:
        return 'newbie';
      case 2:
        return 'beginner';
      case 5:
        return 'intermediate';
      case 8:
        return 'advanced';
      default:
        return 'expert';
    }
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _knowledge != null;
      case 1:
        return _experience != null;
      case 2:
        return true; // picking none is allowed
      default:
        return _path != null;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _goNext() {
    if (!_canContinue || _isSaving) return;

    if (_step < _lastStep) {
      setState(() {
        _step++;

        // A complete beginner only has one sensible choice.
        if (_step == _lastStep && _startIndex == 0) {
          _path = 0;
        }
      });
    } else {
      _finish();
    }
  }

  void _goBack() {
    if (_step == 0 || _isSaving) return;
    setState(() => _step--);
  }

  Future<void> _finish() async {
    final learning = context.read<LearningProvider>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSaving = true);

    final useLevel = _path == 1 && _startIndex > 0;

    final ok = await learning.completeOnboarding(
      startTopicIndex: useLevel ? _startIndex : 0,
      level: useLevel ? _levelName : 'newbie',
    );

    // On success main.dart swaps this screen out for the app.
    if (!mounted) return;

    setState(() => _isSaving = false);

    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            learning.error ?? 'Could not save your starting place. Try again.',
          ),
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<QuizProvider, bool>((q) => q.isDarkMode);
    final text = isDark ? Colors.white : AppColors.lightTextPrimary;
    final muted = isDark ? Colors.white54 : AppColors.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          _buildTopBar(isDark),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey<int>(_step),
                  child: _buildStep(isDark, text, muted),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildContinueButton(),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Row(
      children: [
        IgnorePointer(
          ignoring: _step == 0,
          child: Opacity(
            opacity: _step == 0 ? 0 : 1,
            child: IconButton(
              onPressed: _goBack,
              icon: Icon(
                Icons.arrow_back_rounded,
                color: isDark ? Colors.white54 : AppColors.lightTextMuted,
              ),
            ),
          ),
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0,
              end: (_step + 1) / (_lastStep + 1),
            ),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            builder: (_, value, __) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 12,
                backgroundColor:
                    isDark ? Colors.white10 : const Color(0xFFE5E5E5),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.emerald,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  // ── Steps ─────────────────────────────────────────────────────────────────

  String get _prompt {
    switch (_step) {
      case 0:
        return 'How much do you know about stocks?';
      case 1:
        return 'Have you ever bought a stock?';
      case 2:
        return 'Which of these do you already know?';
      default:
        return "Now let's find the best place to start!";
    }
  }

  Widget _buildStep(bool isDark, Color text, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMascot(isDark, text),
        const SizedBox(height: 22),
        if (_step == 0)
          ...List.generate(
            _knowledgeOptions.length,
            (i) => _optionCard(
              isDark: isDark,
              text: text,
              title: _knowledgeOptions[i].title,
              selected: _knowledge == i,
              leading: _SignalBars(filled: i),
              onTap: () => setState(() => _knowledge = i),
            ),
          ),
        if (_step == 1)
          ...List.generate(
            _experienceOptions.length,
            (i) => _optionCard(
              isDark: isDark,
              text: text,
              title: _experienceOptions[i].title,
              selected: _experience == i,
              leading: Text(
                _experienceOptions[i].emoji ?? '',
                style: const TextStyle(fontSize: 24),
              ),
              onTap: () => setState(() => _experience = i),
            ),
          ),
        if (_step == 2) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              'Pick all that apply. It is fine to pick none!',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          ...List.generate(
            _concepts.length,
            (i) => _optionCard(
              isDark: isDark,
              text: text,
              title: _concepts[i],
              selected: _known.contains(i),
              leading: Icon(
                _known.contains(i)
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: _known.contains(i) ? AppColors.emerald : muted,
              ),
              onTap: () => setState(() {
                if (!_known.remove(i)) _known.add(i);
              }),
            ),
          ),
        ],
        if (_step == 3) ..._buildPathOptions(isDark, text),
      ],
    );
  }

  List<Widget> _buildPathOptions(bool isDark, Color text) {
    final idx = _startIndex;

    return [
      _optionCard(
        isDark: isDark,
        text: text,
        title: 'Start from scratch',
        subtitle: 'Begin with Topic 1: ${_topicTitles[0]}',
        selected: _path == 0,
        leading: const Text('📖', style: TextStyle(fontSize: 28)),
        onTap: () => setState(() => _path = 0),
      ),
      if (idx > 0)
        _optionCard(
          isDark: isDark,
          text: text,
          title: 'Start at my level',
          subtitle: 'Unlock the first ${idx + 1} topics and begin with '
              'Topic ${idx + 1}: ${_topicTitles[idx]}',
          selected: _path == 1,
          leading: const Text('🧭', style: TextStyle(fontSize: 28)),
          onTap: () => setState(() => _path = 1),
        ),
    ];
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  Widget _buildMascot(bool isDark, Color text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 66,
          height: 66,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.emerald.withOpacity(0.15),
          ),
          child: const Text('🐂', style: TextStyle(fontSize: 36)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                width: 2,
              ),
            ),
            child: Text(
              _prompt,
              style: TextStyle(
                fontSize: 16,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionCard({
    required bool isDark,
    required Color text,
    required String title,
    String? subtitle,
    required bool selected,
    required Widget leading,
    required VoidCallback onTap,
  }) {
    final borderColor = selected
        ? AppColors.emerald
        : (isDark ? Colors.white12 : const Color(0xFFE2E8F0));

    // Must be fully opaque: the flat bottom-edge shadow is drawn underneath
    // the card and would show through any transparency as a solid block.
    final Color base = isDark ? AppColors.darkSurface : Colors.white;

    final Color background = selected
        ? Color.alphaBlend(
            AppColors.emerald.withOpacity(isDark ? 0.18 : 0.10),
            base,
          )
        : base;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: _isSaving ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 2),
            // Flat "pressed button" edge like Duolingo's option cards.
            boxShadow: [
              BoxShadow(
                color: borderColor,
                offset: const Offset(0, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Center(child: leading),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.emerald : text,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: isDark
                              ? Colors.white60
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    final enabled = _canContinue && !_isSaving;
    final isLast = _step == _lastStep;

    return GestureDetector(
      onTap: enabled ? _goNext : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.emerald : const Color(0xFFE5E5E5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.emerald.withOpacity(0.55),
                    offset: const Offset(0, 4),
                    blurRadius: 0,
                  ),
                ]
              : [],
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                isLast ? 'START LEARNING' : 'CONTINUE',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: enabled ? Colors.white : const Color(0xFFAFAFAF),
                ),
              ),
      ),
    );
  }
}

/// Three little bars, [filled] of them solid (0-3), like Duolingo's level icons.
class _SignalBars extends StatelessWidget {
  final int filled;

  const _SignalBars({required this.filled});

  @override
  Widget build(BuildContext context) {
    const heights = [10.0, 17.0, 24.0];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        return Container(
          width: 7,
          height: heights[i],
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: i < filled
                ? AppColors.emerald
                : AppColors.emerald.withOpacity(0.25),
          ),
        );
      }),
    );
  }
}