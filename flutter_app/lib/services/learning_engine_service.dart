import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Talks directly to the FastAPI learning backend.
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

  // The backend generates (and validates) questions with an LLM, so a call
  // can take longer than a normal API request.
  static const Duration _requestTimeout = Duration(seconds: 45);

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  // ───────────────────────────────────────────────────────────────────────
  // Last error (human readable)
  // ───────────────────────────────────────────────────────────────────────

  static String? _lastError;

  /// Reason the most recent call returned null (or null if it succeeded).
  /// Safe to show in the UI.
  static String? get lastError => _lastError;

  static String? _extractDetail(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is Map) {
        final detail = decoded['detail'];

        if (detail is String && detail.isNotEmpty) {
          return detail;
        }

        // FastAPI validation errors (422) send a list.
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;

          if (first is Map && first['msg'] != null) {
            return first['msg'].toString();
          }
        }
      }
    } catch (_) {
      // Body was not JSON.
    }

    return null;
  }

  static String _friendlyError(
    int status,
    String body, {
    required bool isAnswer,
  }) {
    final detail = _extractDetail(body);

    switch (status) {
      case 403:
        return detail ?? 'You do not have access to this lesson.';

      case 404:
        return isAnswer
            ? 'This lesson is no longer active (the server restarted, it '
                'expired, or another lesson was started). '
                'Please restart the lesson.'
            : (detail ?? 'Topic not found.');

      case 409:
        return 'That question was already answered. '
            'Please restart the lesson.';

      case 502:
        return 'The learning engine could not generate a question right '
            'now. Please try again.';

      case 503:
        return 'The learning engine is not configured on the server '
            '(missing GROQ_API_KEY).';

      default:
        return detail ?? 'Unexpected server error ($status).';
    }
  }

  static String _networkError(Object error) {
    if (error is TimeoutException) {
      return 'The server took too long to respond. Please try again.';
    }

    return 'Cannot reach the learning server at $baseUrl. '
        'Make sure the backend is running.';
  }

  /// Backend score (1-10) -> the skill-level names QuizProvider understands.
  /// Mirrors QuizProvider._scoreToUserLevel: ((score + 1) ~/ 2) -> 1..5.
  static String _levelNameForScore(int score) {
    switch (((score + 1) ~/ 2).clamp(1, 5)) {
      case 1:
        return 'novice';
      case 2:
        return 'beginner';
      case 3:
        return 'intermediate';
      case 4:
        return 'advanced';
      default:
        return 'expert';
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Start lesson
  // ───────────────────────────────────────────────────────────────────────

  /// Starts a learning lesson.
  ///
  /// Backend:
  /// POST /api/learning/lesson/start
  ///
  /// Pass [topicId] to practise a specific unlocked topic; omit it to
  /// continue with the user's current topic.
  static Future<Map<String, dynamic>?> fetchQuestion({
    String userId = 'default-user',
    int xaiLevel = 2,
    String? topicId,
  }) async {
    _lastError = null;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/learning/lesson/start'),
            headers: _headers,
            body: jsonEncode({
              'userId': userId,
              if (topicId != null && topicId.isNotEmpty) 'topicId': topicId,
            }),
          )
          .timeout(_requestTimeout);

      debugPrint(
        'Learning lesson/start status: ${response.statusCode}',
      );

      debugPrint(
        'Learning lesson/start response: ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // The whole learning path is already finished: the backend sends
        // {"completedAllTopics": true, "message": ...} instead of a question.
        if (data['completedAllTopics'] == true) {
          _lastError = (data['message'] as String?) ??
              'You have completed the full learning path!';
          return null;
        }

        // The backend sends ONE question at a time under "question".
        final rawQuestion = data['question'];

        if (rawQuestion is! Map) {
          debugPrint('Learning lesson returned no question.');
          _lastError = 'The lesson did not return a question.';
          return null;
        }

        final question = Map<String, dynamic>.from(rawQuestion);

        final topic = data['topic'] is Map
            ? Map<String, dynamic>.from(data['topic'] as Map)
            : <String, dynamic>{};

        // Convert the lesson response into the shape
        // expected by QuizProvider / LearningProvider.
        return {
          'sessionId': data['lessonId'],
          'userId': userId,
          'lessonId': data['lessonId'],
          'topicId': topic['id'] ?? question['topicId'],
          'topicTitle': topic['title'] ?? question['topicTitle'],
          'questions': [question],
          'question': question,
          'questionIndex': 0,
          'totalQuestions': data['totalQuestions'] ?? 10,
          'requiredCorrect': data['requiredCorrect'] ?? 8,
          'score': data['score'],
          'scoreName': data['scoreName'],
          'difficulty': data['difficulty'],
          'attempt': data['attempt'],
          'isPractice': data['isPractice'] ?? false,
          'sessionStatus': 'ACTIVE',
        };
      }

      debugPrint(
        'lesson/start failed: ${response.statusCode} ${response.body}',
      );

      _lastError = _friendlyError(
        response.statusCode,
        response.body,
        isAnswer: false,
      );
    } catch (e) {
      debugPrint(
        'Error reaching Learning Engine (lesson/start): $e',
      );

      _lastError = _networkError(e);
    }

    return null;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Submit answer
  // ───────────────────────────────────────────────────────────────────────

  /// Submits one answer to the current learning lesson.
  ///
  /// Backend:
  /// POST /api/learning/lesson/answer
  ///
  /// The backend only records an answer when it succeeds, so after a null
  /// return caused by a network or generation error the user can safely
  /// submit the same answer again.
  static Future<Map<String, dynamic>?> evaluateLevel({
    required Map<String, dynamic> session,
    required String selectedOptionId,
    required String questionId,
    required String userId,
    int hintsUsed = 0,
    int responseTimeMs = 1000,
  }) async {
    _lastError = null;

    try {
      final lessonId =
          session['lessonId'] ??
          session['sessionId'] ??
          '';

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/learning/lesson/answer'),
            headers: _headers,
            body: jsonEncode({
              'userId': userId,
              'lessonId': lessonId,
              'questionId': questionId,
              'selectedOptionId': selectedOptionId,
            }),
          )
          .timeout(_requestTimeout);

      debugPrint(
        'Learning lesson/answer status: ${response.statusCode}',
      );

      debugPrint(
        'Learning lesson/answer response: ${response.body}',
      );

      if (response.statusCode == 200) {
        final result =
            jsonDecode(response.body) as Map<String, dynamic>;

        final currentIndex =
            (session['questionIndex'] as num?)?.toInt() ?? 0;

        // "questionNumber" is the 1-based number of the question that was
        // just answered, so it is also the 0-based index of the next one.
        // Fall back to counting locally if the backend omits it.
        final nextIndex =
            (result['questionNumber'] as num?)?.toInt() ??
                currentIndex + 1;

        // The backend tells us whether the lesson is finished and sends
        // the next question itself (it is generated after each answer).
        final isComplete = result['lessonComplete'] == true;

        Map<String, dynamic>? nextQuestion;

        if (!isComplete && result['nextQuestion'] is Map) {
          nextQuestion = Map<String, dynamic>.from(
            result['nextQuestion'] as Map,
          );
        }

        // 1-10 backend score after the lesson (only present at the end).
        final scoreAfter = (result['scoreAfter'] as num?)?.toInt();

        return {
          ...result,
          'sessionId': lessonId,
          'nextQuestion': nextQuestion,
          'sessionStatus': isComplete
              ? 'COMPLETED'
              : 'ACTIVE',
          'questionIndex': nextIndex,
          'completionSummary': isComplete
              ? {
                  'currentLevel': scoreAfter != null
                      ? _levelNameForScore(scoreAfter)
                      : 'beginner',
                  'score': scoreAfter ?? 0,
                  'scoreBefore': result['scoreBefore'],
                  'scoreIncreased': result['scoreIncreased'] ?? false,
                  'passed': result['passed'] ?? false,
                  'correctAnswers': result['correctAnswers'] ?? 0,
                  'percentage': result['percentage'] ?? 0,
                  'xpEarned': result['xpEarned'] ?? 0,
                  'scoreName': result['scoreName'],
                  'dayStreak': result['dayStreak'] ?? 0,
                }
              : null,
        };
      }

      debugPrint(
        'lesson/answer failed: ${response.statusCode} ${response.body}',
      );

      _lastError = _friendlyError(
        response.statusCode,
        response.body,
        isAnswer: true,
      );
    } catch (e) {
      debugPrint(
        'Error evaluating answer in Learning Engine: $e',
      );

      _lastError = _networkError(e);
    }

    return null;
  }
}