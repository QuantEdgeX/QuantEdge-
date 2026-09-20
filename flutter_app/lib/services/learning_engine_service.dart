import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LearningEngineService {
  static String get baseUrl {
    if (kIsWeb) {
      // Use explicit 127.0.0.1 for Web to avoid IPv6 localhost resolution drops
      return 'http://127.0.0.1:3000/api/learning';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000/api/learning';
    } else {
      return 'http://127.0.0.1:3000/api/learning';
    }
  }

  static Future<Map<String, dynamic>?> fetchQuestion({String userId = 'default-user'}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/question?userId=$userId'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error reaching Learning Engine: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> evaluateLevel({
    required Map<String, dynamic> session,
    required String selectedOptionId,
    int hintsUsed = 0,
    int responseTimeMs = 1000,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/evaluate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session': session,
          'selectedOptionId': selectedOptionId,
          'hintsUsed': hintsUsed,
          'responseTimeMs': responseTimeMs,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error evaluating score in Learning Engine: $e');
    }
    return null;
  }
}