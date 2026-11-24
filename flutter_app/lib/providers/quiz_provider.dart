import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_models.dart';
import '../models/learning_models.dart';
import '../providers/learning_provider.dart' show AppTab;
import '../services/api_service.dart';
import '../services/learning_engine_service.dart';
import '../services/learning_service.dart';
import '../services/practice_service.dart';
import '../services/qwen_xai_service.dart';

enum AppPhase {
  splash,
  login,
  enrichment,
  onboarding1,
  onboarding2,
  assessmentComplete,
  tour,
  tickerSelection,
  mainApp,
}


class QuizProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  // Try syncing profile to Firebase
  Future<void> _syncToFirebase() async {
    try {
      if (Firebase.apps.isEmpty) return; // Not initialized
      final firestore = FirebaseFirestore.instance;
      
      // Use email as doc ID if available, else fallback
      final docId = _userProfile.email.isNotEmpty 
          ? _userProfile.email 
          : 'guest_user';
          
      await firestore.collection('users').doc(docId).set({
        'name': _userProfile.name,
        'email': _userProfile.email,
        'experienceLevel': _userProfile.experienceLevel,
        'riskStyle': _userProfile.riskStyle,
        'sectorInterests': _userProfile.sectorInterests,
        'investingGoal': _userProfile.investingGoal,
        'chosenTickers': _userProfile.chosenTickers,
        'level': _userLevel,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Firebase sync failed: $e');
    }
  }

  // App & Navigation State
  AppPhase _phase = AppPhase.splash;
  AppTab _currentTab = AppTab.dashboard;
  bool _isDarkMode = false;
  int _userLevel = 2;

  // Onboarding Phase 1 (Backend Adaptive Quiz) State
  Map<String, dynamic>? _activeSession;
  Map<String, dynamic>? _currentQuestion;
  Map<String, dynamic>? _completionSummary;
  String? _selectedQuizOption;
  bool _isLoadingQuiz = false;

  // Onboarding Phase 2 (Glossary) State
  String? _selectedWordId;
  String? _selectedMeaningId;
  final Set<String> _matchedPairs = {};
  bool _showXpPop = false;

  // Live Data Lists
  List<MarketAsset> _marketAssets = [];
  List<FactorImpact> _factorImpacts = [];
  final List<AssistantMessage> _messages = [];
  bool _isLoadingAssets = false;
  bool _isLoadingAssistant = false;

  // Dashboard & Portfolio State
  DashboardMetrics? _dashboardMetrics;
  List<PortfolioHolding> _portfolioHoldings = [];
  bool _isLoadingDashboard = false;
  bool _isLoadingPortfolio = false;

  // User Profile & New-flow State
  UserProfile _userProfile = const UserProfile();
  bool _enrichmentSkipped = false;
  List<String> _selectedTickers = [];
  List<TickerSearchResult> _tickerSearchResults = [];
  bool _isSearchingTickers = false;
  bool _isLaunchingWorkspace = false;
  Timer? _searchDebounce;
  final Map<String, TickerDetail> _tickerDetailCache = {};
  bool _isLoadingTickerDetail = false;

  static const List<Map<String, String>> _popularTickers = [
    {'ticker': 'NVDA', 'name': 'NVIDIA Corporation'},
    {'ticker': 'AAPL', 'name': 'Apple Inc.'},
    {'ticker': 'TSLA', 'name': 'Tesla Inc.'},
    {'ticker': 'MSFT', 'name': 'Microsoft Corporation'},
    {'ticker': 'AMZN', 'name': 'Amazon.com Inc.'},
    {'ticker': 'GOOGL', 'name': 'Alphabet Inc.'},
    {'ticker': 'META', 'name': 'Meta Platforms'},
    {'ticker': 'AMD', 'name': 'Advanced Micro Devices'},
    {'ticker': 'JPM', 'name': 'JPMorgan Chase'},
    {'ticker': 'NFLX', 'name': 'Netflix Inc.'},
    {'ticker': 'DIS', 'name': 'Walt Disney Co.'},
    {'ticker': 'BABA', 'name': 'Alibaba Group'},
  ];

  // ─── Qwen XAI Narrative Service State ───────────────────────────────────
  final QwenXaiService _qwenXaiService = const QwenXaiService();
  final Map<String, String> _qwenExplanationCache = {};

  QwenXaiService get qwenXaiService => _qwenXaiService;

  // ─── Firebase Auth & User State ──────────────────────────────────────────
  String _userId = '';
  StreamSubscription<User?>? _authSubscription;

  String get userId => _userId.isNotEmpty ? _userId : 'default_user';
  String get learningUserId => userId;

  // ─── Disha's Learning Engine State ───────────────────────────────────────
  final LearningService _learningService = LearningService();
  List<LearningTopic> _learningTopics = [];
  LearningProgress? _learningProgress;
  LearningLesson? _currentLearningLesson;
  List<LearningQuestion> _learningQuestions = [];
  int _learningTotalQuestions = 10;
  int _currentLearningQuestionIndex = 0;
  String? _selectedLearningOptionId;
  AnswerResult? _lastLearningAnswerResult;
  Map<String, dynamic>? _lastLearningRawResult;
  bool _learningLessonComplete = false;
  bool _learningLessonPassed = false;
  bool _isLoadingLearning = false;
  bool _isSubmittingLearningAnswer = false;
  String? _learningError;

  QuizProvider() {
    _initAuthListener();
    _initInitialData();
  }

  void _initAuthListener() {
    try {
      if (Firebase.apps.isNotEmpty) {
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) {
          _userId = current.uid;
          PracticeService.setUserId(current.uid);
          _userProfile = _userProfile.copyWith(
            uid: current.uid,
            name: current.displayName ?? current.email?.split('@').first ?? 'Trader',
            email: current.email ?? '',
          );
        }
        _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
          if (user != null) {
            _userId = user.uid;
            PracticeService.setUserId(user.uid);
            _userProfile = _userProfile.copyWith(
              uid: user.uid,
              name: user.displayName ?? user.email?.split('@').first ?? 'Trader',
              email: user.email ?? '',
            );
            notifyListeners();
          }
        });
      }
    } catch (e) {
      debugPrint('Auth listener init notice: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // Getters
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

  // Quiz Getters
  Map<String, dynamic>? get activeSession => _activeSession;
  Map<String, dynamic>? get currentQuestion => _currentQuestion;
  Map<String, dynamic>? get completionSummary => _completionSummary;
  String? get selectedQuizOption => _selectedQuizOption;
  bool get isLoadingQuiz => _isLoadingQuiz;

  // Glossary Getters
  String? get selectedWordId => _selectedWordId;
  String? get selectedMeaningId => _selectedMeaningId;
  Set<String> get matchedPairs => _matchedPairs;
  bool get showXpPop => _showXpPop;
  bool get isGlossaryFinished => _matchedPairs.length >= 2;

  // Dynamic App State Getters
  List<MarketAsset> get marketAssets => _marketAssets;
  List<FactorImpact> get factorImpacts => _factorImpacts;
  List<AssistantMessage> get messages => _messages;
  bool get isLoadingAssets => _isLoadingAssets;
  bool get isLoadingAssistant => _isLoadingAssistant;
  DashboardMetrics? get dashboardMetrics => _dashboardMetrics;
  List<PortfolioHolding> get portfolioHoldings => _portfolioHoldings;
  bool get isLoadingDashboard => _isLoadingDashboard;
  bool get isLoadingPortfolio => _isLoadingPortfolio;

  // New-flow Getters
  UserProfile get userProfile => _userProfile;
  bool get enrichmentSkipped => _enrichmentSkipped;
  List<String> get selectedTickers => _selectedTickers;
  List<TickerSearchResult> get tickerSearchResults => _tickerSearchResults;
  bool get isSearchingTickers => _isSearchingTickers;
  bool get isLaunchingWorkspace => _isLaunchingWorkspace;
  bool get isLoadingTickerDetail => _isLoadingTickerDetail;
  Map<String, TickerDetail> get tickerDetailCache => _tickerDetailCache;
  List<Map<String, String>> get popularTickers => _popularTickers;

  // Disha's Learning Engine Getters
  List<LearningTopic> get learningTopics => _learningTopics;
  LearningProgress? get learningProgress => _learningProgress;
  LearningLesson? get currentLearningLesson => _currentLearningLesson;
  List<LearningQuestion> get learningQuestions => _learningQuestions;
  int get currentLearningQuestionIndex => _currentLearningQuestionIndex;
  LearningQuestion? get currentLearningQuestion {
    if (_currentLearningLesson == null || _currentLearningQuestionIndex >= _learningQuestions.length) {
      return null;
    }
    return _learningQuestions[_currentLearningQuestionIndex];
  }
  String? get selectedLearningOptionId => _selectedLearningOptionId;
  AnswerResult? get lastLearningAnswerResult => _lastLearningAnswerResult;
  Map<String, dynamic>? get lastLearningRawResult => _lastLearningRawResult;
  bool get learningLessonComplete => _learningLessonComplete;
  bool get learningLessonPassed => _learningLessonPassed;
  bool get isLoadingLearning => _isLoadingLearning;
  bool get isSubmittingLearningAnswer => _isSubmittingLearningAnswer;
  String? get learningError => _learningError;
  int get learningTotalQuestions => _currentLearningLesson == null ? 0 : _learningTotalQuestions;
  int get learningQuestionNumber => _currentLearningQuestionIndex + 1;
  int get learningStreak => _lastLearningRawResult != null
      ? ((_lastLearningRawResult!['currentStreak'] as num?)?.toInt() ?? 0)
      : 0;
  int get learningXp => _learningProgress?.xp ?? 0;
  int get learningScore => _learningProgress?.score ?? 0;

  // Navigation & UI Actions
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

  // ─── Adaptive Quiz Backend Logic ─────────────────────────────────────────

  Future<void> initQuizSession() async {
    _isLoadingQuiz = true;
    _selectedQuizOption = null;
    notifyListeners();

    try {
      final data = await LearningEngineService.fetchQuestion(
        userId: userId,
        xaiLevel: _userLevel,
      );

      if (data != null) {
        // New FastAPI response shape: sessionId, userId, question, sessionStatus
        _activeSession = data;
        _currentQuestion = data['question'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('Error initializing quiz session: $e');
    } finally {
      _isLoadingQuiz = false;
      notifyListeners();
    }
  }

  void selectQuizOption(String optionId) {
    _selectedQuizOption = optionId;
    notifyListeners();
  }

  Future<void> submitQuizAnswer(String optionId) async {
    if (_activeSession == null || _currentQuestion == null) return;

    _selectedQuizOption = optionId;
    _isLoadingQuiz = true;
    notifyListeners();

    try {
      final response = await LearningEngineService.evaluateLevel(
        session: _activeSession!,
        selectedOptionId: optionId,
        questionId: _currentQuestion!['questionId'] as String,
        userId: userId,
      );

      if (response != null) {
        // Backend returns: sessionId, answer, sessionDelta, nextQuestion,
        // sessionStatus, completionSummary, session.state
        final status = response['sessionStatus'] as String? ?? '';
        final nextQ  = response['nextQuestion'] as Map<String, dynamic>?;
        final summary = response['completionSummary'] as Map<String, dynamic>?;

        // Update stored session with latest state
        _activeSession = response;

        if (status == 'COMPLETED' || (summary != null)) {
          _completionSummary = summary;
          if (summary?['currentLevel'] != null) {
            _userLevel = _parseSkillLevelToNumeric(summary!['currentLevel'].toString());
          }
          _currentQuestion = null;
          setPhase(AppPhase.onboarding2);
        } else if (nextQ != null) {
          _currentQuestion = nextQ;
          _selectedQuizOption = null;
        } else {
          // Fallback: advance phase if no next question
          _currentQuestion = null;
          setPhase(AppPhase.onboarding2);
        }
      }
    } catch (e) {
      debugPrint('Error submitting answer: $e');
    } finally {
      _isLoadingQuiz = false;
      notifyListeners();
    }
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

  // ─── Glossary Match Game Actions ─────────────────────────────────────────

  void selectWord(String id) {
    _selectedWordId = id;
    notifyListeners();
  }

  void selectMeaning(String id, String targetWordId) {
    _selectedMeaningId = id;
    if (_selectedWordId != null) {
      if (_selectedWordId == targetWordId) {
        _matchedPairs.add(_selectedWordId!);
        _showXpPop = true;
        _selectedWordId = null;
        _selectedMeaningId = null;
        notifyListeners();

        Future.delayed(const Duration(milliseconds: 900), () {
          _showXpPop = false;
          notifyListeners();
        });
      } else {
        Future.delayed(const Duration(milliseconds: 400), () {
          _selectedWordId = null;
          _selectedMeaningId = null;
          notifyListeners();
        });
      }
    } else {
      notifyListeners();
    }
  }

  // ─── Initial App Data Load ───────────────────────────────────────────────

  Future<void> _initInitialData() async {
    _messages.add(
      AssistantMessage(
        id: 'msg_welcome',
        content:
            "Hello, I'm your QuantEdge Assistant. Ask me anything about structural anomalies or custom market inquiries.",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    // Show splash for 1.5s then immediately show login — data loads in background
    await Future.delayed(const Duration(milliseconds: 1500));
    setPhase(AppPhase.login);

    // Fire-and-forget: UI shows loading states; no need to block on these
    unawaited(initQuizSession());
    unawaited(refreshMarketData());
    unawaited(refreshDashboardMetrics());
    unawaited(refreshPortfolioData());
    unawaited(loadLearningData());
  }

  // ─── Disha's Learning Engine Actions ─────────────────────────────────────

  Future<void> loadLearningData() async {
    _isLoadingLearning = true;
    _learningError = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _learningService.getTopics(userId: userId),
        _learningService.getProgress(userId),
      ]);

      final topicsJson = results[0]['topics'] as List? ?? [];
      _learningTopics = topicsJson
          .map((t) => LearningTopic.fromJson(t as Map<String, dynamic>))
          .toList();
      _learningProgress = LearningProgress.fromJson(results[1]);
    } catch (e) {
      _learningError = e.toString();
      if (_learningTopics.isEmpty) {
        _learningTopics = _fallbackCurriculumTopics();
      }
    } finally {
      _isLoadingLearning = false;
      notifyListeners();
    }
  }

  Future<bool> startLearningLesson([String? topicId]) async {
    _isLoadingLearning = true;
    _learningError = null;
    notifyListeners();

    try {
      final data = await _learningService.startLesson(userId, topicId: topicId);
      if (data['completedAllTopics'] == true) {
        _learningError = (data['message'] as String?) ?? 'All topics completed!';
        return false;
      }
      final rawQuestion = data['question'];
      if (rawQuestion is! Map) {
        _learningError = 'Could not generate lesson question.';
        return false;
      }
      final normalized = Map<String, dynamic>.from(data);
      if (normalized['questions'] is! List || (normalized['questions'] as List).isEmpty) {
        normalized['questions'] = [rawQuestion];
      }
      final topic = data['topic'];
      if (topic is Map) {
        normalized['topicId'] ??= topic['id'];
        normalized['topicTitle'] ??= topic['title'];
      }
      final lesson = LearningLesson.fromJson(normalized);
      _currentLearningLesson = lesson;
      _learningQuestions = List<LearningQuestion>.from(lesson.questions);
      _learningTotalQuestions = (data['totalQuestions'] as num?)?.toInt() ?? 10;
      _currentLearningQuestionIndex = 0;
      _selectedLearningOptionId = null;
      _lastLearningAnswerResult = null;
      _lastLearningRawResult = null;
      _learningLessonComplete = false;
      _learningLessonPassed = false;
      return true;
    } catch (e) {
      _learningError = e.toString();
      return false;
    } finally {
      _isLoadingLearning = false;
      notifyListeners();
    }
  }

  void selectLearningAnswer(String optionId) {
    if (_learningLessonComplete || _isSubmittingLearningAnswer || _lastLearningAnswerResult != null) return;
    _selectedLearningOptionId = optionId;
    notifyListeners();
  }

  Future<bool> submitLearningAnswer() async {
    if (_selectedLearningOptionId == null || _isSubmittingLearningAnswer || _currentLearningLesson == null) {
      return false;
    }
    final question = currentLearningQuestion;
    if (question == null) return false;

    _isSubmittingLearningAnswer = true;
    _learningError = null;
    notifyListeners();

    try {
      final data = await _learningService.submitAnswer(
        userId: userId,
        lessonId: _currentLearningLesson!.lessonId,
        questionId: question.id,
        selectedOptionId: _selectedLearningOptionId!,
      );

      final result = AnswerResult.fromJson(data);
      _lastLearningRawResult = Map<String, dynamic>.from(data);

      if (!result.lessonComplete) {
        final rawNext = data['nextQuestion'];
        if (rawNext is Map) {
          _learningQuestions.add(LearningQuestion.fromJson(Map<String, dynamic>.from(rawNext)));
        }
      }

      _lastLearningAnswerResult = result;
      if (result.lessonComplete) {
        _learningLessonComplete = true;
        _learningLessonPassed = result.passed;
        await loadLearningData();
      }
      return true;
    } catch (e) {
      _learningError = e.toString();
      return false;
    } finally {
      _isSubmittingLearningAnswer = false;
      notifyListeners();
    }
  }

  void nextLearningQuestion() {
    if (_currentLearningLesson == null || _learningLessonComplete || _lastLearningAnswerResult == null) return;
    if (_currentLearningQuestionIndex >= _learningQuestions.length - 1) return;
    _currentLearningQuestionIndex++;
    _selectedLearningOptionId = null;
    _lastLearningAnswerResult = null;
    _lastLearningRawResult = null;
    notifyListeners();
  }

  Future<bool> retryLearningLesson() => startLearningLesson(_currentLearningLesson?.topicId);

  void clearLearningLesson() {
    _currentLearningLesson = null;
    _learningQuestions = [];
    _learningTotalQuestions = 10;
    _currentLearningQuestionIndex = 0;
    _selectedLearningOptionId = null;
    _lastLearningAnswerResult = null;
    _lastLearningRawResult = null;
    _learningLessonComplete = false;
    _learningLessonPassed = false;
    notifyListeners();
  }

  static List<LearningTopic> _fallbackCurriculumTopics() => [
    LearningTopic(
      id: 'topic_01',
      number: 1,
      title: 'Stock Market Basics',
      description: 'Understand public markets, shares, and basic exchanges.',
      status: 'current',
      unlocked: true,
      completed: false,
      subtopics: const ['Exchanges', 'Shares', 'Orders'],
      icon: '📈',
    ),
    LearningTopic(
      id: 'topic_02',
      number: 2,
      title: 'Stock Ownership & Exchanges',
      description: 'How equities, brokers, and market orders operate.',
      status: 'available',
      unlocked: true,
      completed: false,
      subtopics: const ['Brokers', 'Order Execution', 'Clearing'],
      icon: '🏛️',
    ),
    LearningTopic(
      id: 'topic_03',
      number: 3,
      title: 'Stock Prices & Market Capitalization',
      description: 'Valuation scale, mega-cap vs. small-cap asset classes.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['Market Cap', 'Stock Splits', 'Free Float'],
      icon: '💰',
    ),
    LearningTopic(
      id: 'topic_04',
      number: 4,
      title: 'Reading Stock Charts',
      description: 'Candlesticks, volume bars, and price action patterns.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['Candlesticks', 'Volume', 'Trends'],
      icon: '📊',
    ),
    LearningTopic(
      id: 'topic_05',
      number: 5,
      title: 'Fundamental Analysis',
      description: 'Balance sheets, cash flows, and corporate earnings.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['Balance Sheets', 'Income Statements', 'Free Cash Flow'],
      icon: '📑',
    ),
    LearningTopic(
      id: 'topic_06',
      number: 6,
      title: 'Valuation Ratios',
      description: 'P/E, P/B, EV/EBITDA, and comparative peer valuation.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['P/E Ratio', 'P/B Ratio', 'EV/EBITDA'],
      icon: '📐',
    ),
    LearningTopic(
      id: 'topic_07',
      number: 7,
      title: 'Technical Analysis',
      description: 'RSI, moving averages, Bollinger bands, and momentum.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['RSI', 'Moving Averages', 'MACD'],
      icon: '📉',
    ),
    LearningTopic(
      id: 'topic_08',
      number: 8,
      title: 'Risk Management',
      description: 'Position sizing, stop losses, and downside protection.',
      status: 'locked',
      unlocked: false,
      completed: false,
      subtopics: const ['Position Sizing', 'Stop Loss', 'Risk/Reward'],
      icon: '🛡️',
    ),
  ];

  Future<void> refreshDashboardMetrics() async {
    _isLoadingDashboard = true;
    notifyListeners();

    _dashboardMetrics = await _apiService.fetchDashboardMetrics(userId: userId);

    _isLoadingDashboard = false;
    notifyListeners();
  }

  Future<void> refreshPortfolioData() async {
    _isLoadingPortfolio = true;
    notifyListeners();

    _portfolioHoldings = await _apiService.fetchPortfolioData(userId: userId);

    _isLoadingPortfolio = false;
    notifyListeners();
  }

  Future<void> refreshMarketData() async {
    _isLoadingAssets = true;
    notifyListeners();

    _marketAssets = await _apiService.fetchMarketAssets();
    _factorImpacts = await _apiService.fetchFactorImpacts();

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

  Future<void> sendAssistantMessage(String query) async {
    if (query.trim().isEmpty) return;

    final userMsg = AssistantMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      content: query.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );

    _messages.add(userMsg);
    _isLoadingAssistant = true;
    notifyListeners();

    final replyText = await _apiService.sendAssistantQuery(query, _userLevel);

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

  // ─── Practice Quiz Leveling & XP Actions ───────────────────────────────
// ─── Practice Quiz Leveling & XP Actions ───────────────────────────────

  void completePracticeQuiz(int xpGained) {
    if (_dashboardMetrics != null) {
      final updatedXp = _dashboardMetrics!.xpPoints + xpGained;
      int newLevel = _userLevel;

      // Auto level-up logic
      if (updatedXp >= 3500 && _userLevel < 5) {
        newLevel += 1;
      }

      _userLevel = newLevel;
      _dashboardMetrics = DashboardMetrics(
        portfolioValue: _dashboardMetrics!.portfolioValue,
        dailyChange: _dashboardMetrics!.dailyChange,
        weeklyChange: _dashboardMetrics!.weeklyChange,
        xpPoints: updatedXp,
        userLevel: newLevel, // Fixed: Added required userLevel field!
        winRate: _dashboardMetrics!.winRate,
        nextLevelMilestone:
            newLevel >= 5 ? 'MAX LEVEL' : '${newLevel * 1500 + 500} XP',
      );
      notifyListeners();
    }
  }

  // ─── Dynamic XAI Insight Fetcher ─────────────────────────────────────────

  Future<String> fetchXaiInsightForAsset(MarketAsset asset) async {
    try {
      // Use real RSI from asset (populated from live yfinance data)
      final double rsi = asset.rsi;
      final double sentiment = asset.numericSentiment;

      final response = await http.post(
        Uri.parse('${LearningEngineService.baseUrl}/api/learning/xai/explain'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ticker': asset.ticker,
          'decision': asset.status.toUpperCase(),
          'features': {
            'rsi': rsi,
            'ma5': 0.0,
            'ma10': 0.0,
            'volatility': 0.015,
            'sentimentScore': sentiment,
            'marketMood': sentiment > 0.1 ? 'Bullish' : (sentiment < -0.1 ? 'Bearish' : 'Neutral'),
            'confidence': double.tryParse(asset.confidence.replaceAll('%', '')) != null
                ? (double.parse(asset.confidence.replaceAll('%', '')) / 100)
                : 0.70,
          },
          'xaiLevel': _userLevel,
        }),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Backend returns `summary` field
        final text = data['summary'] ?? data['detailedExplanation'] ?? '';
        if (text.toString().isNotEmpty) return text.toString();
      }
    } catch (e) {
      debugPrint('Error fetching XAI insight: $e');
    }

    // Fallback 1: asset insight from backend
    if (asset.insight.isNotEmpty) return asset.insight;

    // Fallback 2: level-appropriate static summary
    final status = asset.status.toUpperCase();
    final sentiment = asset.numericSentiment;
    if (_userLevel <= 2) {
      if (status == 'BUY')  return 'Strong buying pressure for ${asset.ticker}. Sentiment score sits at +$sentiment with high confidence.';
      if (status == 'SELL') return 'Increased selling activity detected in ${asset.ticker}. Sentiment has dipped to $sentiment.';
      return '${asset.ticker} is trading in a neutral range with a $sentiment sentiment score. Recommendation is to hold.';
    }
    return '${asset.ticker} shows a confidence level of ${asset.confidence} driven by technical and sentiment factor alignment.';
  }

  // ─── Qwen XAI Narrative Copilot ──────────────────────────────────────────

  Future<String> fetchQwenExplanation({
    required String ticker,
    required String signalType,
    required Map<String, dynamic> factors,
    int? userLevel,
    bool forceRefresh = false,
    bool simplify = false,
  }) async {
    final effectiveLevel = userLevel ?? _userLevel;
    final cacheKey =
        '${ticker.toUpperCase()}_${signalType.toUpperCase()}_lvl$effectiveLevel${simplify ? "_simple" : ""}';
    if (!forceRefresh && _qwenExplanationCache.containsKey(cacheKey)) {
      return _qwenExplanationCache[cacheKey]!;
    }
    final explanation = await _qwenXaiService.fetchExplanation(
      ticker: ticker,
      signalType: signalType,
      factors: factors,
      userLevel: effectiveLevel,
      simplify: simplify,
    );
    _qwenExplanationCache[cacheKey] = explanation;
    return explanation;
  }

  // ─── Auth ────────────────────────────────────────────────────────────────

  void completeLogin({
    required String uid,
    required String name,
    required String email,
  }) {
    _userId = uid;
    PracticeService.setUserId(uid);
    _userProfile = _userProfile.copyWith(uid: uid, name: name, email: email);
    _syncToFirebase();
    // Clean initial state: start newly registered users with an empty practice portfolio
    _portfolioHoldings = [];
    _dashboardMetrics = null;
    setPhase(AppPhase.enrichment);
  }

  Future<void> signOut() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      debugPrint('Error signing out of Firebase: $e');
    }
    _userId = '';
    PracticeService.setUserId('user_demo_123');
    _userProfile = const UserProfile();
    _portfolioHoldings = [];
    _dashboardMetrics = null;
    _activeSession = null;
    _currentQuestion = null;
    _completionSummary = null;
    setPhase(AppPhase.login);
    notifyListeners();
  }

  void updateUserProfile(UserProfile updated) {
    _userProfile = updated;
    _syncToFirebase();
    notifyListeners();
  }

  void setUserLevel(int level) {
    _userLevel = level;
    notifyListeners();
  }

  void logout() {
    signOut();
  }

  // ─── Enrichment ──────────────────────────────────────────────────────────

  void saveEnrichmentAnswers({
    required String experienceLevel,
    required String riskStyle,
    required List<String> sectorInterests,
    required String investingGoal,
  }) {
    _userProfile = UserProfile(
      name: _userProfile.name,
      email: _userProfile.email,
      experienceLevel: experienceLevel,
      riskStyle: riskStyle,
      sectorInterests: sectorInterests,
      investingGoal: investingGoal,
      chosenTickers: _userProfile.chosenTickers,
    );
    _syncToFirebase();
    _enrichmentSkipped = false;
    setPhase(AppPhase.onboarding1);
  }

  void skipEnrichment() {
    _enrichmentSkipped = true;
    setPhase(AppPhase.onboarding1);
  }

  // ─── Ticker Selection ────────────────────────────────────────────────────

  void toggleTickerSelection(String ticker, {bool allowUnlimited = false}) {
    if (_selectedTickers.contains(ticker)) {
      _selectedTickers = _selectedTickers.where((t) => t != ticker).toList();
    } else if (allowUnlimited || _phase == AppPhase.mainApp || _selectedTickers.length < 3) {
      _selectedTickers = [..._selectedTickers, ticker];
    }
    notifyListeners();
  }

  bool isTickerSelected(String ticker) => _selectedTickers.contains(ticker);

  Future<void> launchWorkspace() async {
    await confirmTickerSelection();
  }

  Future<void> confirmTickerSelection() async {
    if (_selectedTickers.isEmpty) return;
    _isLaunchingWorkspace = true;
    notifyListeners();
    try {
      _userProfile = _userProfile.copyWith(chosenTickers: _selectedTickers);
      await _syncToFirebase();
      setPhase(AppPhase.mainApp);
    } catch (e) {
      debugPrint('Error confirming ticker selection: $e');
    } finally {
      _isLaunchingWorkspace = false;
      notifyListeners();
    }
  }

  // ─── Practice Portfolio Operations ────────────────────────────────────────

  Future<bool> addPortfolioHolding({
    required String ticker,
    required double shares,
    double? avgPrice,
    String mode = 'add',
  }) async {
    final success = await _apiService.addPortfolioHolding(
      ticker: ticker,
      shares: shares,
      userId: userId,
      avgPrice: avgPrice,
      mode: mode,
    );
    if (success) {
      await refreshPortfolioData();
      await refreshDashboardMetrics();
    }
    return success;
  }

  Future<bool> removePortfolioHolding(String ticker) async {
    final success = await _apiService.removePortfolioHolding(
      ticker: ticker,
      userId: userId,
    );
    if (success) {
      await refreshPortfolioData();
      await refreshDashboardMetrics();
    }
    return success;
  }

  Future<bool> adjustHoldingShares(String ticker, double deltaShares) async {
    return addPortfolioHolding(
      ticker: ticker,
      shares: deltaShares,
      mode: 'add',
    );
  }

  void searchTickers(String query) {
    final q = query.trim().toUpperCase();
    _searchDebounce?.cancel();
    if (q.isEmpty) {
      _tickerSearchResults = [];
      notifyListeners();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _doTickerSearch(q);
    });
  }

  Future<void> _doTickerSearch(String query) async {
    _isSearchingTickers = true;
    notifyListeners();
    try {
      final uri = Uri.parse(
        '${ApiService.baseUrl}/api/tickers/search?q=${Uri.encodeComponent(query)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _tickerSearchResults = data
            .map((e) => TickerSearchResult.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _tickerSearchResults = _popularTickers
          .where((t) =>
              t['ticker']!.startsWith(query) ||
              t['name']!.toUpperCase().contains(query))
          .map((t) => TickerSearchResult(
                ticker: t['ticker']!,
                name: t['name']!,
                price: 0.0,
                changePercent: 0.0,
                exchange: 'NASDAQ',
              ))
          .toList();
    } finally {
      _isSearchingTickers = false;
      notifyListeners();
    }
  }

  // ─── Tour ────────────────────────────────────────────────────────────────

  void completeTour() => setPhase(AppPhase.tickerSelection);

  // ─── Ticker Detail ───────────────────────────────────────────────────────

  Future<TickerDetail?> fetchTickerDetail(String ticker, {bool forceRefresh = false}) async {
    final symKey = ticker.toUpperCase().trim();
    if (!forceRefresh && _tickerDetailCache.containsKey(symKey)) {
      return _tickerDetailCache[symKey];
    }
    _isLoadingTickerDetail = true;
    notifyListeners();
    try {
      final uri = Uri.parse(
        '${ApiService.baseUrl}/api/tickers/$symKey/detail?xaiLevel=$_userLevel',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final detail = TickerDetail.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
        _tickerDetailCache[symKey] = detail;

        // Propagate live updated signal, confidence, sentiment immediately to _marketAssets
        final updatedAsset = MarketAsset(
          ticker: detail.ticker,
          status: detail.aiSignal,
          confidence: '${(detail.aiConfidence * 100).toInt()}%',
          sentiment: detail.sentimentScore.toStringAsFixed(2),
          insight: detail.xaiInsight,
          rsi: detail.rsi,
          price: detail.currentPrice,
          changePercent: detail.changePercent,
        );

        final idx = _marketAssets.indexWhere(
          (a) => a.ticker.toUpperCase() == symKey,
        );
        if (idx >= 0) {
          _marketAssets[idx] = updatedAsset;
        } else {
          _marketAssets.add(updatedAsset);
        }

        _isLoadingTickerDetail = false;
        notifyListeners();
        return detail;
      }
    } catch (e) {
      debugPrint('fetchTickerDetail error: $e');
    }
    _isLoadingTickerDetail = false;
    notifyListeners();
    return null;
  }
}
