import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Qwen LLM inference service providing natural-language financial AI explanations.
/// Synthesizes quantitative factors (Price Momentum, Buyer/Seller Demand, News & Social Sentiment, Volatility)
/// into a 2-sentence user summary followed by concise bullet points calibrated to user Insight Depth.
class QwenXaiService {
  final String? customEndpoint;

  const QwenXaiService({this.customEndpoint});

  /// Main inference method.
  /// Main inference method.
  /// Calls the Qwen LLM endpoint with a 5-second timeout, falling back
  /// seamlessly to structured offline narrative templates upon failure or timeout.
  Future<String> fetchExplanation({
    required String ticker,
    required String signalType,
    required Map<String, dynamic> factors,
    required int userLevel,
    bool simplify = false,
  }) async {
    final effectiveLevel = simplify ? (userLevel > 1 ? userLevel - 1 : 1) : userLevel;
    try {
      final endpoint = customEndpoint ?? '${ApiService.baseUrl}/api/learning/xai/qwen';
      final uri = Uri.parse(endpoint);

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'ticker': ticker,
              'signalType': signalType,
              'factors': factors,
              'userLevel': effectiveLevel,
              'simplify': simplify,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final explanation =
              data['explanation'] ?? data['summary'] ?? data['text'];
          if (explanation != null && explanation.toString().trim().isNotEmpty) {
            return explanation.toString().trim();
          }
        }
      }
    } catch (e) {
      debugPrint('QwenXaiService: API call failed or timed out ($e). Using offline fallback.');
    }

    // High-fidelity pre-computed offline narrative fallback calibrated to user level
    return generateFallbackExplanation(
      ticker: ticker,
      signalType: signalType,
      factors: factors,
      userLevel: effectiveLevel,
      simplify: simplify,
    );
  }

  /// Generates a resilient, level-appropriate 2-sentence summary followed by
  /// concise bullet points.
  ///
  /// For Level 1-2 (Simple): strictly plain conversational English with NO raw math
  /// values (no "+0.45", "0.015 variance", or "RSI 68.4").
  ///
  /// For Level 3-4 (Advanced): includes detailed quantitative parameters.
  String generateFallbackExplanation({
    required String ticker,
    required String signalType,
    required Map<String, dynamic> factors,
    required int userLevel,
    bool simplify = false,
  }) {
    final rawRsi = factors['rsi'];
    final double rsi = (rawRsi is num)
        ? rawRsi.toDouble()
        : (double.tryParse(rawRsi?.toString() ?? '52.0') ?? 52.0);

    final rawSentiment = factors['finbertSentiment'] ?? factors['sentiment'];
    final double sentiment = (rawSentiment is num)
        ? rawSentiment.toDouble()
        : (double.tryParse(rawSentiment?.toString() ?? '0.0') ?? 0.0);

    final String orderBook = factors['orderBookIntensity']?.toString() ??
        factors['volumeAnalysis']?.toString() ??
        'Steady institutional bid concentration';

    final String volatility = factors['volatility']?.toString() ?? 'normal channel volatility';

    final sig = signalType.toUpperCase();
    final bool isSimpleLevel = userLevel <= 2 || simplify;

    if (simplify) {
      if (sig == 'BUY') {
        return 'Think of $ticker like a popular store where customers are lining up at the registers with upbeat buzz all around. High customer excitement and strong demand are carrying the stock forward smoothly.\n\n'
            '• **News & Social Sentiment:** Recent headlines and discussions are cheerful, giving investors confidence.\n'
            '• **Buyer/Seller Demand:** Buyers are outnumbering sellers, creating strong support that prevents sudden dips.\n'
            '• **Price Momentum:** Price movement is stepping up steadily like a smooth escalator.';
      } else if (sig == 'SELL') {
        return 'Think of $ticker like an approaching storm where shoppers are packing up and heading for the exits. Growing caution suggests it is wiser to hold on to your umbrella and reduce risk for now.\n\n'
            '• **News & Social Sentiment:** News coverage has turned cautious, with rising worries over near-term road bumps.\n'
            '• **Buyer/Seller Demand:** Sellers are outpacing buyers, leaving fewer supports to catch falling prices.\n'
            '• **Price Momentum:** Upward momentum is running out of steam and beginning to slide downward.';
      } else {
        return 'Think of $ticker like a calm afternoon where traffic is cruising at a steady, predictable speed with no jams. With buyers and sellers in balance, taking your time and observing is the smartest play.\n\n'
            '• **News & Social Sentiment:** News headlines and online chatter are neutral, waiting on upcoming company updates.\n'
            '• **Buyer/Seller Demand:** Buying and selling orders remain balanced in a calm tug-of-war.\n'
            '• **Price Momentum:** The price is drifting sideways in a gentle, predictable channel.';
      }
    }

    if (isSimpleLevel) {
      // ── Level 1 & 2: Simple / Layman Narrative (Zero raw numbers) ─────────
      if (sig == 'BUY') {
        return 'QuantEdge AI Insight sees strong buyer interest pushing $ticker upward, backed by encouraging news and steady market optimism. Overall conditions look favorable for steady growth without unusual wild swings.\n\n'
            '• **News & Social Sentiment:** Positive news coverage and upbeat sentiment across investors show strong confidence.\n'
            '• **Buyer/Seller Demand:** Strong buying demand outweighs sellers, helping keep the price stable against sudden dips.\n'
            '• **Price Momentum:** Healthy upward momentum shows steady buying strength without looking overstretched.';
      } else if (sig == 'SELL') {
        return 'QuantEdge AI Insight cautions that selling pressure is rising for $ticker as negative headlines and cautious trading take over. The market shows increased turbulence, suggesting it may be wise to protect gains or reduce risk.\n\n'
            '• **News & Social Sentiment:** Media coverage and online discussions have turned cautious, with growing concerns over near-term prospects.\n'
            '• **Buyer/Seller Demand:** Sellers are outpacing buyers, meaning there is less demand support to catch falling prices.\n'
            '• **Price Momentum:** Upward momentum is fading rapidly, increasing the chances of a noticeable price pullback.';
      } else {
        return 'QuantEdge AI Insight observes a balanced tug-of-war for $ticker with buyers and sellers evenly matched. With no strong catalyst pulling the stock in either direction, patience is the smartest approach right now.\n\n'
            '• **News & Social Sentiment:** News headlines and social chatter are neutral, with investors awaiting clearer updates.\n'
            '• **Buyer/Seller Demand:** Buying and selling orders are balanced, keeping the stock trading within a steady, normal range.\n'
            '• **Price Momentum:** Price movement is moving sideways at a calm, predictable pace without sudden breakouts.';
      }
    } else {
      // ── Level 3 & 4: Advanced Narrative (Technical parameters included) ────
      if (sig == 'BUY') {
        final sentimentFormatted = sentiment >= 0
            ? '+${sentiment.toStringAsFixed(2)}'
            : sentiment.toStringAsFixed(2);

        return 'QuantEdge AI Insight confirms an AI Overall Signal of BUY for $ticker, driven by constructive buyer/seller demand and positive sentiment velocity. Multi-factor key price drivers indicate sustained upside expansion while technical momentum remains below extreme overbought resistance.\n\n'
            '• **News & Social Sentiment ($sentimentFormatted):** Sentiment metrics reflect robust positive news coverage and high institutional participation.\n'
            '• **Buyer/Seller Demand:** $orderBook demonstrates heavy buy-side order book depth, mitigating downside slippage.\n'
            '• **Price Momentum:** Price momentum oscillator (RSI) at ${rsi.toStringAsFixed(1)} with $volatility variance provides clear headroom for further breakout.';
      } else if (sig == 'SELL') {
        final sentimentFormatted = sentiment.toStringAsFixed(2);

        return 'QuantEdge AI Insight flags an AI Overall Signal of SELL for $ticker as order book liquidity deteriorates amid negative sentiment divergence. Heightened volatility and weakening momentum suggest asymmetric downside risk.\n\n'
            '• **News & Social Sentiment ($sentimentFormatted):** Sentiment velocity reflects rapid institutional de-risking and spreading retail caution.\n'
            '• **Buyer/Seller Demand:** $orderBook reveals thin bid-side depth across primary support levels, elevating drop vulnerability.\n'
            '• **Price Momentum:** Price momentum oscillator (RSI) at ${rsi.toStringAsFixed(1)} confirms fading momentum with $volatility variance elevating correction risks.';
      } else {
        final sentimentFormatted = sentiment >= 0
            ? '+${sentiment.toStringAsFixed(2)}'
            : sentiment.toStringAsFixed(2);

        return 'QuantEdge AI Insight rates $ticker with an AI Overall Signal of HOLD during rangebound consolidation with balanced factor vectors. The asset remains in dynamic equilibrium, making capital preservation the optimal posture.\n\n'
            '• **News & Social Sentiment ($sentimentFormatted):** Balanced sentiment metrics indicate current corporate news is fully discounted by the market.\n'
            '• **Buyer/Seller Demand:** $orderBook illustrates neutral bid-ask equilibrium without anomalous accumulation or distribution.\n'
            '• **Price Momentum:** Price momentum oscillator (RSI) at ${rsi.toStringAsFixed(1)} sits comfortably in the neutral channel with $volatility variance indicating sideways trading.';
      }
    }
  }
}
