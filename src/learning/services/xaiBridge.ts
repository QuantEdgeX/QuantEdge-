/**
 * src/services/xaiBridge.ts
 *
 * XAI Bridge service: ingests raw quiz/market metrics and a learner's
 * skill level, then produces a level-appropriate explainable-AI (XAI)
 * payload. Uses Google's Gemini API as the underlying generative
 * explanation service, with a deterministic local fallback so the
 * Learning Engine never blocks on network/API availability.
 *
 * All output includes an educational disclaimer — this module never
 * produces trading advice or recommendations to act on.
 */

import type { SkillLevel, XAIFactor, XAIPayload } from "../types/learning.js";
import type { ScoreVector } from "../engine/quizEngine.js";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const GEMINI_API_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent";

const EDUCATIONAL_DISCLAIMER =
  "This explanation is for educational purposes only. It does not constitute financial, investment, or trading advice, and past patterns do not guarantee future results.";

export interface RawMetricsInput {
  sessionId: string;
  ticker: string;
  rsi: number;
  finbertScore: number;
  priceChangePct?: number;
  isCorrect: boolean;
  hintsUsed: number;
  domain: string;
  skillLevel: SkillLevel;
}

export interface XAIBridgeOptions {
  /** Optional Gemini API key. If omitted, falls back to local deterministic explanation. */
  apiKey?: string;
  /** Timeout in ms before falling back to the local explanation generator. */
  timeoutMs?: number;
}

// ---------------------------------------------------------------------------
// Level-appropriate tone/vocabulary mapping
// ---------------------------------------------------------------------------

const LEVEL_STYLE_GUIDE: Record<SkillLevel, string> = {
  novice:
    "Explain in 2 simple sentences using everyday language for a complete beginner. Strictly avoid institutional or technical jargon like 'order book intensity', 'decoupling', or 'institutional accumulation'. Focus only on basic buying interest and overall news mood.",
  beginner:
    "Use clear, plain language with light financial terms. Briefly define terms in simple words in 2-3 short sentences.",
  intermediate:
    "Use standard technical-analysis concepts and terms (like RSI and sentiment scores) without needing to re-explain basic definitions, in 2-3 sentences.",
  advanced:
    "Use technical quantitative language. Reference momentum indicators and sentiment models directly, in 3-4 sentences.",
  expert:
    "Use dense, high-level quantitative terminology (e.g., order book dynamics, volume profile, volatility decoupling, institutional flow patterns), focusing on edge cases, model nuances, and caveats.",
};

function styleGuideFor(level: SkillLevel): string {
  return LEVEL_STYLE_GUIDE[level] ?? LEVEL_STYLE_GUIDE.intermediate;
}

// ---------------------------------------------------------------------------
// Local deterministic fallback (no network dependency)
// ---------------------------------------------------------------------------

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

function buildLocalFactors(metrics: RawMetricsInput): XAIFactor[] {
  const rsiState = classifyRSI(metrics.rsi);
  const sentimentState = classifySentiment(metrics.finbertScore);

  const factors: XAIFactor[] = [
    {
      name: "rsi_reading",
      weight: metrics.isCorrect ? 0.4 : -0.2,
      description: `${metrics.ticker} RSI of ${metrics.rsi.toFixed(1)} is classified as "${rsiState}".`,
    },
    {
      name: "finbert_sentiment",
      weight: metrics.isCorrect ? 0.35 : -0.15,
      description: `FinBERT sentiment score of ${metrics.finbertScore.toFixed(2)} is classified as "${sentimentState}".`,
    },
    {
      name: "answer_correctness",
      weight: metrics.isCorrect ? 0.25 : -0.5,
      description: metrics.isCorrect
        ? "The learner selected the correct interpretation of the underlying signal."
        : "The learner's selection did not match the correct interpretation of the underlying signal.",
    },
  ];

  if (metrics.hintsUsed > 0) {
    factors.push({
      name: "hints_used",
      weight: -0.05 * metrics.hintsUsed,
      description: `${metrics.hintsUsed} hint(s) were used before answering, indicating partial reliance on scaffolding.`,
    });
  }

  return factors;
}

function buildLocalSummary(metrics: RawMetricsInput): string {
  const rsiState = classifyRSI(metrics.rsi);
  const sentimentState = classifySentiment(metrics.finbertScore);

  switch (metrics.skillLevel) {
    case "novice":
      return `More buyers are showing interest in ${metrics.ticker}, and recent news coverage leans ${sentimentState}. This combination suggests strong steady demand right now.`;
    case "beginner":
      return `${metrics.ticker} shows an ${rsiState} price trend alongside ${sentimentState} headline sentiment. Traders often watch both signals together to spot momentum.`;
    case "intermediate":
      return `${metrics.ticker}'s RSI is ${rsiState} (${metrics.rsi.toFixed(1)}), while sentiment on recent coverage is ${sentimentState} (${metrics.finbertScore.toFixed(2)}), forming a combined momentum read.`;
    case "advanced":
      return `RSI(${metrics.rsi.toFixed(1)}) places ${metrics.ticker} in the ${rsiState} regime; FinBERT sentiment (${metrics.finbertScore.toFixed(2)}) is ${sentimentState}. Multi-factor alignment points to sustained momentum.`;
    case "expert":
    default:
      return `${metrics.ticker}: RSI=${metrics.rsi.toFixed(1)} (${rsiState} regime), FinBERT=${metrics.finbertScore.toFixed(2)} (${sentimentState}). Current momentum is supported by order book intensity and institutional accumulation dynamics.`;
  }
}

function buildLocalPayload(metrics: RawMetricsInput): XAIPayload {
  return {
    decisionId: `xai-local-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    sessionId: metrics.sessionId,
    decisionType: "question-selection",
    summary: `${buildLocalSummary(metrics)} ${EDUCATIONAL_DISCLAIMER}`,
    factors: buildLocalFactors(metrics),
    confidence: metrics.isCorrect ? 0.75 : 0.6,
    generatedAt: new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Gemini-backed explanation generation
// ---------------------------------------------------------------------------

interface GeminiGenerateContentResponse {
  candidates?: {
    content?: {
      parts?: { text?: string }[];
    };
  }[];
}

function buildGeminiPrompt(metrics: RawMetricsInput): string {
  const style = styleGuideFor(metrics.skillLevel);
  const rsiState = classifyRSI(metrics.rsi);
  const sentimentState = classifySentiment(metrics.finbertScore);

  return [
    "You are an explainable-AI module inside an educational trading-literacy app.",
    "Explain why the model arrived at this signal/interpretation for the learner.",
    "Do NOT give financial advice, price targets, or buy/sell recommendations. This is strictly educational.",
    `Learner skill level: ${metrics.skillLevel}. Target guidance: ${style}`,
    `Ticker: ${metrics.ticker}`,
    `RSI: ${metrics.rsi.toFixed(1)} (${rsiState})`,
    `FinBERT sentiment score: ${metrics.finbertScore.toFixed(2)} (${sentimentState})`,
    `Domain: ${metrics.domain}`,
    `Learner answered correctly: ${metrics.isCorrect}`,
    "Respond with only the explanation text, no preamble, no markdown formatting.",
  ].join("\n");
}

async function callGemini(
  metrics: RawMetricsInput,
  apiKey: string,
  timeoutMs: number
): Promise<string | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${GEMINI_API_URL}?key=${encodeURIComponent(apiKey)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [{ text: buildGeminiPrompt(metrics) }],
          },
        ],
        generationConfig: {
          temperature: 0.3,
          maxOutputTokens: 200,
        },
      }),
    });

    if (!response.ok) {
      return null;
    }

    const data = (await response.json()) as GeminiGenerateContentResponse;
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
    return text?.trim() || null;
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

// ---------------------------------------------------------------------------
// Public bridge API
// ---------------------------------------------------------------------------

/**
 * Produces a level-appropriate XAIPayload for a given quiz answer's raw
 * metrics. Attempts a Gemini-generated explanation first (if an API key is
 * supplied); falls back to a deterministic local explanation on any
 * failure, timeout, or missing key, guaranteeing the payload is always
 * returned without throwing.
 */
export async function explainDecision(
  metrics: RawMetricsInput,
  options: XAIBridgeOptions = {}
): Promise<XAIPayload> {
  const { apiKey, timeoutMs = 4000 } = options;

  const localPayload = buildLocalPayload(metrics);

  if (!apiKey) {
    return localPayload;
  }

  const geminiText = await callGemini(metrics, apiKey, timeoutMs);

  if (!geminiText) {
    return localPayload;
  }

  return {
    ...localPayload,
    decisionId: `xai-gemini-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    summary: `${geminiText} ${EDUCATIONAL_DISCLAIMER}`,
  };
}

/** Applies the score vector as additional weighted factors for a session-level (not single-question) XAI summary. */
export function explainSessionScoreVector(
  sessionId: string,
  vector: ScoreVector,
  skillLevel: SkillLevel
): XAIPayload {
  const factors: XAIFactor[] = [
    {
      name: "technical_analysis_score",
      weight: vector.technicalAnalysis,
      description: `Technical-analysis mastery score: ${(vector.technicalAnalysis * 100).toFixed(0)}%.`,
    },
    {
      name: "sentiment_analysis_score",
      weight: vector.sentimentAnalysis,
      description: `Sentiment-analysis mastery score: ${(vector.sentimentAnalysis * 100).toFixed(0)}%.`,
    },
    {
      name: "risk_management_score",
      weight: vector.riskManagement,
      description: `Risk-management mastery score: ${(vector.riskManagement * 100).toFixed(0)}%.`,
    },
  ];

  const avg = (vector.technicalAnalysis + vector.sentimentAnalysis + vector.riskManagement) / 3;

  return {
    decisionId: `xai-session-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    sessionId,
    decisionType: "difficulty-adjustment",
    summary: `Session mastery averaged ${(avg * 100).toFixed(0)}% across technical, sentiment, and risk-management vectors, consistent with a "${skillLevel}" skill level. ${EDUCATIONAL_DISCLAIMER}`,
    factors,
    confidence: 0.7,
    generatedAt: new Date().toISOString(),
  };
}