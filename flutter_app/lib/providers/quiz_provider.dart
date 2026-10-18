import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/learning_engine_service.dart';
import '../services/practice_service.dart';

enum AppPhase {
  onboarding1,
  onboarding2,
  assessmentComplete,
  mainApp,
}

enum AppTab {
  dashboard,
  quiz,
  learning,
  portfolio,
  assistant,
}

class QuizProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  // Same test user as LearningProvider.
  static const String _quizUserId = 'disha_test';

  // ───────────────────────────────────────────────────────────────────────────
  // App & Navigation State
  // ───────────────────────────────────────────────────────────────────────────

  AppPhase _phase = AppPhase.mainApp;
  AppTab _currentTab = AppTab.dashboard;
  bool _isDarkMode = false;
  int _userLevel = 2;

  // ───────────────────────────────────────────────────────────────────────────
  // Onboarding Phase 1 - Backend Learning Quiz State
  // ───────────────────────────────────────────────────────────────────────────

  Map<String, dynamic>? _activeSession;
  Map<String, dynamic>? _currentQuestion;
  Map<String, dynamic>? _completionSummary;
  String? _selectedQuizOption;
  bool _isLoadingQuiz = false;

  // Feedback for the answer that was just submitted (correct, explanation,
  // correctOptionId, learningTip, ...). Replaced after every answer.
  Map<String, dynamic>? _lastAnswerFeedback;

  // Human-readable error for the quiz UI (null when everything is fine).
  String? _quizError;

  // ───────────────────────────────────────────────────────────────────────────
  // Onboarding Phase 2 - Glossary State
  // ───────────────────────────────────────────────────────────────────────────

  String? _selectedWordId;
  String? _selectedMeaningId;
  final Set<String> _matchedPairs = {};
  bool _showXpPop = false;

  // ───────────────────────────────────────────────────────────────────────────
  // Live Data Lists
  // ───────────────────────────────────────────────────────────────────────────

  List<MarketAsset> _marketAssets = [];
  List<FactorImpact> _factorImpacts = [];

  final List<AssistantMessage> _messages = [];

  bool _isLoadingAssets = false;
  bool _isLoadingAssistant = false;

  // ───────────────────────────────────────────────────────────────────────────
  // Dashboard & Portfolio State
  // ───────────────────────────────────────────────────────────────────────────

  DashboardMetrics? _dashboardMetrics;
  List<PortfolioHolding> _portfolioHoldings = [];

  bool _isLoadingDashboard = false;
  bool _isLoadingPortfolio = false;

  // ───────────────────────────────────────────────────────────────────────────
  // Duolingo-style Practice Quiz State
  // ───────────────────────────────────────────────────────────────────────────

  Map<String, dynamic>? _practiceQuestion;
  Map<String, dynamic>? _practiceSubmitResult;

  bool _isPracticeLoading = false;
  bool _isPracticeSubmitting = false;

  int _practiceXp = 0;
  int _practiceStreak = 0;
  int _practiceHearts = 5;
  int _practiceMaxHearts = 5;
  int _practiceNextLevelXp = 50;
  int _practiceQuestionsAnswered = 0;

  String _practiceDifficulty = 'easy';
  String? _practiceTopic;

  bool _practiceRoundComplete = false;
  bool _practiceRoundPass = false;
  bool _practiceLevelUp = false;

  String? _practiceLevelUpName;
  String _practiceGeneratedBy = 'fallback';

  // ───────────────────────────────────────────────────────────────────────────
  // Constructor
  // ───────────────────────────────────────────────────────────────────────────

  QuizProvider() {
    _initInitialData();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // General Getters
  // ───────────────────────────────────────────────────────────────────────────

  AppPhase get phase => _phase;

  AppTab get currentTab => _currentTab;

  bool get isDarkMode => _isDarkMode;

  int get userLevel => _userLevel;

  String get skillLevel {
    switch (_userLevel) {
      case 1:
        return 'novice';
      case 2:
        return 'beginner';
      case 3:
        return 'intermediate';
      case 4:
        return 'advanced';
      case 5:
        return 'expert';
      default:
        return 'beginner';
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Onboarding Quiz Getters
  // ───────────────────────────────────────────────────────────────────────────

  Map<String, dynamic>? get activeSession => _activeSession;

  Map<String, dynamic>? get currentQuestion => _currentQuestion;

  Map<String, dynamic>? get completionSummary => _completionSummary;

  String? get selectedQuizOption => _selectedQuizOption;

  bool get isLoadingQuiz => _isLoadingQuiz;

  /// Feedback for the last submitted answer. Keys include:
  /// correct, selectedOptionId, correctOptionId, explanation, learningTip,
  /// questionNumber, totalQuestions, correctAnswers, lessonComplete.
  Map<String, dynamic>? get lastAnswerFeedback => _lastAnswerFeedback;

  /// Error message to show in the quiz UI, or null.
  String? get quizError => _quizError;

  /// Total questions in the lesson (backend default: 10).
  int get quizTotalQuestions =>
      (_activeSession?['totalQuestions'] as num?)?.toInt() ?? 10;

  /// 1-based number of the question currently on screen.
  int get quizQuestionNumber {
    final index =
        (_activeSession?['questionIndex'] as num?)?.toInt() ?? 0;

    return (index + 1).clamp(1, quizTotalQuestions).toInt();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Glossary Getters
  // ───────────────────────────────────────────────────────────────────────────

  String? get selectedWordId => _selectedWordId;

  String? get selectedMeaningId => _selectedMeaningId;

  Set<String> get matchedPairs => _matchedPairs;

  bool get showXpPop => _showXpPop;

  bool get isGlossaryFinished => _matchedPairs.length >= 2;

  // ───────────────────────────────────────────────────────────────────────────
  // Dynamic App State Getters
  // ───────────────────────────────────────────────────────────────────────────

  List<MarketAsset> get marketAssets => _marketAssets;

  List<FactorImpact> get factorImpacts => _factorImpacts;

  List<AssistantMessage> get messages => _messages;

  bool get isLoadingAssets => _isLoadingAssets;

  bool get isLoadingAssistant => _isLoadingAssistant;

  DashboardMetrics? get dashboardMetrics => _dashboardMetrics;

  List<PortfolioHolding> get portfolioHoldings => _portfolioHoldings;

  bool get isLoadingDashboard => _isLoadingDashboard;

  bool get isLoadingPortfolio => _isLoadingPortfolio;

  // ───────────────────────────────────────────────────────────────────────────
  // Practice Quiz Getters
  // ───────────────────────────────────────────────────────────────────────────

  Map<String, dynamic>? get practiceQuestion => _practiceQuestion;

  Map<String, dynamic>? get practiceSubmitResult => _practiceSubmitResult;

  bool get isPracticeLoading => _isPracticeLoading;

  bool get isPracticeSubmitting => _isPracticeSubmitting;

  int get practiceXp => _practiceXp;

  int get practiceStreak => _practiceStreak;

  int get practiceHearts => _practiceHearts;

  int get practiceMaxHearts => _practiceMaxHearts;

  int get practiceNextLevelXp => _practiceNextLevelXp;

  int get practiceQuestionsAnswered => _practiceQuestionsAnswered;

  String get practiceDifficulty => _practiceDifficulty;

  String? get practiceTopic => _practiceTopic;

  bool get practiceRoundComplete => _practiceRoundComplete;

  bool get practiceRoundPass => _practiceRoundPass;

  bool get practiceLevelUp => _practiceLevelUp;

  String? get practiceLevelUpName => _practiceLevelUpName;

  String get practiceGeneratedBy => _practiceGeneratedBy;

  // ───────────────────────────────────────────────────────────────────────────
  // Practice Quiz XP Progress
  // ───────────────────────────────────────────────────────────────────────────

  double get practiceXpFraction {
    final prevThreshold = _prevLevelXpThreshold(_practiceXp);
    final range = _practiceNextLevelXp - prevThreshold;

    if (range <= 0) {
      return 1.0;
    }

    return (((_practiceXp - prevThreshold) / range)).clamp(0.0, 1.0);
  }

  int _prevLevelXpThreshold(int xp) {
    const thresholds = [0, 50, 150, 350, 700];

    int prev = 0;

    for (final t in thresholds) {
      if (xp < t) {
        return prev;
      }

      prev = t;
    }

    return 700;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Practice Quiz Methods
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> loadPracticeQuestion() async {
    _isPracticeLoading = true;
    _practiceSubmitResult = null;
    _practiceRoundComplete = false;
    _practiceRoundPass = false;
    _practiceLevelUp = false;
    _practiceLevelUpName = null;

    notifyListeners();

    try {
      final data = await PracticeService.fetchQuestion(
        xaiLevel: _userLevel,
        currentXp: _practiceXp,
      );

      if (data != null) {
        _practiceQuestion =
            data['question'] as Map<String, dynamic>?;

        _practiceXp =
            (data['xp'] as num?)?.toInt() ?? _practiceXp;

        _practiceStreak =
            (data['streak'] as num?)?.toInt() ?? _practiceStreak;

        _practiceHearts =
            (data['hearts'] as num?)?.toInt() ?? _practiceHearts;

        _practiceMaxHearts =
            (data['maxHearts'] as num?)?.toInt() ??
                _practiceMaxHearts;

        _practiceNextLevelXp =
            (data['nextLevelXp'] as num?)?.toInt() ??
                _practiceNextLevelXp;

        _practiceQuestionsAnswered =
            (data['questionsAnswered'] as num?)?.toInt() ??
                _practiceQuestionsAnswered;

        _practiceDifficulty =
            data['difficulty'] as String? ??
                _practiceDifficulty;

        _practiceTopic = data['topic'] as String?;

        _practiceGeneratedBy =
            data['generatedBy'] as String? ?? 'fallback';
      }
    } catch (e) {
      debugPrint('loadPracticeQuestion error: $e');
    } finally {
      _isPracticeLoading = false;
      notifyListeners();
    }
  }

  Future<void> submitPracticeAnswer({
    required String selectedOptionId,
    required String correctOptionId,
  }) async {
    if (_practiceQuestion == null) {
      return;
    }

    _isPracticeSubmitting = true;
    notifyListeners();

    try {
      final qId =
          _practiceQuestion!['questionId'] as String? ?? '';

      final result = await PracticeService.submitAnswer(
        questionId: qId,
        selectedOptionId: selectedOptionId,
        correctOptionId: correctOptionId,
        difficulty: _practiceDifficulty,
        xaiLevel: _userLevel,
        topic: _practiceTopic,
      );

      if (result != null) {
        _practiceSubmitResult = result;

        _practiceXp =
            (result['newXp'] as num?)?.toInt() ?? _practiceXp;

        _practiceStreak =
            (result['newStreak'] as num?)?.toInt() ??
                _practiceStreak;

        _practiceHearts =
            (result['heartsRemaining'] as num?)?.toInt() ??
                _practiceHearts;

        _practiceMaxHearts =
            (result['maxHearts'] as num?)?.toInt() ??
                _practiceMaxHearts;

        _practiceNextLevelXp =
            (result['nextLevelXp'] as num?)?.toInt() ??
                _practiceNextLevelXp;

        _practiceQuestionsAnswered =
            (result['questionsAnswered'] as num?)?.toInt() ??
                _practiceQuestionsAnswered;

        _practiceDifficulty =
            result['newDifficulty'] as String? ??
                _practiceDifficulty;

        _practiceRoundComplete =
            result['roundComplete'] as bool? ?? false;

        _practiceRoundPass =
            result['roundPass'] as bool? ?? false;

        _practiceLevelUp =
            result['levelUp'] as bool? ?? false;

        _practiceLevelUpName =
            result['levelUpName'] as String?;

        // Sync XAI level with practice level.
        final newLevel =
            (result['xaiLevel'] as num?)?.toInt();

        if (newLevel != null && newLevel != _userLevel) {
          _userLevel = newLevel;
        }

        // Update dashboard XP.
        completePracticeQuiz(
          (result['xpDelta'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (e) {
      debugPrint('submitPracticeAnswer error: $e');
    } finally {
      _isPracticeSubmitting = false;
      notifyListeners();
    }
  }

  void resetPracticeSession() {
    _practiceQuestion = null;
    _practiceSubmitResult = null;
    _practiceRoundComplete = false;
    _practiceRoundPass = false;
    _practiceLevelUp = false;
    _practiceLevelUpName = null;

    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Navigation & UI Actions
  // ───────────────────────────────────────────────────────────────────────────

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setPhase(AppPhase newPhase) {
    _phase = newPhase;
    notifyListeners();
  }

  void setTab(AppTab tab) {
    _currentTab = tab;
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Onboarding Adaptive Quiz Backend Logic
  // ───────────────────────────────────────────────────────────────────────────

  /// Starts a backend lesson for the onboarding quiz.
  ///
  /// If a quiz is already loaded this does nothing, so that re-calling it
  /// (e.g. from a screen's initState) does not start a second lesson, burn
  /// another LLM call or invalidate the lesson in progress. Pass
  /// `force: true` to deliberately restart.
  Future<void> initQuizSession({bool force = false}) async {
    if (_isLoadingQuiz) return;

    if (!force && _activeSession != null && _currentQuestion != null) {
      return;
    }

    _isLoadingQuiz = true;
    _selectedQuizOption = null;
    _completionSummary = null;
    _activeSession = null;
    _currentQuestion = null;
    _lastAnswerFeedback = null;
    _quizError = null;

    notifyListeners();

    try {
      debugPrint('Starting onboarding quiz...');
      debugPrint(
        'Backend URL: ${LearningEngineService.baseUrl}',
      );

      final data = await LearningEngineService.fetchQuestion(
        userId: _quizUserId,
        xaiLevel: _userLevel,
      );

      if (data == null) {
        debugPrint(
          'QUIZ ERROR: fetchQuestion returned null. '
          'Check learning_engine_service.dart and backend logs.',
        );
        _quizError =
            'Unable to load dynamic questions. '
            'Check that the backend is running and try again.';
        return;
      }

      debugPrint('Quiz response received: $data');

      final question =
          data['question'] as Map<String, dynamic>?;

      if (question == null || question.isEmpty) {
        debugPrint(
          'QUIZ ERROR: Response does not contain a valid question.',
        );
        debugPrint('Response keys: ${data.keys.toList()}');
        _quizError = 'The lesson did not return a question.';
        return;
      }

      final options = question['options'];

      if (options is! List || options.isEmpty) {
        debugPrint(
          'QUIZ ERROR: The question has no valid options.',
        );
        debugPrint('Question data: $question');
        _quizError = 'The question had no answer options.';
        return;
      }

      _activeSession = data;
      _currentQuestion = question;

      debugPrint('Onboarding quiz initialized successfully.');
      debugPrint('Lesson ID: ${data['lessonId']}');
      debugPrint('Question: ${question['prompt']}');
      debugPrint('Number of options: ${options.length}');
    } catch (e, stackTrace) {
      debugPrint('QUIZ INITIALIZATION ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
      _quizError = 'Unable to load dynamic questions.';
    } finally {
      _isLoadingQuiz = false;
      notifyListeners();
    }
  }

  void selectQuizOption(String optionId) {
    /*
     * Do not allow changing the answer while the backend
     * request is being processed.
     */
    if (_isLoadingQuiz) {
      return;
    }

    _selectedQuizOption = optionId;
    notifyListeners();
  }

  Future<void> submitQuizAnswer(String optionId) async {
    if (_isLoadingQuiz ||
        _activeSession == null ||
        _currentQuestion == null) {
      debugPrint(
        'Cannot submit answer: session or question is missing.',
      );
      return;
    }

    final questionId =
        _currentQuestion!['questionId']?.toString() ??
        _currentQuestion!['id']?.toString() ??
        '';

    if (questionId.isEmpty) {
      debugPrint(
        'QUIZ ERROR: Question has no questionId or id.',
      );
      debugPrint('Question data: $_currentQuestion');
      return;
    }

    _selectedQuizOption = optionId;
    _isLoadingQuiz = true;
    _quizError = null;
    notifyListeners();

    try {
      final response = await LearningEngineService.evaluateLevel(
        session: _activeSession!,
        selectedOptionId: optionId,
        questionId: questionId,
        userId: _quizUserId,
      );

      if (response == null) {
        // The backend does not record an answer that failed, so the user
        // can simply tap the option again.
        debugPrint(
          'QUIZ ERROR: Backend returned no answer response. '
          'Check learning_engine_service.dart and backend logs.',
        );
        _quizError =
            'Could not submit your answer. '
            'Check your connection and try again.';
        return;
      }

      _lastAnswerFeedback = Map<String, dynamic>.from(response);

      final status =
          response['sessionStatus']?.toString() ?? '';

      final nextQuestion =
          response['nextQuestion'] as Map<String, dynamic>?;

      final summary =
          response['completionSummary'] as Map<String, dynamic>?;

      // Merge the response into the session, and keep the session's
      // "question" / "questions" pointing at the question on screen.
      final updatedQuestions = <dynamic>[
        ...((_activeSession!['questions'] as List?) ?? const []),
        if (nextQuestion != null) nextQuestion,
      ];

      _activeSession = {
        ..._activeSession!,
        ...response,
        'questions': updatedQuestions,
        'question': nextQuestion ?? _activeSession!['question'],
        'questionIndex':
            (response['questionIndex'] as num?)?.toInt() ??
            (_activeSession!['questionIndex'] as num?)?.toInt() ??
            0,
      };

      if (status == 'COMPLETED' || summary != null) {
        _completionSummary = summary;

        // Prefer the real backend score (1-10) over the placeholder
        // "currentLevel" string.
        final score = (summary?['score'] as num?)?.toInt();
        final level = summary?['currentLevel'];

        if (score != null && score > 0) {
          _userLevel = _scoreToUserLevel(score);
        } else if (level != null) {
          _userLevel = _parseSkillLevelToNumeric(
            level.toString(),
          );
        }

        _currentQuestion = null;
        _selectedQuizOption = null;
        setPhase(AppPhase.onboarding2);
      } else if (nextQuestion != null) {
        _currentQuestion = nextQuestion;
        _selectedQuizOption = null;

        debugPrint(
          'Next question: ${nextQuestion['prompt']}',
        );
      } else {
        debugPrint(
          'QUIZ ERROR: Response contains neither a next '
          'question nor a completion status.',
        );
        debugPrint('Answer response: $response');
        _quizError = 'The next question could not be loaded.';
      }
    } catch (e, stackTrace) {
      debugPrint('QUIZ ANSWER ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
      _quizError = 'Something went wrong. Please try again.';
    } finally {
      _isLoadingQuiz = false;
      notifyListeners();
    }
  }

  /// Backend score is 1-10; the app's userLevel is 1-5.
  int _scoreToUserLevel(int score) {
    return ((score + 1) ~/ 2).clamp(1, 5).toInt();
  }

  int _parseSkillLevelToNumeric(String level) {
    switch (level.toLowerCase()) {
      case 'novice':
        return 1;

      case 'beginner':
        return 2;

      case 'intermediate':
        return 3;

      case 'advanced':
        return 4;

      case 'expert':
        return 5;

      default:
        return 2;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Glossary Match Game Actions
  // ───────────────────────────────────────────────────────────────────────────

  void selectWord(String id) {
    _selectedWordId = id;
    notifyListeners();
  }

  void selectMeaning(
    String id,
    String targetWordId,
  ) {
    _selectedMeaningId = id;

    if (_selectedWordId != null) {
      if (_selectedWordId == targetWordId) {
        _matchedPairs.add(_selectedWordId!);

        _showXpPop = true;

        _selectedWordId = null;
        _selectedMeaningId = null;

        notifyListeners();

        Future.delayed(
          const Duration(milliseconds: 900),
          () {
            _showXpPop = false;
            notifyListeners();
          },
        );
      } else {
        Future.delayed(
          const Duration(milliseconds: 400),
          () {
            _selectedWordId = null;
            _selectedMeaningId = null;

            notifyListeners();
          },
        );
      }
    } else {
      notifyListeners();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Initial App Data Load
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _initInitialData() async {
    _messages.add(
      AssistantMessage(
        id: 'msg_welcome',
        content:
            "Hello, I'm your QuantEdge Assistant. "
            "Ask me anything about structural anomalies "
            "or custom market inquiries.",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    await Future.wait([
      //initQuizSession(),
      refreshMarketData(),
      refreshDashboardMetrics(),
      refreshPortfolioData(),
    ]);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Dashboard
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> refreshDashboardMetrics() async {
    _isLoadingDashboard = true;
    notifyListeners();

    _dashboardMetrics =
        await _apiService.fetchDashboardMetrics();

    _isLoadingDashboard = false;
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Portfolio
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> refreshPortfolioData() async {
    _isLoadingPortfolio = true;
    notifyListeners();

    _portfolioHoldings =
        await _apiService.fetchPortfolioData();

    _isLoadingPortfolio = false;
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Market Data
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> refreshMarketData() async {
    _isLoadingAssets = true;
    notifyListeners();

    _marketAssets =
        await _apiService.fetchMarketAssets();

    _factorImpacts =
        await _apiService.fetchFactorImpacts();

    _isLoadingAssets = false;
    notifyListeners();
  }

  Future<void> refreshAllData() async {
    await Future.wait([
      refreshMarketData(),
      refreshDashboardMetrics(),
      refreshPortfolioData(),
    ]);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Assistant
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> sendAssistantMessage(
    String query,
  ) async {
    if (query.trim().isEmpty) {
      return;
    }

    final userMsg = AssistantMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      content: query.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );

    _messages.add(userMsg);

    _isLoadingAssistant = true;
    notifyListeners();

    final replyText =
        await _apiService.sendAssistantQuery(
      query,
      _userLevel,
    );

    final botMsg = AssistantMessage(
      id: 'bot_${DateTime.now().millisecondsSinceEpoch}',
      content: replyText,
      isUser: false,
      timestamp: DateTime.now(),
    );

    _messages.add(botMsg);

    _isLoadingAssistant = false;
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Practice Quiz Leveling & XP Actions
  // ───────────────────────────────────────────────────────────────────────────

  void completePracticeQuiz(int xpGained) {
    if (_dashboardMetrics != null) {
      final updatedXp =
          _dashboardMetrics!.xpPoints + xpGained;

      int newLevel = _userLevel;

      // Auto level-up logic.
      if (updatedXp >= 3500 && _userLevel < 5) {
        newLevel += 1;
      }

      _userLevel = newLevel;

      _dashboardMetrics = DashboardMetrics(
        portfolioValue:
            _dashboardMetrics!.portfolioValue,
        dailyChange:
            _dashboardMetrics!.dailyChange,
        weeklyChange:
            _dashboardMetrics!.weeklyChange,
        xpPoints: updatedXp,
        userLevel: newLevel,
        winRate:
            _dashboardMetrics!.winRate,
        nextLevelMilestone:
            newLevel >= 5
                ? 'MAX LEVEL'
                : '${newLevel * 1500 + 500} XP',
      );

      notifyListeners();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Dynamic XAI Insight Fetcher
  // ───────────────────────────────────────────────────────────────────────────

  Future<String> fetchXaiInsightForAsset(
    MarketAsset asset,
  ) async {
    try {
      // Use real RSI from asset.
      final double rsi = asset.rsi;
      final double sentiment =
          asset.numericSentiment;

      final response = await http.post(
        Uri.parse(
          '${LearningEngineService.baseUrl}'
          '/api/learning/xai/explain',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'ticker': asset.ticker,
          'decision': asset.status.toUpperCase(),
          'features': {
            'rsi': rsi,
            'ma5': 0.0,
            'ma10': 0.0,
            'volatility': 0.015,
            'sentimentScore': sentiment,
            'marketMood': sentiment > 0.1
                ? 'Bullish'
                : (sentiment < -0.1
                    ? 'Bearish'
                    : 'Neutral'),
            'confidence': double.tryParse(
                      asset.confidence
                          .replaceAll('%', ''),
                    ) !=
                    null
                ? (double.parse(
                      asset.confidence
                          .replaceAll('%', ''),
                    ) /
                    100)
                : 0.70,
          },
          'xaiLevel': _userLevel,
        }),
      ).timeout(
        const Duration(seconds: 6),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Backend returns `summary` field.
        final text =
            data['summary'] ??
                data['detailedExplanation'] ??
                '';

        if (text.toString().isNotEmpty) {
          return text.toString();
        }
      }
    } catch (e) {
      debugPrint(
        'Error fetching XAI insight: $e',
      );
    }

    // Fallback 1: asset insight from backend.
    if (asset.insight.isNotEmpty) {
      return asset.insight;
    }

    // Fallback 2: level-appropriate static summary.
    final status =
        asset.status.toUpperCase();

    final sentiment =
        asset.numericSentiment;

    if (_userLevel <= 2) {
      if (status == 'BUY') {
        return 'Strong buying pressure for '
            '${asset.ticker}. Sentiment score sits at '
            '+$sentiment with high confidence.';
      }

      if (status == 'SELL') {
        return 'Increased selling activity detected in '
            '${asset.ticker}. Sentiment has dipped to '
            '$sentiment.';
      }

      return '${asset.ticker} is trading in a neutral '
          'range with a $sentiment sentiment score. '
          'Recommendation is to hold.';
    }

    return '${asset.ticker} shows a confidence level of '
        '${asset.confidence} driven by technical and '
        'sentiment factor alignment.';
  }
}