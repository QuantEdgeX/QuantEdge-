import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class EnrichmentQuizScreen extends StatefulWidget {
  const EnrichmentQuizScreen({super.key});

  @override
  State<EnrichmentQuizScreen> createState() => _EnrichmentQuizScreenState();
}

class _EnrichmentQuizScreenState extends State<EnrichmentQuizScreen>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late final PageController _pageCtrl;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  // Answers
  String? _experience;
  String? _riskStyle;
  final Set<String> _sectors = {};
  String? _goal;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 350), vsync: this)..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < 3) {
      _animCtrl.forward(from: 0);
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _finish() {
    context.read<QuizProvider>().saveEnrichmentAnswers(
      experienceLevel: _experience ?? 'beginner',
      riskStyle: _riskStyle ?? 'moderate',
      sectorInterests: _sectors.toList(),
      investingGoal: _goal ?? 'learn',
    );
  }

  bool get _canProceed {
    switch (_step) {
      case 0: return _experience != null;
      case 1: return _riskStyle != null;
      case 2: return _sectors.isNotEmpty;
      case 3: return _goal != null;
      default: return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<QuizProvider>().isDarkMode;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          // ── Step indicator ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PERSONALISE YOUR EXPERIENCE',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                ),
              ),
              Text(
                '${_step + 1} / 4',
                style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w900,
                  color: AppColors.emerald,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress bar
          Row(
            children: List.generate(4, (i) => Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i <= _step
                      ? AppColors.emerald
                      : (isDark ? Colors.white10 : Colors.black12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
          const SizedBox(height: 20),

          // ── Question cards ────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                _QuestionCard(
                  isDark: isDark,
                  icon: Icons.trending_up_rounded,
                  title: 'What\'s your experience\nlevel in investing?',
                  options: const [
                    ('🌱', 'Just starting out', 'beginner'),
                    ('📈', 'Some experience', 'intermediate'),
                    ('🏆', 'Seasoned investor', 'experienced'),
                  ],
                  selected: _experience,
                  onSelect: (v) => setState(() => _experience = v),
                ),
                _QuestionCard(
                  isDark: isDark,
                  icon: Icons.shield_outlined,
                  title: 'How do you approach\nrisk in trading?',
                  options: const [
                    ('🛡️', 'Play it safe', 'conservative'),
                    ('⚖️', 'Balanced approach', 'moderate'),
                    ('🚀', 'High risk, high reward', 'aggressive'),
                  ],
                  selected: _riskStyle,
                  onSelect: (v) => setState(() => _riskStyle = v),
                ),
                _MultiSelectCard(
                  isDark: isDark,
                  icon: Icons.category_outlined,
                  title: 'Which sectors interest\nyou the most?',
                  options: const [
                    '💻 Technology', '⚡ Energy', '🏦 Finance',
                    '🏥 Healthcare', '🛍️ Consumer', '🔬 Biotech',
                  ],
                  selected: _sectors,
                  onToggle: (v) => setState(() {
                    final clean = v.split(' ').skip(1).join(' ');
                    if (_sectors.contains(clean)) {
                      _sectors.remove(clean);
                    } else {
                      _sectors.add(clean);
                    }
                  }),
                ),
                _QuestionCard(
                  isDark: isDark,
                  icon: Icons.flag_outlined,
                  title: 'What\'s your primary\ngoal with QuantEdge?',
                  options: const [
                    ('🎓', 'Learn about markets', 'learn'),
                    ('💰', 'Grow my portfolio', 'grow'),
                    ('⚡', 'Active trading signals', 'trade'),
                  ],
                  selected: _goal,
                  onSelect: (v) => setState(() => _goal = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

          // ── Continue button ───────────────────────────────────────────
          ElevatedButton(
            onPressed: _canProceed ? _next : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              disabledBackgroundColor: isDark ? Colors.white10 : Colors.black12,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: _canProceed ? 10 : 0,
              shadowColor: AppColors.emerald.withOpacity(0.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _step < 3 ? 'CONTINUE' : 'START MY JOURNEY',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0, fontSize: 12,
                    color: _canProceed ? Colors.white
                        : (isDark ? Colors.white30 : Colors.black38),
                  ),
                ),
                if (_canProceed) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Skip ──────────────────────────────────────────────────────
          GestureDetector(
            onTap: () => context.read<QuizProvider>().skipEnrichment(),
            child: Text(
              'Skip for now →',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white30 : AppColors.lightTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single-select question card ───────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final List<(String, String, String)> options; // (emoji, label, value)
  final String? selected;
  final ValueChanged<String> onSelect;

  const _QuestionCard({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard.withOpacity(0.4) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? Colors.white10 : AppColors.lightBorder, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.emerald, size: 22),
          ),
          const SizedBox(height: 16),
          Text(title,
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic, height: 1.25,
              color: textColor,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Column(
              children: options.map((opt) {
                final isSelected = selected == opt.$3;
                return GestureDetector(
                  onTap: () => onSelect(opt.$3),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.emerald.withOpacity(0.15)
                          : (isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.emerald
                            : (isDark ? Colors.white10 : AppColors.lightBorder),
                        width: isSelected ? 2 : 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(opt.$1, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 14),
                        Text(opt.$2,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800,
                            color: isSelected ? AppColors.emerald : textColor,
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded,
                            color: AppColors.emerald, size: 20),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Multi-select card ─────────────────────────────────────────────────────────

class _MultiSelectCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _MultiSelectCard({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard.withOpacity(0.4) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? Colors.white10 : AppColors.lightBorder, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.emerald, size: 22),
          ),
          const SizedBox(height: 16),
          Text(title,
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic, height: 1.25,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text('Pick all that apply',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Wrap(
              spacing: 10, runSpacing: 10,
              children: options.map((opt) {
                final clean = opt.split(' ').skip(1).join(' ');
                final isSelected = selected.contains(clean);
                return GestureDetector(
                  onTap: () => onToggle(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.emerald.withOpacity(0.15)
                          : (isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppColors.emerald
                            : (isDark ? Colors.white10 : AppColors.lightBorder),
                        width: isSelected ? 2 : 1.5,
                      ),
                    ),
                    child: Text(opt,
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: isSelected ? AppColors.emerald : textColor,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
