import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class CustomBottomNavBar extends StatelessWidget {
  const CustomBottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;

    final navItems = [
      {
        'tab': AppTab.dashboard,
        'label': 'Dashboard',
        'icon': AppIcons.layoutDashboard,
      },
      {
        'tab': AppTab.quiz,
        'label': 'Quiz',
        'icon': Icons.quiz,
      },
      {
        'tab': AppTab.portfolio,
        'label': 'Portfolio',
        'icon': AppIcons.briefcase,
      },
      {
        'tab': AppTab.assistant,
        'label': 'Assistant',
        'icon': AppIcons.messageSquare,
      },
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? Colors.white12 : AppColors.lightBorder,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: navItems.map((item) {
          final tab = item['tab'] as AppTab;
          final isSelected = quizProvider.currentTab == tab;

          return GestureDetector(
            onTap: () => quizProvider.setTab(tab),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.emerald.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    item['icon'] as IconData,
                    size: 20,
                    color: isSelected
                        ? AppColors.emerald
                        : (isDark ? Colors.white54 : AppColors.lightTextMuted),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Text(
                      item['label'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.emerald,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}