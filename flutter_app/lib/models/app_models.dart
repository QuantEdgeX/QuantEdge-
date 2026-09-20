import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MarketAsset {
  final String ticker;
  final String status;
  final String confidence;
  final String sentiment;
  final String insight;

  MarketAsset({
    required this.ticker,
    required this.status,
    required this.confidence,
    required this.sentiment,
    required this.insight,
  });

  factory MarketAsset.fromJson(Map<String, dynamic> json) {
    return MarketAsset(
      ticker: json['ticker'] ?? 'N/A',
      status: json['status'] ?? 'HOLD',
      confidence: json['confidence'] ?? '0%',
      sentiment: json['sentiment'] ?? '0.00',
      insight: json['insight'] ?? '',
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
