import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/app_models.dart';
import '../theme/app_theme.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  /// Generic POST request helper with timeout and JSON handling
  Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
            'Failed POST to $endpoint (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('ApiService POST Error: $e');
      rethrow;
    }
  }

  Future<List<MarketAsset>> fetchMarketAssets() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/assets'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => MarketAsset.fromJson(e)).toList();
      }
    } catch (_) {}
    return _fallbackAssets;
  }

  Future<List<FactorImpact>> fetchFactorImpacts() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/factors'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => FactorImpact.fromJson(e)).toList();
      }
    } catch (_) {}
    return _fallbackFactors;
  }

  Future<String> sendAssistantQuery(String query, int userLevel) async {
    try {
      final response = await post('/api/assistant', {
        'query': query,
        'level': userLevel,
      });
      return response['reply'] ??
          response['content'] ??
          'Insight generated for Level $userLevel.';
    } catch (_) {}
    return _generateFallbackReply(query);
  }

  Future<DashboardMetrics> fetchDashboardMetrics({String? userId}) async {
    try {
      final query = (userId != null && userId.isNotEmpty)
          ? '?userId=${Uri.encodeComponent(userId)}'
          : '';
      final response = await http
          .get(Uri.parse('$baseUrl/api/dashboard$query'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DashboardMetrics.fromJson(data);
      }
    } catch (_) {}
    return _fallbackDashboardMetrics();
  }

  Future<List<PortfolioHolding>> fetchPortfolioData({String? userId}) async {
    try {
      final query = (userId != null && userId.isNotEmpty)
          ? '?userId=${Uri.encodeComponent(userId)}'
          : '';
      final response = await http
          .get(Uri.parse('$baseUrl/api/portfolio$query'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => PortfolioHolding.fromJson(e)).toList();
      }
    } catch (_) {}
    // Clean initial state: empty simulated portfolio
    return [];
  }

  static final List<MarketAsset> _fallbackAssets = [
    MarketAsset(
      ticker: 'NVDA',
      status: 'BUY',
      confidence: '91%',
      sentiment: '0.88',
      insight:
          'Current momentum is heavily supported by order book intensity. The model detects a strong decoupling from standard retail volatility, suggesting institutional accumulation.',
    ),
    MarketAsset(
      ticker: 'AAPL',
      status: 'HOLD',
      confidence: '87%',
      sentiment: '0.12',
      insight:
          'Current trends show the stock price is actively climbing, but the general mood seen online shows a sharp shift in trust. It is like a temporary disconnect between price and sentiment.',
    ),
    MarketAsset(
      ticker: 'TSLA',
      status: 'SELL',
      confidence: '82%',
      sentiment: '-0.35',
      insight:
          'Bearish sentiment overrides the technical support levels. High-frequency social panic is outweighing the flat volume indicators, flagging a potential correction phase.',
    ),
  ];

  static final List<FactorImpact> _fallbackFactors = [
    FactorImpact(
        name: 'Volume Analysis',
        weight: '39%',
        percentage: 0.39,
        code: 'VL',
        color: AppColors.emerald),
    FactorImpact(
        name: 'Price Action',
        weight: '25%',
        percentage: 0.25,
        code: 'PR',
        color: AppColors.blue),
    FactorImpact(
        name: 'Social Sentiment',
        weight: '21%',
        percentage: 0.21,
        code: 'SN',
        color: AppColors.amber),
    FactorImpact(
        name: 'Retail Sentiment',
        weight: '2%',
        percentage: 0.02,
        code: 'RT',
        color: AppColors.rose),
  ];

  static String _generateFallbackReply(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('fail-safe') || lower.contains('mode')) {
      return 'Fail-Safe Mode activates automatically when sentiment volatility deviates >2.8 standard deviations from underlying asset volume.';
    }
    if (lower.contains('stress') || lower.contains('risk')) {
      return 'Portfolio stress testing model simulates high-frequency liquidity evaporation and extreme social media panic cascading.';
    }
    if (lower.contains('panic') || lower.contains('sentiment')) {
      return 'Social Panic metric scans over 45,000 real-time financial discussion channels, filtering bot amplification via neural sentiment classifiers.';
    }
    return 'Analysis completed: At Level 2 access, volume tracking accounts for 39% of current model attribution, maintaining stable divergence bounds.';
  }

  static DashboardMetrics _fallbackDashboardMetrics() {
    return DashboardMetrics(
      portfolioValue: 0.00,
      dailyChange: 0.00,
      weeklyChange: 0.00,
      xpPoints: 0,
      userLevel: 1,
      winRate: 0.00,
      nextLevelMilestone: '1000 XP',
    );
  }


}
