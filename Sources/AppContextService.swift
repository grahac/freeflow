import Foundation
import ApplicationServices
import AppKit

struct AppSelectionSnapshot {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
}

struct AppContext {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let currentActivity: String
    let contextPrompt: String?
    let screenshotDataURL: String? = nil
    let screenshotMimeType: String? = nil
    let screenshotError: String? = nil

    var contextSummary: String {
        currentActivity
    }
}

final class AppContextService {
    static let defaultContextPrompt = """
You are a context synthesis assistant for a speech-to-text pipeline.
Given app/window metadata and an optional screenshot, output exactly two sentences that describe what the user is doing right now and the likely writing intent in the current window.
Prioritize concrete details only from the context: for email, identify recipients, subject or thread cues, and whether the user is replying or composing; for terminal/code/text work, identify the active command, file, document title, or topic.
If details are missing, state uncertainty instead of inventing facts.
Return only two sentences, no labels, no markdown, no extra commentary.
"""
    static let defaultContextPromptDate = "2026-02-24"

    private let apiKey: String
    private let baseURL: String
    private let customContextPrompt: String
    private let contextModel: String
    private var contextRequestTimeoutSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "context_request_timeout_seconds")
        return override > 0 ? override : 20
    }

    init(
        apiKey: String,
        baseURL: String = "https://api.groq.com/openai/v1",
        customContextPrompt: String = "",
        contextModel: String = "meta-llama/llama-4-scout-17b-16e-instruct"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.customContextPrompt = customContextPrompt
        let trimmedModel = contextModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.contextModel = trimmedModel.isEmpty ? "meta-llama/llama-4-scout-17b-16e-instruct" : trimmedModel
    }

    func collectSelectionSnapshot() -> AppSelectionSnapshot {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppSelectionSnapshot(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil
            )
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        return AppSelectionSnapshot(
            appName: frontmostApp.localizedName,
            bundleIdentifier: frontmostApp.bundleIdentifier,
            windowTitle: focusedWindowTitle(from: appElement) ?? frontmostApp.localizedName,
            selectedText: rawSelectedText(from: appElement)
        )
    }

    func collectContext() async -> AppContext {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil,
                currentActivity: "You are dictating in an unrecognized context.",
                contextPrompt: nil
            )
        }

        let appName = frontmostApp.localizedName
        let bundleIdentifier = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        let windowTitle = focusedWindowTitle(from: appElement) ?? appName
        let selectedText = selectedText(from: appElement)
        let currentActivity: String
        let contextPrompt: String?
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let result = await inferActivityWithLLM(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                selectedText: selectedText
            ) {
                currentActivity = result.activity
                contextPrompt = result.prompt
            } else {
                currentActivity = fallbackCurrentActivity(
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    selectedText: selectedText,
                    windowTitle: windowTitle
                )
                contextPrompt = nil
            }
        } else {
            currentActivity = fallbackCurrentActivity(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                selectedText: selectedText,
                windowTitle: windowTitle
            )
            contextPrompt = nil
        }

        return AppContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: selectedText,
            currentActivity: currentActivity,
            contextPrompt: contextPrompt
        )
    }

    private func inferActivityWithLLM(
        appName: String?,
        bundleIdentifier: String?,
        windowTitle: String?,
        selectedText: String?
    ) async -> (activity: String, prompt: String)? {
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = contextRequestTimeoutSeconds
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let metadata = """
App: \(appName ?? "Unknown")
Bundle ID: \(bundleIdentifier ?? "Unknown")
Window: \(windowTitle ?? "Unknown")
Selected text: \(selectedText ?? "None")
"""

            let systemPrompt = customContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.defaultContextPrompt
                : customContextPrompt

            let userMessageText = "Analyze the context and infer the user's current activity in exactly two sentences.\n\n\(metadata)"
            let fullPrompt = "Model: \(contextModel)\n\n[System]\n\(systemPrompt)\n[User]\n\(userMessageText)"

            let payload: [String: Any] = [
                "model": contextModel,
                "temperature": 0.2,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userMessageText]
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let (data, response) = try await LLMAPITransport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }

            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return (activity: normalizedActivitySummary(cleaned), prompt: fullPrompt)
        } catch {
            return nil
        }
    }

    private func normalizedActivitySummary(_ value: String) -> String {
        let sentences = value
            .split(whereSeparator: { $0 == "." || $0 == "。" || $0 == "!" || $0 == "?" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.count <= 2 {
            return value
        }

        let firstTwo = sentences.prefix(2)
        return firstTwo.joined(separator: ". ") + "."
    }

    private func fallbackCurrentActivity(
        appName: String?,
        bundleIdentifier: String?,
        selectedText: String?,
        windowTitle: String?
    ) -> String {
        let activeApp = appName ?? "the active application"
        return "Could not reliably infer a two-sentence summary for \(activeApp) from the visible metadata."
    }

    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(from: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        if let windowTitle = accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString) {
            return trimmedText(windowTitle)
        }

        return nil
    }

    private func selectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           let selectedText = accessibilityString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
            return trimmedText(selectedText)
        }

        if let selectedText = accessibilityString(from: appElement, attribute: kAXSelectedTextAttribute as CFString) {
            return trimmedText(selectedText)
        }

        return nil
    }

    private func rawSelectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           let selectedText = accessibilityRawString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText
        }

        if let selectedText = accessibilityRawString(from: appElement, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText
        }

        return nil
    }

    private func accessibilityElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func accessibilityString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return trimmedText(stringValue)
    }

    private func accessibilityRawString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue.isEmpty ? nil : stringValue
    }

    private func accessibilityPoint(from element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func accessibilitySize(from element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func trimmedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.isEmpty ? nil : trimmed
    }
}
