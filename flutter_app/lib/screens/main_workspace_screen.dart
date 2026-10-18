import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/learning_provider.dart';
import '../tabs/dashboard_tab.dart';
import '../screens/learning_path_screen.dart';
import '../tabs/portfolio_tab.dart';
import '../tabs/assistant_tab.dart';
import '../widgets/custom_bottom_nav.dart';

class MainWorkspaceScreen extends StatefulWidget {
  const MainWorkspaceScreen({super.key});

  @override
  State<MainWorkspaceScreen> createState() => _MainWorkspaceScreenState();
}

class _MainWorkspaceScreenState extends State<MainWorkspaceScreen> {
  // Used to detect the moment the user switches TO the Learn tab.
  AppTab? _previousTab;

  /// Explicit tab -> IndexedStack position, so reordering the enum can
  /// never silently show the wrong tab.
  int _indexFor(AppTab tab) {
    switch (tab) {
      case AppTab.dashboard:
        return 0; // Home / Dashboard
      case AppTab.learning:
        return 1; // Learn
      case AppTab.portfolio:
        return 2; // Portfolio
      case AppTab.assistant:
        return 3; // AI
    }
  }

  /// IndexedStack keeps tabs alive, so LearningPathScreen.initState only
  /// runs once. Reload the path whenever the user comes back to it so the
  /// score, XP and unlocked topics are never stale.
  void _handleTabChange(AppTab tab) {
    final previous = _previousTab;
    _previousTab = tab;

    // previous == null is the first build; the Learn screen loads itself.
    if (previous != null && previous != tab && tab == AppTab.learning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<LearningProvider>().loadLearningData();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild only when the tab changes (not on every lesson update).
    final tab = context.select<LearningProvider, AppTab>(
      (provider) => provider.currentTab,
    );

    _handleTabChange(tab);

    // Hide the floating nav bar while the keyboard is open so it never
    // covers the assistant's text field.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      // On Home the back button exits the app; on any other tab it first
      // returns to Home.
      canPop: tab == AppTab.dashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          context.read<LearningProvider>().setTab(AppTab.dashboard);
        }
      },
      child: Stack(
        children: [
          IndexedStack(
            index: _indexFor(tab),
            children: const [
              DashboardTab(), // Index 0: Home / Dashboard
              LearningPathScreen(), // Index 1: Learn
              PortfolioTab(), // Index 2: Portfolio
              AssistantTab(), // Index 3: AI
            ],
          ),
          if (!keyboardOpen)
            const Positioned(
              bottom: 0,
              left: 24,
              right: 24,
              // Keeps the original 24px gap, and stays above the
              // system gesture bar on phones that have one.
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