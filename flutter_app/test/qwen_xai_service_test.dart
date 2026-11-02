import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/qwen_xai_service.dart';

void main() {
  group('QwenXaiService', () {
    const service = QwenXaiService();

    group('Level 1-2 (Simple / Layman mode)', () {
      test('generates layman BUY narrative without raw numbers', () async {
        final explanation = await service.fetchExplanation(
          ticker: 'NVDA',
          signalType: 'BUY',
          userLevel: 2,
          factors: {
            'rsi': 68.4,
            'finbertSentiment': 0.88,
            'volatility': 'Low',
            'orderBookIntensity': '39% Institutional Accumulation',
          },
        );

        expect(explanation, contains('QuantEdge AI Insight'));
        expect(explanation, contains('NVDA'));
        expect(explanation, contains('News & Social Sentiment'));
        expect(explanation, contains('Buyer/Seller Demand'));
        expect(explanation, contains('Price Momentum'));
        expect(explanation.contains('•'), isTrue);

        // Strict verification: No raw numbers in simple mode
        expect(explanation, isNot(contains('0.88')));
        expect(explanation, isNot(contains('+0.88')));
        expect(explanation, isNot(contains('68.4')));
        expect(explanation, isNot(contains('RSI')));
      });

      test('generates layman SELL narrative without raw numbers', () async {
        final explanation = await service.fetchExplanation(
          ticker: 'TSLA',
          signalType: 'SELL',
          userLevel: 1,
          factors: {
            'rsi': 32.1,
            'finbertSentiment': -0.45,
            'volatility': 'High',
            'orderBookIntensity': 'Heavy distribution',
          },
        );

        expect(explanation, contains('QuantEdge AI Insight'));
        expect(explanation, contains('TSLA'));
        expect(explanation, contains('News & Social Sentiment'));
        expect(explanation, contains('Buyer/Seller Demand'));
        expect(explanation, contains('Price Momentum'));
        expect(explanation.contains('•'), isTrue);

        // No raw numbers in simple mode
        expect(explanation, isNot(contains('-0.45')));
        expect(explanation, isNot(contains('32.1')));
      });

      test('generates layman HOLD narrative without raw numbers', () async {
        final explanation = await service.fetchExplanation(
          ticker: 'AAPL',
          signalType: 'HOLD',
          userLevel: 2,
          factors: {
            'rsi': 50.5,
            'finbertSentiment': 0.05,
            'volatility': 'Normal',
          },
        );

        expect(explanation, contains('QuantEdge AI Insight'));
        expect(explanation, contains('AAPL'));
        expect(explanation, contains('News & Social Sentiment'));
        expect(explanation, contains('Buyer/Seller Demand'));
        expect(explanation, contains('Price Momentum'));
        expect(explanation.contains('•'), isTrue);

        expect(explanation, isNot(contains('0.05')));
        expect(explanation, isNot(contains('50.5')));
      });
    });

    group('Level 3-4 (Advanced / Technical mode)', () {
      test('generates advanced BUY narrative with quantitative metrics', () async {
        final explanation = await service.fetchExplanation(
          ticker: 'NVDA',
          signalType: 'BUY',
          userLevel: 4,
          factors: {
            'rsi': 68.4,
            'finbertSentiment': 0.88,
            'volatility': 'Low',
            'orderBookIntensity': '39% Institutional Accumulation',
          },
        );

        expect(explanation, contains('QuantEdge AI Insight'));
        expect(explanation, contains('NVDA'));
        expect(explanation, contains('AI Overall Signal of BUY'));
        expect(explanation, contains('News & Social Sentiment (+0.88)'));
        expect(explanation, contains('Buyer/Seller Demand'));
        expect(explanation, contains('Price Momentum'));
        expect(explanation, contains('68.4'));
        expect(explanation.contains('•'), isTrue);
      });

      test('generates advanced SELL narrative with quantitative metrics', () async {
        final explanation = await service.fetchExplanation(
          ticker: 'TSLA',
          signalType: 'SELL',
          userLevel: 3,
          factors: {
            'rsi': 32.1,
            'finbertSentiment': -0.45,
            'volatility': 'High',
            'orderBookIntensity': 'Heavy distribution',
          },
        );

        expect(explanation, contains('QuantEdge AI Insight'));
        expect(explanation, contains('TSLA'));
        expect(explanation, contains('AI Overall Signal of SELL'));
        expect(explanation, contains('News & Social Sentiment (-0.45)'));
        expect(explanation, contains('32.1'));
        expect(explanation.contains('•'), isTrue);
      });
    });
  });
}
