/**
 * src/learning/cli/testQuiz.ts
 *
 * Standalone interactive CLI runner for the Learning Engine's dynamic quiz flow.
 * Run with: npx tsx src/learning/cli/testQuiz.ts
 */
import * as readline from "node:readline";
import { stdin as input, stdout as output } from "node:process";
import { 
  initAdaptiveQuiz, 
  submitAdaptiveAnswer, 
  deriveSkillLevel 
} from "../engine/quizEngine.js";
import { explainDecision, explainSessionScoreVector } from "../services/xaiBridge.js";
import type { ScaffoldConfig } from "../types/learning.js";

const DEFAULT_SCAFFOLD: ScaffoldConfig = {
  configId: "cli-dynamic-default",
  domain: "technical-analysis",
  difficultyTarget: 3,
  hintsEnabled: true,
  maxHintsPerQuestion: 2,
  adaptiveRemediation: true,
  explainOnCorrect: true,
  streakToLevelUp: 2,
  streakToLevelDown: 2,
};

const rl = readline.createInterface({ input, output });

function ask(question: string): Promise<string> {
  return new Promise((resolve) => {
    rl.question(question, (answer) => resolve(answer.trim()));
  });
}

async function main(): Promise<void> {
  console.log("=== Dynamic Learning Engine & XAI CLI Test Runner ===\n");

  const userId = (await ask("Enter a user id (default 'cli-user'): ")) || "cli-user";
  const scaffold = DEFAULT_SCAFFOLD;

  let session = initAdaptiveQuiz(userId, scaffold);

  while (session.state.status === "in-progress") {
    const currentQuestion = session.state.questions[session.state.currentIndex];
    const snapshot = session.snapshots[session.snapshots.length - 1];

    console.log(`\n---------------------------------------------------------`);
    console.log(`[Question ${session.state.currentIndex + 1}/3 | Difficulty ${currentQuestion.difficulty}]`);
    console.log(`Prompt: ${currentQuestion.prompt}`);

    currentQuestion.choices.forEach((choice) => {
      console.log(`  ${choice.id}) ${choice.text}`);
    });

    let hintsUsed = 0;
    const startTime = Date.now();

    while (true) {
      const raw = await ask(
        scaffold.hintsEnabled && hintsUsed < scaffold.maxHintsPerQuestion
          ? "\nYour answer (a/b/c/d or 'hint'): "
          : "\nYour answer (a/b/c/d): "
      );

      const normalized = raw.toLowerCase();

      if (normalized === "hint" && scaffold.hintsEnabled) {
        if (currentQuestion.hints && hintsUsed < currentQuestion.hints.length && hintsUsed < scaffold.maxHintsPerQuestion) {
          console.log(`  💡 Hint: ${currentQuestion.hints[hintsUsed]}`);
          hintsUsed++;
          continue;
        } else {
          console.log("  ⚠️ No more hints available.");
          continue;
        }
      }

      const selectedChoice = currentQuestion.choices.find((c) => c.id === normalized);

      if (!selectedChoice) {
        console.log("  ⚠️ Please enter a valid choice letter (e.g., 'a', 'b', 'c').");
        continue;
      }

      const responseTimeMs = Date.now() - startTime;

      // Submit answer to the adaptive engine
      session = submitAdaptiveAnswer(
        session,
        scaffold,
        selectedChoice.id,
        hintsUsed,
        responseTimeMs
      );

      if (selectedChoice.isCorrect) {
        console.log("  ✅ Correct!");
      } else {
        console.log("  ❌ Incorrect.");
      }
      console.log(`  Explanation: ${currentQuestion.explanation}`);

      // Generate single-question XAI Payload
      const currentLevel = deriveSkillLevel(session.scoreVector);
      const xaiPayload = await explainDecision({
        sessionId: session.state.sessionId,
        ticker: snapshot.ticker,
        rsi: snapshot.rsi,
        finbertScore: snapshot.finbertScore,
        isCorrect: selectedChoice.isCorrect,
        hintsUsed,
        domain: currentQuestion.domain,
        skillLevel: currentLevel,
      });

      console.log(`\n  🔍 [XAI Real-Time Insight]`);
      console.log(`  ${xaiPayload.summary}`);

      break;
    }
  }

  // Quiz Complete - Output Vector Summary & Session XAI
  const finalLevel = deriveSkillLevel(session.scoreVector);
  const sessionXAI = explainSessionScoreVector(
    session.state.sessionId,
    session.scoreVector,
    finalLevel
  );

  console.log("\n=========================================================");
  console.log("                 DYNAMIC QUIZ COMPLETE                   ");
  console.log("=========================================================");
  console.log(`Assigned Skill Tier : ${finalLevel.toUpperCase()}`);
  console.log(`Technical Analysis  : ${(session.scoreVector.technicalAnalysis * 100).toFixed(0)}%`);
  console.log(`Sentiment Analysis  : ${(session.scoreVector.sentimentAnalysis * 100).toFixed(0)}%`);
  console.log(`Risk Management     : ${(session.scoreVector.riskManagement * 100).toFixed(0)}%`);
  console.log("---------------------------------------------------------");
  console.log(`🧠 [XAI Profile Summary]:`);
  console.log(`   ${sessionXAI.summary}`);
  console.log("=========================================================\n");

  rl.close();
}

main().catch((err) => {
  console.error("Fatal error running dynamic quiz CLI:", err);
  rl.close();
  process.exitCode = 1;
});