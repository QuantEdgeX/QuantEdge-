import express, { Request, Response } from 'express';
import {
  initAdaptiveQuiz,
  submitAdaptiveAnswer,
  deriveSkillLevel
} from '../engine/quizEngine.js';
import { explainDecision } from '../services/xaiBridge.js';
import type { ScaffoldConfig } from '../types/learning.js';
import cors from 'cors';

const app = express();

app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

app.use(express.json());

const DEFAULT_SCAFFOLD: ScaffoldConfig = {
  configId: 'express-api-default',
  domain: 'technical-analysis',
  difficultyTarget: 3,
  hintsEnabled: true,
  maxHintsPerQuestion: 2,
  adaptiveRemediation: true,
  explainOnCorrect: true,
  streakToLevelUp: 2,
  streakToLevelDown: 2,
};

app.get('/api/learning/question', (req: Request, res: Response) => {
  try {
    const userId = (req.query.userId as string) || 'default-user';
    const session = initAdaptiveQuiz(userId, DEFAULT_SCAFFOLD);

    res.json({
      sessionId: session.state.sessionId,
      question: session.state.questions[0],
      session,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/learning/evaluate', (req: Request, res: Response) => {
  try {
    const { session, selectedOptionId, hintsUsed = 0, responseTimeMs = 1000 } = req.body;

    if (!session || !selectedOptionId) {
      return res.status(400).json({ error: 'Missing session or selectedOptionId in body' });
    }

    const updatedSession = submitAdaptiveAnswer(
      session,
      DEFAULT_SCAFFOLD,
      selectedOptionId,
      hintsUsed,
      responseTimeMs
    );

    const currentLevel = deriveSkillLevel(updatedSession.scoreVector);

    res.json({
      session: updatedSession,
      currentLevel,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Dynamic XAI Route
app.post('/api/learning/xai-explain', async (req: Request, res: Response) => {
  try {
    const payload = await explainDecision(req.body, {
      apiKey: process.env.GEMINI_API_KEY,
    });
    res.json(payload);
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(Number(PORT), '0.0.0.0', () => {
  console.log(`Learning Engine running on http://127.0.0.1:${PORT}`);
});