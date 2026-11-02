import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/learning_provider.dart';
import '../providers/quiz_provider.dart';
import '../tabs/dashboard_tab.dart';
import '../tabs/portfolio_tab.dart';
import '../tabs/market_tab.dart';
import '../tabs/quiz_tab.dart';
import '../widgets/custom_bottom_nav.dart';


class MainWorkspaceScreen extends StatefulWidget {
  const MainWorkspaceScreen({super.key});

  @override
  State<MainWorkspaceScreen> createState() => _MainWorkspaceScreenState();
}

class _MainWorkspaceScreenState extends State<MainWorkspaceScreen> {
  AppTab? _previousTab;

  /// Exactly 4 tabs in MainWorkspaceScreen:
  /// Index 0: DashboardTab
  /// Index 1: PortfolioTab
  /// Index 2: MarketTab
  /// Index 3: QuizTab (Disha's Learning Engine)
  int _indexFor(AppTab tab) {
    switch (tab) {
      case AppTab.dashboard:
        return 0;
      case AppTab.portfolio:
        return 1;
      case AppTab.market:
        return 2;
      case AppTab.quiz:
      case AppTab.learning:
        return 3;
    }
  }

  void _handleTabChange(AppTab tab) {
    final previous = _previousTab;
    _previousTab = tab;

    if (previous != null && previous != tab && (tab == AppTab.quiz || tab == AppTab.learning)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<LearningProvider>().loadLearningData();
          context.read<QuizProvider>().loadLearningData();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = context.select<LearningProvider, AppTab>(
      (provider) => provider.currentTab,
    );

    _handleTabChange(tab);

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: tab == AppTab.dashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          context.read<LearningProvider>().setTab(AppTab.dashboard);
          context.read<QuizProvider>().setTab(AppTab.dashboard);
        }
      },
      child: Stack(
        children: [
          IndexedStack(
            index: _indexFor(tab),
            children: const [
              DashboardTab(), // Index 0: DashboardTab
              PortfolioTab(), // Index 1: PortfolioTab
              MarketTab(),    // Index 2: MarketTab
              QuizTab(),      // Index 3: QuizTab (Disha's Learning Engine)
            ],
          ),
          if (!keyboardOpen)
            const Positioned(
              bottom: 0,
              left: 24,
              right: 24,
              child: SafeArea(
                top: false,
                minimum: EdgeInsets.only(bottom: 24),
                child: CustomBottomNavBar(),
              ),
            ),
        ],
      ),
    );
  }
}
