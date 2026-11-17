import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../screens/ticker_detail_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/xai_explanation_sheet.dart';

class PortfolioTab extends StatelessWidget {
  const PortfolioTab({super.key});

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<QuizProvider>();
    final isDark = quizProvider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final holdings = quizProvider.portfolioHoldings;
    final isLoading = quizProvider.isLoadingPortfolio;
    final userLevel = quizProvider.userLevel;

    if (userLevel < 3) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark ? Colors.white12 : AppColors.lightBorder,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(
                  AppIcons.lock,
                  color: AppColors.emerald,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'PROTOCOL LOCKED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Asset Locking Protocol',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface.withOpacity(0.5)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white12 : AppColors.lightBorder,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '"Simulated Practice Portfolio Locked. Achieve Level 3 Status to Unlock Advanced Paper-Trading Allocation Layers."',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                        color: isDark
                            ? Colors.white60
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Current Level: $userLevel / 3',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.emerald,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => quizProvider.refreshPortfolioData(),
      color: AppColors.emerald,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SIMULATED PRACTICE PORTFOLIO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: isDark ? Colors.white54 : AppColors.lightTextMuted,
                    ),
                  ),
                  Text(
                    'Practice Holdings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _showAddPracticeTickerModal(context, quizProvider, isDark),
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text('Add Ticker', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white12 : AppColors.lightBorder,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      'LEVEL: $userLevel',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: AppColors.emerald,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isLoading && holdings.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: AppColors.emerald),
              ),
            )
          else if (holdings.isEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface.withOpacity(0.5) : Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDark ? Colors.white12 : AppColors.lightBorder,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: isDark ? Colors.white24 : AppColors.lightTextMuted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Your practice portfolio is empty.\nAdd stocks from your watchlist to start paper trading!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: isDark ? Colors.white60 : AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _showAddPracticeTickerModal(context, quizProvider, isDark),
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                    label: const Text(
                      '+ Add Ticker to Practice',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            )
          else
            ...holdings.map((holding) {
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TickerDetailScreen(ticker: holding.symbol),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface.withOpacity(0.5)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: isDark ? Colors.white12 : AppColors.lightBorder,
                      width: 2,
                    ),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    holding.symbol,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      showXaiExplanationSheet(
                                        context,
                                        ticker: holding.symbol,
                                        isDarkMode: isDark,
                                        signalType: holding.dayChange >= 0
                                            ? 'BUY'
                                            : 'HOLD',
                                        liveFactors: {
                                          'currentPrice': holding.currentPrice,
                                          'dayChangePercent':
                                              holding.dayChangePercent,
                                          'totalValue': holding.totalValue,
                                          'allocation': holding.allocation,
                                          'orderBookIntensity':
                                              'Portfolio weight ${holding.allocation}',
                                          'volatility':
                                              holding.dayChangePercent.abs() > 3
                                                  ? 'High'
                                                  : 'Normal',
                                          'finbertSentiment':
                                              holding.dayChange >= 0
                                                  ? 0.72
                                                  : -0.28,
                                          'rsi': holding.dayChange >= 0
                                              ? 59.2
                                              : 43.8,
                                        },
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.emerald.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppColors.emerald
                                              .withOpacity(0.35),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(AppIcons.info,
                                              size: 11,
                                              color: AppColors.emerald),
                                          SizedBox(width: 4),
                                          Text(
                                            'Explain Position',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.emerald,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                holding.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white60
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$${holding.totalValue.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    holding.allocation,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white60
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Remove Position',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
                                          title: Text('Remove ${holding.symbol}?',
                                              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                                          content: Text(
                                              'Remove ${holding.symbol} from your simulated practice portfolio?',
                                              style: TextStyle(
                                                  color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
                                                  fontSize: 13)),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('CANCEL'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, true),
                                              child: const Text('REMOVE',
                                                  style: TextStyle(color: AppColors.rose, fontWeight: FontWeight.w900)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await quizProvider.removePortfolioHolding(holding.symbol);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quantity',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? Colors.white60
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
                                    color: AppColors.rose,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Sell 1 share',
                                    onPressed: () => quizProvider.adjustHoldingShares(holding.symbol, -1.0),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    holding.quantity.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                                    color: AppColors.emerald,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Buy 1 share',
                                    onPressed: () => quizProvider.adjustHoldingShares(holding.symbol, 1.0),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Day Change',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? Colors.white60
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                              Text(
                                '${holding.dayChange > 0 ? '+' : ''}\$${holding.dayChange.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: holding.changeColor,
                                ),
                              ),
                              Text(
                                '(${holding.dayChangePercent.toStringAsFixed(2)}%)',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: holding.changeColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.hub_outlined,
                                  size: 13, color: AppColors.emerald),
                              const SizedBox(width: 6),
                              Text(
                                'VIEW DETAIL & AI INSIGHT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                  color: isDark
                                      ? Colors.white54
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                          const Row(
                            children: [
                              Text(
                                'VIEW DETAIL',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                  color: AppColors.emerald,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_ios_rounded,
                                  size: 9, color: AppColors.emerald),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showAddPracticeTickerModal(
    BuildContext context,
    QuizProvider quizProvider,
    bool isDark,
  ) {
    String selectedTicker = quizProvider.selectedTickers.isNotEmpty
        ? quizProvider.selectedTickers.first
        : 'NVDA';
    double shares = 5.0;
    final sharesCtrl = TextEditingController(text: '5.0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final textColor =
                isDark ? Colors.white : AppColors.lightTextPrimary;
            final secondaryColor =
                isDark ? Colors.white60 : AppColors.lightTextSecondary;
            final borderColor =
                isDark ? Colors.white12 : AppColors.lightBorder;
            final availableTickers = <String>{
              ...quizProvider.selectedTickers,
              'NVDA',
              'AAPL',
              'TSLA',
              'MSFT',
              'AMD',
              'AMZN',
            }.toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ADD PRACTICE HOLDING',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppColors.emerald,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Simulate a Stock Position',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Ticker selection chips
                  Text(
                    'Select Stock Ticker',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: secondaryColor),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableTickers.map((t) {
                      final isSel = t == selectedTicker;
                      return ChoiceChip(
                        label: Text(t),
                        selected: isSel,
                        onSelected: (val) {
                          if (val) {
                            setModalState(() => selectedTicker = t);
                          }
                        },
                        selectedColor: AppColors.emerald,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isSel ? Colors.white : textColor,
                        ),
                        backgroundColor: isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.04),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Shares input
                  Text(
                    'Number of Shares',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: secondaryColor),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: sharesCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Enter quantity (e.g. 10)',
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.black.withOpacity(0.03),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          onChanged: (val) {
                            final parsed = double.tryParse(val) ?? 1.0;
                            setModalState(() => shares = parsed);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...[1, 5, 10, 25].map((preset) => Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: ActionChip(
                              label: Text('+$preset',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                              onPressed: () {
                                final current =
                                    double.tryParse(sharesCtrl.text) ?? 0.0;
                                final next = current + preset;
                                sharesCtrl.text = next.toStringAsFixed(1);
                                setModalState(() => shares = next);
                              },
                              backgroundColor: isDark
                                  ? Colors.white10
                                  : Colors.black.withOpacity(0.04),
                            ),
                          )),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Add button
                  ElevatedButton(
                    onPressed: shares > 0
                        ? () async {
                            Navigator.pop(ctx);
                            final ok = await quizProvider.addPortfolioHolding(
                              ticker: selectedTicker,
                              shares: shares,
                            );
                            if (ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Added ${shares.toStringAsFixed(1)} shares of $selectedTicker to Simulated Practice Portfolio'),
                                  backgroundColor: AppColors.emerald,
                                ),
                              );
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text(
                      'ADD $selectedTicker TO PRACTICE',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
