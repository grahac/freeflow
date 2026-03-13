import Foundation

enum PostProcessingError: LocalizedError {
    case requestFailed(Int, String)
    case invalidResponse(String)
    case requestTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode, let details):
            "Post-processing failed with status \(statusCode): \(details)"
        case .invalidResponse(let details):
            "Invalid post-processing response: \(details)"
        case .requestTimedOut(let seconds):
            "Post-processing timed out after \(Int(seconds))s"
        }
    }
}

struct PostProcessingResult {
    let transcript: String
    let prompt: String
}

final class PostProcessingService {
    static let defaultSystemPrompt = """
You are a text filter. Your ENTIRE response is pasted directly into a text field. Never explain, comment, or add anything beyond the cleaned text.

Rules:
- Remove filler words (um, uh, like, you know) unless meaningful.
- Fix spelling, grammar, and punctuation.
- Correct misspellings of names/terms from context or vocabulary. Never insert words the speaker did not say.
- Preserve intent, tone, and meaning exactly.
- Apply mid-speech corrections (e.g. "do Y oh I mean X" becomes "do X").
- When the speaker lists items using spoken numbers (e.g. "one ... two ... three ...") or sequence words, format as a numbered list (1. 2. 3.). Add paragraph breaks between distinct thoughts.
- Combine duplicate/redundant sentences into one.
- If the transcription is empty, return exactly: EMPTY

CRITICAL: Your response must contain ONLY the cleaned text. No preamble, no explanations, no "Here is the cleaned text:", no commentary, no notes. Just the text itself.
"""
    static let defaultSystemPromptDate = "2026-02-27"

    private let apiKey: String
    private let baseURL: String
    private let defaultModel = "meta-llama/llama-4-scout-17b-16e-instruct"
    private let postProcessingTimeoutSeconds: TimeInterval = 20

    init(apiKey: String, baseURL: String = "https://api.groq.com/openai/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func postProcess(
        transcript: String,
        context: AppContext,
        customVocabulary: String,
        customSystemPrompt: String = ""
    ) async throws -> PostProcessingResult {
        let vocabularyTerms = mergedVocabularyTerms(rawVocabulary: customVocabulary)

        let timeoutSeconds = postProcessingTimeoutSeconds
        return try await withThrowingTaskGroup(of: PostProcessingResult.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    throw PostProcessingError.invalidResponse("Post-processing service deallocated")
                }
                return try await self.process(
                    transcript: transcript,
                    contextSummary: context.contextSummary,
                    model: defaultModel,
                    customVocabulary: vocabularyTerms,
                    customSystemPrompt: customSystemPrompt
                )
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw PostProcessingError.requestTimedOut(timeoutSeconds)
            }

            do {
                guard let result = try await group.next() else {
                    throw PostProcessingError.invalidResponse("No post-processing result")
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func process(
        transcript: String,
        contextSummary: String,
        model: String,
        customVocabulary: [String],
        customSystemPrompt: String = ""
    ) async throws -> PostProcessingResult {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = postProcessingTimeoutSeconds

        let normalizedVocabulary = normalizedVocabularyText(customVocabulary)
        let vocabularyPrompt = if !normalizedVocabulary.isEmpty {
            """
The speaker uses the following terms. ONLY use these to fix the spelling of a word the speaker clearly said. Never substitute a different word with one of these terms:
\(normalizedVocabulary)
"""
        } else {
            ""
        }

        var systemPrompt = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultSystemPrompt
            : customSystemPrompt
        if !vocabularyPrompt.isEmpty {
            systemPrompt += "\n\n" + vocabularyPrompt
        }

        let userMessage = """
Clean up the following dictation and return only the cleaned text.

CONTEXT: "\(contextSummary)"

RAW_TRANSCRIPTION: "\(transcript)"
"""

        let promptForDisplay = """
Model: \(model)

[System]
\(systemPrompt)

[User]
\(userMessage)
"""

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.0,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": userMessage
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostProcessingError.invalidResponse("No HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw PostProcessingError.requestFailed(httpResponse.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PostProcessingError.invalidResponse("Missing choices[0].message.content")
        }

        return PostProcessingResult(
            transcript: sanitizePostProcessedTranscript(content),
            prompt: promptForDisplay
        )
    }

    private func sanitizePostProcessedTranscript(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        // Strip outer quotes if the LLM wrapped the entire response
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Treat the sentinel value as empty
        if result == "EMPTY" {
            return ""
        }

        return result
    }

    private func mergedVocabularyTerms(rawVocabulary: String) -> [String] {
        let terms = rawVocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        return terms.filter { seen.insert($0.lowercased()).inserted }
    }

    private func normalizedVocabularyText(_ vocabularyTerms: [String]) -> String {
        let terms = vocabularyTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else { return "" }
        return terms.joined(separator: ", ")
    }
}
