import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';
import 'ticker_detail_screen.dart';

class TickerSelectionScreen extends StatefulWidget {
  final bool isEditingWorkspace;
  const TickerSelectionScreen({super.key, this.isEditingWorkspace = false});

  @override
  State<TickerSelectionScreen> createState() => _TickerSelectionScreenState();
}

class _TickerSelectionScreenState extends State<TickerSelectionScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuizProvider>();
    final isDark = provider.isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final selected = provider.selectedTickers;
    final results = provider.tickerSearchResults;
    final isSearching = provider.isSearchingTickers;
    final isSearchMode = _searchCtrl.text.trim().isNotEmpty;
    final canPop = Navigator.canPop(context);
    final isEditing = widget.isEditingWorkspace || canPop || provider.phase == AppPhase.mainApp;

    final bodyContent = Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Text(isEditing ? 'CUSTOMISE WATCHLIST' : 'PERSONALISE YOUR FEED',
            style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2.0,
              color: isDark ? Colors.white38 : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(isEditing ? 'Manage Your Feed Tickers' : 'Pick 3 Tickers to Follow',
            style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic, color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your dashboard will show live AI signals for these stocks.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // ── Search bar ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard.withOpacity(0.4) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white12 : AppColors.lightBorder, width: 2),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w700),
              textCapitalization: TextCapitalization.characters,
              onChanged: (v) {
                setState(() {});
                provider.searchTickers(v);
              },
              decoration: InputDecoration(
                hintText: 'Search any ticker (e.g. NVDA, AMZN)…',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white24 : AppColors.lightTextMuted,
                ),
                prefixIcon: Icon(Icons.search_rounded, size: 20,
                  color: isDark ? Colors.white38 : AppColors.lightTextMuted),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, size: 18,
                          color: isDark ? Colors.white38 : AppColors.lightTextMuted),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                          provider.searchTickers('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Selected chips ─────────────────────────────────────────────
          if (selected.isNotEmpty) ...[
            Row(
              children: [
                Text('Selected: ',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: selected.map((t) => _SelectedChip(
                        ticker: t, isDark: isDark,
                        onRemove: () => provider.toggleTickerSelection(t, allowUnlimited: isEditing),
                      )).toList(),
                    ),
                  ),
                ),
                Text(isEditing ? '${selected.length} active' : '${selected.length}/3',
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w900,
                    color: AppColors.emerald,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── Ticker list ────────────────────────────────────────────────
          Expanded(
            child: isSearching
                ? const Center(child: CircularProgressIndicator(color: AppColors.emerald, strokeWidth: 2))
                : isSearchMode && results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 40,
                              color: isDark ? Colors.white24 : AppColors.lightTextMuted),
                            const SizedBox(height: 12),
                            Text('No results for "${_searchCtrl.text}"',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                              )),
                          ],
                        ),
                      )
                    : ListView(
                        children: [
                          if (!isSearchMode)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text('POPULAR TICKERS',
                                style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2.0,
                                  color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                                ),
                              ),
                            ),
                          ...(isSearchMode ? results.map((r) => _SearchResultTile(
                            ticker: r.ticker, name: r.name,
                            price: r.price > 0 ? '\$${r.price.toStringAsFixed(2)}' : '—',
                            change: r.changePercent,
                            signal: r.signal,
                            isSelected: provider.isTickerSelected(r.ticker),
                            canSelect: isEditing || selected.length < 3 || provider.isTickerSelected(r.ticker),
                            isDark: isDark,
                            onTap: () => provider.toggleTickerSelection(r.ticker, allowUnlimited: isEditing),
                          )) : provider.popularTickers.map((t) => _SearchResultTile(
                            ticker: t['ticker']!,
                            name: t['name']!,
                            price: '—',
                            change: 0,
                            signal: null,
                            isSelected: provider.isTickerSelected(t['ticker']!),
                            canSelect: isEditing || selected.length < 3 || provider.isTickerSelected(t['ticker']!),
                            isDark: isDark,
                            onTap: () => provider.toggleTickerSelection(t['ticker']!, allowUnlimited: isEditing),
                          ))),
                        ],
                      ),
          ),
          const SizedBox(height: 14),

          // ── Confirm button ─────────────────────────────────────────────
          ElevatedButton(
            onPressed: isEditing
                ? (selected.isNotEmpty
                    ? () async {
                        final navigator = Navigator.of(context);
                        await provider.confirmTickerSelection();
                        if (mounted && canPop) {
                          navigator.pop();
                        }
                      }
                    : null)
                : (selected.length == 3
                    ? () => provider.confirmTickerSelection()
                    : null),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              disabledBackgroundColor: isDark ? Colors.white10 : Colors.black12,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: (isEditing ? selected.isNotEmpty : selected.length == 3) ? 10 : 0,
              shadowColor: AppColors.emerald.withOpacity(0.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (provider.isLaunchingWorkspace)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                else
                  Text(
                    isEditing
                        ? (selected.isNotEmpty
                            ? 'SAVE WATCHLIST (${selected.length})'
                            : 'SELECT AT LEAST 1 TICKER')
                        : (selected.length == 3
                            ? 'LAUNCH MY WORKSPACE →'
                            : 'SELECT ${3 - selected.length} MORE'),
                    style: TextStyle(
                      fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12,
                      color: (isEditing ? selected.isNotEmpty : selected.length == 3)
                          ? Colors.white
                          : (isDark ? Colors.white30 : Colors.black38),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (canPop) {
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
            'CUSTOMISE WATCHLIST',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: textColor,
            ),
          ),
        ),
        body: SafeArea(child: bodyContent),
      );
    }

    return bodyContent;
  }
}

// ── Selected chip ─────────────────────────────────────────────────────────────

class _SelectedChip extends StatelessWidget {
  final String ticker;
  final bool isDark;
  final VoidCallback onRemove;

  const _SelectedChip({required this.ticker, required this.isDark, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.emerald.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.emerald, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ticker, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.emerald)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 13, color: AppColors.emerald),
          ),
        ],
      ),
    );
  }
}

// ── Ticker list tile ──────────────────────────────────────────────────────────

class _SearchResultTile extends StatelessWidget {
  final String ticker;
  final String name;
  final String price;
  final double change;
  final String? signal;
  final bool isSelected;
  final bool canSelect;
  final bool isDark;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.ticker, required this.name, required this.price,
    required this.change, this.signal, required this.isSelected, required this.canSelect,
    required this.isDark, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final changeColor = change >= 0 ? AppColors.emerald : AppColors.rose;

    return GestureDetector(
      onTap: canSelect ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.emerald.withOpacity(0.12)
              : (isDark ? AppColors.darkCard.withOpacity(0.3) : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.emerald
                : (isDark ? Colors.white10 : AppColors.lightBorder),
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            // Ticker badge
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.emerald
                    : (isDark ? Colors.white10 : AppColors.lightTextPrimary),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  ticker.length > 4 ? ticker.substring(0, 3) : ticker,
                  style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name & ticker
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ticker, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    color: isSelected ? AppColors.emerald : textColor,
                  )),
                  Text(name, style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                  )),
                ],
              ),
            ),
            // Price & change
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (price != '—')
                  Text(price, style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: textColor)),
                if (change != 0)
                  Text(
                    '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: changeColor),
                  ),
              ],
            ),
            if (signal != null && signal!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (signal == 'BUY'
                          ? AppColors.emerald
                          : (signal == 'SELL' ? AppColors.rose : AppColors.amber))
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (signal == 'BUY'
                            ? AppColors.emerald
                            : (signal == 'SELL' ? AppColors.rose : AppColors.amber))
                        .withOpacity(0.3),
                  ),
                ),
                child: Text(
                  signal!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: signal == 'BUY'
                        ? AppColors.emerald
                        : (signal == 'SELL' ? AppColors.rose : AppColors.amber),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            // Inspect ticker detail button
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TickerDetailScreen(ticker: ticker)),
                );
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: isDark ? Colors.white54 : AppColors.lightTextMuted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Select icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.emerald : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.emerald
                      : (isDark ? Colors.white24 : AppColors.lightBorder),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                  : (!canSelect
                      ? Icon(Icons.block_rounded, size: 14,
                          color: isDark ? Colors.white24 : AppColors.lightTextMuted)
                      : null),
            ),
          ],
        ),
      ),
    );
  }
}
