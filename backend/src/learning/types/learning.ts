/**
 * QuantEdge Learning Engine — Canonical Type Definitions
 *
 * These types are the single source of truth shared between:
 *   - The FastAPI/Express backend routes (learningRoutes.py / .ts)
 *   - The Flutter API client (api_service.dart)
 *   - Firestore document schemas (firestore_learning_repository.dart)
 *   - The quiz state provider (quiz_provider.dart)
 *
 * Naming follows QuantEdge Mobile conventions (camelCase fields,
 * PascalCase types, SCREAMING_SNAKE for string-literal unions).
 */

// ─── User Level Tiers ────────────────────────────────────────────────────────

export type XaiLevel = 1 | 2 | 3 | 4;

/** Maps 1-to-1 with XaiLevel; stored as string in Firestore. */
export type LevelTier = 'novice' | 'beginner' | 'intermediate' | 'quant';

export const LEVEL_TIER_MAP: Record<XaiLevel, LevelTier> = {
  1: 'novice',
  2: 'beginner',
  3: 'intermediate',
  4: 'quant',
};

// ─── Score Vectors ─────────────────────────────────────────────────────────

/**
 * Multi-dimensional competency vector accumulated over all quiz sessions.
 * Each dimension maps to a domain from the QuantEdge decision engine.
 */
export interface ScoreVector {
  /** Technical analysis comprehension (RSI, MA, momentum). */
  technical: number;
  /** Sentiment/NLP reasoning (FinBERT output interpretation). */
  sentiment: number;
  /** Risk management & volatility judgment. */
  riskManagement: number;
  /** XAI / explainability understanding. */
  xaiComprehension: number;
}

export const EMPTY_SCORE_VECTOR: ScoreVector = {
  technical: 0,
  sentiment: 0,
  riskManagement: 0,
  xaiComprehension: 0,
};

// ─── Quiz Question ────────────────────────────────────────────────────────────

export type QuestionType =
  | 'SCENARIO'       // Case-study style (like OnboardingQuiz NVDA divergence)
  | 'TECHNICAL'      // Indicator / model mechanics
  | 'SENTIMENT'      // Mood / NLP interpretation
  | 'XAI';          // Explain the model's decision

export interface QuizOption {
  id: string;          // 'A' | 'B' | 'C' | 'D'
  text: string;
}

export interface QuizQuestion {
  questionId: string;
  type: QuestionType;
  /** Index within the 3-question adaptive session (0 = Q1, 1 = Q2, 2 = Q3). */
  position: 0 | 1 | 2;
  prompt: string;
  contextBlurb?: string; // Italic scenario blurb, mirrors OnboardingQuiz italic paragraph
  options: QuizOption[];
  correctOptionId: string;
  /** Which score vector dimension is exercised by this question. */
  scoreDimension: keyof ScoreVector;
  /** Points awarded for a correct answer. */
  pointValue: number;
  /** Points deducted for incorrect answer (always ≤ 0). */
  penalty: number;
}

// ─── Quiz Session ────────────────────────────────────────────────────────────

export type SessionStatus = 'IN_PROGRESS' | 'COMPLETED' | 'ABANDONED';

export interface QuizSession {
  sessionId: string;
  userId: string;
  startedAt: string;          // ISO-8601
  completedAt?: string;       // ISO-8601, set on COMPLETED
  status: SessionStatus;
  /** The 3 questions for this session. Q2/Q3 selected adaptively after Q1. */
  questions: QuizQuestion[];
  /** Answers submitted so far, keyed by questionId. */
  answers: Record<string, SubmittedAnswer>;
  /** Running score deltas applied to the user's cumulative vector. */
  sessionDelta: ScoreVector;
  /** XAI level at session start — used to select explanation depth. */
  initialXaiLevel: XaiLevel;
  /** XAI level at session end (may differ if threshold crossed). */
  finalXaiLevel?: XaiLevel;
}

// ─── Answer Submission ───────────────────────────────────────────────────────

export interface SubmittedAnswer {
  questionId: string;
  selectedOptionId: string;
  isCorrect: boolean;
  pointsDelta: number;        // positive or negative
  scoreDimension: keyof ScoreVector;
  answeredAt: string;         // ISO-8601
}

// ─── XAI Explanation ─────────────────────────────────────────────────────────

export type ExplanationDepth = 'simple' | 'standard' | 'detailed' | 'quant';

export interface XaiExplainRequest {
  ticker: string;
  decision: 'BUY' | 'HOLD' | 'SELL';
  features: {
    rsi: number;
    ma5: number;
    ma10: number;
    volatility: number;
    sentimentScore: number;
    marketMood: 'Bullish' | 'Neutral' | 'Bearish';
    confidence: number;
  };
  xaiLevel: XaiLevel;
  sessionId?: string;
}

export interface XaiExplainResponse {
  ticker: string;
  decision: 'BUY' | 'HOLD' | 'SELL';
  explanationDepth: ExplanationDepth;
  headline: string;           // Short 1-line summary shown in DashboardTab card
  detailedExplanation: string;
  /** Insight shown in InfoTooltip in DashboardTab */
  tooltipInsight: string;
  /** Which features most drove the decision (for XAI visualisation). */
  featureImportance: FeatureImportanceEntry[];
  generatedBy: 'gemini' | 'deterministic_fallback';
  generatedAt: string;        // ISO-8601
}

export interface FeatureImportanceEntry {
  feature: string;            // e.g. 'RSI', 'sentimentScore'
  importance: number;         // 0.0 – 1.0
  direction: 'positive' | 'negative' | 'neutral';
}

// ─── API Request / Response Shapes ──────────────────────────────────────────

// POST /api/learning/quiz/init
export interface QuizInitRequest {
  userId: string;
  xaiLevel: XaiLevel;
}

export interface QuizInitResponse {
  sessionId: string;
  userId: string;
  question: QuizQuestion;     // Q1 always returned immediately
  sessionStatus: SessionStatus;
  startedAt: string;
}

// POST /api/learning/quiz/submit
export interface QuizSubmitRequest {
  sessionId: string;
  userId: string;
  questionId: string;
  selectedOptionId: string;
}

export interface QuizSubmitResponse {
  sessionId: string;
  answer: SubmittedAnswer;
  sessionDelta: ScoreVector;
  /** Next question to render, or null when all 3 questions done. */
  nextQuestion: QuizQuestion | null;
  sessionStatus: SessionStatus;
  /** Only populated when sessionStatus === 'COMPLETED'. */
  completionSummary?: SessionCompletionSummary;
}

export interface SessionCompletionSummary {
  finalXaiLevel: XaiLevel;
  levelTier: LevelTier;
  levelChanged: boolean;
  totalPointsEarned: number;
  updatedScoreVector: ScoreVector;
  xpAwarded: number;
}

// POST /api/learning/xai/explain
// (Request shape re-exported for route use)
export type { XaiExplainRequest, XaiExplainResponse };
