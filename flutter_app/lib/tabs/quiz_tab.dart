import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class QuizTab extends StatefulWidget {
  const QuizTab({super.key});

  @override
  State<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<QuizTab> {
  String? _selectedOptionId;
  bool _submitted = false;
  bool _isCorrect = false;
  bool _isFinished = false;
  Map<String, dynamic>? _completionSummary;

  // Accumulated definitions from answered questions for summary screen
  final List<Map<String, String>> _answeredTerms = [];

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _options(Map<String, dynamic> question) {
    final raw = question['options'];
    if (raw == null) return [];
    return (raw as List).map((o) => o as Map<String, dynamic>).toList();
  }

  String _questionText(Map<String, dynamic> q) =>
      q['prompt'] ?? q['question'] ?? 'Question';

  String _contextBlurb(Map<String, dynamic> q) =>
      q['contextBlurb'] ?? q['blurb'] ?? '';

  String _questionType(Map<String, dynamic> q) =>
      q['type']?.toString() ?? 'GENERAL';

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  void _submit(QuizProvider provider, String correctOptionId) {
    if (_selectedOptionId == null) return;
    setState(() {
      _submitted = true;
      _isCorrect = _selectedOptionId == correctOptionId;
    });

    // Record term/definition for summary
    final q = provider.currentQuestion!;
    _answeredTerms.add({
      'term': _questionText(q),
      'definition': q['contextBlurb'] ?? 'See the QuantEdge glossary for details.',
    });
  }

  Future<void> _next(QuizProvider provider, String submittedOptionId) async {
    setState(() {
      _submitted = false;
      _selectedOptionId = null;
    });
    await provider.submitQuizAnswer(submittedOptionId);
  }

  void _retake(QuizProvider provider) {
    setState(() {
      _isFinished = false;
      _submitted = false;
      _selectedOptionId = null;
      _answeredTerms.clear();
      _completionSummary = null;
    });
    provider.initQuizSession();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuizProvider>();
    final isDark = provider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final mutedColor = isDark ? Colors.white54 : AppColors.lightTextMuted;
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;

    // ── Finished Screen ───────────────────────────────────────────────────
    if (_isFinished || (provider.currentQuestion == null && !provider.isLoadingQuiz)) {
      final summary = _completionSummary ?? provider.completionSummary;
      final xp = summary?['xpAwarded'] ?? 0;
      final level = summary?['currentLevel'] ?? summary?['levelTier'] ?? provider.skillLevel;
      final levelChanged = summary?['levelChanged'] == true;

      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          // Completion banner
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.12),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.emerald, width: 2),
            ),
            child: Column(children: [
              const Icon(Icons.stars_rounded, color: AppColors.emerald, size: 48),
              const SizedBox(height: 12),
              Text('QUIZ COMPLETED!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                      color: textColor, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text('+$xp XP Earned',
                  style: const TextStyle(color: AppColors.emerald, fontWeight: FontWeight.w700)),
              if (levelChanged) ...[
                const SizedBox(height: 4),
                Text('Level progressed → ${level.toString().toUpperCase()}',
                    style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ]),
          ),
          const SizedBox(height: 24),

          // Level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white12 : AppColors.lightBorder),
            ),
            child: Row(children: [
              const Icon(Icons.bar_chart_rounded, color: AppColors.emerald, size: 20),
              const SizedBox(width: 10),
              Text('Current XAI Level: ${level.toString().toUpperCase()}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: textColor, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 20),

          // Definitions recap
          if (_answeredTerms.isNotEmpty) ...[
            Text('QUESTIONS COVERED',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                    letterSpacing: 1.5, color: mutedColor)),
            const SizedBox(height: 12),
            ..._answeredTerms.map((t) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? Colors.white12 : AppColors.lightBorder),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t['term'] ?? '', style: const TextStyle(
                        fontWeight: FontWeight.w900, color: AppColors.emerald, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text(t['definition'] ?? '',
                        style: TextStyle(fontSize: 12, color: textColor, height: 1.4)),
                  ]),
                )),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => _retake(provider),
              child: const Text('RETAKE QUIZ',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      );
    }

    // ── Loading ───────────────────────────────────────────────────────────
    if (provider.isLoadingQuiz || provider.currentQuestion == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: AppColors.emerald),
          const SizedBox(height: 16),
          Text('Loading question from engine...',
              style: TextStyle(color: mutedColor, fontSize: 13)),
        ]),
      );
    }

    // ── Active Question ───────────────────────────────────────────────────
    final question = provider.currentQuestion!;
    final options = _options(question);
    final correct = question['correctOptionId'] as String? ?? '';
    final blurb = _contextBlurb(question);
    final qType = _questionType(question);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: [
        // Header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('SKILL ASSESSMENT',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                  letterSpacing: 2.0, color: mutedColor)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Level: ${provider.skillLevel.toUpperCase()}',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                    color: AppColors.emerald)),
          ),
        ]),
        const SizedBox(height: 12),

        // Type badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _typeColor(qType).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(qType,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                  color: _typeColor(qType))),
        ),
        const SizedBox(height: 12),

        // Question card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: isDark ? Colors.white12 : AppColors.lightBorder, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Context blurb (italicised scenario text)
            if (blurb.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
                ),
                child: Text(blurb,
                    style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: textColor.withOpacity(0.85),
                        height: 1.4)),
              ),
              const SizedBox(height: 16),
            ],

            // Question text
            Text(_questionText(question),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: textColor, height: 1.3)),
            const SizedBox(height: 20),

            // Options
            ...options.map((opt) {
              final id = opt['id'] as String? ?? '';
              final text = opt['text'] as String? ?? '';
              final isSelected = _selectedOptionId == id;
              final isCorrectOpt = id == correct;

              Color borderColor = Colors.transparent;
              Color bgColor = isDark ? Colors.black26 : const Color(0xFFF8FAFC);

              if (_submitted) {
                if (isCorrectOpt) {
                  borderColor = AppColors.emerald;
                  bgColor = AppColors.emerald.withOpacity(0.12);
                } else if (isSelected && !isCorrectOpt) {
                  borderColor = AppColors.rose;
                  bgColor = AppColors.rose.withOpacity(0.10);
                }
              } else if (isSelected) {
                borderColor = AppColors.emerald;
                bgColor = AppColors.emerald.withOpacity(0.12);
              }

              return GestureDetector(
                onTap: _submitted ? null : () => setState(() => _selectedOptionId = id),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: 2),
                  ),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected && !_submitted ? AppColors.emerald
                            : _submitted && isCorrectOpt ? AppColors.emerald
                            : _submitted && isSelected ? AppColors.rose
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.emerald
                              : Colors.grey.shade400,
                        ),
                      ),
                      child: _submitted && isCorrectOpt
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : _submitted && isSelected && !isCorrectOpt
                              ? const Icon(Icons.close, size: 14, color: Colors.white)
                              : Text(id,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900, fontSize: 12,
                                      color: isSelected ? Colors.white
                                          : (isDark ? Colors.white70 : Colors.black87))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(text,
                          style: TextStyle(fontSize: 13, color: textColor,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              );
            }),

            // Feedback after submit
            if (_submitted) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_isCorrect ? AppColors.emerald : AppColors.rose).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(_isCorrect ? Icons.check_circle_outline : Icons.info_outline,
                      color: _isCorrect ? AppColors.emerald : AppColors.rose, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isCorrect
                          ? 'Correct! Great analysis.'
                          : 'Not quite — review the context blurb above.',
                      style: TextStyle(
                          fontSize: 12,
                          color: _isCorrect ? AppColors.emerald : AppColors.rose,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 14),

            // Action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  if (!_submitted) {
                    if (_selectedOptionId != null) _submit(provider, correct);
                  } else {
                    // Capture before clearing
                    final captured = _selectedOptionId ?? 'A';
                    _next(provider, captured).then((_) {
                      if (provider.currentQuestion == null) {
                        setState(() {
                          _isFinished = true;
                          _completionSummary =
                              provider.completionSummary;
                        });
                      }
                    });
                  }
                },
                child: Text(
                  _submitted ? 'NEXT QUESTION →' : 'SUBMIT ANSWER',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Color _typeColor(String type) {
    switch (type.toUpperCase()) {
      case 'XAI':       return AppColors.emerald;
      case 'TECHNICAL': return AppColors.blue;
      case 'SENTIMENT': return AppColors.amber;
      case 'SCENARIO':  return AppColors.rose;
      default:          return Colors.grey;
    }
  }
}