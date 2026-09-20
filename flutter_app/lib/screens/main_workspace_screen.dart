import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../tabs/dashboard_tab.dart';
import '../tabs/quiz_tab.dart';
import '../tabs/portfolio_tab.dart';
import '../tabs/assistant_tab.dart';
import '../widgets/custom_bottom_nav.dart';

class MainWorkspaceScreen extends StatelessWidget {
  const MainWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();

    return Stack(
      children: [
        IndexedStack(
          index: quizProvider.currentTab.index,
          children: const [
            DashboardTab(),
            QuizTab(),
            PortfolioTab(),
            AssistantTab(),
          ],
        ),
        const Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: CustomBottomNavBar(),
        ),
      ],
    );
  }
}
