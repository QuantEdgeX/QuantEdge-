import 'package:flutter/foundation.dart';

import '../models/learning_models.dart';
import '../services/learning_service.dart';

// Enum definition for bottom bar tabs
enum AppTab {
  dashboard,
  learning,
  portfolio,
  assistant,
}

class LearningProvider extends ChangeNotifier {
  final LearningService _service = LearningService();

  // ------------------------------------------------------------
  // Active Navigation Tab State (Default: Dashboard / Home)
  // ------------------------------------------------------------

  AppTab _currentTab = AppTab.dashboard;

  AppTab get currentTab => _currentTab;

  void setTab(AppTab tab) {
    if (_currentTab != tab) {
      _currentTab = tab;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------
  // User
  // ------------------------------------------------------------

  String _userId = 'disha1_test';

  String get userId => _userId;

  void setUserId(String userId) {
    _userId = userId;
    notifyListeners();
  }

  // ------------------------------------------------------------
  // Onboarding (shown once, at the very start of the app)
  // ------------------------------------------------------------

  bool _onboardingChecked = false;
  bool _needsOnboarding = false;
  bool _isOnboarding = false;

  bool get onboardingChecked => _onboardingChecked;
  bool get needsOnboarding => _needsOnboarding;
  bool get isOnboarding => _isOnboarding;

  Future<void> checkOnboardingStatus() async {
    var needs = false;

    try {
      final data = await _service.getProgress(_userId);

      needs = data['onboarded'] != true;

      try {
        _progress = LearningProgress.fromJson(data);
      } catch (_) {
        // Progress will be reloaded later by loadLearningData().
      }
    } catch (e) {
      // Backend unreachable: don't trap the user behind onboarding.
      debugPrint('checkOnboardingStatus failed: $e');
    }

    _needsOnboarding = needs;
    _onboardingChecked = true;
    notifyListeners();
  }

  /// Saves the learner's starting place and unlocks topics up to it.
  Future<bool> completeOnboarding({
    required int startTopicIndex,
    required String level,
  }) async {
    _isOnboarding = true;
    _clearError();
    notifyListeners();

    try {
      await _service.completeOnboarding(
        userId: _userId,
        startTopicIndex: startTopicIndex,
        level: level,
      );

      // Refresh topics + progress so the Learn tab shows the unlocked topics.
      await loadLearningData();

      _needsOnboarding = false;
      _currentTab = AppTab.learning; // use AppTab.dashboard to land on Home

      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isOnboarding = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------
  // Topics
  // ------------------------------------------------------------

  List<LearningTopic> _topics = [];

  List<LearningTopic> get topics => _topics;

  // ------------------------------------------------------------
  // Progress
  // ------------------------------------------------------------

  LearningProgress? _progress;

  LearningProgress? get progress => _progress;

  // ------------------------------------------------------------
  // Current Lesson
  // ------------------------------------------------------------

  // The backend generates ONE question at a time. Questions are added to
  // this list as they arrive (first from lesson/start, then from the
  // "nextQuestion" field of every lesson/answer response).
  static const int _defaultQuestionsPerLesson = 10;

  LearningLesson? _currentLesson;

  LearningLesson? get currentLesson => _currentLesson;

  List<LearningQuestion> _questions = [];

  int _totalQuestions = _defaultQuestionsPerLesson;

  int _currentQuestionIndex = 0;

  int get currentQuestionIndex => _currentQuestionIndex;

  LearningQuestion? get currentQuestion {
    if (_currentLesson == null) {
      return null;
    }

    if (_currentQuestionIndex >= _questions.length) {
      return null;
    }

    return _questions[_currentQuestionIndex];
  }

  // ------------------------------------------------------------
  // Selected Answer
  // ------------------------------------------------------------

  String? _selectedOptionId;

  String? get selectedOptionId => _selectedOptionId;

  // ------------------------------------------------------------
  // Answer Feedback
  // ------------------------------------------------------------

  AnswerResult? _lastAnswerResult;

  AnswerResult? get lastAnswerResult => _lastAnswerResult;

  bool get hasAnswered => _lastAnswerResult != null;

  // Raw backend response of the last answer. Useful for the result screen:
  // xpEarned, scoreBefore/scoreAfter, dayStreak, weakAreas, mistakes,
  // allTopicsCompleted, message, etc.
  Map<String, dynamic>? _lastRawResult;

  Map<String, dynamic>? get lastRawResult => _lastRawResult;

  // ------------------------------------------------------------
  // Lesson State
  // ------------------------------------------------------------

  bool _lessonComplete = false;

  bool get lessonComplete => _lessonComplete;

  bool _lessonPassed = false;

  bool get lessonPassed => _lessonPassed;

  // ------------------------------------------------------------
  // Loading
  // ------------------------------------------------------------

  bool _isLoading = false;

  bool get isLoading => _isLoading;

  bool _isSubmitting = false;

  bool get isSubmitting => _isSubmitting;

  // ------------------------------------------------------------
  // Error
  // ------------------------------------------------------------

  String? _error;

  String? get error => _error;

  // ------------------------------------------------------------
  // Convenience getters
  // ------------------------------------------------------------

  /// Total questions in the lesson (10), NOT the number loaded so far.
  int get totalQuestions {
    return _currentLesson == null ? 0 : _totalQuestions;
  }

  int get questionNumber {
    return _currentQuestionIndex + 1;
  }

  bool get hasCurrentLesson {
    return _currentLesson != null;
  }

  bool get canSubmitAnswer {
    return _selectedOptionId != null &&
        !_isSubmitting &&
        !_lessonComplete;
  }

  // ------------------------------------------------------------
  // Load Topics
  // ------------------------------------------------------------

  Future<void> loadTopics() async {
    _setLoading(true);
    _clearError();

    try {
      final data = await _service.getTopics(userId: _userId);

      final topicsJson = data['topics'] as List? ?? [];

      _topics = topicsJson
          .map(
            (topic) => LearningTopic.fromJson(
              topic as Map<String, dynamic>,
            ),
          )
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ------------------------------------------------------------
  // Load Progress
  // ------------------------------------------------------------

  Future<void> loadProgress() async {
    _setLoading(true);
    _clearError();

    try {
      final data = await _service.getProgress(_userId);

      _progress = LearningProgress.fromJson(data);
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ------------------------------------------------------------
  // Load Everything
  // ------------------------------------------------------------

  Future<void> loadLearningData() async {
    _setLoading(true);
    _clearError();

    try {
      final results = await Future.wait([
        _service.getTopics(userId: _userId),
        _service.getProgress(_userId),
      ]);

      final topicsData = results[0];
      final progressData = results[1];

      final topicsJson = topicsData['topics'] as List? ?? [];

      _topics = topicsJson
          .map(
            (topic) => LearningTopic.fromJson(
              topic as Map<String, dynamic>,
            ),
          )
          .toList();

      _progress = LearningProgress.fromJson(progressData);
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ------------------------------------------------------------
  // Start Lesson
  // ------------------------------------------------------------

  Future<bool> startLesson([String? topicId]) async {
    _setLoading(true);
    _clearError();

    try {
      final data = await _service.startLesson(_userId, topicId: topicId);

      // Path already finished: backend returns completedAllTopics
      // instead of a question.
      if (data['completedAllTopics'] == true) {
        _error = (data['message'] as String?) ??
            'You have completed the full learning path!';
        return false;
      }

      final rawQuestion = data['question'];

      if (rawQuestion is! Map) {
        _error = 'The lesson did not return a question. Please try again.';
        return false;
      }

      // The backend sends a single "question" and a nested "topic".
      // Convert it into the shape LearningLesson.fromJson expects
      // (a "questions" list plus topicId / topicTitle).
      final normalized = Map<String, dynamic>.from(data);

      if (normalized['questions'] is! List ||
          (normalized['questions'] as List).isEmpty) {
        normalized['questions'] = [rawQuestion];
      }

      final topic = data['topic'];

      if (topic is Map) {
        normalized['topicId'] ??= topic['id'];
        normalized['topicTitle'] ??= topic['title'];
      }

      final lesson = LearningLesson.fromJson(normalized);

      _currentLesson = lesson;

      _questions = List<LearningQuestion>.from(lesson.questions);

      _totalQuestions =
          (data['totalQuestions'] as num?)?.toInt() ??
              _defaultQuestionsPerLesson;

      _currentQuestionIndex = 0;
      _selectedOptionId = null;
      _lastAnswerResult = null;
      _lastRawResult = null;
      _lessonComplete = false;
      _lessonPassed = false;

      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ------------------------------------------------------------
  // Select Answer
  // ------------------------------------------------------------

  void selectAnswer(String optionId) {
    if (_lessonComplete || _isSubmitting) {
      return;
    }

    if (_lastAnswerResult != null) {
      return;
    }

    _selectedOptionId = optionId;

    notifyListeners();
  }

  // ------------------------------------------------------------
  // Submit Answer
  // ------------------------------------------------------------

  Future<bool> submitAnswer() async {
    if (!canSubmitAnswer) {
      return false;
    }

    final lesson = _currentLesson;
    final question = currentQuestion;
    final selectedOption = _selectedOptionId;

    if (lesson == null ||
        question == null ||
        selectedOption == null) {
      return false;
    }

    _isSubmitting = true;
    _clearError();
    notifyListeners();

    try {
      final data = await _service.submitAnswer(
        userId: _userId,
        lessonId: lesson.lessonId,
        questionId: question.id,
        selectedOptionId: selectedOption,
      );

      final result = AnswerResult.fromJson(data);

      _lastRawResult = Map<String, dynamic>.from(data);

      // Keep the next question that the backend just generated so that
      // nextQuestion() has something to move to.
      if (!result.lessonComplete) {
        final rawNext = data['nextQuestion'];

        if (rawNext is Map) {
          _questions.add(
            LearningQuestion.fromJson(
              Map<String, dynamic>.from(rawNext),
            ),
          );
        }
      }

      _lastAnswerResult = result;

      if (result.lessonComplete) {
        _lessonComplete = true;
        _lessonPassed = result.passed;

        // Refresh progress after the lesson finishes.
        await loadLearningData();
      }

      return true;
    } catch (e) {
      // The backend does not record the answer if it fails (e.g. the next
      // question could not be generated), so the user can simply retry.
      _error = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------
  // Move to Next Question
  // ------------------------------------------------------------

  void nextQuestion() {
    if (_currentLesson == null) {
      return;
    }

    if (_lessonComplete) {
      return;
    }

    if (_lastAnswerResult == null) {
      return;
    }

    // The next question is added in submitAnswer(); if it is missing
    // there is nothing to move to.
    if (_currentQuestionIndex >= _questions.length - 1) {
      return;
    }

    _currentQuestionIndex++;

    _selectedOptionId = null;
    _lastAnswerResult = null;
    _lastRawResult = null;

    notifyListeners();
  }

  // ------------------------------------------------------------
  // Retry Lesson
  // ------------------------------------------------------------

  /// Starts a fresh lesson on the same topic. The backend remembers every
  /// question already asked, so a retake always has different questions.
  Future<bool> retryLesson() async {
    return startLesson(_currentLesson?.topicId);
  }

  // ------------------------------------------------------------
  // Clear Current Lesson
  // ------------------------------------------------------------

  void clearLesson() {
    _currentLesson = null;
    _questions = [];
    _totalQuestions = _defaultQuestionsPerLesson;
    _currentQuestionIndex = 0;
    _selectedOptionId = null;
    _lastAnswerResult = null;
    _lastRawResult = null;
    _lessonComplete = false;
    _lessonPassed = false;

    notifyListeners();
  }

  // ------------------------------------------------------------
  // Clear Error
  // ------------------------------------------------------------

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------
  // Private Helpers
  // ------------------------------------------------------------

  void _clearError() {
    _error = null;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}