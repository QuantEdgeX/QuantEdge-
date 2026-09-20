/**
 * src/engine/quizEngine.ts
 *
 * Dynamic adaptive quiz engine for the Learning Engine module.
 * Generates a 3-question sequence with randomized market parameters
 * (tickers, RSI, FinBERT sentiment scores), branches Q2 based on the
 * learner's Q1 response, and scores performance across three vectors:
 * technical-analysis, sentiment-analysis, and risk-management.
 */

import type {
  LearningDomain,
  QuizAnswerRecord,
  QuizChoice,
  QuizQuestion,
  QuizState,
  ScaffoldConfig,
  SkillLevel,
} from "../types/learning.js";

// ---------------------------------------------------------------------------
// Randomized market-parameter generation
// ---------------------------------------------------------------------------

const TICKER_POOL = ["NVDA", "TSLA", "AAPL", "AMD", "MSFT", "META"] as const;
type Ticker = (typeof TICKER_POOL)[number];

interface MarketSnapshot {
  ticker: Ticker;
  rsi: number; // 0-100
  finbertScore: number; // -1 (bearish) to 1 (bullish)
  priceChangePct: number; // recent % move, signed
}

function randomInRange(min: number, max: number): number {
  return Math.round((Math.random() * (max - min) + min) * 100) / 100;
}

function pickTicker(exclude?: Ticker): Ticker {
  const pool = TICKER_POOL.filter((t) => t !== exclude);
  return pool[Math.floor(Math.random() * pool.length)];
}

function generateMarketSnapshot(exclude?: Ticker): MarketSnapshot {
  const ticker = pickTicker(exclude);
  return {
    ticker,
    rsi: randomInRange(15, 85),
    finbertScore: randomInRange(-1, 1),
    priceChangePct: randomInRange(-8, 8),
  };
}

function classifyRSI(rsi: number): "oversold" | "neutral" | "overbought" {
  if (rsi < 30) return "oversold";
  if (rsi > 70) return "overbought";
  return "neutral";
}

function classifySentiment(score: number): "bearish" | "neutral" | "bullish" {
  if (score < -0.25) return "bearish";
  if (score > 0.25) return "bullish";
  return "neutral";
}

// ---------------------------------------------------------------------------
// Scoring vectors
// ---------------------------------------------------------------------------

export interface ScoreVector {
  technicalAnalysis: number; // 0-1
  sentimentAnalysis: number; // 0-1
  riskManagement: number; // 0-1
}

function emptyVector(): ScoreVector {
  return { technicalAnalysis: 0, sentimentAnalysis: 0, riskManagement: 0 };
}

function addToVector(vector: ScoreVector, key: keyof ScoreVector, amount: number): void {
  vector[key] = Math.max(0, Math.min(1, vector[key] + amount));
}

// ---------------------------------------------------------------------------
// Question builders
// ---------------------------------------------------------------------------

function buildChoices(
  correctText: string,
  distractors: string[]
): QuizChoice[] {
  const shuffled = [...distractors];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  const insertAt = Math.floor(Math.random() * (shuffled.length + 1));
  const texts = [...shuffled];
  texts.splice(insertAt, 0, correctText);

  return texts.map((text, i) => ({
    id: String.fromCharCode(97 + i),
    text,
    isCorrect: text === correctText,
  }));
}

/** Q1: Always a technical-analysis (RSI) question. Its outcome drives Q2 branching. */
function buildQ1(snapshot: MarketSnapshot, difficulty: number): QuizQuestion {
  const rsiState = classifyRSI(snapshot.rsi);
  const correctText =
    rsiState === "oversold"
      ? "It suggests the stock may be oversold and due for a potential rebound"
      : rsiState === "overbought"
      ? "It suggests the stock may be overbought and due for a potential pullback"
      : "It suggests the stock is trading in a neutral momentum zone";

  const distractors = [
    "It suggests the stock may be overbought and due for a potential pullback",
    "It suggests the stock is trading in a neutral momentum zone",
    "It suggests the stock may be oversold and due for a potential rebound",
    "It has no relationship to momentum or price extremes",
  ].filter((d) => d !== correctText);

  return {
    questionId: `q1-${snapshot.ticker}-${Date.now()}`,
    domain: "technical-analysis",
    difficulty,
    prompt: `${snapshot.ticker} currently has an RSI of ${snapshot.rsi.toFixed(1)}. What does this most likely indicate?`,
    choices: buildChoices(correctText, distractors.slice(0, 3)),
    hints: [
      "RSI below 30 typically signals 'oversold'; above 70 typically signals 'overbought'.",
      `${snapshot.ticker}'s RSI of ${snapshot.rsi.toFixed(1)} falls into the "${rsiState}" zone.`,
    ],
    explanation: `An RSI of ${snapshot.rsi.toFixed(1)} places ${snapshot.ticker} in the "${rsiState}" zone, which traders often use as a momentum-exhaustion signal (not a guarantee of reversal).`,
    tags: ["rsi", "momentum", snapshot.ticker.toLowerCase()],
  };
}

/**
 * Q2: Branches based on whether Q1 was answered correctly.
 * - Correct Q1  -> deeper sentiment-analysis question (FinBERT), reinforcing progression.
 * - Incorrect Q1 -> remedial risk-management question at a gentler difficulty.
 */
function buildQ2(
  snapshot: MarketSnapshot,
  q1WasCorrect: boolean,
  difficulty: number
): QuizQuestion {
  if (q1WasCorrect) {
    const sentiment = classifySentiment(snapshot.finbertScore);
    const correctText =
      sentiment === "bullish"
        ? "News-based sentiment is leaning positive"
        : sentiment === "bearish"
        ? "News-based sentiment is leaning negative"
        : "News-based sentiment is roughly neutral";

    const distractors = [
      "News-based sentiment is leaning positive",
      "News-based sentiment is leaning negative",
      "News-based sentiment is roughly neutral",
      "FinBERT scores measure trading volume, not sentiment",
    ].filter((d) => d !== correctText);

    return {
      questionId: `q2-sentiment-${snapshot.ticker}-${Date.now()}`,
      domain: "sentiment-analysis",
      difficulty: Math.min(10, difficulty + 1),
      prompt: `A FinBERT model scores recent ${snapshot.ticker} headlines at ${snapshot.finbertScore.toFixed(2)} (scale -1 to +1). What does this score indicate?`,
      choices: buildChoices(correctText, distractors.slice(0, 3)),
      hints: [
        "FinBERT scores range from -1 (very negative) to +1 (very positive).",
        `${snapshot.ticker}'s score of ${snapshot.finbertScore.toFixed(2)} falls into the "${sentiment}" range.`,
      ],
      explanation: `FinBERT is a sentiment-classification model fine-tuned on financial text. A score of ${snapshot.finbertScore.toFixed(2)} is classified as "${sentiment}" sentiment for recent ${snapshot.ticker} coverage.`,
      tags: ["finbert", "sentiment", snapshot.ticker.toLowerCase()],
    };
  }

  // Remedial branch: risk management, slightly easier.
  const correctText = "Reduce position size to limit exposure to a single signal";
  const distractors = [
    "Double the position size to average down immediately",
    "Ignore the signal entirely since indicators are unreliable",
    "Move the entire portfolio into a single position",
  ];

  return {
    questionId: `q2-risk-${snapshot.ticker}-${Date.now()}`,
    domain: "risk-management",
    difficulty: Math.max(1, difficulty - 1),
    prompt: `If a single technical indicator like RSI gives a conflicting or uncertain signal for ${snapshot.ticker}, what is the generally safer risk-management response?`,
    choices: buildChoices(correctText, distractors),
    hints: [
      "Think about position sizing rather than making an all-or-nothing bet.",
      "No single indicator should drive a full-conviction trade.",
    ],
    explanation: "Prudent risk management avoids over-committing capital to any single signal. Reducing position size limits downside while more confirming evidence is gathered.",
    tags: ["position-sizing", "risk-management", snapshot.ticker.toLowerCase()],
  };
}

/** Q3: Always a synthesis question combining technical + sentiment context. */
function buildQ3(
  snapshot: MarketSnapshot,
  secondSnapshot: MarketSnapshot,
  difficulty: number
): QuizQuestion {
  const rsiState = classifyRSI(snapshot.rsi);
  const sentiment = classifySentiment(secondSnapshot.finbertScore);

  const aligned =
    (rsiState === "oversold" && sentiment === "bullish") ||
    (rsiState === "overbought" && sentiment === "bearish");

  const correctText = aligned
    ? "The technical and sentiment signals are reinforcing each other"
    : "The technical and sentiment signals are conflicting";

  const distractors = [
    "The technical and sentiment signals are reinforcing each other",
    "The technical and sentiment signals are conflicting",
    "Technical and sentiment signals cannot be compared",
  ].filter((d) => d !== correctText);

  return {
    questionId: `q3-synthesis-${snapshot.ticker}-${Date.now()}`,
    domain: "quantitative-modeling",
    difficulty,
    prompt: `${snapshot.ticker} has an RSI of ${snapshot.rsi.toFixed(1)} ("${rsiState}"), while ${secondSnapshot.ticker} news sentiment scores ${secondSnapshot.finbertScore.toFixed(2)} ("${sentiment}"). Treating these as a combined read on market posture, what would you conclude?`,
    choices: buildChoices(correctText, distractors.slice(0, 2)),
    hints: [
      "Oversold + bullish sentiment reinforce each other; overbought + bearish sentiment reinforce each other.",
      "Any other pairing suggests the signals disagree.",
    ],
    explanation: `Combining an RSI reading of "${rsiState}" with a sentiment reading of "${sentiment}" ${aligned ? "points in the same directional bias" : "points in opposing directions"}, which is a core idea behind multi-factor quantitative models.`,
    tags: ["multi-factor", "synthesis"],
  };
}

// ---------------------------------------------------------------------------
// Public engine API
// ---------------------------------------------------------------------------

export interface AdaptiveQuizSession {
  state: QuizState;
  snapshots: MarketSnapshot[];
  scoreVector: ScoreVector;
}

/** Initializes a new 3-question adaptive session with randomized market data. */
export function initAdaptiveQuiz(userId: string, scaffold: ScaffoldConfig): AdaptiveQuizSession {
  const snapshotA = generateMarketSnapshot();
  const q1 = buildQ1(snapshotA, scaffold.difficultyTarget);

  const now = new Date().toISOString();
  const state: QuizState = {
    sessionId: `adaptive-${Date.now()}`,
    userId,
    domain: q1.domain,
    scaffoldConfigId: scaffold.configId,
    questions: [q1],
    currentIndex: 0,
    answers: [],
    currentStreak: 0,
    status: "in-progress",
    startedAt: now,
    currentDifficulty: scaffold.difficultyTarget,
  };

  return {
    state,
    snapshots: [snapshotA],
    scoreVector: emptyVector(),
  };
}

/**
 * Records the answer for the current question, applies scoring, and — if
 * applicable — dynamically appends the next branched question (Q2 or Q3).
 * Returns the updated session.
 */
export function submitAdaptiveAnswer(
  session: AdaptiveQuizSession,
  scaffold: ScaffoldConfig,
  selectedChoiceId: string,
  hintsUsed: number,
  responseTimeMs: number
): AdaptiveQuizSession {
  const { state } = session;
  const currentQuestion = state.questions[state.currentIndex];
  const selected = currentQuestion.choices.find((c: QuizChoice) => c.id === selectedChoiceId);
  const isCorrect = Boolean(selected?.isCorrect);

  const record: QuizAnswerRecord = {
    questionId: currentQuestion.questionId,
    selectedChoiceId,
    isCorrect,
    hintsUsed,
    responseTimeMs,
    answeredAt: new Date().toISOString(),
  };
  state.answers.push(record);
  state.currentStreak = isCorrect ? state.currentStreak + 1 : 0;

  applyScoring(session.scoreVector, currentQuestion.domain, isCorrect, hintsUsed);

  const questionNumber = state.currentIndex + 1;

  if (questionNumber === 1) {
    // Branch into Q2 based on Q1 correctness.
    const secondSnapshot = generateMarketSnapshot(session.snapshots[0].ticker);
    const q2 = buildQ2(session.snapshots[0], isCorrect, state.currentDifficulty);
    session.snapshots.push(secondSnapshot);
    state.questions.push(q2);
    state.currentIndex += 1;
    state.currentDifficulty = adjustDifficulty(state.currentDifficulty, isCorrect, scaffold);
  } else if (questionNumber === 2) {
    // Q3 synthesizes both snapshots regardless of branch taken.
    const q3 = buildQ3(session.snapshots[0], session.snapshots[1], state.currentDifficulty);
    state.questions.push(q3);
    state.currentIndex += 1;
    state.currentDifficulty = adjustDifficulty(state.currentDifficulty, isCorrect, scaffold);
  } else {
    // Q3 answered; session complete.
    state.status = "completed";
    state.completedAt = new Date().toISOString();
  }

  return session;
}

function adjustDifficulty(current: number, wasCorrect: boolean, scaffold: ScaffoldConfig): number {
  if (wasCorrect) {
    return Math.min(10, current + (1 / Math.max(1, scaffold.streakToLevelUp)) * 2);
  }
  return Math.max(1, current - (1 / Math.max(1, scaffold.streakToLevelDown)) * 2);
}

function applyScoring(
  vector: ScoreVector,
  domain: LearningDomain,
  isCorrect: boolean,
  hintsUsed: number
): void {
  const base = isCorrect ? 0.34 : 0.05;
  const hintPenalty = hintsUsed * 0.05;
  const delta = Math.max(0, base - hintPenalty);

  switch (domain) {
    case "technical-analysis":
      addToVector(vector, "technicalAnalysis", delta);
      break;
    case "sentiment-analysis":
      addToVector(vector, "sentimentAnalysis", delta);
      break;
    case "risk-management":
      addToVector(vector, "riskManagement", delta);
      break;
    case "quantitative-modeling":
      // Synthesis question contributes a smaller share to all three vectors.
      addToVector(vector, "technicalAnalysis", delta / 3);
      addToVector(vector, "sentimentAnalysis", delta / 3);
      addToVector(vector, "riskManagement", delta / 3);
      break;
    default:
      break;
  }
}

/** Derives an overall SkillLevel label from a completed ScoreVector. */
export function deriveSkillLevel(vector: ScoreVector): SkillLevel {
  const avg = (vector.technicalAnalysis + vector.sentimentAnalysis + vector.riskManagement) / 3;
  if (avg >= 0.85) return "expert";
  if (avg >= 0.65) return "advanced";
  if (avg >= 0.4) return "intermediate";
  if (avg >= 0.15) return "beginner";
  return "novice";
}