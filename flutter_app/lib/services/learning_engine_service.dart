import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Talks directly to the FastAPI backend on port 8000.
class LearningEngineService {
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    } else {
      return 'http://127.0.0.1:8000';
    }
  }

  /// POST /api/learning/quiz/init
  static Future<Map<String, dynamic>?> fetchQuestion({
    String userId = 'default-user',
    int xaiLevel = 2,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/learning/quiz/init'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'xaiLevel': xaiLevel}),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error reaching Learning Engine (quiz/init): $e');
    }
    return null;
  }

  /// POST /api/learning/quiz/submit
  static Future<Map<String, dynamic>?> evaluateLevel({
    required Map<String, dynamic> session,
    required String selectedOptionId,
    required String questionId,
    required String userId,
    int hintsUsed = 0,
    int responseTimeMs = 1000,
  }) async {
    try {
      final sessionId = session['sessionId'] ??
          session['state']?['sessionId'] ?? '';

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/learning/quiz/submit'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sessionId': sessionId,
              'userId': userId,
              'questionId': questionId,
              'selectedOptionId': selectedOptionId,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error evaluating score in Learning Engine (quiz/submit): $e');
    }
    return null;
  }
}