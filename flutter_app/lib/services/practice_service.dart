import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Talks to the Duolingo-style practice quiz endpoints on the FastAPI backend.
class PracticeService {
  static String get baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  static const String _userId = 'user_demo_123';

  /// POST /api/learning/practice/question
  /// Returns question + user state (XP, hearts, streak, difficulty).
  static Future<Map<String, dynamic>?> fetchQuestion({
    int xaiLevel = 2,
    int? currentXp,
  }) async {
    try {
      final body = <String, dynamic>{
        'userId': _userId,
        'xaiLevel': xaiLevel,
      };
      if (currentXp != null) body['currentXp'] = currentXp;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/learning/practice/question'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('PracticeService.fetchQuestion error: $e');
    }
    return null;
  }

  /// POST /api/learning/practice/submit
  /// Returns isCorrect, xpDelta, newXp, streak, hearts, levelUp info, roundComplete.
  static Future<Map<String, dynamic>?> submitAnswer({
    required String questionId,
    required String selectedOptionId,
    required String correctOptionId,
    required String difficulty,
    int xaiLevel = 2,
    String? topic,
  }) async {
    try {
      final body = <String, dynamic>{
        'userId': _userId,
        'questionId': questionId,
        'selectedOptionId': selectedOptionId,
        'correctOptionId': correctOptionId,
        'difficulty': difficulty,
        'xaiLevel': xaiLevel,
        if (topic != null) 'topic': topic,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/learning/practice/submit'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('PracticeService.submitAnswer error: $e');
    }
    return null;
  }

  /// GET /api/learning/practice/profile?userId=...
  static Future<Map<String, dynamic>?> fetchProfile() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/learning/practice/profile?userId=$_userId'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('PracticeService.fetchProfile error: $e');
    }
    return null;
  }
}
