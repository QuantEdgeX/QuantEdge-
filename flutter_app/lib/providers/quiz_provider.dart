import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/learning_engine_service.dart';

enum AppPhase { onboarding1, onboarding2, assessmentComplete, mainApp }

enum AppTab {
  dashboard,
  quiz,
  portfolio,
  assistant
} // Updated: replaced market with quiz

class QuizProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  // App & Navigation State
  AppPhase _phase = AppPhase.onboarding1;
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

  QuizProvider() {
    _initInitialData();
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
      final data =
          await LearningEngineService.fetchQuestion(userId: 'user_demo_123');

      if (data != null) {
        _activeSession = data['session'] ?? data;
        _currentQuestion = data['question'];
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
      );

      if (response != null) {
        _activeSession = response['session'];
        final questions = _activeSession?['state']?['questions'] as List?;
        final currentIndex =
            _activeSession?['state']?['currentIndex'] as int? ?? 0;
        final status = _activeSession?['state']?['status'] as String?;

        if (status == 'completed' ||
            questions == null ||
            currentIndex >= questions.length) {
          _completionSummary = response;
          if (response['currentLevel'] != null) {
            _userLevel =
                _parseSkillLevelToNumeric(response['currentLevel'].toString());
          }
          _currentQuestion = null;
          setPhase(AppPhase.onboarding2);
        } else {
          _currentQuestion = questions[currentIndex] as Map<String, dynamic>?;
          _selectedQuizOption = null;
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

    await Future.wait([
      initQuizSession(),
      refreshMarketData(),
      refreshDashboardMetrics(),
      refreshPortfolioData(),
    ]);
  }

  Future<void> refreshDashboardMetrics() async {
    _isLoadingDashboard = true;
    notifyListeners();

    _dashboardMetrics = await _apiService.fetchDashboardMetrics();

    _isLoadingDashboard = false;
    notifyListeners();
  }

  Future<void> refreshPortfolioData() async {
    _isLoadingPortfolio = true;
    notifyListeners();

    _portfolioHoldings = await _apiService.fetchPortfolioData();

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
      final response = await http.post(
        Uri.parse('${LearningEngineService.baseUrl}/xai-explain'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sessionId':
              _activeSession?['state']?['sessionId'] ?? 'dashboard-session',
          'ticker': asset.ticker,
          'rsi': 55.0,
          'finbertScore': asset.numericSentiment,
          'isCorrect': true,
          'hintsUsed': 0,
          'domain': 'technical-analysis',
          'skillLevel': skillLevel,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['summary'] != null && data['summary'].toString().isNotEmpty) {
          return data['summary'];
        }
      }
    } catch (e) {
      debugPrint('Error fetching dynamic XAI insight: $e');
    }

    // 1. First fallback: Use the explicit insight provided by the asset object
    if (asset.insight.isNotEmpty) {
      return asset.insight;
    }

    // 2. Second fallback: Dynamic level-appropriate summary tailored to the asset's status & sentiment
    final status = asset.status.toUpperCase();
    final sentiment = asset.numericSentiment;

    if (_userLevel <= 2) {
      if (status == 'BUY') {
        return 'Strong buying pressure for ${asset.ticker}. Sentiment score sits at +$sentiment with high confidence.';
      } else if (status == 'SELL') {
        return 'Increased selling activity detected in ${asset.ticker}. Sentiment has dipped to $sentiment.';
      } else {
        return '${asset.ticker} is trading in a neutral range with a $sentiment sentiment score. Recommendation is to hold.';
      }
    }

    return '${asset.ticker} shows a confidence level of ${asset.confidence} driven by institutional order flows and factor alignment.';
  }
}
