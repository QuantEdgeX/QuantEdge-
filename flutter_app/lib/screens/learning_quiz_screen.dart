import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/learning_provider.dart';

class LearningQuizScreen extends StatefulWidget {
  const LearningQuizScreen({super.key});

  @override
  State<LearningQuizScreen> createState() => _LearningQuizScreenState();
}

class _LearningQuizScreenState extends State<LearningQuizScreen> {
  // The provider marks the lesson complete as soon as question 10 is
  // answered. This flag lets the user see that last question's feedback
  // before the result screen appears.
  bool _showResult = false;

  bool _isRetrying = false;

  // ──────────────────────────────────────────────────────────────────────────
  // Small safe helpers (the backend response is dynamic JSON)
  // ──────────────────────────────────────────────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    return Consumer<LearningProvider>(
      builder: (context, provider, child) {
        if (provider.currentLesson == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Learning Quiz'),
            ),
            body: const Center(
              child: Text('No lesson is currently loaded.'),
            ),
          );
        }

        if (provider.lessonComplete && _showResult) {
          return _buildResultScreen(context, provider);
        }

        final question = provider.currentQuestion;

        if (question == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _handleClose(context, provider),
            ),
            title: Text(
              provider.currentLesson!.topicTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: _buildQuizBody(
              context,
              provider,
              question,
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Close / quit
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _handleClose(
    BuildContext context,
    LearningProvider provider,
  ) async {
    // Nothing to lose once the lesson is finished.
    if (provider.lessonComplete) {
      provider.clearLesson();
      Navigator.pop(context);
      return;
    }

    final quit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quit lesson?'),
        content: const Text(
          'Your progress in this lesson will be lost.',
        ),
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

    if (quit == true && context.mounted) {
      provider.clearLesson();
      Navigator.pop(context);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Quiz body
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildQuizBody(
    BuildContext context,
    LearningProvider provider,
    dynamic question,
  ) {
    final total = provider.totalQuestions;
    final current = provider.questionNumber;

    // Progress = questions already answered (current one counts once
    // it has been checked).
    final answeredCount = (current - 1) + (provider.hasAnswered ? 1 : 0);
    final progress = total == 0 ? 0.0 : answeredCount / total;

    return Column(
      children: [
        _buildProgressHeader(
          context,
          provider,
          progress,
          current,
          total,
          _isReview(question),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuestionType(context, question.type),
                const SizedBox(height: 12),
                _buildQuestionCard(context, question),
                const SizedBox(height: 20),
                _buildOptions(context, provider, question),
                if (provider.hasAnswered) ...[
                  const SizedBox(height: 18),
                  _buildFeedback(context, provider),
                ],
              ],
            ),
          ),
        ),
        if (provider.error != null && !provider.hasAnswered)
          _buildErrorBanner(context, provider),
        _buildBottomButton(context, provider),
      ],
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    LearningProvider provider,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.red.withOpacity(0.08),
        border: Border.all(
          color: Colors.red.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not check your answer. Please try again.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.red,
            ),
            onPressed: provider.clearError,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHeader(
    BuildContext context,
    LearningProvider provider,
    double progress,
    int current,
    int total,
    bool isReview,
  ) {
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'QUESTION $current',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: primary,
                ),
              ),
              if (isReview) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: Colors.orange.withOpacity(0.15),
                  ),
                  child: const Text(
                    'REVIEW',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '$current / $total',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withOpacity(0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor:
                  Theme.of(context).dividerColor.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionType(BuildContext context, String type) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: Theme.of(context)
            .colorScheme
            .primary
            .withOpacity(0.08),
      ),
      child: Text(
        type.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    dynamic question,
  ) {
    final blurb = (question.contextBlurb ?? '').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blurb.isNotEmpty) ...[
            Text(
              blurb,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            question.prompt,
            style: const TextStyle(
              fontSize: 20,
              height: 1.3,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(
    BuildContext context,
    LearningProvider provider,
    dynamic question,
  ) {
    return Column(
      children: question.options.map<Widget>((option) {
        final answered = provider.hasAnswered;
        final result = provider.lastAnswerResult;
        final optionId = option.id.toUpperCase();
        final selectedOptionId =
            (result?.selectedOptionId ?? provider.selectedOptionId)
                ?.toUpperCase();
        final correctOptionId = result?.correctOptionId?.toUpperCase();
        final selected = selectedOptionId == optionId;

        // Always reveal the right answer once the question is checked,
        // whether the learner got it right or wrong.
        final isCorrectOption = answered && correctOptionId == optionId;

        final incorrectSelection =
            answered && selected && !isCorrectOption;

        final feedbackColor = isCorrectOption
            ? Colors.green
            : incorrectSelection
                ? Colors.red
                : null;

        final highlightColor = feedbackColor ??
            (selected ? Theme.of(context).colorScheme.primary : null);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: answered || provider.isSubmitting
                ? null
                : () {
                    provider.selectAnswer(option.id);
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: highlightColor != null
                    ? highlightColor.withOpacity(0.09)
                    : Theme.of(context).cardColor,
                border: Border.all(
                  color: highlightColor ??
                      Theme.of(context).dividerColor.withOpacity(0.45),
                  width: highlightColor != null ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: highlightColor ??
                          Theme.of(context)
                              .dividerColor
                              .withOpacity(0.18),
                    ),
                    child: Text(
                      option.id.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: highlightColor != null
                            ? Colors.white
                            : Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isCorrectOption)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green,
                      size: 21,
                    )
                  else if (incorrectSelection)
                    const Icon(
                      Icons.cancel_rounded,
                      color: Colors.red,
                      size: 21,
                    )
                  else if (selected && !answered)
                    Icon(
                      Icons.radio_button_checked_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 21,
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFeedback(
    BuildContext context,
    LearningProvider provider,
  ) {
    final result = provider.lastAnswerResult;

    if (result == null) {
      return const SizedBox.shrink();
    }

    final raw = provider.lastRawResult ?? const <String, dynamic>{};

    final correct = result.correct;
    final tip = (raw['learningTip'] ?? '').toString();
    final streak = _toInt(raw['currentStreak']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: correct
            ? Colors.green.withOpacity(0.08)
            : Colors.red.withOpacity(0.08),
        border: Border.all(
          color: correct
              ? Colors.green.withOpacity(0.25)
              : Colors.red.withOpacity(0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: correct ? Colors.green : Colors.red,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      correct ? 'Correct!' : 'Not quite.',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: correct ? Colors.green : Colors.red,
                      ),
                    ),
                    if (correct && streak >= 2) ...[
                      const SizedBox(width: 8),
                      Text(
                        '🔥 $streak in a row',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
                if (result.explanation != null &&
                    result.explanation!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    result.explanation!,
                    style: const TextStyle(
                      fontSize: 12,
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
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withOpacity(0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton(
    BuildContext context,
    LearningProvider provider,
  ) {
    final answered = provider.hasAnswered;
    final canSubmit = provider.canSubmitAnswer;
    final lessonDone = provider.lessonComplete;

    String buttonText;

    if (provider.isSubmitting) {
      buttonText = 'CHECKING...';
    } else if (answered) {
      buttonText = lessonDone ||
              provider.currentQuestionIndex >=
                  provider.totalQuestions - 1
          ? 'VIEW RESULT'
          : 'NEXT QUESTION';
    } else {
      buttonText = 'CHECK ANSWER';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: provider.isSubmitting
              ? null
              : answered
                  ? () {
                      if (lessonDone) {
                        setState(() => _showResult = true);
                      } else {
                        provider.nextQuestion();
                      }
                    }
                  : canSubmit
                      ? () async {
                          await provider.submitAnswer();
                        }
                      : null,
          child: provider.isSubmitting
              ? const SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  buttonText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Result screen
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildResultScreen(
    BuildContext context,
    LearningProvider provider,
  ) {
    final result = provider.lastAnswerResult;
    final raw = provider.lastRawResult ?? const <String, dynamic>{};
    final passed = provider.lessonPassed;

    final correctCount = _toInt(raw['correctAnswers'], result?.score ?? 0);
    final xp = _toInt(raw['xpEarned'], result?.xpEarned ?? 0);
    final scoreBefore = _toInt(raw['scoreBefore']);
    final scoreAfter = _toInt(raw['scoreAfter']);
    final scoreName = (raw['scoreName'] ?? '').toString();
    final scoreIncreased = raw['scoreIncreased'] == true;
    final dayStreak = _toInt(raw['dayStreak']);
    final allCompleted = raw['allTopicsCompleted'] == true;

    final message = (raw['message'] ?? '').toString();

    final weakAreas = (raw['weakAreas'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();

    final mistakes = (raw['mistakes'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final nextTopic = raw['nextTopic'] is Map
        ? Map<String, dynamic>.from(raw['nextTopic'] as Map)
        : null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: passed
                        ? Colors.green.withOpacity(0.12)
                        : Colors.red.withOpacity(0.12),
                  ),
                  child: Icon(
                    passed
                        ? Icons.emoji_events_rounded
                        : Icons.refresh_rounded,
                    size: 42,
                    color: passed ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  passed ? 'Lesson Complete!' : 'Keep Practicing!',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message.isNotEmpty
                      ? message
                      : passed
                          ? 'Great work. You passed this lesson.'
                          : 'You need 8 correct answers to unlock the next topic.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withOpacity(0.65),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: _buildResultStat(
                        context,
                        '$correctCount/10',
                        'SCORE',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildResultStat(
                        context,
                        '+$xp',
                        'XP EARNED',
                      ),
                    ),
                  ],
                ),
                if (scoreIncreased && scoreAfter > 0) ...[
                  const SizedBox(height: 14),
                  _buildInfoBanner(
                    context,
                    icon: Icons.trending_up_rounded,
                    color: Colors.green,
                    text: 'Level up! Score $scoreBefore → $scoreAfter'
                        '${scoreName.isNotEmpty ? ' · $scoreName' : ''}',
                  ),
                ],
                if (dayStreak >= 1) ...[
                  const SizedBox(height: 10),
                  _buildInfoBanner(
                    context,
                    icon: Icons.local_fire_department_rounded,
                    color: Colors.orange,
                    text: '$dayStreak day streak',
                  ),
                ],
                if (passed && allCompleted) ...[
                  const SizedBox(height: 10),
                  _buildInfoBanner(
                    context,
                    icon: Icons.workspace_premium_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    text: 'You completed the entire learning path!',
                  ),
                ] else if (passed && nextTopic != null) ...[
                  const SizedBox(height: 10),
                  _buildInfoBanner(
                    context,
                    icon: Icons.lock_open_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    text: 'Unlocked: ${nextTopic['title'] ?? 'Next topic'}',
                  ),
                ],
                if (weakAreas.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'NEEDS PRACTICE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.55),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: weakAreas
                          .map(
                            (area) => Chip(
                              label: Text(
                                area,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                if (mistakes.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _buildMistakesReview(context, mistakes),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      provider.clearLesson();
                      Navigator.pop(context);
                    },
                    child: Text(
                      passed ? 'CONTINUE' : 'BACK TO LEARNING PATH',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                if (!passed) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _isRetrying
                          ? null
                          : () async {
                              setState(() => _isRetrying = true);

                              final success = await provider.retryLesson();

                              if (!mounted) return;

                              setState(() {
                                _isRetrying = false;

                                // A new lesson starts at question 1.
                                if (success) {
                                  _showResult = false;
                                }
                              });

                              if (!success && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      provider.error ??
                                          'Could not restart the lesson.',
                                    ),
                                  ),
                                );
                              }
                            },
                      child: _isRetrying
                          ? const SizedBox(
                              width: 21,
                              height: 21,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'RETRY WITH NEW QUESTIONS',
                              style: TextStyle(
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
    );
  }

  Widget _buildInfoBanner(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withOpacity(0.09),
        border: Border.all(
          color: color.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMistakesReview(
    BuildContext context,
    List<Map<String, dynamic>> mistakes,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.4),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          title: Text(
            'Review your mistakes (${mistakes.length})',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: mistakes.map((m) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (m['prompt'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your answer: ${m['yourAnswer'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Correct answer: ${m['correctAnswer'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (m['explanation'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildResultStat(
    BuildContext context,
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.4),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }
}