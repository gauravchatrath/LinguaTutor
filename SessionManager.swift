import Foundation
import Combine

// MARK: - Session Manager
// Drives the 30-minute daily session:
//  1. Picks a language (random, weighted toward weaker languages)
//  2. Generates a lesson via AnthropicService (Sonnet, one-time cost)
//  3. Serves exercises one by one and collects results
//  4. Persists the completed session to ProgressStore

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    enum SessionState {
        case idle
        case loading
        case exercising(exercise: Exercise, index: Int, total: Int)
        case feedback(result: ExerciseResult, next: Exercise?)
        case completed(LessonSession)
        case error(String)
    }

    @Published var state: SessionState = .idle
    @Published var timeRemaining: TimeInterval = 1800   // 30 minutes
    @Published var exercises: [Exercise] = []
    @Published var currentIndex: Int = 0
    @Published var results: [ExerciseResult] = []
    @Published var lastUsage: UsageSummary?

    private var sessionLanguage: Language?
    private var sessionStart: Date?
    private var timer: Timer?

    private let targetSeconds: TimeInterval = 1800

    private init() {}

    // MARK: - Session Lifecycle

    func startDailySession() async {
        guard case .idle = state else { return }
        state = .loading

        let language = pickLanguage()
        sessionLanguage = language
        sessionStart = Date()
        timeRemaining = targetSeconds
        results = []

        do {
            let progress = ProgressStore.shared.progress(for: language)
            let level = progress.currentLevel
            let focus = progress.weakestSkill

            let (lesson, usage) = try await AnthropicService.shared.generateLesson(
                language: language,
                level: level,
                focusSkill: focus
            )
            lastUsage = usage

            // Convert generated exercises to typed Exercise structs
            exercises = lesson.exercises.map { gen in
                Exercise(
                    type: ExerciseType(rawValue: gen.type) ?? .vocabulary,
                    language: language,
                    level: level,
                    prompt: gen.prompt,
                    targetAnswer: gen.answer,
                    hint: gen.hint
                )
            }
            currentIndex = 0

            let session = LessonSession(
                id: UUID(),
                language: language,
                startedAt: Date(),
                completedAt: nil,
                results: [],
                totalSeconds: 0
            )

            startTimer()
            advanceToExercise(session: session)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func submitAnswer(_ answer: String) async {
        guard case .exercising(let exercise, let index, let total) = state else { return }

        do {
            let eval: EvaluationResponse

            if exercise.type == .speaking {
                // Speaking answers are already transcribed text passed as answer
                let speechEval = try await AnthropicService.shared.evaluateSpeech(
                    language: exercise.language,
                    level: exercise.level,
                    expected: exercise.targetAnswer ?? exercise.prompt,
                    transcribed: answer
                )
                eval = EvaluationResponse(
                    score: speechEval.score,
                    correct: speechEval.correct,
                    feedback: speechEval.feedback,
                    correction: speechEval.correction,
                    hint: speechEval.pronunciation_note
                )
            } else {
                eval = try await AnthropicService.shared.evaluateExercise(
                    type: exercise.type,
                    language: exercise.language,
                    level: exercise.level,
                    prompt: exercise.prompt,
                    userAnswer: answer
                )
            }

            let usage = lastUsage
            let result = ExerciseResult(
                exerciseType: exercise.type,
                userAnswer: answer,
                score: eval.score,
                feedback: eval.feedback,
                inputTokens: usage?.inputTokens ?? 0,
                outputTokens: usage?.outputTokens ?? 0,
                cacheHit: usage?.cacheHit ?? false
            )
            results.append(result)

            let next: Exercise? = index + 1 < total ? exercises[index + 1] : nil
            state = .feedback(result: result, next: next)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func continueToNext() {
        guard case .feedback(_, let next) = state else { return }

        if let nextExercise = next {
            currentIndex += 1
            state = .exercising(
                exercise: nextExercise,
                index: currentIndex,
                total: exercises.count
            )
        } else {
            finishSession()
        }
    }

    func skipExercise() {
        guard case .exercising(_, let index, let total) = state else { return }
        if index + 1 < total {
            currentIndex += 1
            state = .exercising(
                exercise: exercises[currentIndex],
                index: currentIndex,
                total: total
            )
        } else {
            finishSession()
        }
    }

    func cancelSession() {
        timer?.invalidate()
        timer = nil
        state = .idle
        exercises = []
        results = []
    }

    func dismissError() {
        state = .idle
    }

    // MARK: - Internal

    private func advanceToExercise(session: LessonSession) {
        guard !exercises.isEmpty else {
            finishSession()
            return
        }
        state = .exercising(
            exercise: exercises[0],
            index: 0,
            total: exercises.count
        )
    }

    private func finishSession() {
        timer?.invalidate()
        timer = nil

        let elapsed = Int(targetSeconds - timeRemaining)
        let session = LessonSession(
            id: UUID(),
            language: sessionLanguage ?? .swedish,
            startedAt: sessionStart ?? Date(),
            completedAt: Date(),
            results: results,
            totalSeconds: elapsed
        )
        ProgressStore.shared.recordSession(session)
        state = .completed(session)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    self.finishSession()
                }
            }
        }
    }

    // MARK: - Language Selection (weighted by weakness)

    private func pickLanguage() -> Language {
        let store = ProgressStore.shared
        let all = Language.allCases

        // Weight by inverse of average skill score — weaker languages get higher weight
        var weights: [Language: Double] = [:]
        for lang in all {
            let p = store.progress(for: lang)
            let avg = p.skillScores.values.isEmpty ? 0.5 : p.skillScores.values.reduce(0, +) / Double(p.skillScores.count)
            weights[lang] = 1.0 - avg + 0.1  // minimum 0.1 weight
        }

        let total = weights.values.reduce(0, +)
        var roll = Double.random(in: 0..<total)
        for lang in all {
            roll -= weights[lang] ?? 0.1
            if roll <= 0 { return lang }
        }
        return all.randomElement() ?? .swedish
    }

    // MARK: - Formatted time remaining

    var formattedTimeRemaining: String {
        let m = Int(timeRemaining) / 60
        let s = Int(timeRemaining) % 60
        return String(format: "%d:%02d", m, s)
    }
}
