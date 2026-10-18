import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Both providers declare an `AppTab` enum, so import only what is needed.
import '../providers/learning_provider.dart' show LearningProvider;
import '../providers/quiz_provider.dart' show QuizProvider;
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// QuizTab — Duolingo-style adaptive stock lesson (runs on the learning engine)
// ─────────────────────────────────────────────────────────────────────────────
class QuizTab extends StatefulWidget {
  const QuizTab({super.key});

  @override
  State<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<QuizTab> with TickerProviderStateMixin {
  // Same ladder as the backend's SCORE_NAMES (score 1-10).
  static const Map<int, String> _scoreNames = {
    1: 'Newbie',
    2: 'Beginner',
    3: 'Beginner+',
    4: 'Intermediate',
    5: 'Intermediate+',
    6: 'Advanced',
    7: 'Advanced+',
    8: 'Expert',
    9: 'Expert+',
    10: 'Master',
  };

  // ── UI state ──────────────────────────────────────────────────────────────
  // The provider marks the lesson complete as soon as question 10 is
  // answered; this lets the learner read that last explanation first.
  bool _showResult = false;
  bool _isStarting = false;
  bool _isRetrying = false;
  int _lessonStreak = 0;

  late final AnimationController _feedbackAnim;
  late final Animation<double> _feedbackScale;

  late final AnimationController _streakAnim;
  late final Animation<double> _streakScale;

  @override
  void initState() {
    super.initState();

    _feedbackAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _feedbackScale = CurvedAnimation(
      parent: _feedbackAnim,
      curve: Curves.elasticOut,
    );

    _streakAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _streakScale = CurvedAnimation(
      parent: _streakAnim,
      curve: Curves.elasticOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final provider = context.read<LearningProvider>();

      if (provider.progress == null &&
          provider.topics.isEmpty &&
          !provider.isLoading) {
        provider.loadLearningData();
      }
    });
  }

  @override
  void dispose() {
    _feedbackAnim.dispose();
    _streakAnim.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _scoreName(int score) => _scoreNames[score] ?? 'Newbie';

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _isReview(dynamic question) {
    try {
      return question.isReview == true;
    } catch (_) {
      return false;
    }
  }

  Color _typeColor(String type) {
    switch (type.toUpperCase()) {
      case 'CONCEPT':
        return AppColors.blue;
      case 'SCENARIO':
        return AppColors.rose;
      case 'CALCULATION':
        return AppColors.amber;
      case 'CHART':
        return AppColors.emerald;
      case 'COMPARISON':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _startLesson(
    LearningProvider provider, [
    String? topicId,
  ]) async {
    setState(() => _isStarting = true);

    final started = await provider.startLesson(topicId);

    if (!mounted) return;

    setState(() {
      _isStarting = false;

      if (started) {
        _showResult = false;
        _lessonStreak = 0;
      }
    });

    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not start the lesson.'),
        ),
      );
    }
  }

  Future<void> _submit(LearningProvider provider) async {
    final ok = await provider.submitAnswer();

    // On failure the backend has NOT recorded the answer, so the learner can
    // simply tap "Check answer" again (an error banner explains what happened).
    if (!mounted || !ok) return;

    final raw = provider.lastRawResult ?? const <String, dynamic>{};
    final correct = provider.lastAnswerResult?.correct == true;

    setState(() => _lessonStreak = _toInt(raw['currentStreak']));

    _feedbackAnim.forward(from: 0);

    if (correct) {
      _streakAnim.forward(from: 0);
    }
  }

  void _next(LearningProvider provider) {
    if (provider.lessonComplete) {
      setState(() => _showResult = true);
    } else {
      provider.nextQuestion();
    }
  }

  Future<void> _confirmQuit(LearningProvider provider) async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quit lesson?'),
        content: const Text('Your progress in this lesson will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('KEEP LEARNING'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('QUIT'),
          ),
        ],
      ),
    );

    if (quit == true && mounted) {
      provider.clearLesson();
      setState(() {
        _showResult = false;
        _lessonStreak = 0;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<QuizProvider, bool>((q) => q.isDarkMode);
    final provider = context.watch<LearningProvider>();

    final text = isDark ? Colors.white : AppColors.lightTextPrimary;
    final muted = isDark ? Colors.white54 : AppColors.lightTextMuted;
    final surface = isDark ? AppColors.darkSurface : Colors.white;

    final inLesson = provider.currentLesson != null;
    final showResult = inLesson && provider.lessonComplete && _showResult;

    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(provider, isDark, text, surface, inLesson),
            if (inLesson) _buildProgressBar(provider, isDark),
            Expanded(
              child: _buildBody(
                provider,
                isDark,
                text,
                muted,
                surface,
                inLesson,
              ),
            ),
          ],
        ),
        if (showResult)
          _buildResultOverlay(provider, isDark, text, muted, surface),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER (score level, streak, XP, quit)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(
    LearningProvider p,
    bool isDark,
    Color text,
    Color surface,
    bool inLesson,
  ) {
    final score = p.progress?.score ?? 0;
    final xp = p.progress?.xp ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          _levelBadge(score),
          const SizedBox(width: 8),
          if (inLesson) _buildStreakBadge(text),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.flash_on_rounded,
                  color: AppColors.amber,
                  size: 14,
                ),
                const SizedBox(width: 3),
                Text(
                  '$xp XP',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.amber,
                  ),
                ),
              ],
            ),
          ),
          if (inLesson && !p.lessonComplete) ...[
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Quit lesson',
              icon: Icon(
                Icons.close_rounded,
                size: 20,
                color: text.withOpacity(0.6),
              ),
              onPressed: () => _confirmQuit(p),
            ),
          ],
        ],
      ),
    );
  }

  Widget _levelBadge(int score) {
    final color = score >= 7
        ? AppColors.rose
        : score >= 4
            ? AppColors.amber
            : AppColors.emerald;

    final icon = score >= 7
        ? Icons.whatshot_rounded
        : score >= 4
            ? Icons.trending_up_rounded
            : Icons.star_outline_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 3),
          Text(
            score > 0 ? _scoreName(score).toUpperCase() : 'LEVEL',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakBadge(Color text) {
    const orange = Color(0xFFFF6D00);

    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.0).animate(_streakScale),
      child: AnimatedBuilder(
        animation: _streakScale,
        builder: (_, child) => Transform.scale(
          scale: 1 + (_streakScale.value * 0.0) + (_streakAnim.isAnimating ? 0.15 : 0),
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _lessonStreak > 0
                ? orange.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 3),
              Text(
                '$_lessonStreak',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _lessonStreak > 0 ? orange : text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LESSON PROGRESS BAR (replaces the old XP / hearts bar)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildProgressBar(LearningProvider p, bool isDark) {
    final total = p.totalQuestions;
    final answered =
        (p.questionNumber - 1) + (p.hasAnswered ? 1 : 0);
    final target = total == 0 ? 0.0 : (answered / total).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                p.currentLesson!.topicTitle.toString().toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppColors.emerald,
                ),
              ),
              Text(
                '${p.questionNumber} / $total',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: target),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (_, value, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor:
                    isDark ? Colors.white10 : AppColors.lightBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.emerald,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BODY
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBody(
    LearningProvider p,
    bool isDark,
    Color text,
    Color muted,
    Color surface,
    bool inLesson,
  ) {
    if (!inLesson) {
      if (p.isLoading || _isStarting) {
        return _buildLoadingView(
          isDark,
          muted,
          _isStarting ? 'Preparing your lesson...' : 'Loading...',
        );
      }

      return _buildHub(p, isDark, text, muted, surface);
    }

    final q = p.currentQuestion;

    if (q == null) {
      return _buildLoadingView(isDark, muted, 'Generating your question...');
    }

    return _buildQuestionView(p, q, isDark, text, muted, surface);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HUB (no lesson running): current topic + start button
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHub(
    LearningProvider p,
    bool isDark,
    Color text,
    Color muted,
    Color surface,
  ) {
    if (p.topics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📡', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 14),
              Text(
                'Could not load your lessons',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p.error ?? 'Check that the backend is running.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted, height: 1.4),
              ),
              const SizedBox(height: 20),
              _primaryButton(
                label: 'TRY AGAIN',
                onPressed: p.loadLearningData,
              ),
            ],
          ),
        ),
      );
    }

    // Current topic, otherwise the first available one, otherwise the last.
    dynamic target;

    for (final t in p.topics) {
      if (t.status == 'current') {
        target = t;
        break;
      }
    }

    target ??= p.topics.cast<dynamic>().firstWhere(
          (t) => t.unlocked == true && t.completed != true,
          orElse: () => p.topics.last,
        );

    final allDone = p.topics.every((t) => t.completed == true);
    final icon = target.icon.toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.white12 : AppColors.lightBorder,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                allDone ? '🏆' : (icon.isNotEmpty ? icon : '📚'),
                style: const TextStyle(fontSize: 44),
              ),
              const SizedBox(height: 12),
              Text(
                allDone
                    ? 'PATH COMPLETE'
                    : 'TOPIC ${target.number} · UP NEXT',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                target.title.toString(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: text,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                allDone
                    ? 'You finished every topic. Keep practising to stay sharp!'
                    : target.description.toString(),
                style: TextStyle(fontSize: 13, color: muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoChip('10 questions', AppColors.blue),
                  _infoChip('8 to pass', AppColors.emerald),
                  _infoChip('New questions every time', AppColors.amber),
                ],
              ),
              const SizedBox(height: 20),
              _primaryButton(
                label: allDone ? 'PRACTISE AGAIN' : 'START LESSON',
                onPressed: () => _startLesson(p, target.id.toString()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.emerald,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QUESTION VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildQuestionView(
    LearningProvider p,
    dynamic q,
    bool isDark,
    Color text,
    Color muted,
    Color surface,
  ) {
    final result = p.lastAnswerResult;
    final answered = p.hasAnswered;
    final correct = result?.correct == true;

    final blurb = (q.contextBlurb ?? '').toString();
    final qType = (q.type ?? 'CONCEPT').toString();
    final topic = p.currentLesson!.topicTitle.toString();
    final isReview = _isReview(q);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        if (topic.isNotEmpty) ...[
          Container(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '📚  $topic',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        Row(
          children: [
            _typeBadge(qType),
            if (isReview) ...[
              const SizedBox(width: 8),
              _typeBadge('REVIEW', color: Colors.orange),
            ],
            const Spacer(),
            Text(
              'Q ${p.questionNumber} of ${p.totalQuestions}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white38 : muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (blurb.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.emerald.withOpacity(0.25)),
            ),
            child: Text(
              blurb,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: text.withOpacity(0.85),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: answered
                  ? (correct ? AppColors.emerald : AppColors.rose)
                  : (isDark ? Colors.white12 : AppColors.lightBorder),
              width: answered ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                q.prompt.toString(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: text,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),

              ...q.options.map<Widget>(
                (option) => _buildOption(option, p, isDark, text),
              ),

              if (answered) ...[
                const SizedBox(height: 10),
                _buildFeedback(p, text),
              ],

              if (p.error != null && !answered) ...[
                const SizedBox(height: 10),
                _buildErrorBanner(p),
              ],

              const SizedBox(height: 14),
              _buildActionButton(p),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typeBadge(String type, {Color? color}) {
    final c = color ?? _typeColor(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        type.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: c,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OPTION TILE
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOption(
    dynamic option,
    LearningProvider p,
    bool isDark,
    Color text,
  ) {
    final id = option.id.toString().toUpperCase();
    final optText = option.text.toString();

    final answered = p.hasAnswered;
    final result = p.lastAnswerResult;

    final selectedId =
        (result?.selectedOptionId ?? p.selectedOptionId)?.toUpperCase();
    final correctId = result?.correctOptionId?.toUpperCase();

    final isSelected = selectedId == id;

    // Always reveal the right answer once the question has been checked.
    final isCorrectOpt = answered && correctId == id;
    final isWrongSelection = answered && isSelected && !isCorrectOpt;

    Color borderCol = isDark ? Colors.white12 : const Color(0xFFE2E8F0);
    Color bgCol = isDark ? const Color(0xFF1A2235) : const Color(0xFFF8FAFC);

    if (isWrongSelection) {
      borderCol = AppColors.rose;
      bgCol = AppColors.rose.withOpacity(0.10);
    } else if (isCorrectOpt) {
      borderCol = AppColors.emerald;
      bgCol = AppColors.emerald.withOpacity(0.12);
    } else if (!answered && isSelected) {
      borderCol = AppColors.emerald;
      bgCol = AppColors.emerald.withOpacity(0.1);
    }

    Widget leading;

    if (isWrongSelection) {
      leading = _circleIcon(Icons.close_rounded, AppColors.rose);
    } else if (isCorrectOpt) {
      leading = _circleIcon(Icons.check_rounded, AppColors.emerald);
    } else {
      leading = _circleLabel(id, !answered && isSelected, isDark);
    }

    return GestureDetector(
      onTap: answered || p.isSubmitting
          ? null
          : () => p.selectAnswer(option.id.toString()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgCol,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderCol, width: 1.8),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                optText,
                style: TextStyle(
                  fontSize: 13,
                  color: text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleIcon(IconData icon, Color color) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }

  Widget _circleLabel(String label, bool selected, bool isDark) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColors.emerald : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.emerald : Colors.grey.shade400,
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: selected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FEEDBACK PANEL (explanation + tip come from the answer response)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildFeedback(LearningProvider p, Color text) {
    final result = p.lastAnswerResult;

    if (result == null) {
      return const SizedBox.shrink();
    }

    final raw = p.lastRawResult ?? const <String, dynamic>{};
    final correct = result.correct == true;
    final color = correct ? AppColors.emerald : AppColors.rose;

    final explanation = (result.explanation ?? '').toString();
    final tip = (raw['learningTip'] ?? '').toString();

    return ScaleTransition(
      scale: _feedbackScale,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  correct ? Icons.check_circle_rounded : Icons.info_rounded,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  correct ? 'Excellent! 🎉' : 'Not quite.',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                explanation,
                style: TextStyle(
                  fontSize: 12,
                  color: text.withOpacity(0.85),
                  height: 1.4,
                ),
              ),
            ],
            if (tip.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '💡 $tip',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: text.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(LearningProvider p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.rose.withOpacity(0.08),
        border: Border.all(color: AppColors.rose.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.rose,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${p.error}',
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppColors.rose,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            onTap: p.clearError,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AppColors.rose,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTION BUTTON
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildActionButton(LearningProvider p) {
    final answered = p.hasAnswered;
    final canSubmit = p.canSubmitAnswer;
    final correct = p.lastAnswerResult?.correct == true;

    final isLast = p.lessonComplete ||
        p.currentQuestionIndex >= p.totalQuestions - 1;

    final label = p.isSubmitting
        ? 'CHECKING...'
        : answered
            ? (isLast ? 'VIEW RESULT' : 'NEXT QUESTION  →')
            : 'CHECK ANSWER';

    final background = answered
        ? (correct ? AppColors.emerald : AppColors.rose)
        : canSubmit
            ? AppColors.emerald
            : Colors.grey.shade600;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: canSubmit ? 3 : 0,
        ),
        onPressed: p.isSubmitting
            ? null
            : answered
                ? () => _next(p)
                : canSubmit
                    ? () => _submit(p)
                    : null,
        child: p.isSubmitting
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOADING VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLoadingView(bool isDark, Color muted, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            height: 42,
            width: 42,
            child: CircularProgressIndicator(
              color: AppColors.emerald,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Questions are written for your level',
            style: TextStyle(
              color: AppColors.emerald.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESULT OVERLAY (replaces the old round-complete + level-up overlays)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildResultOverlay(
    LearningProvider p,
    bool isDark,
    Color text,
    Color muted,
    Color surface,
  ) {
    final raw = p.lastRawResult ?? const <String, dynamic>{};

    final passed = p.lessonPassed;
    final correctCount = _toInt(raw['correctAnswers']);
    final xp = _toInt(raw['xpEarned']);
    final scoreBefore = _toInt(raw['scoreBefore']);
    final scoreAfter = _toInt(raw['scoreAfter']);
    final scoreIncreased = raw['scoreIncreased'] == true;
    final dayStreak = _toInt(raw['dayStreak']);
    final message = (raw['message'] ?? '').toString();

    final weakAreas = (raw['weakAreas'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();

    final nextTopic = raw['nextTopic'] is Map
        ? Map<String, dynamic>.from(raw['nextTopic'] as Map)
        : null;

    final accent = passed ? AppColors.emerald : AppColors.amber;

    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: accent, width: 2.5),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    passed ? '🏆' : '💪',
                    style: const TextStyle(fontSize: 48),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    passed ? 'LESSON COMPLETE!' : 'KEEP PRACTISING',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: accent,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$correctCount / 10 correct',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+$xp XP',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.amber,
                    ),
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: muted, height: 1.4),
                    ),
                  ],
                  if (scoreIncreased && scoreAfter > 0) ...[
                    const SizedBox(height: 10),
                    _resultChip(
                      '⭐ Level up! $scoreBefore → $scoreAfter · '
                      '${_scoreName(scoreAfter)}',
                      AppColors.amber,
                    ),
                  ],
                  if (passed && nextTopic != null) ...[
                    const SizedBox(height: 8),
                    _resultChip(
                      '🔓 Unlocked: ${nextTopic['title'] ?? 'Next topic'}',
                      AppColors.emerald,
                    ),
                  ],
                  if (dayStreak >= 1) ...[
                    const SizedBox(height: 8),
                    _resultChip(
                      '🔥 $dayStreak day streak',
                      const Color(0xFFFF6D00),
                    ),
                  ],
                  if (weakAreas.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'NEEDS PRACTICE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: weakAreas
                          .map((a) => _resultChip(a, AppColors.rose))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        p.clearLesson();
                        setState(() {
                          _showResult = false;
                          _lessonStreak = 0;
                        });
                      },
                      child: Text(
                        passed ? 'CONTINUE  →' : 'BACK TO LESSONS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (!passed) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.emerald),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isRetrying
                            ? null
                            : () async {
                                setState(() => _isRetrying = true);

                                final ok = await p.retryLesson();

                                if (!mounted) return;

                                setState(() {
                                  _isRetrying = false;

                                  if (ok) {
                                    _showResult = false;
                                    _lessonStreak = 0;
                                  }
                                });

                                if (!ok) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        p.error ??
                                            'Could not restart the lesson.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        child: _isRetrying
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.emerald,
                                ),
                              )
                            : const Text(
                                'RETRY WITH NEW QUESTIONS',
                                style: TextStyle(
                                  color: AppColors.emerald,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}