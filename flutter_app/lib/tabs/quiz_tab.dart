import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/learning_models.dart';
import '../providers/learning_provider.dart';
import '../providers/quiz_provider.dart';
import '../screens/learning_quiz_screen.dart';
import '../theme/app_theme.dart';

/// QuizTab — Disha's DuoLingo-style Learning Engine
///
/// Features:
/// - Modules & Categories (15 progressive stock market curriculum topics)
/// - Daily streaks counter with animated flame badge (🔥)
/// - Overall progress & mastery bar
/// - XP, Level, and Score summary stats
/// - Interactive module quiz launcher (starts lesson and navigates to LearningQuizScreen)
class QuizTab extends StatefulWidget {
  const QuizTab({super.key});

  @override
  State<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<QuizTab> {
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

  String _scoreName(int score) => _scoreNames[score] ?? 'Newbie';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LearningProvider>().loadLearningData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final mutedColor = isDark ? Colors.white54 : AppColors.lightTextMuted;

    return Consumer<LearningProvider>(
      builder: (context, provider, _) {
        final topics = provider.topics.isNotEmpty
            ? provider.topics
            : _fallbackCurriculumTopics();

        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadLearningData();
          },
          color: AppColors.emerald,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header & Streak Bar
              SliverToBoxAdapter(
                child: _buildHeader(context, provider, isDark, textColor, mutedColor),
              ),

              // Progress & Stats Card (Streaks, XP, Score, Level)
              SliverToBoxAdapter(
                child: _buildProgressCard(context, provider, isDark, textColor, mutedColor),
              ),

              // Section Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'LEARNING MODULES',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                        ),
                      ),
                      Text(
                        '${topics.where((t) => t.completed).length}/${topics.length} COMPLETED',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.emerald,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Topic Modules List
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final topic = topics[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildTopicCard(context, provider, topic, isDark, textColor, mutedColor),
                      );
                    },
                    childCount: topics.length,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Header with Streak ──────────────────────────────────────────────────
  Widget _buildHeader(
    BuildContext context,
    LearningProvider provider,
    bool isDark,
    Color text,
    Color muted,
  ) {
    final raw = provider.lastRawResult;
    final streak = raw != null && raw['currentStreak'] != null
        ? (raw['currentStreak'] as num).toInt()
        : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LEARNING ENGINE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Master Market Concepts',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: text,
                ),
              ),
            ],
          ),
          // Animated Streak Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6D00).withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFF6D00).withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Text(
                  '$streak',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFF6D00),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress & Mastery Card ─────────────────────────────────────────────
  Widget _buildProgressCard(
    BuildContext context,
    LearningProvider provider,
    bool isDark,
    Color text,
    Color muted,
  ) {
    final progress = provider.progress;
    final score = progress?.score ?? 1;
    final xp = progress?.xp ?? 0;
    final levelName = _scoreName(score);
    final topics = provider.topics;
    final completedCount = topics.where((t) => t.completed).length;
    final double completionPct = topics.isNotEmpty
        ? (completedCount / topics.length).clamp(0.0, 1.0)
        : 0.1;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard.withOpacity(0.5) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : AppColors.lightBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatItem('SCORE', '$score/10', Icons.star_rounded, AppColors.amber),
              ),
              _buildDivider(isDark),
              Expanded(
                child: _buildStatItem('XP EARNED', '$xp', Icons.bolt_rounded, AppColors.emerald),
              ),
              _buildDivider(isDark),
              Expanded(
                child: _buildStatItem('LEVEL', levelName, Icons.trending_up_rounded, AppColors.blue),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CURRICULUM MASTERY',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                    ),
                  ),
                  Text(
                    '${(completionPct * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.emerald,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: completionPct,
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.white10 : AppColors.lightBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.emerald),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.lightTextMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      height: 32,
      width: 1,
      color: isDark ? Colors.white12 : AppColors.lightBorder,
    );
  }

  // ── Topic Module Card ───────────────────────────────────────────────────
  Widget _buildTopicCard(
    BuildContext context,
    LearningProvider provider,
    LearningTopic topic,
    bool isDark,
    Color text,
    Color muted,
  ) {
    final isLocked = !topic.unlocked;
    final isCompleted = topic.completed;
    final isCurrent = topic.status == 'current';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: isLocked
          ? () => _showLockedSnackBar(context)
          : () => _startTopicLesson(context, provider, topic),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isLocked ? 0.55 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard.withOpacity(0.5) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCurrent
                  ? AppColors.emerald
                  : (isDark ? Colors.white10 : AppColors.lightBorder),
              width: isCurrent ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Topic Icon / Status Avatar
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppColors.emerald.withOpacity(0.18)
                      : (isCurrent
                          ? AppColors.emerald.withOpacity(0.12)
                          : (isDark ? Colors.white10 : const Color(0xFFF1F5F9))),
                ),
                child: Text(
                  topic.icon.isNotEmpty ? topic.icon : '📚',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 14),

              // Topic Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'TOPIC ${topic.number}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: AppColors.emerald,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(topic),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      topic.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      topic.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Trailing action icon
              Icon(
                isLocked
                    ? Icons.lock_rounded
                    : (isCompleted ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded),
                size: isLocked ? 18 : (isCompleted ? 20 : 16),
                color: isLocked
                    ? (isDark ? Colors.white24 : AppColors.lightTextMuted)
                    : (isCompleted ? AppColors.emerald : AppColors.emerald),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(LearningTopic topic) {
    String label = 'LOCKED';
    Color bg = Colors.grey.withOpacity(0.15);
    Color fg = Colors.grey;

    if (topic.completed) {
      label = 'COMPLETED';
      bg = AppColors.emerald.withOpacity(0.15);
      fg = AppColors.emerald;
    } else if (topic.status == 'current') {
      label = 'CURRENT';
      bg = AppColors.blue.withOpacity(0.15);
      fg = AppColors.blue;
    } else if (topic.unlocked) {
      label = 'AVAILABLE';
      bg = AppColors.amber.withOpacity(0.15);
      fg = AppColors.amber;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }

  void _showLockedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pass previous topics with 8/10 to unlock this module.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _startTopicLesson(
    BuildContext context,
    LearningProvider provider,
    LearningTopic topic,
  ) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final localNav = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.emerald,
                ),
              ),
              SizedBox(width: 16),
              Flexible(child: Text('Generating adaptive lesson…')),
            ],
          ),
        ),
      ),
    );

    bool started = false;
    try {
      started = await provider.startLesson(topic.id);
    } finally {
      if (nav.canPop()) {
        nav.pop();
      }
    }

    if (!mounted) return;

    if (started) {
      await localNav.push(
        MaterialPageRoute(
          builder: (_) => const LearningQuizScreen(),
        ),
      );
      if (mounted) {
        provider.loadLearningData();
      }
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not start lesson. Please verify backend connection.'),
        ),
      );
    }
  }

  static List<LearningTopic> _fallbackCurriculumTopics() => [
    LearningTopic(
      id: 'topic_01',
      number: 1,
      title: 'Stock Market Basics',
      description: 'Understand public markets, shares, and basic exchanges.',
      status: 'current',
      unlocked: true,
      completed: false,
      subtopics: const ['Exchanges', 'Shares', 'Orders'],
      icon: '📈',
    ),
    LearningTopic(
      id: 'topic_02',
      number: 2,
      title: 'Stock Ownership & Exchanges',
      description: 'How equities, brokers, and market orders operate.',
      status: 'available',
      unlocked: true,
      completed: false,
      subtopics: const ['Brokers', 'Order Execution', 'Clearing'],
      icon: '🏛️',
    ),
    LearningTopic(
      id: 'topic_03',
      number: 3,
      title: 'Stock Prices & Market Capitalization',
      description: 'Valuation scale, mega-cap vs. small-cap asset classes.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['Market Cap', 'Stock Splits', 'Free Float'],
      icon: '💰',
    ),
    LearningTopic(
      id: 'topic_04',
      number: 4,
      title: 'Reading Stock Charts',
      description: 'Candlesticks, volume bars, and price action patterns.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['Candlesticks', 'Volume', 'Trends'],
      icon: '📊',
    ),
    LearningTopic(
      id: 'topic_05',
      number: 5,
      title: 'Fundamental Analysis',
      description: 'Balance sheets, cash flows, and corporate earnings.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['Balance Sheets', 'Income Statements', 'Free Cash Flow'],
      icon: '📑',
    ),
    LearningTopic(
      id: 'topic_06',
      number: 6,
      title: 'Valuation Ratios',
      description: 'P/E, P/B, EV/EBITDA, and comparative peer valuation.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['P/E Ratio', 'P/B Ratio', 'EV/EBITDA'],
      icon: '📐',
    ),
    LearningTopic(
      id: 'topic_07',
      number: 7,
      title: 'Technical Analysis',
      description: 'RSI, moving averages, Bollinger bands, and momentum.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['RSI', 'Moving Averages', 'MACD'],
      icon: '📉',
    ),
    LearningTopic(
      id: 'topic_08',
      number: 8,
      title: 'Risk Management',
      description: 'Position sizing, stop losses, and downside protection.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['Position Sizing', 'Stop Loss', 'Risk/Reward'],
      icon: '🛡️',
    ),
  ];
}
