import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/learning_provider.dart';
import '../models/learning_models.dart';
import 'learning_quiz_screen.dart';

class LearningPathScreen extends StatefulWidget {
  const LearningPathScreen({super.key});

  @override
  State<LearningPathScreen> createState() => _LearningPathScreenState();
}

class _LearningPathScreenState extends State<LearningPathScreen> {
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

  String _scoreName(int score) => _scoreNames[score] ?? 'Newbie';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LearningProvider>().loadLearningData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LearningProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: _buildBody(context, provider),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    LearningProvider provider,
  ) {
    if (provider.isLoading && provider.topics.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (provider.error != null && provider.topics.isEmpty) {
      return _buildError(context, provider);
    }

    return RefreshIndicator(
      onRefresh: provider.loadLearningData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeader(context, provider),
          ),
          SliverToBoxAdapter(
            child: _buildProgressCard(context, provider),
          ),
          SliverToBoxAdapter(
            child: _buildSectionTitle(context),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final topic = provider.topics[index];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildTopicCard(
                      context,
                      provider,
                      topic,
                    ),
                  );
                },
                childCount: provider.topics.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    LearningProvider provider,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LEARNING PATH',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Master the market,\none topic at a time.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Build your investing knowledge through short interactive lessons.',
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
        ],
      ),
    );
  }

  Widget _buildProgressCard(
    BuildContext context,
    LearningProvider provider,
  ) {
    final progress = provider.progress;

    final score = progress?.score ?? 0;
    final xp = progress?.xp ?? 0;

    // The backend has no numeric "level"; the level is the score's name
    // (Newbie ... Master), derived from the 1-10 score.
    final levelName = score > 0 ? _scoreName(score) : '-';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildProgressStat(
              context,
              value: '$score',
              label: 'SCORE',
              icon: Icons.star_rounded,
            ),
          ),
          _buildDivider(context),
          Expanded(
            child: _buildProgressStat(
              context,
              value: '$xp',
              label: 'XP',
              icon: Icons.bolt_rounded,
            ),
          ),
          _buildDivider(context),
          Expanded(
            child: _buildProgressStat(
              context,
              value: levelName,
              label: 'LEVEL',
              icon: Icons.trending_up_rounded,
              valueSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStat(
    BuildContext context, {
    required String value,
    required String label,
    required IconData icon,
    double valueSize = 20,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: primary,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: valueSize,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: Theme.of(context)
                .textTheme
                .bodySmall
                ?.color
                ?.withOpacity(0.55),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      height: 45,
      width: 1,
      color: Theme.of(context).dividerColor.withOpacity(0.5),
    );
  }

  Widget _buildSectionTitle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Text(
            'YOUR JOURNEY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withOpacity(0.6),
            ),
          ),
          const Spacer(),
          Text(
            '10 QUESTIONS / LESSON',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withOpacity(0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicCard(
    BuildContext context,
    LearningProvider provider,
    LearningTopic topic,
  ) {
    final isLocked = !topic.unlocked;
    final isCompleted = topic.completed;
    final isCurrent = topic.status == 'current';

    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: isLocked
          ? () => _showLockedMessage(context)
          : () => _startTopic(context, provider, topic),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isLocked ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(context).cardColor,
            border: Border.all(
              color: isCurrent
                  ? primary.withOpacity(0.5)
                  : Theme.of(context).dividerColor.withOpacity(0.4),
              width: isCurrent ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildTopicIcon(
                context,
                topic,
                isLocked,
                isCompleted,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'TOPIC ${topic.number}',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: primary,
                          ),
                        ),
                        const SizedBox(width: 7),
                        _buildStatusBadge(
                          context,
                          topic,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      topic.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      topic.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isLocked
                    ? Icons.lock_rounded
                    : isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.arrow_forward_ios_rounded,
                size: isLocked ? 18 : 19,
                color: isLocked
                    ? Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.4)
                    : primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopicIcon(
    BuildContext context,
    LearningTopic topic,
    bool isLocked,
    bool isCompleted,
  ) {
    final primary = Theme.of(context).colorScheme.primary;

    Widget child;

    if (isLocked) {
      child = Icon(
        Icons.lock_outline_rounded,
        color: Theme.of(context)
            .textTheme
            .bodySmall
            ?.color
            ?.withOpacity(0.45),
        size: 22,
      );
    } else if (isCompleted) {
      child = Icon(
        Icons.check_rounded,
        color: primary,
        size: 22,
      );
    } else {
      final namedIcon = _iconFromName(topic.icon);

      if (namedIcon != null) {
        child = Icon(
          namedIcon,
          color: primary,
          size: 22,
        );
      } else {
        // The backend sends an emoji (e.g. "📈") as the topic icon.
        child = Text(
          topic.icon.isNotEmpty ? topic.icon : '🎓',
          style: const TextStyle(fontSize: 22),
        );
      }
    }

    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLocked
            ? Theme.of(context).dividerColor.withOpacity(0.2)
            : primary.withOpacity(0.1),
      ),
      child: child,
    );
  }

  Widget _buildStatusBadge(
    BuildContext context,
    LearningTopic topic,
  ) {
    String text;

    if (topic.completed) {
      text = 'COMPLETED';
    } else if (topic.status == 'current') {
      text = 'CURRENT';
    } else if (topic.unlocked) {
      text = 'AVAILABLE';
    } else {
      text = 'LOCKED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: Theme.of(context)
            .colorScheme
            .primary
            .withOpacity(topic.unlocked ? 0.1 : 0.05),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: Theme.of(context)
              .colorScheme
              .primary
              .withOpacity(topic.unlocked ? 1 : 0.5),
        ),
      ),
    );
  }

  void _showLockedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pass the previous topic with 8/10 to unlock this one.',
        ),
      ),
    );
  }

  Future<void> _startTopic(
    BuildContext context,
    LearningProvider provider,
    LearningTopic topic,
  ) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    // Show loading dialog while the backend generates the first question
    // (this can take a few seconds because questions are validated).
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
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Flexible(
                child: Text('Preparing your lesson…'),
              ),
            ],
          ),
        ),
      ),
    );

    var started = false;

    try {
      // Pass topic.id directly to startLesson
      started = await provider.startLesson(topic.id);
    } finally {
      // Always close the dialog, even if something threw.
      rootNavigator.pop();
    }

    if (!context.mounted) {
      return;
    }

    if (!started) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.error ?? 'Could not start the lesson.',
          ),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LearningQuizScreen(),
      ),
    );

    // Refresh unlock status / score after coming back from the lesson.
    if (context.mounted) {
      provider.loadLearningData();
    }
  }

  /// Maps legacy icon NAMES to Material icons. Returns null for anything
  /// else (e.g. the emoji the backend sends), so the emoji can be shown.
  IconData? _iconFromName(String icon) {
    switch (icon.toLowerCase()) {
      case 'book':
      case 'book_open':
        return Icons.menu_book_rounded;

      case 'chart':
      case 'chart_line':
        return Icons.show_chart_rounded;

      case 'stock':
      case 'stocks':
        return Icons.candlestick_chart_rounded;

      case 'risk':
        return Icons.shield_rounded;

      case 'money':
      case 'finance':
        return Icons.account_balance_wallet_rounded;

      case 'brain':
      case 'ai':
        return Icons.psychology_rounded;

      default:
        return null;
    }
  }

  Widget _buildError(
    BuildContext context,
    LearningProvider provider,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 45,
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to load your learning path',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: provider.loadLearningData,
              child: const Text('TRY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }
}