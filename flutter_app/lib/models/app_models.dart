import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MarketAsset {
  final String ticker;
  final String status;
  final String confidence;
  final String sentiment;
  final String insight;
  final double rsi;
  final double price;
  final double changePercent;

  MarketAsset({
    required this.ticker,
    required this.status,
    required this.confidence,
    required this.sentiment,
    required this.insight,
    this.rsi = 50.0,
    this.price = 0.0,
    this.changePercent = 0.0,
  });

  factory MarketAsset.fromJson(Map<String, dynamic> json) {
    return MarketAsset(
      ticker: json['ticker'] ?? 'N/A',
      status: json['status'] ?? 'HOLD',
      confidence: json['confidence'] ?? '0%',
      sentiment: json['sentiment'] ?? '0.00',
      insight: json['insight'] ?? '',
      rsi: (json['rsi'] as num?)?.toDouble() ?? 50.0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      changePercent: (json['changePercent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Color get statusColor {
    switch (status.toUpperCase()) {
      case 'BUY':
        return AppColors.emerald;
      case 'SELL':
        return AppColors.rose;
      case 'HOLD':
      default:
        return AppColors.amber;
    }
  }

  double get numericSentiment => double.tryParse(sentiment) ?? 0.0;
}

class FactorImpact {
  final String name;
  final String weight;
  final double percentage;
  final String code;
  final Color color;

  FactorImpact({
    required this.name,
    required this.weight,
    required this.percentage,
    required this.code,
    required this.color,
  });

  factory FactorImpact.fromJson(Map<String, dynamic> json) {
    Color resolveColor(String? colorKey) {
      switch (colorKey?.toLowerCase()) {
        case 'blue':
          return AppColors.blue;
        case 'amber':
          return AppColors.amber;
        case 'rose':
          return AppColors.rose;
        case 'emerald':
        default:
          return AppColors.emerald;
      }
    }

    final double pct = (json['percentage'] != null)
        ? (json['percentage'] as num).toDouble()
        : (double.tryParse(
                    json['weight']?.toString().replaceAll('%', '') ?? '0') ??
                0) /
            100.0;

    return FactorImpact(
      name: json['name'] ?? '',
      weight: json['weight'] ?? '${(pct * 100).toInt()}%',
      percentage: pct.clamp(0.0, 1.0),
      code: json['code'] ??
          (json['name'] != null && json['name'].toString().isNotEmpty
              ? json['name'].toString().substring(0, 2).toUpperCase()
              : 'NA'),
      color: resolveColor(json['color']),
    );
  }
}

class AssistantMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;

  AssistantMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
  });
}

// Dashboard metrics for user performance overview
class DashboardMetrics {
  final double portfolioValue;
  final double dailyChange;
  final double weeklyChange;
  final int xpPoints;
  final int userLevel;
  final double winRate;
  final String nextLevelMilestone;

  DashboardMetrics({
    required this.portfolioValue,
    required this.dailyChange,
    required this.weeklyChange,
    required this.xpPoints,
    required this.userLevel,
    required this.winRate,
    required this.nextLevelMilestone,
  });

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) {
    return DashboardMetrics(
      portfolioValue: (json['portfolio_value'] as num?)?.toDouble() ?? 10500.0,
      dailyChange: (json['daily_change'] as num?)?.toDouble() ?? 125.50,
      weeklyChange: (json['weekly_change'] as num?)?.toDouble() ?? 875.25,
      xpPoints: json['xp_points'] as int? ?? 2450,
      userLevel: json['user_level'] as int? ?? 2,
      winRate: (json['win_rate'] as num?)?.toDouble() ?? 0.68,
      nextLevelMilestone: json['next_level_milestone'] as String? ?? '3500 XP',
    );
  }
}

// Portfolio holding for asset allocation
class PortfolioHolding {
  final String symbol;
  final String name;
  final double quantity;
  final double currentPrice;
  final double totalValue;
  final double dayChange;
  final double dayChangePercent;
  final String allocation;

  PortfolioHolding({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.currentPrice,
    required this.totalValue,
    required this.dayChange,
    required this.dayChangePercent,
    required this.allocation,
  });

  factory PortfolioHolding.fromJson(Map<String, dynamic> json) {
    final value = (json['total_value'] as num?)?.toDouble() ?? 0.0;
    final change = (json['day_change'] as num?)?.toDouble() ?? 0.0;
    return PortfolioHolding(
      symbol: json['symbol'] as String? ?? 'N/A',
      name: json['name'] as String? ?? 'Unknown',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      currentPrice: (json['current_price'] as num?)?.toDouble() ?? 0.0,
      totalValue: value,
      dayChange: change,
      dayChangePercent: value > 0 ? (change / value * 100) : 0.0,
      allocation: json['allocation'] as String? ?? '0%',
    );
  }

  Color get changeColor {
    if (dayChange > 0) return AppColors.emerald;
    if (dayChange < 0) return AppColors.rose;
    return AppColors.amber;
  }
}

// User profile from login + enrichment flow
class UserProfile {
  final String name;
  final String email;
  final String experienceLevel;
  final String riskStyle;
  final List<String> sectorInterests;
  final String investingGoal;
  final List<String> chosenTickers;

  const UserProfile({
    this.name = '',
    this.email = '',
    this.experienceLevel = '',
    this.riskStyle = '',
    this.sectorInterests = const [],
    this.investingGoal = '',
    this.chosenTickers = const [],
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? experienceLevel,
    String? riskStyle,
    List<String>? sectorInterests,
    String? investingGoal,
    List<String>? chosenTickers,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      riskStyle: riskStyle ?? this.riskStyle,
      sectorInterests: sectorInterests ?? this.sectorInterests,
      investingGoal: investingGoal ?? this.investingGoal,
      chosenTickers: chosenTickers ?? this.chosenTickers,
    );
  }

  String get greeting {
    final hour = DateTime.now().hour;
    final timeOfDay = hour < 12 ? 'morning' : (hour < 17 ? 'afternoon' : 'evening');
    final displayName = name.isNotEmpty ? name : 'Trader';
    return 'Good $timeOfDay, $displayName';
  }
}

// Ticker search result from backend
class TickerSearchResult {
  final String ticker;
  final String name;
  final double price;
  final double changePercent;
  final String exchange;

  const TickerSearchResult({
    required this.ticker,
    required this.name,
    required this.price,
    required this.changePercent,
    required this.exchange,
  });

  factory TickerSearchResult.fromJson(Map<String, dynamic> json) {
    return TickerSearchResult(
      ticker: json['ticker'] as String? ?? '',
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      changePercent: (json['changePercent'] as num?)?.toDouble() ?? 0.0,
      exchange: json['exchange'] as String? ?? '',
    );
  }

  bool get isPositive => changePercent >= 0;
}

// Detailed ticker info for the detail screen
class TickerDetail {
  final String ticker;
  final String companyName;
  final double currentPrice;
  final double changePercent;
  final double high52w;
  final double low52w;
  final double volume;
  final double marketCap;
  final List<double> priceHistory;
  final List<String> priceLabels;
  final String aiSignal;
  final double aiConfidence;
  final double sentimentScore;
  final double rsi;
  final String boldPrediction;
  final List<FactorImpact> factors;
  final String xaiInsight;

  const TickerDetail({
    required this.ticker,
    required this.companyName,
    required this.currentPrice,
    required this.changePercent,
    required this.high52w,
    required this.low52w,
    required this.volume,
    required this.marketCap,
    required this.priceHistory,
    required this.priceLabels,
    required this.aiSignal,
    required this.aiConfidence,
    required this.sentimentScore,
    required this.rsi,
    required this.boldPrediction,
    required this.factors,
    required this.xaiInsight,
  });

  factory TickerDetail.fromJson(Map<String, dynamic> json) {
    final List<dynamic> historyRaw = json['priceHistory'] as List<dynamic>? ?? [];
    final List<dynamic> labelsRaw  = json['priceLabels']  as List<dynamic>? ?? [];
    final List<dynamic> factorsRaw = json['factors']      as List<dynamic>? ?? [];
    return TickerDetail(
      ticker:         json['ticker']       as String? ?? '',
      companyName:    json['companyName']  as String? ?? '',
      currentPrice:   (json['currentPrice']  as num?)?.toDouble() ?? 0.0,
      changePercent:  (json['changePercent'] as num?)?.toDouble() ?? 0.0,
      high52w:        (json['high52w']       as num?)?.toDouble() ?? 0.0,
      low52w:         (json['low52w']        as num?)?.toDouble() ?? 0.0,
      volume:         (json['volume']        as num?)?.toDouble() ?? 0.0,
      marketCap:      (json['marketCap']     as num?)?.toDouble() ?? 0.0,
      priceHistory:   historyRaw.map((e) => (e as num).toDouble()).toList(),
      priceLabels:    labelsRaw.map((e) => e.toString()).toList(),
      aiSignal:       json['aiSignal']       as String? ?? 'HOLD',
      aiConfidence:   (json['aiConfidence']  as num?)?.toDouble() ?? 0.0,
      sentimentScore: (json['sentimentScore'] as num?)?.toDouble() ?? 0.0,
      rsi:            (json['rsi']           as num?)?.toDouble() ?? 50.0,
      boldPrediction: json['boldPrediction'] as String? ?? '',
      factors:        factorsRaw
                        .map((e) => FactorImpact.fromJson(e as Map<String, dynamic>))
                        .toList(),
      xaiInsight:     json['xaiInsight']     as String? ?? '',
    );
  }

  Color get signalColor {
    switch (aiSignal.toUpperCase()) {
      case 'BUY':  return AppColors.emerald;
      case 'SELL': return AppColors.rose;
      default:     return AppColors.amber;
    }
  }

  bool get isPositive => changePercent >= 0;
}
