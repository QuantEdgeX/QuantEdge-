import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'learning_engine_service.dart';

/// Error thrown by [LearningService]. Its [toString] is a clean,
/// user-friendly message, so `error = e.toString()` in a provider can be
/// shown directly in the UI.
class LearningServiceException implements Exception {
  final String message;
  final int? statusCode;

  const LearningServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class LearningService {
  // FastAPI backend. Single source of truth shared with
  // LearningEngineService (handles Android emulator vs. desktop/web).
  static String get baseUrl => LearningEngineService.baseUrl;

  // Quick data calls vs. calls where the backend asks the LLM to generate
  // (and validate) a question, which can take several seconds.
  static const Duration _quickTimeout = Duration(seconds: 15);
  static const Duration _lessonTimeout = Duration(seconds: 45);

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  // ---------------------------------------------------------
  // GET LEARNING TOPICS
  // ---------------------------------------------------------

  /// Pass [userId] to get that user's unlocked / completed state.
  /// Without it the backend treats the caller as a brand-new user and
  /// every topic except the first one comes back locked.
  Future<Map<String, dynamic>> getTopics({String? userId}) {
    final uri = Uri.parse('$baseUrl/api/learning/topics').replace(
      queryParameters: (userId != null && userId.isNotEmpty)
          ? {'userId': userId}
          : null,
    );

    return _send(
      http.get(uri),
      timeout: _quickTimeout,
    );
  }

  // ---------------------------------------------------------
  // GET USER PROGRESS
  // ---------------------------------------------------------

  Future<Map<String, dynamic>> getProgress(String userId) {
    final uri = Uri.parse('$baseUrl/api/learning/progress').replace(
      queryParameters: {
        'userId': userId,
      },
    );

    return _send(
      http.get(uri),
      timeout: _quickTimeout,
    );
  }

  // ---------------------------------------------------------
  // COMPLETE ONBOARDING
  // ---------------------------------------------------------

  /// Saves the learner's starting place. The backend unlocks every topic
  /// up to [startTopicIndex] (0-based) and sets a matching starting score.
  Future<Map<String, dynamic>> completeOnboarding({
    required String userId,
    required int startTopicIndex,
    required String level,
  }) {
    return _send(
      http.post(
        Uri.parse('$baseUrl/api/learning/onboarding'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'userId': userId,
          'startTopicIndex': startTopicIndex,
          'level': level,
        }),
      ),
      timeout: _quickTimeout,
    );
  }

  // ---------------------------------------------------------
  // PREWARM LESSON
  // ---------------------------------------------------------

  Future<void> prewarmLesson(String userId, {String? topicId}) async {
    try {
      final Map<String, dynamic> body = {'userId': userId};
      if (topicId != null && topicId.isNotEmpty) {
        body['topicId'] = topicId;
      }
      await http.post(
        Uri.parse('$baseUrl/api/learning/lesson/prewarm'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // ---------------------------------------------------------
  // START LESSON
  // ---------------------------------------------------------

  Future<Map<String, dynamic>> startLesson(
    String userId, {
    String? topicId,
  }) {
    final Map<String, dynamic> body = {
      'userId': userId,
    };

    if (topicId != null && topicId.isNotEmpty) {
      body['topicId'] = topicId;
    }

    return _send(
      http.post(
        Uri.parse('$baseUrl/api/learning/lesson/start'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      ),
      timeout: _lessonTimeout,
    );
  }

  // ---------------------------------------------------------
  // SUBMIT ANSWER
  // ---------------------------------------------------------

  /// The backend only records an answer when the call succeeds, so after
  /// an error the same answer can safely be submitted again.
  Future<Map<String, dynamic>> submitAnswer({
    required String userId,
    required String lessonId,
    required String questionId,
    required String selectedOptionId,
  }) {
    return _send(
      http.post(
        Uri.parse('$baseUrl/api/learning/lesson/answer'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'userId': userId,
          'lessonId': lessonId,
          'questionId': questionId,
          'selectedOptionId': selectedOptionId,
        }),
      ),
      timeout: _lessonTimeout,
      isAnswer: true,
    );
  }

  // ---------------------------------------------------------
  // INTERNAL HELPERS
  // ---------------------------------------------------------

  /// Sends a request with a timeout, and converts every failure into a
  /// [LearningServiceException] with a readable message.
  Future<Map<String, dynamic>> _send(
    Future<http.Response> request, {
    required Duration timeout,
    bool isAnswer = false,
  }) async {
    final http.Response response;

    try {
      response = await request.timeout(timeout);
    } on TimeoutException {
      throw const LearningServiceException(
        'The server took too long to respond. Please try again.',
      );
    } catch (_) {
      throw LearningServiceException(
        'Cannot reach the learning server at $baseUrl. '
        'Make sure the backend is running.',
      );
    }

    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Fall through to the error below.
      }

      throw const LearningServiceException(
        'The server sent an unexpected response.',
        statusCode: 200,
      );
    }

    throw LearningServiceException(
      _friendlyError(
        response.statusCode,
        response.body,
        isAnswer: isAnswer,
      ),
      statusCode: response.statusCode,
    );
  }

  /// Reads FastAPI's {"detail": "..."} (or the 422 validation list).
  String? _extractDetail(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is Map) {
        final detail = decoded['detail'];

        if (detail is String && detail.isNotEmpty) {
          return detail;
        }

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

  String _friendlyError(
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
            : (detail ?? 'Not found.');

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
}