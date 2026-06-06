import Foundation

// MARK: - Anthropic API Service
// Implements prompt caching (anthropic-beta: prompt-caching-2024-07-31).
// The master system prompt (~520 tokens) is sent with cache_control: ephemeral.
// After the first call it is cached for 5 minutes; subsequent calls cost 0.1x input price.
// Model routing: Haiku for quick drills, Sonnet for deep evaluation.

actor AnthropicService {
    static let shared = AnthropicService()

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let cachingBeta = "prompt-caching-2024-07-31"

    // Model IDs
    private let haikuModel = "claude-haiku-4-5-20251001"   // vocab, grammar, translation
    private let sonnetModel = "claude-sonnet-4-6"           // writing, speaking, reading eval

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? ""
    }

    // MARK: - Public API

    func evaluateExercise(
        type: ExerciseType,
        language: Language,
        level: CEFRLevel,
        prompt: String,
        userAnswer: String
    ) async throws -> EvaluationResponse {
        let command = SkillTemplates.evalCommand(
            type: type, language: language, level: level,
            prompt: prompt, userAnswer: userAnswer
        )
        let model = type.requiresDeepEvaluation ? sonnetModel : haikuModel
        let raw = try await call(command: command, model: model, maxTokens: 256)
        return try decode(EvaluationResponse.self, from: raw.text)
    }

    func generateLesson(
        language: Language,
        level: CEFRLevel,
        focusSkill: ExerciseType
    ) async throws -> (LessonContent, UsageSummary) {
        let command = SkillTemplates.lessonCommand(language: language, level: level, focusSkill: focusSkill)
        let raw = try await call(command: command, model: sonnetModel, maxTokens: 1024)
        let content = try decode(LessonContent.self, from: raw.text)
        return (content, raw.usage)
    }

    func generateTestQuestion(
        language: Language,
        level: CEFRLevel,
        skill: ExerciseType,
        questionNumber: Int
    ) async throws -> TestQuestion {
        let command = SkillTemplates.testCommand(
            language: language, level: level,
            skill: skill, questionNumber: questionNumber
        )
        let raw = try await call(command: command, model: haikuModel, maxTokens: 400)
        return try decode(TestQuestion.self, from: raw.text)
    }

    func evaluateSpeech(
        language: Language,
        level: CEFRLevel,
        expected: String,
        transcribed: String
    ) async throws -> SpeechEvaluation {
        let command = SkillTemplates.speakCommand(
            language: language, level: level,
            expected: expected, transcribed: transcribed
        )
        let raw = try await call(command: command, model: sonnetModel, maxTokens: 256)
        return try decode(SpeechEvaluation.self, from: raw.text)
    }

    // MARK: - Core HTTP Call

    private func call(command: String, model: String, maxTokens: Int) async throws -> RawResponse {
        guard !apiKey.isEmpty else { throw AnthropicError.missingAPIKey }

        let requestBody = AnthropicRequest(
            model: model,
            max_tokens: maxTokens,
            system: [
                SystemBlock(
                    type: "text",
                    text: SkillTemplates.masterSystemPrompt,
                    cache_control: CacheControl(type: "ephemeral")
                )
            ],
            messages: [ChatMessage(role: "user", content: command)],
            temperature: 0.3
        )

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(cachingBeta, forHTTPHeaderField: "anthropic-beta")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 401 { throw AnthropicError.invalidAPIKey }
        if httpResponse.statusCode == 429 { throw AnthropicError.rateLimited }
        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AnthropicError.httpError(httpResponse.statusCode, body)
        }

        let parsed = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = parsed.content.first?.text else {
            throw AnthropicError.emptyResponse
        }

        let usage = UsageSummary(
            inputTokens: parsed.usage.input_tokens,
            outputTokens: parsed.usage.output_tokens,
            cacheCreationTokens: parsed.usage.cache_creation_input_tokens ?? 0,
            cacheReadTokens: parsed.usage.cache_read_input_tokens ?? 0
        )

        return RawResponse(text: text, usage: usage)
    }

    // MARK: - JSON Decode Helper

    private func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        // Strip code fences if model accidentally wraps the JSON
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = clean.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = clean.data(using: .utf8) else { throw AnthropicError.parseError(text) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AnthropicError.parseError("Could not decode \(type): \(error.localizedDescription)\nRaw: \(text)")
        }
    }
}

// MARK: - Request / Response Types

private struct AnthropicRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: [SystemBlock]
    let messages: [ChatMessage]
    let temperature: Double
}

private struct SystemBlock: Encodable {
    let type: String
    let text: String
    let cache_control: CacheControl?
}

private struct CacheControl: Encodable {
    let type: String
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicResponse: Decodable {
    let content: [ContentBlock]
    let usage: RawUsage

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct RawUsage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }
}

private struct RawResponse {
    let text: String
    let usage: UsageSummary
}

// MARK: - Public Supporting Types

struct UsageSummary {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }
    var cacheHit: Bool { cacheReadTokens > 0 }

    var estimatedCostUSD: Double {
        // claude-haiku-4-5 pricing (approximate)
        let inputCost = Double(inputTokens - cacheReadTokens) * 0.00000025
        let cacheWriteCost = Double(cacheCreationTokens) * 0.0000003125
        let cacheReadCost = Double(cacheReadTokens) * 0.000000025
        let outputCost = Double(outputTokens) * 0.00000125
        return inputCost + cacheWriteCost + cacheReadCost + outputCost
    }
}

struct SpeechEvaluation: Codable {
    let score: Double
    let correct: Bool
    let feedback: String
    let correction: String?
    let pronunciation_note: String?
}

// MARK: - Errors

enum AnthropicError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case httpError(Int, String)
    case networkError(String)
    case emptyResponse
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No API key set. Add it in Settings."
        case .invalidAPIKey: return "Invalid API key. Check Settings."
        case .rateLimited: return "Rate limited. Wait a moment and try again."
        case .httpError(let code, _): return "Server error \(code). Try again."
        case .networkError(let msg): return "Network error: \(msg)"
        case .emptyResponse: return "Empty response from API."
        case .parseError: return "Could not parse the AI response."
        }
    }
}
