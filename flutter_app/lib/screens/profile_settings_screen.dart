import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';
import 'ticker_detail_screen.dart';
import 'ticker_selection_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _isEditingName = false;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final profile = context.read<QuizProvider>().userProfile;
    _nameCtrl = TextEditingController(text: profile.name.isNotEmpty ? profile.name : 'Quant Trader');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _saveName() {
    final provider = context.read<QuizProvider>();
    final newName = _nameCtrl.text.trim();
    if (newName.isNotEmpty) {
      provider.updateUserProfile(provider.userProfile.copyWith(name: newName));
    }
    setState(() => _isEditingName = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuizProvider>();
    final isDark = provider.isDarkMode;
    final profile = provider.userProfile;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final cardBg = isDark ? AppColors.darkCard.withOpacity(0.6) : Colors.white;
    final borderColor = isDark ? Colors.white12 : AppColors.lightBorder;
    final displayName = profile.name.isNotEmpty ? profile.name : 'Quant Trader';
    final displayEmail = profile.email.isNotEmpty ? profile.email : 'trader@quantedge.ai';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, size: 18, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'PROFILE & SETTINGS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: textColor,
          ),
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: () => provider.toggleTheme(),
            icon: Icon(
              isDark ? AppIcons.sun : AppIcons.moon,
              size: 20,
              color: isDark ? Colors.white : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // ── Header Profile Card ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [Colors.white, const Color(0xFFF8FAFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: borderColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar with glowing ring
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.emerald, AppColors.blue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emerald.withOpacity(0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'Q',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isEditingName)
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _nameCtrl,
                                    autofocus: true,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: textColor,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                                    ),
                                    onSubmitted: (_) => _saveName(),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.check, size: 20, color: AppColors.emerald),
                                  onPressed: _saveName,
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => setState(() => _isEditingName = true),
                                  child: Icon(
                                    Icons.edit_rounded,
                                    size: 15,
                                    color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 4),
                          Text(
                            displayEmail,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.emerald.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.emerald.withOpacity(0.4)),
                                ),
                                child: Text(
                                  'LEVEL ${provider.userLevel} TRADER',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: AppColors.emerald,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.blue.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.blue.withOpacity(0.4)),
                                ),
                                child: Text(
                                  provider.skillLevel.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: AppColors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Section 1: XAI Explanation Engine ────────────────────────
          _buildSectionHeader('EXPLAINABLE AI ENGINE', isDark),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Insight Complexity Tier',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textColor),
                    ),
                    Text(
                      'Level ${provider.userLevel}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.emerald),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _getLevelDescription(provider.userLevel),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : AppColors.lightTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [1, 2, 3].map((lvl) {
                    final isSelected = provider.userLevel == lvl;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => provider.setUserLevel(lvl),
                        child: Container(
                          margin: EdgeInsets.only(right: lvl < 3 ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.emerald
                                : (isDark ? Colors.black26 : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? AppColors.emerald : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Tier $lvl',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : AppColors.lightTextPrimary),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Section 2: Trading Persona & Risk ────────────────────────
          _buildSectionHeader('INVESTOR PERSONA', isDark),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPreferenceRow(
                  label: 'Experience Level',
                  value: profile.experienceLevel.isNotEmpty ? profile.experienceLevel : 'Intermediate',
                  options: const ['Beginner', 'Intermediate', 'Advanced'],
                  isDark: isDark,
                  textColor: textColor,
                  onSelected: (val) {
                    provider.updateUserProfile(profile.copyWith(experienceLevel: val));
                  },
                ),
                const Divider(height: 28),
                _buildPreferenceRow(
                  label: 'Risk Tolerance',
                  value: profile.riskStyle.isNotEmpty ? profile.riskStyle : 'Balanced',
                  options: const ['Conservative', 'Balanced', 'Aggressive'],
                  isDark: isDark,
                  textColor: textColor,
                  onSelected: (val) {
                    provider.updateUserProfile(profile.copyWith(riskStyle: val));
                  },
                ),
                const Divider(height: 28),
                _buildPreferenceRow(
                  label: 'Primary Goal',
                  value: profile.investingGoal.isNotEmpty ? profile.investingGoal : 'Alpha Growth',
                  options: const ['Wealth Preservation', 'Alpha Growth', 'Day Trading'],
                  isDark: isDark,
                  textColor: textColor,
                  onSelected: (val) {
                    provider.updateUserProfile(profile.copyWith(investingGoal: val));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Section 3: Tracked Watchlist Tickers ─────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader('FOLLOWED ASSETS', isDark),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TickerSelectionScreen()),
                  );
                },
                child: const Text(
                  'CHANGE TICKERS →',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: AppColors.emerald,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: (profile.chosenTickers.isEmpty && provider.selectedTickers.isEmpty)
                ? Text(
                    'No custom tickers selected yet. Tap above to customize your watchlist.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : AppColors.lightTextMuted,
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (profile.chosenTickers.isNotEmpty
                            ? profile.chosenTickers
                            : provider.selectedTickers)
                        .map((t) => GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TickerDetailScreen(ticker: t),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.emerald.withOpacity(0.5),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.emerald,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.north_east_rounded, size: 12, color: AppColors.emerald),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 28),

          // ── Section 4: Account Actions ──────────────────────────────
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              provider.setPhase(AppPhase.onboarding1);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
              foregroundColor: textColor,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: borderColor, width: 2),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh_rounded, size: 18, color: AppColors.blue),
                SizedBox(width: 8),
                Text(
                  'RETAKE SKILL QUIZ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              provider.logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rose.withOpacity(0.12),
              foregroundColor: AppColors.rose,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: AppColors.rose.withOpacity(0.3), width: 1.5),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, size: 18, color: AppColors.rose),
                SizedBox(width: 8),
                Text(
                  'SIGN OUT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
        color: isDark ? Colors.white38 : AppColors.lightTextMuted,
      ),
    );
  }

  Widget _buildPreferenceRow({
    required String label,
    required String value,
    required List<String> options,
    required bool isDark,
    required Color textColor,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.emerald),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((opt) {
            final isSelected = opt == value;
            return ChoiceChip(
              label: Text(opt),
              selected: isSelected,
              onSelected: (_) => onSelected(opt),
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : AppColors.lightTextSecondary),
              ),
              selectedColor: AppColors.emerald,
              backgroundColor: isDark ? Colors.black26 : const Color(0xFFF1F5F9),
              side: BorderSide(
                color: isSelected ? AppColors.emerald : (isDark ? Colors.white12 : AppColors.lightBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _getLevelDescription(int level) {
    switch (level) {
      case 1:
        return 'Simplified natural-language explanations without quantitative jargon. Best for beginning traders.';
      case 2:
        return 'Balanced XAI insights combining momentum signals, sentiment indicators, and key technical factors.';
      case 3:
      default:
        return 'Full quantitative transparency with factor weight distributions, FinBERT sentiment vectors, and institutional risk metrics.';
    }
  }
}
