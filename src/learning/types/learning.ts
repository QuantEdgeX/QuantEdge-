/**
 * src/types/learning.ts
 *
 * Core type definitions for the Learning Engine module.
 * Covers user profiling, scaffolding configuration, quiz mechanics,
 * and explainable-AI (XAI) payloads surfaced to the client/CLI.
 */

/** Supported proficiency levels tracked for a learner. */
export type SkillLevel = "novice" | "beginner" | "intermediate" | "advanced" | "expert";

/** Named topics/domains the Learning Engine can quiz or scaffold against. */
export type LearningDomain =
  | "market-fundamentals"
  | "technical-analysis"
  | "risk-management"
  | "sentiment-analysis"
  | "quantitative-modeling"
  | "portfolio-theory";

/** A single tracked skill/topic mastery record for a user. */
export interface SkillMastery {
  domain: LearningDomain;
  level: SkillLevel;
  /** 0-1 confidence score derived from historical quiz performance. */
  masteryScore: number;
  /** Number of questions answered correctly in this domain. */
  correctCount: number;
  /** Number of questions attempted in this domain. */
  attemptCount: number;
  /** ISO-8601 timestamp of the last interaction in this domain. */
  lastUpdated: string;
}

/** Represents a learner's persistent profile within the Learning Engine. */
export interface UserProfile {
  userId: string;
  displayName: string;
  /** Overall skill level, typically derived from aggregated masteries. */
  overallLevel: SkillLevel;
  /** Per-domain mastery breakdown. */
  masteries: SkillMastery[];
  /** Preferred learning pace; used to tune scaffold aggressiveness. */
  preferredPace: "slow" | "standard" | "accelerated";
  /** Running streak of consecutive correct answers across sessions. */
  currentStreak: number;
  /** Total quiz sessions completed. */
  sessionsCompleted: number;
  createdAt: string;
  updatedAt: string;
}

/** Defines how much scaffolding/support the engine should provide a learner. */
export interface ScaffoldConfig {
  /** Unique identifier for this scaffold configuration. */
  configId: string;
  /** The domain this scaffold applies to. */
  domain: LearningDomain;
  /** Difficulty target (1 = easiest, 10 = hardest) the engine should aim for. */
  difficultyTarget: number;
  /** Whether hints are offered before an answer is submitted. */
  hintsEnabled: boolean;
  /** Max number of hints available per question. */
  maxHintsPerQuestion: number;
  /** Whether incorrect answers trigger a simplified follow-up question. */
  adaptiveRemediation: boolean;
  /** Whether explanations are shown after every answer, not just incorrect ones. */
  explainOnCorrect: boolean;
  /** Number of consecutive correct answers required to raise difficulty by one tier. */
  streakToLevelUp: number;
  /** Number of consecutive incorrect answers required to lower difficulty by one tier. */
  streakToLevelDown: number;
}

/** A single answer choice for a multiple-choice quiz question. */
export interface QuizChoice {
  id: string;
  text: string;
  isCorrect: boolean;
}

/** A quiz question served to the learner. */
export interface QuizQuestion {
  questionId: string;
  domain: LearningDomain;
  /** Difficulty on the same 1-10 scale as ScaffoldConfig.difficultyTarget. */
  difficulty: number;
  prompt: string;
  choices: QuizChoice[];
  /** Optional hint text, revealed progressively up to maxHintsPerQuestion. */
  hints?: string[];
  /** Explanation shown after the learner answers. */
  explanation: string;
  /** Optional tags for analytics/filtering. */
  tags?: string[];
}

/** A recorded response to a single quiz question during a session. */
export interface QuizAnswerRecord {
  questionId: string;
  selectedChoiceId: string;
  isCorrect: boolean;
  hintsUsed: number;
  /** Milliseconds taken to answer, measured from question display to submission. */
  responseTimeMs: number;
  answeredAt: string;
}

/** Represents the live/persisted state of an in-progress or completed quiz session. */
export interface QuizState {
  sessionId: string;
  userId: string;
  domain: LearningDomain;
  scaffoldConfigId: string;
  questions: QuizQuestion[];
  /** Index into `questions` for the currently active question. */
  currentIndex: number;
  answers: QuizAnswerRecord[];
  currentStreak: number;
  status: "not-started" | "in-progress" | "completed" | "abandoned";
  startedAt: string;
  completedAt?: string;
  /** Running difficulty level, mutated as the session adapts. */
  currentDifficulty: number;
}

/** A single contributing factor in an explainable-AI decision breakdown. */
export interface XAIFactor {
  name: string;
  /** Signed weight/contribution; positive favors the outcome, negative opposes it. */
  weight: number;
  /** Human-readable description of why this factor mattered. */
  description: string;
}

/**
 * Payload describing why the Learning Engine made a particular adaptive
 * decision (e.g., difficulty adjustment, question selection, remediation).
 * Surfaced to the UI/CLI for transparency.
 */
export interface XAIPayload {
  decisionId: string;
  sessionId: string;
  /** The type of decision being explained. */
  decisionType: "difficulty-adjustment" | "question-selection" | "remediation-trigger" | "level-up" | "level-down";
  /** Short, human-readable summary of the decision. */
  summary: string;
  /** Ranked list of factors that contributed to the decision. */
  factors: XAIFactor[];
  /** Overall confidence in the decision, 0-1. */
  confidence: number;
  generatedAt: string;
}