class LearningTopic {
  final String id;
  final int number;
  final String title;
  final String description;
  final String icon;
  final String status;
  final bool unlocked;
  final bool completed;
  final List<String> subtopics;

  LearningTopic({
    required this.id,
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    required this.status,
    required this.unlocked,
    required this.completed,
    required this.subtopics,
  });

  factory LearningTopic.fromJson(Map<String, dynamic> json) {
    final subtopicsJson = json['subtopics'] as List? ?? [];

    return LearningTopic(
      id: json['id']?.toString() ?? '',
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '',
      status: json['status']?.toString() ?? 'locked',
      unlocked: json['unlocked'] ?? false,
      completed: json['completed'] ?? false,
      subtopics: subtopicsJson.map((e) => e.toString()).toList(),
    );
  }
}


// ============================================================
// LEARNING OPTION
// ============================================================

class LearningOption {
  final String id;
  final String text;

  LearningOption({
    required this.id,
    required this.text,
  });

  factory LearningOption.fromJson(Map<String, dynamic> json) {
    return LearningOption(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
    );
  }
}


// ============================================================
// LEARNING QUESTION
// ============================================================

class LearningQuestion {
  final String id;
  final String prompt;
  final String contextBlurb;
  final String type;
  final List<LearningOption> options;
  final String topicId;
  final String topicTitle;
  final String difficulty;
  final int scoreLevel;
  final String generatedBy;

  LearningQuestion({
    required this.id,
    required this.prompt,
    required this.contextBlurb,
    required this.type,
    required this.options,
    required this.topicId,
    required this.topicTitle,
    required this.difficulty,
    required this.scoreLevel,
    required this.generatedBy,
  });

  factory LearningQuestion.fromJson(Map<String, dynamic> json) {
    final optionsJson = json['options'] as List? ?? [];

    return LearningQuestion(
      id: json['questionId']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      contextBlurb: json['contextBlurb']?.toString() ?? '',
      type: json['type']?.toString() ?? 'CONCEPT',
      options: optionsJson
          .map(
            (option) => LearningOption.fromJson(
              option as Map<String, dynamic>,
            ),
          )
          .toList(),
      topicId: json['topicId']?.toString() ?? '',
      topicTitle: json['topicTitle']?.toString() ?? '',
      difficulty: json['difficulty']?.toString() ?? '',
      scoreLevel: (json['scoreLevel'] as num?)?.toInt() ?? 1,
      generatedBy: json['generatedBy']?.toString() ?? '',
    );
  }
}


// ============================================================
// LEARNING LESSON
// ============================================================

class LearningLesson {
  final String lessonId;
  final String topicId;
  final String topicTitle;
  final List<LearningQuestion> questions;

  LearningLesson({
    required this.lessonId,
    required this.topicId,
    required this.topicTitle,
    required this.questions,
  });

  factory LearningLesson.fromJson(Map<String, dynamic> json) {
    final questionsJson = json['questions'] as List? ?? [];

    return LearningLesson(
      lessonId: json['lessonId']?.toString() ?? '',
      topicId: json['topicId']?.toString() ?? '',
      topicTitle: json['topicTitle']?.toString() ?? '',
      questions: questionsJson
          .map(
            (question) => LearningQuestion.fromJson(
              question as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}


// ============================================================
// ANSWER RESULT
// ============================================================

class AnswerResult {
  final bool correct;
  final String? selectedOptionId;
  final String? correctOptionId;
  final String? explanation;
  final bool lessonComplete;
  final int currentQuestion;
  final int score;
  final int xpEarned;
  final bool passed;

  AnswerResult({
    required this.correct,
    required this.selectedOptionId,
    required this.correctOptionId,
    required this.explanation,
    required this.lessonComplete,
    required this.currentQuestion,
    required this.score,
    required this.xpEarned,
    required this.passed,
  });

  factory AnswerResult.fromJson(Map<String, dynamic> json) {
    return AnswerResult(
      correct: json['correct'] ?? false,
      selectedOptionId: json['selectedOptionId']?.toString(),
      correctOptionId: json['correctOptionId']?.toString(),
      explanation: json['explanation']?.toString(),
      lessonComplete: json['lessonComplete'] ?? false,
      currentQuestion:
          (json['currentQuestion'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt() ?? 0,
      xpEarned: (json['xpEarned'] as num?)?.toInt() ?? 0,
      passed: json['passed'] ?? false,
    );
  }
}


// ============================================================
// LEARNING PROGRESS
// ============================================================

class LearningProgress {
  final int score;
  final int xp;
  final int level;
  final String currentTopic;
  final List<String> completedTopics;

  LearningProgress({
    required this.score,
    required this.xp,
    required this.level,
    required this.currentTopic,
    required this.completedTopics,
  });

  factory LearningProgress.fromJson(Map<String, dynamic> json) {
    final completed = json['completedTopics'] as List? ?? [];

    return LearningProgress(
      score: (json['score'] as num?)?.toInt() ?? 0,
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      currentTopic: json['currentTopic']?.toString() ?? '',
      completedTopics:
          completed.map((e) => e.toString()).toList(),
    );
  }
}