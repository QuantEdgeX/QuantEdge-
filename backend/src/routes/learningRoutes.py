"""
QuantEdge Learning Engine - FastAPI Route Layer v2.0
=====================================================
POST /api/learning/quiz/init    - Adaptive quiz session init
POST /api/learning/quiz/submit  - Submit answer, branch Q2/Q3
POST /api/learning/xai/explain  - Gemini XAI explanation (5 levels)
GET  /api/dashboard             - Dashboard metrics (snake_case)
GET  /api/assets                - Live yfinance market assets
GET  /api/portfolio             - Flat portfolio holdings list
GET  /api/factors               - Factor impact breakdown
POST /api/assistant             - Gemini educational assistant (5 levels)

uvicorn src.routes.learningRoutes:app --reload --port 8000
"""

from __future__ import annotations
from dotenv import load_dotenv
load_dotenv()

import os, uuid, random, logging, asyncio, time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from google import genai
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("quantedge.learning")

app = FastAPI(title="QuantEdge Learning API", version="2.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True,
                   allow_methods=["*"], allow_headers=["*"])

_GEMINI_KEY = os.getenv("GEMINI_API_KEY", "")
_gemini_client = genai.Client(api_key=_GEMINI_KEY) if _GEMINI_KEY else None
if not _GEMINI_KEY:
    logger.warning("GEMINI_API_KEY not set - using deterministic fallback.")

_SESSION_STORE: Dict[str, Dict[str, Any]] = {}

# --------------------------------------------------------------------------
# 5-Level XAI Configuration
# 1=novice  2=beginner  3=intermediate  4=advanced  5=expert
# --------------------------------------------------------------------------
_LEVEL_MAP: Dict[int, str] = {1:"novice",2:"beginner",3:"intermediate",4:"advanced",5:"expert"}

_LEVEL_CONFIG: Dict[str, Dict[str, Any]] = {
    "novice": {
        "label": "Novice",
        "features_shown": ["decision", "market_mood"],
        "word_limit": 40,
        "prompt": (
            "Explain in 1-2 very simple sentences for someone who has never invested. "
            "Use everyday analogies. Avoid ALL jargon. Focus on the buy/sell result and overall mood."
        ),
    },
    "beginner": {
        "label": "Beginner",
        "features_shown": ["decision", "market_mood", "sentiment_score"],
        "word_limit": 60,
        "prompt": (
            "Explain in 2-3 sentences for someone with very basic finance knowledge. "
            "Briefly define any term you use. Mention the sentiment score simply."
        ),
    },
    "intermediate": {
        "label": "Intermediate",
        "features_shown": ["decision", "rsi", "sentiment_score", "market_mood"],
        "word_limit": 80,
        "prompt": (
            "Explain in 3-4 sentences for someone with standard finance knowledge. "
            "Reference RSI and FinBERT sentiment score by name without re-defining them."
        ),
    },
    "advanced": {
        "label": "Advanced",
        "features_shown": ["decision","rsi","ma5","ma10","sentiment_score","volatility","confidence"],
        "word_limit": 100,
        "prompt": (
            "Paragraph-length explanation referencing RSI, MA5/MA10 crossovers, 5-day volatility, "
            "FinBERT sentiment pipeline, and model confidence. Note any price-sentiment divergence."
        ),
    },
    "expert": {
        "label": "Expert / Quant",
        "features_shown": ["decision","rsi","ma5","ma10","sentiment_score","volatility","confidence","shap"],
        "word_limit": 130,
        "prompt": (
            "Quant-level: SHAP feature contributions, alpha decay risk from price-sentiment divergence, "
            "volatility regime, and confidence interval risk. Dense technical language for quant analysts."
        ),
    },
}

# --------------------------------------------------------------------------
# Question Bank (9 questions across 3 tiers, adaptive branching)
# --------------------------------------------------------------------------
_QUESTION_BANK: List[Dict[str, Any]] = [
    # TIER 1
    {"questionId":"q_scen_001","type":"SCENARIO","tier":1,"position":0,
     "prompt":"Case Study: Market Divergence",
     "contextBlurb":"NVDA price is climbing rapidly but social sentiment has plummeted into panic. What do you do?",
     "options":[{"id":"A","text":"Chase the momentum rally immediately."},
                {"id":"B","text":"Liquidate all holdings to avoid the crash."},
                {"id":"C","text":"Pause and evaluate whether price and sentiment are out of sync."}],
     "correctOptionId":"C","scoreDimension":"sentiment","pointValue":10,"penalty":-3},

    {"questionId":"q_tech_001","type":"TECHNICAL","tier":1,"position":1,
     "prompt":"RSI Reading",
     "contextBlurb":"AAPL's RSI just crossed above 70 while its 5-day MA is still rising.",
     "options":[{"id":"A","text":"Strong buy - momentum is building."},
                {"id":"B","text":"Overbought territory - consider profit-taking or reduced position."},
                {"id":"C","text":"RSI above 70 is always a definitive sell signal."},
                {"id":"D","text":"RSI is irrelevant when MA is rising."}],
     "correctOptionId":"B","scoreDimension":"technical","pointValue":10,"penalty":-3},

    {"questionId":"q_risk_001","type":"SCENARIO","tier":1,"position":2,
     "prompt":"Volatility Spike",
     "contextBlurb":"TSLA's 5-day rolling volatility doubled overnight. FinBERT sentiment flags -0.35 (bearish).",
     "options":[{"id":"A","text":"Double your position - high volatility means high reward."},
                {"id":"B","text":"Reduce position size to cap downside exposure."},
                {"id":"C","text":"Ignore volatility; only price direction matters."}],
     "correctOptionId":"B","scoreDimension":"riskManagement","pointValue":10,"penalty":-3},

    # TIER 2
    {"questionId":"q_tech_002","type":"TECHNICAL","tier":2,"position":1,
     "prompt":"Golden Cross Signal",
     "contextBlurb":"MSFT's MA5 just crossed above MA10. FinBERT sentiment is +0.42 (bullish).",
     "options":[{"id":"A","text":"Golden Cross + bullish sentiment - both signals align. Weight towards BUY."},
                {"id":"B","text":"Ignore the MA crossover; sentiment alone is the reliable signal."},
                {"id":"C","text":"Wait for RSI to exceed 80 before acting on the crossover."}],
     "correctOptionId":"A","scoreDimension":"technical","pointValue":15,"penalty":-4},

    {"questionId":"q_sent_002","type":"SENTIMENT","tier":2,"position":1,
     "prompt":"FinBERT Divergence",
     "contextBlurb":"AMD's price climbed 6% today. But FinBERT scores across 12 headlines average -0.48.",
     "options":[{"id":"A","text":"Price momentum dominates - buy immediately."},
                {"id":"B","text":"Price-sentiment divergence detected. Negative headlines may delay momentum. Reduce confidence weighting."},
                {"id":"C","text":"Negative sentiment always means sell regardless of price."}],
     "correctOptionId":"B","scoreDimension":"sentiment","pointValue":15,"penalty":-4},

    {"questionId":"q_risk_002","type":"SCENARIO","tier":2,"position":2,
     "prompt":"Portfolio Correlation Risk",
     "contextBlurb":"QuantEdge signals BUY on NVDA and SELL on TSLA simultaneously. NVDA-TSLA correlation: 0.78.",
     "options":[{"id":"A","text":"Execute both signals at full position size independently."},
                {"id":"B","text":"High correlation means positions partially offset - size down to account for correlation risk."},
                {"id":"C","text":"Ignore correlation - each signal is independent."}],
     "correctOptionId":"B","scoreDimension":"riskManagement","pointValue":20,"penalty":-5},

    # TIER 3
    {"questionId":"q_sent_003","type":"SENTIMENT","tier":3,"position":2,
     "prompt":"Sentiment Time-Lag",
     "contextBlurb":"Headlines from 48h ago: +0.72 sentiment. Today's real-time FinBERT: -0.31.",
     "options":[{"id":"A","text":"Use the older positive score - more data points."},
                {"id":"B","text":"Weight recent sentiment more heavily; 48h-old headlines are stale and the market has repriced."},
                {"id":"C","text":"Average both scores for a balanced view."}],
     "correctOptionId":"B","scoreDimension":"sentiment","pointValue":20,"penalty":-5},

    {"questionId":"q_xai_001","type":"XAI","tier":3,"position":2,
     "prompt":"Feature Importance Interpretation",
     "contextBlurb":"QuantEdge outputs BUY for META (89% conf). SHAP: RSI=0.34, sentiment=0.28, MA5=0.21, Vol=0.12, MA10=0.05.",
     "options":[{"id":"A","text":"RSI alone drove this decision - ignore all other features."},
                {"id":"B","text":"RSI + sentiment together account for >62% of the weight - both technical momentum and mood are critical drivers."},
                {"id":"C","text":"Volatility is the most important feature at 0.12."}],
     "correctOptionId":"B","scoreDimension":"xaiComprehension","pointValue":25,"penalty":-6},

    {"questionId":"q_risk_003","type":"SCENARIO","tier":3,"position":2,
     "prompt":"Alpha Decay Risk",
     "contextBlurb":"QuantEdge issued BUY on NVDA 3 sessions ago. Since then: RSI 28->74, sentiment +0.65->-0.15, volatility doubled.",
     "options":[{"id":"A","text":"Hold - the original BUY signal is still valid."},
                {"id":"B","text":"Original signal conditions have decayed - RSI overbought, sentiment reversed, volatility elevated. Re-evaluate now."},
                {"id":"C","text":"Average down immediately to improve entry price."}],
     "correctOptionId":"B","scoreDimension":"riskManagement","pointValue":25,"penalty":-6},
]

_QUESTIONS_BY_ID: Dict[str, Dict[str, Any]] = {q["questionId"]: q for q in _QUESTION_BANK}


# --------------------------------------------------------------------------
# Utility helpers
# --------------------------------------------------------------------------
def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()

def _level_for_score(delta: Dict[str, float]) -> int:
    t = sum(delta.values())
    if t < 10: return 1
    if t < 25: return 2
    if t < 50: return 3
    if t < 80: return 4
    return 5

def _level_name(level: int) -> str:
    return _LEVEL_MAP.get(level, "beginner")

def _level_config(level: int) -> Dict[str, Any]:
    return _LEVEL_CONFIG.get(_level_name(level), _LEVEL_CONFIG["beginner"])

def _empty_score_vector() -> Dict[str, float]:
    return {"technical": 0.0, "sentiment": 0.0, "riskManagement": 0.0, "xaiComprehension": 0.0}

def _select_q1() -> Dict[str, Any]:
    return {**_QUESTIONS_BY_ID["q_scen_001"], "position": 0}

def _select_next_question(session: Dict[str, Any], last_correct: bool) -> Optional[Dict[str, Any]]:
    answered = set(session["answers"].keys())
    count = len(answered)
    if count >= 3:
        return None
    target_tier = (2 if last_correct else 1) if count == 1 else min(3, 2 + (1 if last_correct else 0))
    candidates = [q for q in _QUESTION_BANK
                  if q["tier"] == target_tier and q["questionId"] not in answered
                  and q["questionId"] != "q_scen_001"]
    if not candidates:
        candidates = [q for q in _QUESTION_BANK if q["questionId"] not in answered]
    return {**random.choice(candidates)} if candidates else None


# --------------------------------------------------------------------------
# Pydantic models
# --------------------------------------------------------------------------
class QuizInitRequest(BaseModel):
    userId: str
    xaiLevel: int = Field(ge=1, le=5)

class QuizSubmitRequest(BaseModel):
    sessionId: str; userId: str; questionId: str; selectedOptionId: str

class XaiFeatures(BaseModel):
    rsi: float; ma5: float; ma10: float; volatility: float
    sentimentScore: float; marketMood: str; confidence: float

class XaiExplainRequest(BaseModel):
    ticker: str; decision: str
    features: XaiFeatures
    xaiLevel: int = Field(ge=1, le=5)
    sessionId: Optional[str] = None

class AssistantQuery(BaseModel):
    query: str
    level: Optional[int] = Field(default=2, ge=1, le=5)
    userId: Optional[str] = None


# --------------------------------------------------------------------------
# Quiz routes
# --------------------------------------------------------------------------
@app.post("/api/learning/quiz/init")
async def quiz_init(req: QuizInitRequest) -> Dict[str, Any]:
    sid = str(uuid.uuid4())
    q1 = _select_q1()
    session = {"sessionId": sid, "userId": req.userId, "startedAt": _now_iso(),
                "completedAt": None, "status": "IN_PROGRESS", "questions": [q1],
                "answers": {}, "sessionDelta": _empty_score_vector(),
                "initialXaiLevel": req.xaiLevel, "finalXaiLevel": None}
    _SESSION_STORE[sid] = session
    logger.info("Session %s created for %s", sid, req.userId)
    return {"sessionId": sid, "userId": req.userId, "question": q1,
            "sessionStatus": "IN_PROGRESS", "startedAt": session["startedAt"]}


@app.post("/api/learning/quiz/submit")
async def quiz_submit(req: QuizSubmitRequest) -> Dict[str, Any]:
    session = _SESSION_STORE.get(req.sessionId)
    if not session: raise HTTPException(404, "Session not found.")
    if session["status"] != "IN_PROGRESS": raise HTTPException(409, "Session already completed.")
    if req.userId != session["userId"]: raise HTTPException(403, "User ID mismatch.")
    if req.questionId in session["answers"]: raise HTTPException(409, "Question already answered.")
    question = _QUESTIONS_BY_ID.get(req.questionId)
    if not question: raise HTTPException(404, "Question not found.")

    is_correct = req.selectedOptionId == question["correctOptionId"]
    points = question["pointValue"] if is_correct else question["penalty"]
    dim = question["scoreDimension"]
    now = _now_iso()

    answer = {"questionId": req.questionId, "selectedOptionId": req.selectedOptionId,
              "isCorrect": is_correct, "pointsDelta": points, "scoreDimension": dim, "answeredAt": now}
    session["answers"][req.questionId] = answer
    session["sessionDelta"][dim] = session["sessionDelta"].get(dim, 0) + points
    if not any(q["questionId"] == req.questionId for q in session["questions"]):
        session["questions"].append(question)

    count = len(session["answers"])
    next_q: Optional[Dict[str, Any]] = None
    summary: Optional[Dict[str, Any]] = None

    if count < 3:
        next_q = _select_next_question(session, is_correct)
        if next_q and next_q["questionId"] not in [q["questionId"] for q in session["questions"]]:
            session["questions"].append(next_q)
    else:
        session["status"] = "COMPLETED"
        session["completedAt"] = now
        fl = _level_for_score(session["sessionDelta"])
        session["finalXaiLevel"] = fl
        total = sum(a["pointsDelta"] for a in session["answers"].values())
        summary = {"finalXaiLevel": fl, "levelTier": _level_name(fl), "currentLevel": _level_name(fl),
                   "levelChanged": fl != session["initialXaiLevel"], "totalPointsEarned": total,
                   "updatedScoreVector": session["sessionDelta"], "xpAwarded": max(0, total) * 5}
        logger.info("Session %s done. Level %s->%s", req.sessionId, session["initialXaiLevel"], fl)

    return {"sessionId": req.sessionId, "answer": answer, "sessionDelta": session["sessionDelta"],
            "nextQuestion": next_q, "sessionStatus": session["status"], "completionSummary": summary,
            "session": {"state": {"sessionId": req.sessionId, "status": session["status"],
                                  "questions": session["questions"],
                                  "currentIndex": count if count < 3 else 3}}}


# --------------------------------------------------------------------------
# XAI explain route
# --------------------------------------------------------------------------
@app.post("/api/learning/xai/explain")
async def xai_explain(req: XaiExplainRequest) -> Dict[str, Any]:
    cfg = _level_config(req.xaiLevel)
    depth = _level_name(req.xaiLevel)
    f = req.features
    if _gemini_client:
        text = await _gemini_xai(req, cfg)
        source = "gemini"
    else:
        text = _det_xai(req, depth)
        source = "deterministic_fallback"
    return {
        "ticker": req.ticker, "decision": req.decision, "explanationDepth": depth,
        "headline": _headline(req.ticker, req.decision, f),
        "summary": text,                 # Flutter quiz_provider reads `summary`
        "detailedExplanation": text,
        "tooltipInsight": _tooltip(req.ticker, req.decision, f, req.xaiLevel),
        "featureImportance": _feat_imp(f, req.decision),
        "generatedBy": source, "generatedAt": _now_iso(),
        "levelConfig": {"label": cfg["label"], "featuresShown": cfg["features_shown"]},
    }


# --------------------------------------------------------------------------
# App data endpoints
# --------------------------------------------------------------------------
@app.get("/api/dashboard")
async def get_dashboard():
    """Snake_case keys matching Flutter DashboardMetrics.fromJson."""
    return {"portfolio_value": 124500.80, "daily_change": 1250.40, "weekly_change": 5430.20,
            "xp_points": 2450, "user_level": 2, "win_rate": 0.68, "next_level_milestone": "3500 XP"}


_ASSETS_CACHE: Dict[str, Any] = {"timestamp": 0.0, "data": []}

def _fetch_yfinance_assets() -> List[Dict[str, Any]]:
    tickers = ["NVDA", "AAPL", "TSLA", "MSFT", "AMD"]
    try:
        import yfinance as yf
        assets = []
        for sym in tickers:
            try:
                hist = yf.Ticker(sym).history(period="5d")
                if hist.empty: raise ValueError("empty")
                close = hist["Close"].dropna()
                price = float(close.iloc[-1])
                prev  = float(close.iloc[-2]) if len(close) >= 2 else price
                chg   = ((price - prev) / prev) * 100
                d     = close.diff()
                gain  = d.where(d > 0, 0).mean()
                loss  = (-d.where(d < 0, 0)).mean()
                rsi   = round(100 - 100 / (1 + gain / loss), 1) if loss else 50.0
                if rsi < 35 and chg > 0:   status, conf = "BUY",  f"{min(95, 60+int(35-rsi))}%"
                elif rsi > 65 and chg < 0: status, conf = "SELL", f"{min(95, 60+int(rsi-65))}%"
                else:                       status, conf = "HOLD", f"{max(50, 80-int(abs(rsi-50)))}%"
                sent = round(chg / 10, 2)
                assets.append({"ticker": sym, "status": status, "confidence": conf,
                                "sentiment": str(sent), "rsi": rsi, "price": round(price,2),
                                "changePercent": round(chg,2), "insight": _asset_insight(sym,status,rsi,sent)})
            except Exception as e:
                logger.warning("yfinance %s: %s - seed", sym, e)
                assets.append(_seed_asset(sym))
        return assets
    except Exception as e:
        logger.warning("yfinance error: %s - fallback", e)
        return [_seed_asset(s) for s in tickers]


def _fetch_yfinance_assets_for(target_tickers: List[str]) -> List[Dict[str, Any]]:
    """Parameterised version of _fetch_yfinance_assets for a custom ticker list."""
    try:
        import yfinance as yf
        assets = []
        for sym in target_tickers:
            try:
                hist = yf.Ticker(sym).history(period="5d")
                if hist.empty: raise ValueError("empty")
                close = hist["Close"].dropna()
                price = float(close.iloc[-1])
                prev  = float(close.iloc[-2]) if len(close) >= 2 else price
                chg   = ((price - prev) / prev) * 100
                d     = close.diff()
                gain  = d.where(d > 0, 0).mean()
                loss  = (-d.where(d < 0, 0)).mean()
                rsi   = round(100 - 100 / (1 + gain / loss), 1) if loss else 50.0
                if rsi < 35 and chg > 0:   status, conf = "BUY",  f"{min(95, 60+int(35-rsi))}%"
                elif rsi > 65 and chg < 0: status, conf = "SELL", f"{min(95, 60+int(rsi-65))}%"
                else:                       status, conf = "HOLD", f"{max(50, 80-int(abs(rsi-50)))}%"
                sent = round(chg / 10, 2)
                assets.append({"ticker": sym, "status": status, "confidence": conf,
                                "sentiment": str(sent), "rsi": rsi, "price": round(price,2),
                                "changePercent": round(chg,2), "insight": _asset_insight(sym,status,rsi,sent)})
            except Exception as e:
                logger.warning("yfinance %s: %s - seed", sym, e)
                assets.append(_seed_asset(sym))
        return assets
    except Exception as e:
        logger.warning("yfinance error: %s - fallback", e)
        return [_seed_asset(s) for s in target_tickers]


# --------------------------------------------------------------------------
# Ticker search cache (30s TTL, keyed by query string)
# --------------------------------------------------------------------------
_TICKER_SEARCH_CACHE: Dict[str, Any] = {}   # {query: {"ts": float, "data": list}}

_POPULAR_TICKERS = [
    {"ticker": "NVDA", "name": "NVIDIA Corporation"},
    {"ticker": "AAPL", "name": "Apple Inc."},
    {"ticker": "TSLA", "name": "Tesla Inc."},
    {"ticker": "MSFT", "name": "Microsoft Corporation"},
    {"ticker": "AMZN", "name": "Amazon.com Inc."},
    {"ticker": "GOOGL", "name": "Alphabet Inc."},
    {"ticker": "META", "name": "Meta Platforms"},
    {"ticker": "AMD",  "name": "Advanced Micro Devices"},
    {"ticker": "JPM",  "name": "JPMorgan Chase"},
    {"ticker": "NFLX", "name": "Netflix Inc."},
    {"ticker": "DIS",  "name": "Walt Disney Co."},
    {"ticker": "BABA", "name": "Alibaba Group"},
]


def _popular_fallback(query: str) -> List[Dict[str, Any]]:
    q = query.upper()
    results = []
    for t in _POPULAR_TICKERS:
        if t["ticker"].startswith(q) or q in t["name"].upper():
            results.append({
                "ticker": t["ticker"],
                "name": t["name"],
                "price": 0.0,
                "changePercent": 0.0,
                "exchange": "NASDAQ",
            })
    return results


def _fetch_ticker_search(query: str) -> List[Dict[str, Any]]:
    """Try yfinance for exact ticker, fall back to popular list filter."""
    try:
        import yfinance as yf

        ticker_obj = yf.Ticker(query)
        info = ticker_obj.info  # may block up to 4s
        long_name = info.get("longName") or info.get("shortName")
        if not long_name:
            return _popular_fallback(query)
        price = float(info.get("currentPrice") or info.get("regularMarketPrice") or 0.0)
        prev  = float(info.get("previousClose") or price)
        chg   = ((price - prev) / prev * 100) if prev else 0.0
        exchange = info.get("exchange") or info.get("exchangeName") or "N/A"
        return [{
            "ticker": query,
            "name": long_name,
            "price": round(price, 2),
            "changePercent": round(chg, 2),
            "exchange": exchange,
        }]
    except Exception:
        return _popular_fallback(query)


@app.get("/api/tickers/search")
async def ticker_search(q: str = "") -> List[Dict[str, Any]]:
    """Search for tickers matching the query string.
    Instant popular-ticker fallback, 30s cache, never errors."""
    query = q.strip().upper()
    if not query:
        return []

    now = time.time()
    cached = _TICKER_SEARCH_CACHE.get(query)
    if cached and (now - cached["ts"]) < 30:
        return cached["data"]

    try:
        results = await asyncio.wait_for(
            asyncio.to_thread(_fetch_ticker_search, query),
            timeout=4.0,
        )
    except Exception:
        results = _popular_fallback(query)

    _TICKER_SEARCH_CACHE[query] = {"ts": now, "data": results}
    return results


# --------------------------------------------------------------------------
# Ticker detail cache (60s TTL, keyed by ticker)
# --------------------------------------------------------------------------
_TICKER_DETAIL_CACHE: Dict[str, Any] = {}  # {ticker: {"ts": float, "data": dict}}


def _build_bold_prediction(ticker: str, signal: str, conf: float) -> str:
    pct = round(conf * 100)
    if signal == "BUY":
        return (f"Model signals {ticker} is positioned for a short-term breakout with "
                f"{pct}% confidence. Upside target: +8-12% over 5 sessions.")
    if signal == "SELL":
        return (f"Elevated risk detected in {ticker}. Model recommends reducing exposure "
                f"- {pct}% confidence of pullback within 3-5 sessions.")
    return (f"{ticker} is consolidating near key support. Model holds neutral with "
            f"{pct}% confidence. Wait for volume confirmation.")


def _xai_insight_for_level(ticker: str, signal: str, conf: float,
                            rsi: float, sentiment: float, xai_level: int) -> str:
    level_name = _LEVEL_MAP.get(xai_level, "beginner")
    if level_name == "novice":
        return (f"The AI thinks {ticker} looks {'good to buy' if signal == 'BUY' else 'risky right now' if signal == 'SELL' else 'neutral'}. "
                f"Overall market mood is {'positive' if sentiment > 0 else 'negative'}.")
    if level_name == "beginner":
        return (f"{ticker} signal: {signal}. Sentiment score is {sentiment:+.2f} and confidence is {round(conf*100)}%. "
                f"The model spotted {'buying' if signal == 'BUY' else 'selling'} pressure.")
    if level_name == "intermediate":
        rsi_note = "overbought" if rsi > 70 else "oversold" if rsi < 30 else f"neutral at {rsi:.0f}"
        return (f"{ticker} RSI is {rsi_note}. FinBERT sentiment at {sentiment:+.2f}. "
                f"Model confidence {round(conf*100)}% - {signal} signal generated.")
    if level_name == "advanced":
        return (f"RSI {rsi:.1f} with FinBERT sentiment {sentiment:+.2f}. "
                f"Model outputs {signal} at {round(conf*100)}% confidence. "
                f"{'Price-sentiment divergence detected - elevated reversal risk.' if (rsi > 60 and sentiment < -0.1) else 'Signals broadly aligned.'}")
    # expert
    return (f"RSI={rsi:.1f}. FinBERT={sentiment:+.2f}. SHAP: RSI~0.34, sentiment~0.28, MA5~0.21, Vol~0.12, MA10~0.05. "
            f"Signal: {signal} @ {round(conf*100)}% conf. "
            f"{'Alpha decay risk: price-sentiment divergence detected.' if (rsi > 60 and sentiment < -0.1) else 'Signals aligned - low divergence.'}")


def _fetch_ticker_detail(ticker: str, xai_level: int) -> Dict[str, Any]:
    """Fetch full ticker detail from yfinance + build AI signal. Falls back to mock on error."""
    try:
        import yfinance as yf
        import pandas as pd

        t = yf.Ticker(ticker)
        info = t.info

        current_price = float(info.get("currentPrice") or info.get("regularMarketPrice") or 0.0)
        prev_close    = float(info.get("previousClose") or current_price)
        change_pct    = ((current_price - prev_close) / prev_close * 100) if prev_close else 0.0
        high52w       = float(info.get("fiftyTwoWeekHigh") or 0.0)
        low52w        = float(info.get("fiftyTwoWeekLow") or 0.0)
        volume        = float(info.get("volume") or info.get("regularMarketVolume") or 0.0)
        market_cap    = float(info.get("marketCap") or 0.0)
        company_name  = info.get("longName") or info.get("shortName") or ticker

        # 30-day price history
        hist = yf.download(ticker, period="30d", interval="1d", progress=False)
        if not hist.empty and "Close" in hist.columns:
            close_series = hist["Close"].dropna()
            price_history = [round(float(p), 2) for p in close_series.to_numpy().tolist()]
            price_labels  = [ts.strftime("%d %b") for ts in close_series.index.to_pydatetime()]
        else:
            price_history = []
            price_labels  = []

        # RSI from history
        if len(price_history) >= 14:
            s = pd.Series(price_history)
            delta = s.diff()
            gain  = delta.where(delta > 0, 0).rolling(14).mean()
            loss  = (-delta.where(delta < 0, 0)).rolling(14).mean()
            rsi   = round(float(100 - 100 / (1 + (gain / loss).iloc[-1])), 1)
        else:
            rsi = 50.0

        # Derive signal from technicals
        sentiment = round(change_pct / 10, 2)
        if rsi < 35 and change_pct > 0:
            signal, conf = "BUY",  min(0.95, 0.60 + (35 - rsi) / 100)
        elif rsi > 65 and change_pct < 0:
            signal, conf = "SELL", min(0.95, 0.60 + (rsi - 65) / 100)
        else:
            signal, conf = "HOLD", max(0.50, 0.80 - abs(rsi - 50) / 100)

        factors = [
            {"name": "Volume Analysis",   "weight": "39%", "percentage": 0.39, "code": "VL", "color": "emerald"},
            {"name": "Price Action",       "weight": "25%", "percentage": 0.25, "code": "PR", "color": "blue"},
            {"name": "Social Sentiment",   "weight": "21%", "percentage": 0.21, "code": "SN", "color": "amber"},
            {"name": "Retail Sentiment",   "weight": "15%", "percentage": 0.15, "code": "RT", "color": "rose"},
        ]

        return {
            "ticker":         ticker,
            "companyName":    company_name,
            "currentPrice":   round(current_price, 2),
            "changePercent":  round(change_pct, 2),
            "high52w":        round(high52w, 2),
            "low52w":         round(low52w, 2),
            "volume":         volume,
            "marketCap":      market_cap,
            "priceHistory":   price_history,
            "priceLabels":    price_labels,
            "aiSignal":       signal,
            "aiConfidence":   round(conf, 4),
            "sentimentScore": sentiment,
            "rsi":            rsi,
            "boldPrediction": _build_bold_prediction(ticker, signal, conf),
            "factors":        factors,
            "xaiInsight":     _xai_insight_for_level(ticker, signal, conf, rsi, sentiment, xai_level),
        }

    except Exception as e:
        logger.warning("fetchTickerDetail %s error: %s - mock", ticker, e)
        return _mock_ticker_detail(ticker, xai_level)


def _mock_ticker_detail(ticker: str, xai_level: int) -> Dict[str, Any]:
    prices = [420.0, 435.0, 428.0, 445.0, 460.0, 455.0, 471.0,
              468.0, 480.0, 487.0, 492.0, 488.0, 495.0, 501.0, 498.0]
    labels = ["1d","2d","3d","4d","5d","6d","7d",
              "8d","9d","10d","11d","12d","13d","14d","15d"]
    signal, conf, rsi, sentiment = "BUY", 0.91, 68.4, 0.88
    return {
        "ticker":         ticker,
        "companyName":    ticker,
        "currentPrice":   487.20,
        "changePercent":  2.34,
        "high52w":        502.0,
        "low52w":         180.0,
        "volume":         42300000.0,
        "marketCap":      1200000000000.0,
        "priceHistory":   prices,
        "priceLabels":    labels,
        "aiSignal":       signal,
        "aiConfidence":   conf,
        "sentimentScore": sentiment,
        "rsi":            rsi,
        "boldPrediction": _build_bold_prediction(ticker, signal, conf),
        "factors": [
            {"name": "Volume Analysis",  "weight": "39%", "percentage": 0.39, "code": "VL", "color": "emerald"},
            {"name": "Price Action",      "weight": "25%", "percentage": 0.25, "code": "PR", "color": "blue"},
            {"name": "Social Sentiment",  "weight": "21%", "percentage": 0.21, "code": "SN", "color": "amber"},
            {"name": "Retail Sentiment",  "weight": "15%", "percentage": 0.15, "code": "RT", "color": "rose"},
        ],
        "xaiInsight": _xai_insight_for_level(ticker, signal, conf, rsi, sentiment, xai_level),
    }


@app.get("/api/tickers/{ticker}/detail")
async def ticker_detail(ticker: str, xaiLevel: int = 2) -> Dict[str, Any]:
    """Full ticker detail: price, history, AI signal, XAI insight. 60s cache. Never errors."""
    sym = ticker.upper()
    xai_level = max(1, min(5, xaiLevel))
    cache_key = f"{sym}:{xai_level}"
    now = time.time()
    cached = _TICKER_DETAIL_CACHE.get(cache_key)
    if cached and (now - cached["ts"]) < 60:
        return cached["data"]

    try:
        data = await asyncio.wait_for(
            asyncio.to_thread(_fetch_ticker_detail, sym, xai_level),
            timeout=6.0,
        )
    except Exception:
        data = _mock_ticker_detail(sym, xai_level)

    _TICKER_DETAIL_CACHE[cache_key] = {"ts": now, "data": data}
    return data


@app.get("/api/assets")
async def get_assets(tickers: Optional[str] = None):
    """Live yfinance market data with 60s cache and fast fallback.
    Accepts optional ?tickers=NVDA,AAPL,TSLA to filter which tickers are returned.
    Non-blocking to avoid stalling concurrent Flutter requests."""
    now = time.time()
    requested = [t.strip().upper() for t in tickers.split(",")] if tickers else None
    default_tickers = ["NVDA", "AAPL", "TSLA", "MSFT", "AMD"]
    target_tickers = requested if requested else default_tickers

    if _ASSETS_CACHE["data"] and (now - _ASSETS_CACHE["timestamp"]) < 60.0:
        cached = _ASSETS_CACHE["data"]
        if requested:
            cached = [a for a in cached if a["ticker"] in requested]
            # If any requested ticker is missing from cache, fetch fresh
            if len(cached) == len(requested):
                return cached
        else:
            return cached

    try:
        data = await asyncio.wait_for(
            asyncio.to_thread(_fetch_yfinance_assets_for, target_tickers),
            timeout=2.5,
        )
        # Merge into full cache
        data_by_ticker = {a["ticker"]: a for a in data}
        if _ASSETS_CACHE["data"]:
            for a in _ASSETS_CACHE["data"]:
                if a["ticker"] not in data_by_ticker:
                    data_by_ticker[a["ticker"]] = a
        _ASSETS_CACHE["data"] = list(data_by_ticker.values())
        _ASSETS_CACHE["timestamp"] = now
        return data
    except Exception as err:
        logger.warning("yfinance fetch took >2.5s or error: %s. Using seed fallback.", err)
        seed_data = [_seed_asset(s) for s in target_tickers]
        if not _ASSETS_CACHE["data"]:
            _ASSETS_CACHE["data"] = seed_data
            _ASSETS_CACHE["timestamp"] = now
        cached = _ASSETS_CACHE["data"]
        if requested:
            return [a for a in cached if a["ticker"] in requested] or seed_data
        return cached or seed_data


@app.get("/api/portfolio")
async def get_portfolio():
    """Flat list matching Flutter PortfolioHolding.fromJson."""
    return [
        {"symbol":"NVDA","name":"NVIDIA Corporation","quantity":5.0,
         "current_price":128.50,"total_value":642.50,"day_change":21.50,"allocation":"47.7%"},
        {"symbol":"AAPL","name":"Apple Inc.","quantity":3.0,
         "current_price":224.20,"total_value":672.60,"day_change":-7.65,"allocation":"49.9%"},
        {"symbol":"CASH","name":"Cash Reserve","quantity":1.0,
         "current_price":32.00,"total_value":32.00,"day_change":0.0,"allocation":"2.4%"},
    ]


@app.get("/api/factors")
async def get_factors():
    """Fields matching Flutter FactorImpact.fromJson."""
    return [
        {"name":"Technical Momentum","weight":"38%","percentage":0.38,"code":"TM","color":"blue"},
        {"name":"NLP Sentiment",     "weight":"31%","percentage":0.31,"code":"NS","color":"emerald"},
        {"name":"Volatility Risk",   "weight":"19%","percentage":0.19,"code":"VR","color":"amber"},
        {"name":"Macro Correlation", "weight":"12%","percentage":0.12,"code":"MC","color":"rose"},
    ]


@app.post("/api/assistant")
async def assistant_chat(req: AssistantQuery) -> Dict[str, Any]:
    """Gemini educational assistant, adapts to level 1-5."""
    cfg = _level_config(req.level or 2)
    depth = _level_name(req.level or 2)
    if _gemini_client:
        try:
            prompt = (f"You are QuantEdge Assistant, an educational AI for young investors.\n"
                      f"User skill level: {cfg['label']}.\n{cfg['prompt']}\n"
                      f"Rules: educational only, no real financial advice, max {cfg['word_limit']} words.\n\n"
                      f"User: {req.query}")
            resp = _gemini_client.models.generate_content(model="gemini-2.5-flash", contents=prompt)
            reply = resp.text.strip()
        except Exception as exc:
            logger.error("Gemini assistant error: %s", exc)
            reply = _det_assistant(req.query)
    else:
        reply = _det_assistant(req.query)
    return {"reply": reply, "timestamp": _now_iso(), "level": depth}


# --------------------------------------------------------------------------
# Internal helpers
# --------------------------------------------------------------------------
def _asset_insight(ticker: str, status: str, rsi: float, sentiment: float) -> str:
    mood = "bullish" if sentiment > 0.1 else "bearish" if sentiment < -0.1 else "neutral"
    msgs = {"BUY": f"{ticker} RSI {rsi:.0f} (oversold) with {mood} sentiment - engine signals buying opportunity.",
            "SELL": f"{ticker} RSI {rsi:.0f} (overbought) with {mood} sentiment - engine signals caution.",
            "HOLD": f"{ticker} RSI {rsi:.0f} with {mood} sentiment - holding position recommended."}
    return msgs.get(status, msgs["HOLD"])


def _seed_asset(sym: str) -> Dict[str, Any]:
    seeds = {
        "NVDA":{"status":"BUY", "confidence":"84%","sentiment":"0.78", "rsi":48.2,"price":128.50,"changePercent":3.42,
                "insight":"NVDA shows strong momentum with bullish sentiment backing the BUY signal."},
        "AAPL":{"status":"HOLD","confidence":"71%","sentiment":"-0.12","rsi":55.1,"price":224.20,"changePercent":-0.85,
                "insight":"AAPL RSI neutral at 55 with mildly bearish sentiment - hold recommended."},
        "TSLA":{"status":"BUY", "confidence":"76%","sentiment":"0.45", "rsi":42.3,"price":210.10,"changePercent":5.15,
                "insight":"TSLA recovering RSI with positive momentum - accumulation favoured."},
        "MSFT":{"status":"HOLD","confidence":"68%","sentiment":"0.22", "rsi":58.7,"price":415.30,"changePercent":0.62,
                "insight":"MSFT range-bound with moderate bullish sentiment - no strong signal."},
        "AMD": {"status":"SELL","confidence":"79%","sentiment":"-0.34","rsi":68.4,"price":152.80,"changePercent":-2.10,
                "insight":"AMD RSI approaching overbought with bearish sentiment - SELL signalled."},
    }
    base = seeds.get(sym, {"status":"HOLD","confidence":"60%","sentiment":"0.00","rsi":50.0,
                            "price":100.0,"changePercent":0.0,"insight":f"{sym} - insufficient live data."})
    return {"ticker": sym, **base}


async def _gemini_xai(req: XaiExplainRequest, cfg: Dict[str, Any]) -> str:
    f = req.features
    prompt = (f"QuantEdge XAI: RF model produced a {req.decision} for {req.ticker}.\n"
              f"RSI:{f.rsi:.1f} MA5:{f.ma5:.2f} MA10:{f.ma10:.2f} Vol:{f.volatility:.4f} "
              f"Sentiment:{f.sentimentScore:.3f}({f.marketMood}) Confidence:{f.confidence*100:.1f}%\n\n"
              f"Audience:{cfg['label']}\n{cfg['prompt']}\nMax {cfg['word_limit']} words. Plain text only.")
    try:
        r = _gemini_client.models.generate_content(model="gemini-2.5-flash", contents=prompt)
        return r.text.strip()
    except Exception as exc:
        logger.error("Gemini XAI error: %s", exc)
        return _det_xai(req, _level_name(req.xaiLevel))


def _det_xai(req: XaiExplainRequest, depth: str) -> str:
    f = req.features
    rsi_n = "RSI overbought" if f.rsi > 70 else ("RSI oversold" if f.rsi < 30 else f"RSI neutral at {f.rsi:.0f}")
    ma_n  = "MA5 above MA10 (bullish)" if f.ma5 > f.ma10 else "MA5 below MA10 (bearish)"
    s_n   = f"FinBERT {f.marketMood.lower()} ({f.sentimentScore:+.2f})"
    div   = f.ma5 > f.ma10 and f.sentimentScore < -0.2
    base  = f"{req.ticker} -> {req.decision} ({f.confidence*100:.0f}% conf). {rsi_n}. {ma_n}. {s_n}."

    if depth == "novice":
        d = {"BUY": f"Buy {req.ticker} - price signals look good and the mood is positive!",
             "SELL": f"Sell {req.ticker} - negative news mood and weak price signals.",
             "HOLD": f"Hold {req.ticker} - mixed signals, best to wait and see."}
        return d.get(req.decision, d["HOLD"])
    if depth == "beginner":
        d = {"BUY":  f"{req.ticker} positive signals. Sentiment {f.sentimentScore:+.2f} (bullish) and price trend favourable.",
             "SELL": f"{req.ticker} selling signals. Sentiment {f.sentimentScore:+.2f} (bearish) and price indicators weakening.",
             "HOLD": f"{req.ticker} mixed. Sentiment {f.sentimentScore:+.2f} and technicals not clearly directional."}
        return d.get(req.decision, d["HOLD"])
    if depth == "intermediate": return base
    if depth == "advanced":
        dn = " Price-sentiment divergence: price bullish but sentiment negative - reversal risk." if div else ""
        return f"{base} Vol:{f.volatility:.4f} ({'elevated' if f.volatility>0.02 else 'moderate'}).{dn}"
    # expert
    return (f"{base} Vol s={f.volatility:.4f}. SHAP: RSI~0.34, sentiment~0.28, MA5~0.21, Vol~0.12, MA10~0.05. "
            f"{'Price-sentiment divergence -> alpha decay risk 1-3 sessions.' if div else 'Signals aligned.'}")


def _feat_imp(f: XaiFeatures, decision: str) -> List[Dict[str, Any]]:
    rsi_d  = "positive" if decision=="BUY" and f.rsi<70 else ("negative" if f.rsi>70 else "neutral")
    sent_d = "positive" if f.sentimentScore>0.1 else ("negative" if f.sentimentScore<-0.1 else "neutral")
    ma_d   = "positive" if f.ma5>f.ma10 else "negative"
    return [{"feature":"RSI","importance":0.34,"direction":rsi_d},
            {"feature":"sentimentScore","importance":0.28,"direction":sent_d},
            {"feature":"MA5","importance":0.21,"direction":ma_d},
            {"feature":"Volatility","importance":0.12,"direction":"neutral"},
            {"feature":"MA10","importance":0.05,"direction":ma_d}]


def _headline(ticker: str, decision: str, f: XaiFeatures) -> str:
    icon = {"Bullish":"up","Bearish":"down","Neutral":"flat"}.get(f.marketMood,"flat")
    return f"{ticker}: {decision} - {f.confidence*100:.0f}% conf. Sentiment {icon} {f.sentimentScore:+.2f}"


def _tooltip(ticker: str, decision: str, f: XaiFeatures, level: int) -> str:
    div = f.ma5 > f.ma10 and f.sentimentScore < -0.2
    if level <= 2:
        if div:              return f"{ticker}'s price climbing but news mood dropping - signals out of sync."
        if decision=="BUY":  return f"Engine confident about {ticker} - positive price and news signals."
        if decision=="SELL": return f"Negative news and weak price driving SELL for {ticker}."
        return f"{ticker} mixed signals - no strong reason to buy or sell."
    if div:
        return f"{ticker} price-sentiment divergence: MA5 {f.ma5:.2f}>MA10 {f.ma10:.2f} (bullish) but FinBERT {f.sentimentScore:+.2f} (bearish). High reversal risk."
    if decision=="BUY":
        return f"Strong {ticker} BUY. RSI {f.rsi:.0f}, {f.marketMood.lower()} sentiment ({f.sentimentScore:+.2f}), MA crossover confirmed. Confidence: {f.confidence*100:.0f}%."
    if decision=="SELL":
        return f"Bearish sentiment ({f.sentimentScore:+.2f}) overrides {ticker} technical support. RSI {f.rsi:.0f} declining MA - correction risk."
    return f"Mixed for {ticker}. RSI {f.rsi:.0f}, sentiment {f.sentimentScore:+.2f} - no clear bias."


def _det_assistant(query: str) -> str:
    q = query.lower()
    if any(w in q for w in ["rsi","relative strength"]):
        return "RSI measures momentum 0-100. Below 30 = oversold (potential buy). Above 70 = overbought (potential sell). QuantEdge uses RSI as a primary technical indicator."
    if any(w in q for w in ["sentiment","finbert","news"]):
        return "FinBERT classifies financial news as Bullish, Neutral, or Bearish. QuantEdge combines this with technical indicators to generate trading signals."
    if any(w in q for w in ["volatility","risk","panic"]):
        return "Volatility measures price fluctuation intensity. QuantEdge monitors 5-day rolling volatility and flags elevated risk automatically."
    if any(w in q for w in ["moving average","golden cross","death cross"]):
        return "Moving Averages smooth price data. A Golden Cross (MA5 above MA10) signals upward momentum. QuantEdge uses MA5 and MA10 as core trend indicators."
    if any(w in q for w in ["buy","sell","hold","decision","signal"]):
        return "QuantEdge combines RSI, MAs, volatility, and FinBERT to generate BUY/SELL/HOLD signals with confidence scores and level-appropriate explanations."
    if any(w in q for w in ["xai","explainable","shap","model"]):
        return "XAI reveals WHY the model made its decision. QuantEdge shows which features drove each signal and by how much."
    return f"Great question about '{query}'! QuantEdge analyses indicators, sentiment, and volatility to help young investors understand markets. What would you like to explore?"
