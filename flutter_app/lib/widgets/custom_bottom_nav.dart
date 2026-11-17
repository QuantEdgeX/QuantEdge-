import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/learning_provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class CustomBottomNavBar extends StatelessWidget {
  const CustomBottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final learningProvider = context.watch<LearningProvider>();
    final quizProvider = context.watch<QuizProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final navItems = [
      const _NavItem(
        tab: AppTab.dashboard,
        label: 'Dashboard',
        icon: AppIcons.layoutDashboard,
      ),
      const _NavItem(
        tab: AppTab.portfolio,
        label: 'Portfolio',
        icon: AppIcons.briefcase,
      ),
      const _NavItem(
        tab: AppTab.market,
        label: 'Market',
        icon: AppIcons.chartNoAxesColumn,
      ),
      const _NavItem(
        tab: AppTab.quiz,
        label: 'Learn',
        icon: Icons.school_outlined,
      ),
    ];

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? Colors.white10 : AppColors.lightBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: navItems.map((item) {
          final isSelected = learningProvider.currentTab == item.tab ||
              (item.tab == AppTab.quiz && learningProvider.currentTab == AppTab.learning);

          return Expanded(
            child: _NavButton(
              item: item,
              isSelected: isSelected,
              isDark: isDark,
              onTap: () {
                learningProvider.setTab(item.tab);
                quizProvider.setTab(item.tab);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 8 : 2,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.emerald.withOpacity(0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedScale(
          scale: isSelected ? 1.0 : 0.96,
          duration: const Duration(milliseconds: 180),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: isSelected ? 30 : 24,
                height: isSelected ? 24 : 20,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.emerald.withOpacity(0.16)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item.icon,
                  size: isSelected ? 18 : 17,
                  color: isSelected
                      ? AppColors.emerald
                      : (isDark
                          ? Colors.white54
                          : AppColors.lightTextMuted),
                ),
              ),
              const SizedBox(height: 1),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: isSelected ? 9.5 : 8.5,
                  fontWeight:
                      isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected
                      ? AppColors.emerald
                      : (isDark
                          ? Colors.white54
                          : AppColors.lightTextMuted),
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final AppTab tab;
  final String label;
  final IconData icon;

  const _NavItem({
    required this.tab,
    required this.label,
    required this.icon,
  });
}