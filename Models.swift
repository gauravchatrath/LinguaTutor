import Foundation

// MARK: - Language

enum Language: String, CaseIterable, Codable, Identifiable {
    case marathi = "Marathi"
    case swedish = "Swedish"
    case punjabi = "Punjabi"

    var id: String { rawValue }

    var code: String {
        switch self {
        case .marathi: return "mr"
        case .swedish: return "sv"
        case .punjabi: return "pa"
        }
    }

    var localeID: String {
        switch self {
        case .marathi: return "mr-IN"
        case .swedish: return "sv-SE"
        case .punjabi: return "pa-IN"
        }
    }

    var flag: String {
        switch self {
        case .marathi: return "🇮🇳"
        case .swedish: return "🇸🇪"
        case .punjabi: return "🇮🇳"
        }
    }

    var script: String {
        switch self {
        case .marathi: return "Devanagari"
        case .swedish: return "Latin"
        case .punjabi: return "Gurmukhi"
        }
    }
}

// MARK: - CEFR Level

enum CEFRLevel: String, CaseIterable, Codable, Comparable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .a1: return "Beginner"
        case .a2: return "Elementary"
        case .b1: return "Intermediate"
        case .b2: return "Upper-Intermediate"
        case .c1: return "Advanced"
        case .c2: return "Mastery"
        }
    }

    var color: String {
        switch self {
        case .a1: return "green"
        case .a2: return "mint"
        case .b1: return "blue"
        case .b2: return "indigo"
        case .c1: return "purple"
        case .c2: return "red"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .a1: return 0; case .a2: return 1; case .b1: return 2
        case .b2: return 3; case .c1: return 4; case .c2: return 5
        }
    }

    static func < (lhs: CEFRLevel, rhs: CEFRLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var next: CEFRLevel? {
        let all = CEFRLevel.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}

// MARK: - Exercise Type

enum ExerciseType: String, CaseIterable, Codable {
    case vocabulary = "vocab"
    case grammar = "grammar"
    case translation = "translate"
    case reading = "read"
    case writing = "write"
    case speaking = "speak"
    case listening = "listen"

    var displayName: String {
        switch self {
        case .vocabulary: return "Vocabulary"
        case .grammar: return "Grammar"
        case .translation: return "Translation"
        case .reading: return "Reading"
        case .writing: return "Writing"
        case .speaking: return "Speaking"
        case .listening: return "Listening"
        }
    }

    var icon: String {
        switch self {
        case .vocabulary: return "text.book.closed"
        case .grammar: return "list.bullet.rectangle"
        case .translation: return "arrow.left.arrow.right"
        case .reading: return "doc.text"
        case .writing: return "pencil"
        case .speaking: return "mic.fill"
        case .listening: return "ear.fill"
        }
    }

    // Use Sonnet for nuanced evaluation, Haiku for quick drills
    var requiresDeepEvaluation: Bool {
        switch self {
        case .writing, .speaking, .reading: return true
        default: return false
        }
    }
}

// MARK: - Exercise

struct Exercise: Identifiable, Codable {
    let id: UUID
    let type: ExerciseType
    let language: Language
    let level: CEFRLevel
    let prompt: String
    let targetAnswer: String?
    let hint: String?
    let audioText: String?  // text to speak for listening exercises
    let options: [String]?  // for multiple choice

    init(
        id: UUID = UUID(),
        type: ExerciseType,
        language: Language,
        level: CEFRLevel,
        prompt: String,
        targetAnswer: String? = nil,
        hint: String? = nil,
        audioText: String? = nil,
        options: [String]? = nil
    ) {
        self.id = id
        self.type = type
        self.language = language
        self.level = level
        self.prompt = prompt
        self.targetAnswer = targetAnswer
        self.hint = hint
        self.audioText = audioText
        self.options = options
    }
}

// MARK: - Evaluation Response

struct EvaluationResponse: Codable {
    let score: Double        // 0.0 – 1.0
    let correct: Bool
    let feedback: String
    let correction: String?
    let hint: String?
}

// MARK: - Lesson Content (generated once per session)

struct LessonContent: Codable {
    let title: String
    let exercises: [GeneratedExercise]
}

struct GeneratedExercise: Codable, Identifiable {
    var id: UUID = UUID()
    let type: String
    let prompt: String
    let answer: String
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case type, prompt, answer, hint
    }
}

// MARK: - Test Question

struct TestQuestion: Codable, Identifiable {
    var id: UUID = UUID()
    let question: String
    let options: [String]
    let correct: Int      // index into options
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case question, options, correct, explanation
    }
}

// MARK: - Session

struct LessonSession: Identifiable, Codable {
    let id: UUID
    let language: Language
    let startedAt: Date
    var completedAt: Date?
    var results: [ExerciseResult]
    var totalSeconds: Int

    var averageScore: Double {
        guard !results.isEmpty else { return 0 }
        return results.reduce(0) { $0 + $1.score } / Double(results.count)
    }
}

struct ExerciseResult: Codable {
    let exerciseType: ExerciseType
    let userAnswer: String
    let score: Double
    let feedback: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheHit: Bool
}

// MARK: - Progress

struct LanguageProgress: Codable {
    var language: Language
    var currentLevel: CEFRLevel
    var skillScores: [String: Double]  // ExerciseType.rawValue -> avg score
    var sessionsCompleted: Int
    var minutesPracticed: Int
    var lastPracticed: Date?
    var totalTokensUsed: Int
    var cacheHits: Int

    init(language: Language) {
        self.language = language
        self.currentLevel = .a1
        self.skillScores = [:]
        self.sessionsCompleted = 0
        self.minutesPracticed = 0
        self.lastPracticed = nil
        self.totalTokensUsed = 0
        self.cacheHits = 0
    }

    // Weakest skill to focus on
    var weakestSkill: ExerciseType {
        let types = ExerciseType.allCases
        return types.min(by: { a, b in
            (skillScores[a.rawValue] ?? 0) < (skillScores[b.rawValue] ?? 0)
        }) ?? .vocabulary
    }

    var cacheHitRate: Double {
        guard totalTokensUsed > 0 else { return 0 }
        return Double(cacheHits) / Double(cacheHits + max(1, sessionsCompleted))
    }
}
