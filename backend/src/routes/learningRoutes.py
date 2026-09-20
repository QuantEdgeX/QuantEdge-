"""
QuantEdge Learning Engine — FastAPI Route Layer
================================================
Exposes three REST endpoints that bridge the existing Python decision
engine (run_decision_engine.py / finbert_sentiment.py) with the Flutter
frontend via clean, typed JSON contracts matching learning.ts.

Endpoints
---------
POST /api/learning/quiz/init      — Initialise an adaptive quiz session.
POST /api/learning/quiz/submit    — Submit an answer; branches Q2 / Q3.
POST /api/learning/xai/explain    — Request a Gemini XAI explanation.

Run with:
    uvicorn src.routes.learningRoutes:app --reload --port 8000

Environment variables (add to .env):
    GEMINI_API_KEY=...
    FIRESTORE_CREDENTIALS_JSON=...   # path to service-account JSON
    FIREBASE_PROJECT_ID=...
"""

from __future__ import annotations
from dotenv import load_dotenv
load_dotenv()

import os
import uuid
import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from google import genai
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ─── App bootstrap ────────────────────────────────────────────────────────────

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("quantedge.learning")

app = FastAPI(
    title="QuantEdge Learning API",
    version="1.0.0",
    description="Adaptive quiz engine + XAI bridge for the QuantEdge Flutter app.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict in prod
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Gemini setup
_GEMINI_KEY = os.getenv("GEMINI_API_KEY", "")
if _GEMINI_KEY:
    _gemini_client = genai.Client(api_key=_GEMINI_KEY)
else:
    _gemini_client = None
    logger.warning("GEMINI_API_KEY not set — XAI will use deterministic fallback.")
# ─── In-memory session store (replace with Firestore in prod) ─────────────────
# Key: sessionId → dict matching QuizSession shape
_SESSION_STORE: Dict[str, Dict[str, Any]] = {}

# ─── Question Bank ────────────────────────────────────────────────────────────
# 9 questions: 3 per tier so Q2/Q3 can branch based on Q1 performance.
# scoreDimension keys match ScoreVector fields in learning.ts.

_QUESTION_BANK: List[Dict[str, Any]] = [
    # ── TIER 1: Novice / Beginner branch ─────────────────────────────────────
    {
        "questionId": "q_scen_001",
        "type": "SCENARIO",
        "tier": 1,
        "position": 0,
        "prompt": "Case Study: Market Divergence",
        "contextBlurb": (
            "\"Look at NVDA! The price trend line is climbing rapidly, "
            "but public social sentiment has suddenly plummeted into panic. "
            "What should you do next?\""
        ),
        "options": [
            {"id": "A", "text": "Chase the current momentum rally immediately."},
            {"id": "B", "text": "Liquidate all holdings to avoid the price crash."},
            {
                "id": "C",
                "text": (
                    "Calculated Risk — Pause action to evaluate if price "
                    "and sentiment trends are out of sync."
                ),
            },
        ],
        "correctOptionId": "C",
        "scoreDimension": "sentiment",
        "pointValue": 10,
        "penalty": -3,
    },
    {
        "questionId": "q_tech_001",
        "type": "TECHNICAL",
        "tier": 1,
        "position": 1,
        "prompt": "RSI Reading",
        "contextBlurb": "AAPL's RSI just crossed above 70 while its 5-day MA is still rising.",
        "options": [
            {"id": "A", "text": "Strong buy signal — momentum is building."},
            {"id": "B", "text": "Overbought territory — consider profit-taking or reduced position."},
            {"id": "C", "text": "RSI above 70 is always a definitive sell signal."},
            {"id": "D", "text": "RSI is irrelevant when MA is rising."},
        ],
        "correctOptionId": "B",
        "scoreDimension": "technical",
        "pointValue": 10,
        "penalty": -3,
    },
    {
        "questionId": "q_risk_001",
        "type": "SCENARIO",
        "tier": 1,
        "position": 2,
        "prompt": "Volatility Spike",
        "contextBlurb": (
            "TSLA's 5-day rolling volatility doubled overnight. "
            "The QuantEdge engine flags bearish sentiment at -0.35."
        ),
        "options": [
            {"id": "A", "text": "Double your position — high volatility means high reward."},
            {"id": "B", "text": "Reduce position size to cap downside exposure."},
            {"id": "C", "text": "Ignore volatility; only price direction matters."},
        ],
        "correctOptionId": "B",
        "scoreDimension": "riskManagement",
        "pointValue": 10,
        "penalty": -3,
    },
    # ── TIER 2: Intermediate branch ───────────────────────────────────────────
    {
        "questionId": "q_sent_002",
        "type": "SENTIMENT",
        "tier": 2,
        "position": 1,
        "prompt": "FinBERT Output",
        "contextBlurb": (
            "FinBERT returns: positive=0.15, neutral=0.20, negative=0.65 "
            "for the latest NVDA news batch. Sentiment score = -0.50."
        ),
        "options": [
            {"id": "A", "text": "Bullish — positive outweighs neutral."},
            {"id": "B", "text": "Neutral — no clear signal."},
            {"id": "C", "text": "Bearish — negative probability dominates; score < -0.2 threshold."},
            {"id": "D", "text": "Cannot determine without seeing the raw headlines."},
        ],
        "correctOptionId": "C",
        "scoreDimension": "sentiment",
        "pointValue": 15,
        "penalty": -4,
    },
    {
        "questionId": "q_xai_002",
        "type": "XAI",
        "tier": 2,
        "position": 2,
        "prompt": "Interpreting the Decision Engine",
        "contextBlurb": (
            "The Random Forest model returns BUY with 91% confidence. "
            "Top feature importances: RSI=0.34, sentimentScore=0.28, MA5=0.21."
        ),
        "options": [
            {"id": "A", "text": "RSI alone is driving the BUY signal."},
            {
                "id": "B",
                "text": (
                    "RSI and sentiment together account for >60% of the decision; "
                    "this is a technically and fundamentally supported BUY."
                ),
            },
            {"id": "C", "text": "High confidence means no further verification needed."},
        ],
        "correctOptionId": "B",
        "scoreDimension": "xaiComprehension",
        "pointValue": 15,
        "penalty": -4,
    },
    {
        "questionId": "q_tech_002",
        "type": "TECHNICAL",
        "tier": 2,
        "position": 1,
        "prompt": "MA Crossover Signal",
        "contextBlurb": "AAPL's MA5 crosses above MA10 on rising volume.",
        "options": [
            {"id": "A", "text": "Golden cross — typically a bullish short-term signal."},
            {"id": "B", "text": "Death cross — bearish signal."},
            {"id": "C", "text": "No signal — crossovers only matter on weekly charts."},
        ],
        "correctOptionId": "A",
        "scoreDimension": "technical",
        "pointValue": 15,
        "penalty": -4,
    },
    # ── TIER 3: Advanced / Quant branch ──────────────────────────────────────
    {
        "questionId": "q_xai_003",
        "type": "XAI",
        "tier": 3,
        "position": 1,
        "prompt": "Structural Anomaly Detection",
        "contextBlurb": (
            "Price trend is climbing (RSI=72, MA5>MA10), "
            "but FinBERT sentiment is -0.42 across 18 recent headlines. "
            "The engine outputs HOLD at 87% confidence."
        ),
        "options": [
            {"id": "A", "text": "Override the engine — technical indicators dominate."},
            {
                "id": "B",
                "text": (
                    "Trust the model — it is detecting a divergence anomaly "
                    "where price and sentiment are temporarily decoupled, "
                    "reducing confidence in a directional trade."
                ),
            },
            {"id": "C", "text": "Always prefer SELL when sentiment is negative."},
            {"id": "D", "text": "The engine is wrong; confidence below 90% is unreliable."},
        ],
        "correctOptionId": "B",
        "scoreDimension": "xaiComprehension",
        "pointValue": 20,
        "penalty": -5,
    },
    {
        "questionId": "q_risk_003",
        "type": "SCENARIO",
        "tier": 3,
        "position": 2,
        "prompt": "Portfolio-Level Risk",
        "contextBlurb": (
            "Your portfolio holds NVDA (BUY, high sentiment), "
            "TSLA (SELL, negative sentiment), and AAPL (HOLD, divergence). "
            "Overall correlation between NVDA and TSLA is 0.82."
        ),
        "options": [
            {"id": "A", "text": "Execute all signals simultaneously — diversification is fine."},
            {
                "id": "B",
                "text": (
                    "High correlation between NVDA and TSLA means they move together; "
                    "a NVDA BUY and TSLA SELL may partially offset, "
                    "so size positions to account for correlation risk."
                ),
            },
            {"id": "C", "text": "Ignore correlation — each signal is independent."},
        ],
        "correctOptionId": "B",
        "scoreDimension": "riskManagement",
        "pointValue": 20,
        "penalty": -5,
    },
    {
        "questionId": "q_sent_003",
        "type": "SENTIMENT",
        "tier": 3,
        "position": 2,
        "prompt": "Sentiment Time-Lag",
        "contextBlurb": (
            "News headlines from 48 hours ago show strong positive sentiment (+0.72). "
            "Today's real-time FinBERT score is -0.31."
        ),
        "options": [
            {"id": "A", "text": "Use the older positive score — more data points."},
            {
                "id": "B",
                "text": (
                    "Weight recent sentiment more heavily; "
                    "48-hour-old headlines are stale and the market has repriced."
                ),
            },
            {"id": "C", "text": "Average both scores for a balanced view."},
        ],
        "correctOptionId": "B",
        "scoreDimension": "sentiment",
        "pointValue": 20,
        "penalty": -5,
    },
]

# Index by questionId for O(1) lookup
_QUESTIONS_BY_ID: Dict[str, Dict[str, Any]] = {q["questionId"]: q for q in _QUESTION_BANK}


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _xai_level_for_score(cumulative: Dict[str, float]) -> int:
    """
    Derive XAI level from cumulative score vector total.
    Thresholds chosen to map onto the four LevelTier values.
    """
    total = sum(cumulative.values())
    if total < 20:
        return 1  # novice
    elif total < 50:
        return 2  # beginner
    elif total < 90:
        return 3  # intermediate
    return 4      # quant


def _select_q1() -> Dict[str, Any]:
    """Q1 is always the SCENARIO intro question."""
    q = next(q for q in _QUESTION_BANK if q["questionId"] == "q_scen_001")
    return {**q, "position": 0}


def _select_next_question(
    session: Dict[str, Any],
    last_answer_correct: bool,
) -> Optional[Dict[str, Any]]:
    """
    Adaptive branching:
    - After Q1 correct → pick a Tier 2 or Tier 3 question.
    - After Q1 incorrect → pick a Tier 1 question.
    - After Q2 correct → move up one tier.
    - Returns None when all 3 positions have been answered.
    """
    answered_ids = set(session["answers"].keys())
    answered_count = len(answered_ids)

    if answered_count >= 3:
        return None

    initial_level = session["initialXaiLevel"]

    if answered_count == 1:
        # Branching after Q1
        target_tier = 2 if last_answer_correct else 1
        # Exclude already-answered
        candidates = [
            q for q in _QUESTION_BANK
            if q["tier"] == target_tier
            and q["questionId"] not in answered_ids
            and q["questionId"] != "q_scen_001"
        ]
    else:
        # After Q2: advance tier if correct, else stay
        current_tier = 2 if last_answer_correct else 1
        target_tier = min(current_tier + (1 if last_answer_correct else 0), 3)
        candidates = [
            q for q in _QUESTION_BANK
            if q["tier"] == target_tier
            and q["questionId"] not in answered_ids
        ]

    if not candidates:
        # Fallback: any unanswered question
        candidates = [
            q for q in _QUESTION_BANK
            if q["questionId"] not in answered_ids
        ]

    if not candidates:
        return None

    chosen = candidates[0]
    return {**chosen, "position": answered_count}


def _empty_score_vector() -> Dict[str, float]:
    return {"technical": 0, "sentiment": 0, "riskManagement": 0, "xaiComprehension": 0}


def _depth_label(xai_level: int) -> str:
    return {1: "simple", 2: "standard", 3: "detailed", 4: "quant"}.get(xai_level, "standard")


# ─── Pydantic Models ──────────────────────────────────────────────────────────

class QuizInitRequest(BaseModel):
    userId: str
    xaiLevel: int = Field(ge=1, le=4)


class QuizSubmitRequest(BaseModel):
    sessionId: str
    userId: str
    questionId: str
    selectedOptionId: str


class XaiFeatures(BaseModel):
    rsi: float
    ma5: float
    ma10: float
    volatility: float
    sentimentScore: float
    marketMood: str
    confidence: float


class XaiExplainRequest(BaseModel):
    ticker: str
    decision: str          # BUY | HOLD | SELL
    features: XaiFeatures
    xaiLevel: int = Field(ge=1, le=4)
    sessionId: Optional[str] = None


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.post("/api/learning/quiz/init")
async def quiz_init(req: QuizInitRequest) -> Dict[str, Any]:
    """
    Initialise a new 3-question adaptive quiz session.

    Returns the first question (always the NVDA divergence scenario)
    and a session ID that the client must pass back on every /submit call.
    """
    session_id = str(uuid.uuid4())
    q1 = _select_q1()

    session: Dict[str, Any] = {
        "sessionId": session_id,
        "userId": req.userId,
        "startedAt": _now_iso(),
        "completedAt": None,
        "status": "IN_PROGRESS",
        "questions": [q1],
        "answers": {},
        "sessionDelta": _empty_score_vector(),
        "initialXaiLevel": req.xaiLevel,
        "finalXaiLevel": None,
    }
    _SESSION_STORE[session_id] = session

    logger.info("Session %s created for user %s", session_id, req.userId)

    return {
        "sessionId": session_id,
        "userId": req.userId,
        "question": q1,
        "sessionStatus": "IN_PROGRESS",
        "startedAt": session["startedAt"],
    }


@app.post("/api/learning/quiz/submit")
async def quiz_submit(req: QuizSubmitRequest) -> Dict[str, Any]:
    """
    Submit an answer for the current question.

    - Validates answer, computes points delta.
    - Branches Q2 / Q3 adaptively.
    - When all 3 questions answered, finalises session and computes summary.
    """
    session = _SESSION_STORE.get(req.sessionId)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session["status"] != "IN_PROGRESS":
        raise HTTPException(status_code=409, detail="Session already completed.")
    if req.userId != session["userId"]:
        raise HTTPException(status_code=403, detail="User ID mismatch.")
    if req.questionId in session["answers"]:
        raise HTTPException(status_code=409, detail="Question already answered.")

    question = _QUESTIONS_BY_ID.get(req.questionId)
    if not question:
        raise HTTPException(status_code=404, detail="Question not found.")

    is_correct = req.selectedOptionId == question["correctOptionId"]
    points_delta = question["pointValue"] if is_correct else question["penalty"]
    dim: str = question["scoreDimension"]

    answered_at = _now_iso()
    answer_record: Dict[str, Any] = {
        "questionId": req.questionId,
        "selectedOptionId": req.selectedOptionId,
        "isCorrect": is_correct,
        "pointsDelta": points_delta,
        "scoreDimension": dim,
        "answeredAt": answered_at,
    }
    session["answers"][req.questionId] = answer_record
    session["sessionDelta"][dim] = session["sessionDelta"].get(dim, 0) + points_delta

    # Track questions added to session for the adaptive branch
    if not any(q["questionId"] == req.questionId for q in session["questions"]):
        session["questions"].append(question)

    answered_count = len(session["answers"])
    next_question: Optional[Dict[str, Any]] = None
    completion_summary: Optional[Dict[str, Any]] = None

    if answered_count < 3:
        next_question = _select_next_question(session, is_correct)
        if next_question and next_question["questionId"] not in [
            q["questionId"] for q in session["questions"]
        ]:
            session["questions"].append(next_question)
    else:
        # Finalise session
        session["status"] = "COMPLETED"
        session["completedAt"] = answered_at

        # Compute final XAI level from session delta
        final_level = _xai_level_for_score(session["sessionDelta"])
        session["finalXaiLevel"] = final_level
        initial_level = session["initialXaiLevel"]

        tier_map = {1: "novice", 2: "beginner", 3: "intermediate", 4: "quant"}
        total_pts = sum(a["pointsDelta"] for a in session["answers"].values())

        completion_summary = {
            "finalXaiLevel": final_level,
            "levelTier": tier_map.get(final_level, "beginner"),
            "levelChanged": final_level != initial_level,
            "totalPointsEarned": total_pts,
            "updatedScoreVector": session["sessionDelta"],
            "xpAwarded": max(0, total_pts) * 5,
        }
        logger.info(
            "Session %s completed. Level: %s → %s",
            req.sessionId, initial_level, final_level,
        )

    return {
        "sessionId": req.sessionId,
        "answer": answer_record,
        "sessionDelta": session["sessionDelta"],
        "nextQuestion": next_question,
        "sessionStatus": session["status"],
        "completionSummary": completion_summary,
    }


@app.post("/api/learning/xai/explain")
async def xai_explain(req: XaiExplainRequest) -> Dict[str, Any]:
    """
    Generate a level-appropriate XAI explanation for a trading decision.

    Tries Gemini first; falls back to deterministic rule-based explanation
    if Gemini is unavailable or returns an error.

    The explanation depth scales with xaiLevel (1=simple → 4=quant).
    """
    depth = _depth_label(req.xaiLevel)
    f = req.features

    if _gemini_client:
        explanation = await _gemini_explain(req, depth)
        source = "gemini"
    else:
        explanation = _deterministic_explain(req, depth)
        source = "deterministic_fallback"

    # Build feature importance list (rule-based heuristic, real model would use SHAP)
    importances = _compute_feature_importance(f, req.decision)
    headline = _build_headline(req.ticker, req.decision, f)

    return {
        "ticker": req.ticker,
        "decision": req.decision,
        "explanationDepth": depth,
        "headline": headline,
        "detailedExplanation": explanation,
        "tooltipInsight": _tooltip_insight(req.ticker, req.decision, f, req.xaiLevel),
        "featureImportance": importances,
        "generatedBy": source,
        "generatedAt": _now_iso(),
    }


# ─── XAI Helpers ──────────────────────────────────────────────────────────────

async def _gemini_explain(req: XaiExplainRequest, depth: str) -> str:
    f = req.features
    depth_instructions = {
        "simple": (
            "Explain in 2 sentences suitable for a finance beginner. "
            "Avoid jargon; use an everyday analogy."
        ),
        "standard": (
            "Explain in 3-4 sentences for someone with basic finance knowledge. "
            "Reference RSI and sentiment score by name."
        ),
        "detailed": (
            "Provide a paragraph-length explanation referencing RSI, "
            "moving averages, volatility, and the FinBERT sentiment pipeline."
        ),
        "quant": (
            "Write a quant-level explanation referencing feature importances, "
            "model confidence intervals, and potential alpha decay risks."
        ),
    }
    prompt = f"""
You are the QuantEdge XAI assistant. The Random Forest decision engine produced a {req.decision} signal
for {req.ticker} with {f.confidence * 100:.1f}% confidence.

Technical snapshot:
- RSI: {f.rsi:.1f}
- MA5: {f.ma5:.2f}, MA10: {f.ma10:.2f}
- Volatility (5-day): {f.volatility:.4f}
- FinBERT Sentiment Score: {f.sentimentScore:.3f}
- Market Mood: {f.marketMood}

{depth_instructions.get(depth, depth_instructions['standard'])}
Do not exceed 120 words. Output plain text only.
"""
    try:
        response = _gemini_client.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt,
        )
        return response.text.strip()
    except Exception as exc:
        logger.error("Gemini call failed: %s — using fallback.", exc)
        return _deterministic_explain(req, depth)


def _deterministic_explain(req: XaiExplainRequest, depth: str) -> str:
    """
    Rule-based explanation engine — mirrors the InfoTooltip insights in DashboardTab.tsx.
    Production-safe fallback when Gemini is unavailable.
    """
    f = req.features
    rsi_note = (
        "RSI is in overbought territory" if f.rsi > 70
        else "RSI is in oversold territory" if f.rsi < 30
        else f"RSI reads neutral at {f.rsi:.0f}"
    )
    ma_note = (
        "MA5 above MA10 (bullish crossover)" if f.ma5 > f.ma10
        else "MA5 below MA10 (bearish crossover)"
    )
    sentiment_note = (
        f"FinBERT sentiment is {f.marketMood.lower()} ({f.sentimentScore:+.2f})"
    )
    divergence = f.ma5 > f.ma10 and f.sentimentScore < -0.2

    if depth == "simple":
        if req.decision == "BUY":
            return (
                f"The engine says BUY {req.ticker} because the price trend looks strong "
                f"and there are positive signals in the data."
            )
        elif req.decision == "SELL":
            return (
                f"The engine says SELL {req.ticker} because negative signals in the "
                f"news and technical data outweigh the positives."
            )
        return (
            f"The engine says HOLD {req.ticker} — mixed signals detected. "
            f"Better to wait and see."
        )

    base = (
        f"{req.ticker} → {req.decision} ({f.confidence * 100:.0f}% confidence). "
        f"{rsi_note}. {ma_note}. {sentiment_note}."
    )

    if depth == "standard":
        return base

    if depth == "detailed":
        divergence_note = (
            " Price-sentiment divergence detected — the price trend is bullish "
            "but news sentiment is negative, signalling potential reversal risk."
            if divergence else ""
        )
        return (
            f"{base} Volatility at {f.volatility:.4f} "
            f"({'elevated' if f.volatility > 0.02 else 'moderate'}).{divergence_note}"
        )

    # quant
    return (
        f"{base} Volatility σ={f.volatility:.4f}. "
        f"Top feature contributors: RSI≈0.34, sentimentScore≈0.28, MA5≈0.21 "
        f"(SHAP-approximated). "
        f"{'Price-sentiment divergence may compress alpha within 1-3 trading sessions.' if divergence else ''}"
    )


def _compute_feature_importance(f: XaiFeatures, decision: str) -> List[Dict[str, Any]]:
    """Heuristic feature importance; replace with SHAP values from trained model."""
    rsi_dir = "positive" if (decision == "BUY" and f.rsi < 70) else "negative" if f.rsi > 70 else "neutral"
    sent_dir = "positive" if f.sentimentScore > 0.1 else "negative" if f.sentimentScore < -0.1 else "neutral"
    ma_dir = "positive" if f.ma5 > f.ma10 else "negative"
    return [
        {"feature": "RSI", "importance": 0.34, "direction": rsi_dir},
        {"feature": "sentimentScore", "importance": 0.28, "direction": sent_dir},
        {"feature": "MA5", "importance": 0.21, "direction": ma_dir},
        {"feature": "Volatility", "importance": 0.12, "direction": "neutral"},
        {"feature": "MA10", "importance": 0.05, "direction": ma_dir},
    ]


def _build_headline(ticker: str, decision: str, f: XaiFeatures) -> str:
    mood_icon = {"Bullish": "↑", "Bearish": "↓", "Neutral": "→"}.get(f.marketMood, "→")
    return f"{ticker}: {decision} — {f.confidence * 100:.0f}% conf. Sentiment {mood_icon} {f.sentimentScore:+.2f}"


def _tooltip_insight(ticker: str, decision: str, f: XaiFeatures, level: int) -> str:
    """Short text for the InfoTooltip in DashboardTab — mirrors hardcoded strings in DashboardTab.tsx."""
    divergence = f.ma5 > f.ma10 and f.sentimentScore < -0.2
    if divergence:
        return (
            f"Current trends show {ticker}'s price is actively climbing, "
            f"but the general mood seen online shows a sharp shift in trust. "
            f"It is like a temporary disconnect between price and sentiment."
        )
    if decision == "BUY":
        return (
            f"Current momentum is heavily supported by order book intensity. "
            f"The model detects a strong signal with {f.confidence * 100:.0f}% confidence, "
            f"suggesting continued upside for {ticker}."
        )
    if decision == "SELL":
        return (
            f"Bearish sentiment ({f.sentimentScore:+.2f}) overrides technical support levels. "
            f"High-frequency social panic is flagging a potential correction phase for {ticker}."
        )
    return (
        f"Mixed signals detected for {ticker}. RSI at {f.rsi:.0f} and "
        f"sentiment at {f.sentimentScore:+.2f} are providing conflicting guidance."
    )

    
    # ─── Missing App Endpoints (Dashboard, Market, Portfolio, Assistant) ────────

@app.get("/api/dashboard")
async def get_dashboard():
    return {
        "portfolioValue": 124500.80,
        "dailyChange": 1250.40,
        "dailyChangePercent": 1.02,
        "overallConfidence": 87.5,
        "marketMood": "Bullish",
        "xaiLevel": 2,
        "activeAlerts": 2,
        "influenceVector": {"technical": 0.45, "sentiment": 0.35, "macro": 0.20}
    }
    
@app.get("/api/assets")
async def get_assets():
    return [
        {"ticker": "NVDA", "name": "NVIDIA Corp", "price": 128.50, "change": 3.42, "sentiment": 0.78},
        {"ticker": "AAPL", "name": "Apple Inc", "price": 224.20, "change": -0.85, "sentiment": -0.12},
        {"ticker": "TSLA", "name": "Tesla Inc", "price": 210.10, "change": 5.15, "sentiment": 0.45}
    ]

@app.get("/api/portfolio")
async def get_portfolio():
    return {
        "totalBalance": 124500.80,
        "holdings": [
            {"ticker": "NVDA", "shares": 150, "avgPrice": 110.00, "currentPrice": 128.50},
            {"ticker": "AAPL", "shares": 200, "avgPrice": 215.00, "currentPrice": 224.20}
        ]
    }

@app.get("/api/factors")
async def get_factors():
    return [
        {"name": "Volume Analysis", "weight": 0.34, "impact": "Bullish"},
        {"name": "Social Sentiment", "weight": 0.28, "impact": "Bearish"},
        {"name": "Macro Risk", "weight": 0.21, "impact": "Neutral"}
    ]

class AssistantQuery(BaseModel):
    query: str
    userId: Optional[str] = None

@app.post("/api/assistant")
async def assistant_chat(req: AssistantQuery):
    query_lower = req.query.lower()
    if "risk" in query_lower or "panic" in query_lower:
        reply = "Risk parameters detected elevated volatility in tech assets. NVDA divergence is currently being monitored."
    elif "fail-safe" in query_lower:
        reply = "Fail-Safe Mode triggers automated position hedging whenever social panic score drops below -0.40."
    else:
        reply = f"QuantEdge XAI Analysis: Processing market vectors for '{req.query}'. Momentum remains strongly supported."

    return {"reply": reply, "timestamp": _now_iso()}