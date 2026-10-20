import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class TickerDetailScreen extends StatefulWidget {
  final String ticker;
  const TickerDetailScreen({super.key, required this.ticker});

  @override
  State<TickerDetailScreen> createState() => _TickerDetailScreenState();
}

class _TickerDetailScreenState extends State<TickerDetailScreen>
    with SingleTickerProviderStateMixin {
  TickerDetail? _detail;
  bool _loading = true;
  int? _hoveredIndex;
  String _selectedRange = '1W';
  bool _showXaiPopover = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  static const _ranges = ['1D', '1W', '1M', '3M'];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 500), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final detail = await context.read<QuizProvider>().fetchTickerDetail(widget.ticker);
    if (mounted) {
      setState(() { _detail = detail; _loading = false; });
      _fadeCtrl.forward();
    }
  }

  void _showXai(BuildContext ctx, TickerDetail detail, bool isDark) {
    showDialog(
      context: ctx,
      barrierColor: Colors.black54,
      useRootNavigator: false,
      builder: (_) => _XaiDialog(detail: detail, isDark: isDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<QuizProvider>().isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;
    final cardColor = isDark ? AppColors.darkCard : Colors.white;
    final borderColor = isDark ? Colors.white12 : AppColors.lightBorder;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, size: 18, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.ticker,
          style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic, color: textColor,
          ),
        ),
        actions: [
          if (_detail != null)
            Builder(builder: (ctx) => GestureDetector(
              onTap: () => _showXai(ctx, _detail!, isDark),
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.emerald.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded,
                      size: 14, color: AppColors.emerald),
                    const SizedBox(width: 4),
                    const Text('XAI',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w900,
                        color: AppColors.emerald, letterSpacing: 0.8,
                      )),
                  ],
                ),
              ),
            )),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.emerald, strokeWidth: 2))
          : _detail == null
              ? Center(child: Text('Could not load data',
                  style: TextStyle(color: textColor)))
              : FadeTransition(
                  opacity: _fadeAnim,
                  child: _buildBody(_detail!, isDark, textColor, surfaceColor, cardColor, borderColor),
                ),
    );
  }

  Widget _buildBody(TickerDetail d, bool isDark, Color textColor,
      Color surfaceColor, Color cardColor, Color borderColor) {
    final isUp = d.isPositive;
    final changeColor = isUp ? AppColors.emerald : AppColors.rose;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ── Price header ──────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.companyName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : AppColors.lightTextMuted,
                    )),
                  const SizedBox(height: 4),
                  Text('\$${d.currentPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic, color: textColor,
                    )),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 14, color: changeColor),
                    const SizedBox(width: 3),
                    Text(
                      '${isUp ? '+' : ''}${d.changePercent.toStringAsFixed(2)}% today',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: changeColor),
                    ),
                  ]),
                ],
              ),
            ),
            // Signal badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SignalBadge(signal: d.aiSignal, color: d.signalColor),
                const SizedBox(height: 6),
                Text('${(d.aiConfidence * 100).toStringAsFixed(0)}% confidence',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                  )),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Bold prediction statement ──────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: d.signalColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: d.signalColor.withOpacity(0.3), width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: d.signalColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: d.signalColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI PREDICTION',
                      style: TextStyle(
                        fontSize: 8, fontWeight: FontWeight.w900,
                        letterSpacing: 2.0, color: d.signalColor,
                      )),
                    const SizedBox(height: 4),
                    Text(d.boldPrediction,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        height: 1.45, color: textColor,
                        fontStyle: FontStyle.italic,
                      )),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Price chart ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${widget.ticker} · Price Velocity',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
                    )),
                  // Range selector
                  Row(
                    children: _ranges.map((r) {
                      final active = r == _selectedRange;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedRange = r),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: active ? AppColors.emerald : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(r,
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w900,
                              color: active ? Colors.white
                                  : (isDark ? Colors.white38 : AppColors.lightTextMuted),
                            )),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Hovered price tooltip
              if (_hoveredIndex != null && _hoveredIndex! < d.priceHistory.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '\$${d.priceHistory[_hoveredIndex!].toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic, color: changeColor,
                    )),
                ),

              // Chart
              SizedBox(
                height: 130,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d2) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final local = box.globalToLocal(d2.globalPosition);
                    final frac  = (local.dx / box.size.width).clamp(0.0, 1.0);
                    final idx   = (frac * (d.priceHistory.length - 1)).round();
                    setState(() => _hoveredIndex = idx);
                  },
                  onHorizontalDragEnd: (_) => setState(() => _hoveredIndex = null),
                  onTapDown: (d2) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final local = box.globalToLocal(d2.globalPosition);
                    final frac  = (local.dx / box.size.width).clamp(0.0, 1.0);
                    final idx   = (frac * (d.priceHistory.length - 1)).round();
                    setState(() => _hoveredIndex = idx);
                  },
                  child: CustomPaint(
                    painter: _LiveChartPainter(
                      data:         d.priceHistory,
                      color:        changeColor,
                      hoveredIndex: _hoveredIndex,
                    ),
                    size: const Size(double.infinity, 130),
                  ),
                ),
              ),

              // X-axis labels
              if (d.priceLabels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _xLabels(d.priceLabels).map((l) => Text(l,
                      style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white24 : AppColors.lightTextMuted,
                      ))).toList(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Live AI Signals ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.emerald.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.emerald.withOpacity(isDark ? 0.3 : 0.4), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Live AI signals — ${widget.ticker}',
                    style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: AppColors.emerald,
                    )),
                  Builder(builder: (ctx) => GestureDetector(
                    onTap: () => _showXai(ctx, _detail!, isDark),
                    child: const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.emerald),
                  )),
                ],
              ),
              const SizedBox(height: 12),
              _SignalRow('FinBERT sentiment', _sentimentLabel(d.sentimentScore),
                d.sentimentScore >= 0 ? AppColors.emerald : AppColors.rose, isDark, textColor),
              const SizedBox(height: 8),
              _SignalRow('RSI indicator',
                '${d.rsi.toStringAsFixed(1)} (${d.rsi > 70 ? 'Overbought' : d.rsi < 30 ? 'Oversold' : 'Neutral'})',
                d.rsi > 70 ? AppColors.rose : d.rsi < 30 ? AppColors.emerald : AppColors.amber,
                isDark, textColor),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Random Forest signal',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : AppColors.lightTextSecondary)),
                  _SignalBadge(signal: d.aiSignal, color: d.signalColor),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {},
                child: Text('Want to learn more? Click here →',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                  )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Factor Impact Distribution ────────────────────────────────
        _FactorImpactCard(factors: _detail!.factors, isDark: isDark,
          textColor: textColor, borderColor: borderColor, cardColor: cardColor),
        const SizedBox(height: 14),

        // ── Stats grid ────────────────────────────────────────────────
        Row(
          children: [
            _StatCard(label: '52W High', value: '\$${d.high52w.toStringAsFixed(0)}',
              isDark: isDark, textColor: textColor, cardColor: cardColor, borderColor: borderColor),
            const SizedBox(width: 10),
            _StatCard(label: '52W Low', value: '\$${d.low52w.toStringAsFixed(0)}',
              isDark: isDark, textColor: textColor, cardColor: cardColor, borderColor: borderColor),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatCard(
              label: 'Volume',
              value: _formatVolume(d.volume),
              isDark: isDark, textColor: textColor, cardColor: cardColor, borderColor: borderColor,
            ),
            const SizedBox(width: 10),
            _StatCard(
              label: 'Market Cap',
              value: _formatMarketCap(d.marketCap),
              isDark: isDark, textColor: textColor, cardColor: cardColor, borderColor: borderColor,
            ),
          ],
        ),
      ],
    );
  }

  List<String> _xLabels(List<String> all) {
    if (all.length <= 5) return all;
    final step = (all.length / 4).ceil();
    return [all.first, all[step], all[step * 2], all[step * 3], all.last];
  }

  String _sentimentLabel(double s) =>
      '${s >= 0 ? '+' : ''}${s.toStringAsFixed(2)} (${s > 0.2 ? 'Bullish' : s < -0.2 ? 'Bearish' : 'Neutral'})';

  String _formatVolume(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    return v.toStringAsFixed(0);
  }

  String _formatMarketCap(double v) {
    if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(1)}B';
    return '\$${v.toStringAsFixed(0)}';
  }
}

// ── Signal row ────────────────────────────────────────────────────────────────

Widget _SignalRow(String label, String value, Color valueColor, bool isDark, Color textColor) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : AppColors.lightTextSecondary)),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: valueColor)),
    ],
  );
}

// ── Signal badge ──────────────────────────────────────────────────────────────

class _SignalBadge extends StatelessWidget {
  final String signal;
  final Color color;

  const _SignalBadge({required this.signal, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Text(signal,
        style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w900,
          letterSpacing: 1.0, color: color,
        )),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color textColor;
  final Color cardColor;
  final Color borderColor;

  const _StatCard({
    required this.label, required this.value, required this.isDark,
    required this.textColor, required this.cardColor, required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: isDark ? Colors.white38 : AppColors.lightTextMuted)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic, color: textColor)),
          ],
        ),
      ),
    );
  }
}

// ── Factor impact card ────────────────────────────────────────────────────────

class _FactorImpactCard extends StatelessWidget {
  final List<FactorImpact> factors;
  final bool isDark;
  final Color textColor;
  final Color borderColor;
  final Color cardColor;

  const _FactorImpactCard({
    required this.factors, required this.isDark, required this.textColor,
    required this.borderColor, required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Influence Vectors',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: isDark ? Colors.white38 : AppColors.lightTextMuted)),
          const SizedBox(height: 4),
          Text('Factor Impact Distribution',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic, color: AppColors.emerald)),
          const SizedBox(height: 12),
          ...factors.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              children: [
                Row(
                  children: [
                    // Code badge
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: f.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: f.color.withOpacity(0.3)),
                      ),
                      child: Center(
                        child: Text(f.code,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: f.color)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(f.name, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: textColor)),
                    ),
                    Text(f.weight, style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic, color: f.color)),
                    const SizedBox(width: 8),
                    Icon(Icons.info_outline_rounded, size: 14,
                      color: isDark ? Colors.white24 : AppColors.lightTextMuted),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: f.percentage,
                    minHeight: 5,
                    backgroundColor: f.color.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(f.color),
                  ),
                ),
              ],
            ),
          )),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Factor impacts are normalised across all active clusters. Level ${context.read<QuizProvider>().userLevel}',
              style: TextStyle(fontSize: 9,
                color: isDark ? Colors.white24 : AppColors.lightTextMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// ── XAI Dialog (constrained inside the phone frame navigator) ─────────────────

class _XaiDialog extends StatefulWidget {
  final TickerDetail detail;
  final bool isDark;

  const _XaiDialog({required this.detail, required this.isDark});

  @override
  State<_XaiDialog> createState() => _XaiDialogState();
}

class _XaiDialogState extends State<_XaiDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 250), vsync: this)..forward();
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismiss,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Opacity(
            opacity: _fadeAnim.value,
            child: Transform.scale(
              scale: _scaleAnim.value,
              alignment: Alignment.topRight,
              child: child,
            ),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
              child: GestureDetector(
                onTap: () {}, // prevent tap-through
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: widget.isDark ? AppColors.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: AppColors.emerald.withOpacity(0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.emerald.withOpacity(0.12),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.emerald.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.hub_outlined,
                                    size: 12, color: AppColors.emerald),
                                const SizedBox(width: 4),
                                Text(
                                    'XAI INSIGHT — ${widget.detail.ticker}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                      color: AppColors.emerald,
                                    )),
                              ],
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _dismiss,
                            child: Icon(Icons.close_rounded,
                                size: 16,
                                color: widget.isDark
                                    ? Colors.white38
                                    : AppColors.lightTextMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Insight text
                      Text(
                        widget.detail.xaiInsight,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          fontWeight: FontWeight.w600,
                          color: widget.isDark
                              ? Colors.white70
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Mini factor preview
                      ...widget.detail.factors.take(3).map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: f.color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Center(
                                    child: Text(f.code,
                                        style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w900,
                                            color: f.color)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: f.percentage,
                                      minHeight: 4,
                                      backgroundColor:
                                          f.color.withOpacity(0.1),
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(f.color),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(f.weight,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: f.color)),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Live chart painter ────────────────────────────────────────────────────────

class _LiveChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final int? hoveredIndex;

  const _LiveChartPainter({
    required this.data, required this.color, this.hoveredIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final min   = data.reduce(math.min);
    final max   = data.reduce(math.max);
    final range = (max - min).clamp(1.0, double.infinity);
    const pad   = 8.0;

    double x(int i) => (i / (data.length - 1)) * size.width;
    double y(double v) => size.height - pad - ((v - min) / range) * (size.height - pad * 2);

    final path = Path();
    final fill = Path();

    for (int i = 0; i < data.length; i++) {
      if (i == 0) {
        path.moveTo(x(i), y(data[i]));
        fill.moveTo(x(0), size.height);
        fill.lineTo(x(0), y(data[0]));
      } else {
        final cx = (x(i - 1) + x(i)) / 2;
        path.cubicTo(cx, y(data[i - 1]), cx, y(data[i]), x(i), y(data[i]));
        fill.cubicTo(cx, y(data[i - 1]), cx, y(data[i]), x(i), y(data[i]));
      }
    }
    fill.lineTo(x(data.length - 1), size.height);
    fill.close();

    // Fill gradient
    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.25), color.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill);

    // Line
    canvas.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);

    // Hover crosshair
    if (hoveredIndex != null && hoveredIndex! < data.length) {
      final hx = x(hoveredIndex!);
      final hy = y(data[hoveredIndex!]);

      canvas.drawLine(Offset(hx, 0), Offset(hx, size.height),
        Paint()..color = color.withOpacity(0.3)..strokeWidth = 1.0);

      canvas.drawCircle(Offset(hx, hy), 6, Paint()..color = color);
      canvas.drawCircle(Offset(hx, hy), 10,
        Paint()..color = color.withOpacity(0.2)..style = PaintingStyle.fill);
    }

    // Endpoint dot (live indicator)
    final lastX = x(data.length - 1);
    final lastY = y(data.last);
    canvas.drawCircle(Offset(lastX, lastY), 4, Paint()..color = color);
    canvas.drawCircle(Offset(lastX, lastY), 8,
      Paint()..color = color.withOpacity(0.2)..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_LiveChartPainter old) =>
      old.hoveredIndex != hoveredIndex || old.data != data;
}
